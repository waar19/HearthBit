package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PeerTrustStoreTest {
    @Test
    fun `rejects malformed peer ID and Noise binding mismatch`() {
        val storage = FakePeerTrustStorage()
        val store = PeerTrustStore(storage)
        val keys = keys(1)
        val boundPeerId = peerId(keys)

        assertEquals(
            PeerIdentityDecision.REJECT_INVALID_IDENTITY,
            store.validateAndPin(boundPeerId.dropLast(1), keys),
        )
        assertEquals(
            PeerIdentityDecision.REJECT_INVALID_IDENTITY,
            store.validateAndPin(boundPeerId.uppercase(), keys),
        )
        assertEquals(
            PeerIdentityDecision.REJECT_INVALID_IDENTITY,
            store.validateAndPin("0000000000000000", keys),
        )
        assertTrue(storage.values.isEmpty())
    }

    @Test
    fun `capacity evicts one deterministic unprotected pin`() {
        val storage = FakePeerTrustStorage()
        val store = PeerTrustStore(storage, maximumTrustedPeers = 2)
        val first = keys(2)
        val second = keys(3)
        val firstId = peerId(first)
        val secondId = peerId(second)
        val newcomerKeys = keys(4)
        val newcomerId = peerId(newcomerKeys)
        assertEquals(PeerIdentityDecision.FIRST_BINDING, store.validateAndPin(firstId, first))
        assertEquals(PeerIdentityDecision.FIRST_BINDING, store.validateAndPin(secondId, second))

        assertEquals(
            PeerIdentityDecision.FIRST_BINDING,
            store.validateAndPin(newcomerId, newcomerKeys),
        )
        val evictedId = minOf(firstId, secondId)
        val retainedId = maxOf(firstId, secondId)
        assertEquals(
            PeerTrustLookup.Unknown,
            store.lookup(evictedId),
        )
        assertTrue(store.lookup(retainedId) is PeerTrustLookup.Pinned)
        assertTrue(store.lookup(newcomerId) is PeerTrustLookup.Pinned)
        assertEquals(2, storage.values.size)
        assertEquals(
            "peer_$evictedId" to "peer_$newcomerId",
            storage.swapOperations.single(),
        )
        assertEquals(2, storage.putCalls)
        assertEquals(1L, store.operationalCounters()["trustStoreEvictions"])
        assertEquals(0L, store.operationalCounters()["trustConflicts"])
    }

    @Test
    fun `capacity protects relationship pins and evicts another pin`() {
        val storage = FakePeerTrustStorage()
        val store = PeerTrustStore(storage, maximumTrustedPeers = 2)
        val protected = keys(10)
        val evictable = keys(11)
        val newcomer = keys(12)
        val protectedId = peerId(protected)
        val evictableId = peerId(evictable)
        assertEquals(PeerIdentityDecision.FIRST_BINDING, store.validateAndPin(protectedId, protected))
        assertEquals(PeerIdentityDecision.FIRST_BINDING, store.validateAndPin(evictableId, evictable))

        assertEquals(
            PeerIdentityDecision.FIRST_BINDING,
            store.validateAndPin(
                peerId = peerId(newcomer),
                announced = newcomer,
                protectedPeerIds = setOf(protectedId),
            ),
        )

        assertTrue(store.lookup(protectedId) is PeerTrustLookup.Pinned)
        assertEquals(PeerTrustLookup.Unknown, store.lookup(evictableId))
        assertTrue(store.lookup(peerId(newcomer)) is PeerTrustLookup.Pinned)
    }

    @Test
    fun `capacity rejects when every existing pin is protected`() {
        val storage = FakePeerTrustStorage()
        val store = PeerTrustStore(storage, maximumTrustedPeers = 1)
        val existing = keys(20)
        val newcomer = keys(21)
        val existingId = peerId(existing)
        assertEquals(PeerIdentityDecision.FIRST_BINDING, store.validateAndPin(existingId, existing))

        assertEquals(
            PeerIdentityDecision.REJECT_CAPACITY,
            store.validateAndPin(
                peerId = peerId(newcomer),
                announced = newcomer,
                protectedPeerIds = setOf(existingId),
            ),
        )

        assertTrue(store.lookup(existingId) is PeerTrustLookup.Pinned)
        assertEquals(PeerTrustLookup.Unknown, store.lookup(peerId(newcomer)))
    }

    @Test
    fun `failed atomic swap preserves old pin and rejects newcomer`() {
        val storage = FakePeerTrustStorage()
        val store = PeerTrustStore(storage, maximumTrustedPeers = 1)
        val first = keys(30)
        val newcomer = keys(31)
        assertEquals(
            PeerIdentityDecision.FIRST_BINDING,
            store.validateAndPin(peerId(first), first),
        )
        val before = storage.values.toMap()
        storage.failSwap = true

        assertEquals(
            PeerIdentityDecision.REJECT_CAPACITY,
            store.validateAndPin(peerId(newcomer), newcomer),
        )
        assertEquals(before, storage.values)
        assertTrue(store.lookup(peerId(first)) is PeerTrustLookup.Pinned)
        assertEquals(PeerTrustLookup.Unknown, store.lookup(peerId(newcomer)))
        assertEquals(1, storage.swapAttempts)
    }

    @Test
    fun `rotation tombstones do not consume trusted peer capacity`() {
        val storage = FakePeerTrustStorage()
        val store = PeerTrustStore(storage, maximumTrustedPeers = 2)
        val original = keys(40)
        val replacement = keys(41)
        val newcomer = keys(42)
        val originalId = peerId(original)
        val replacementId = peerId(replacement)
        assertEquals(
            PeerIdentityDecision.FIRST_BINDING,
            store.validateAndPin(originalId, original),
        )
        assertEquals(
            PeerIdentityDecision.ACCEPT_AUTHENTICATED_ROTATION,
            store.rotate(originalId, replacement, sequence = 1L),
        )
        assertEquals(
            PeerIdentityDecision.FIRST_BINDING,
            store.validateAndPin(peerId(newcomer), newcomer),
        )

        assertEquals(PeerTrustLookup.Invalid, store.lookup(originalId))
        assertTrue(store.lookup(replacementId) is PeerTrustLookup.Pinned)
        assertTrue(store.lookup(peerId(newcomer)) is PeerTrustLookup.Pinned)
        assertEquals(0, storage.swapAttempts)
        assertTrue(storage.values.containsKey("peer_$originalId"))
    }

    @Test
    fun `corrupt persisted pin is invalid rather than unknown`() {
        val storage = FakePeerTrustStorage()
        val store = PeerTrustStore(storage)
        val peerId = "0011223344556677"
        storage.values["peer_$peerId"] = "corrupt"

        assertEquals(PeerTrustLookup.Invalid, store.lookup(peerId))
    }

    @Test
    fun `authenticated rotation migrates pin atomically and rejects replay and collision`() {
        val storage = FakePeerTrustStorage()
        val store = PeerTrustStore(storage)
        val old = keys(4)
        val replacement = keys(5)
        val occupied = keys(6)
        val oldId = peerId(old)
        val replacementId = peerId(replacement)
        assertEquals(PeerIdentityDecision.FIRST_BINDING, store.validateAndPin(oldId, old))
        assertEquals(
            PeerIdentityDecision.ACCEPT_AUTHENTICATED_ROTATION,
            store.rotate(oldId, replacement, 7),
        )
        assertEquals(PeerTrustLookup.Invalid, store.lookup(oldId))
        assertTrue(store.lookup(replacementId) is PeerTrustLookup.Pinned)
        assertEquals(
            PeerIdentityDecision.REJECT_REPLAY,
            store.rotate(replacementId, keys(7), 7),
        )
        assertEquals(
            PeerIdentityDecision.FIRST_BINDING,
            store.validateAndPin(peerId(occupied), occupied),
        )
        assertEquals(
            PeerIdentityDecision.REJECT_COLLISION,
            store.rotate(replacementId, occupied, 8),
        )
    }

    @Test
    fun `rescue roster batch is persisted pre-pinned and protected`() {
        val storage = FakePeerTrustStorage()
        val store = PeerTrustStore(storage, maximumTrustedPeers = 1)
        val rescuer = keys(70)
        val rescuerId = peerId(rescuer)
        store.importRescueRosterPins(
            listOf(RescueRosterPin(rescuerId, rescuer.signingPublicKey)),
        )

        val restored = PeerTrustStore(storage, maximumTrustedPeers = 1)
        assertEquals(
            rescuer.signingPublicKey.toList(),
            restored.rescueSigningKey(rescuerId)?.toList(),
        )
        assertTrue(rescuerId in restored.rescueProtectedPeerIds())
        assertEquals(
            PeerIdentityDecision.FIRST_BINDING,
            restored.validateAndPin(rescuerId, rescuer),
        )
        val newcomer = keys(71)
        assertEquals(
            PeerIdentityDecision.REJECT_CAPACITY,
            restored.validateAndPin(peerId(newcomer), newcomer),
        )
    }

    @Test
    fun `rescue roster batch validates everything before replacing`() {
        val storage = FakePeerTrustStorage()
        val store = PeerTrustStore(storage)
        val original = keys(80)
        val originalId = peerId(original)
        store.importRescueRosterPins(
            listOf(RescueRosterPin(originalId, original.signingPublicKey)),
        )
        val before = storage.values.toMap()

        val valid = keys(81)
        val invalid = keys(82)
        val error = runCatching {
            store.importRescueRosterPins(
                listOf(
                    RescueRosterPin(peerId(valid), valid.signingPublicKey),
                    RescueRosterPin(peerId(invalid).uppercase(), invalid.signingPublicKey),
                ),
            )
        }.exceptionOrNull()

        assertTrue(error is IllegalArgumentException)
        assertEquals(before, storage.values)
        assertTrue(store.rescueSigningKey(originalId) != null)
    }

    @Test
    fun `rescue roster rejects an announced signing key conflict`() {
        val storage = FakePeerTrustStorage()
        val store = PeerTrustStore(storage)
        val rescuer = keys(90)
        store.importRescueRosterPins(
            listOf(RescueRosterPin(peerId(rescuer), rescuer.signingPublicKey)),
        )

        assertEquals(
            PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION,
            store.validateAndPin(
                peerId(rescuer),
                rescuer.copy(signingPublicKey = ByteArray(32) { 7 }),
            ),
        )
        assertEquals(PeerTrustLookup.Unknown, store.lookup(peerId(rescuer)))
        assertEquals(1L, store.operationalCounters()["trustConflicts"])
    }

    private fun keys(seed: Int): PeerIdentityKeys = PeerIdentityKeys(
        signingPublicKey = ByteArray(32) { (seed + it).toByte() },
        noisePublicKey = ByteArray(32) { (seed * 3 + it).toByte() },
    )

    private fun peerId(keys: PeerIdentityKeys): String =
        MeshProtocol.hex(MeshProtocol.peerIdFromNoiseKey(keys.noisePublicKey))

    private class FakePeerTrustStorage : PeerTrustStorage {
        val values = linkedMapOf<String, String>()
        val swapOperations = mutableListOf<Pair<String, String>>()
        var putCalls = 0
        var swapAttempts = 0
        var failSwap = false

        override fun getString(key: String): String? = values[key]
        override fun contains(key: String): Boolean = values.containsKey(key)
        override fun putString(key: String, value: String): Boolean {
            putCalls += 1
            values[key] = value
            return true
        }
        override fun swapString(oldKey: String, newKey: String, value: String): Boolean {
            swapAttempts += 1
            if (failSwap || !values.containsKey(oldKey)) return false
            val replacement = LinkedHashMap(values)
            replacement.remove(oldKey)
            replacement[newKey] = value
            values.clear()
            values.putAll(replacement)
            swapOperations += oldKey to newKey
            return true
        }
        override fun replaceString(oldKey: String, newKey: String, value: String): Boolean {
            values[oldKey] = "retired-by-key-rotation"
            values[newKey] = value
            return true
        }
        override fun keys(): Set<String> = values.keys
        override fun clear(): Boolean {
            values.clear()
            return true
        }
    }
}
