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
    fun `capacity fails closed without replacing existing pins`() {
        val storage = FakePeerTrustStorage()
        val store = PeerTrustStore(storage)
        val existing = keys(2)
        val existingPeerId = peerId(existing)
        assertEquals(
            PeerIdentityDecision.FIRST_BINDING,
            store.validateAndPin(existingPeerId, existing),
        )
        repeat(4_095) { index ->
            storage.values["peer_${index.toString(16).padStart(16, '0')}"] = "occupied"
        }
        val newcomer = keys(3)

        assertEquals(
            PeerIdentityDecision.REJECT_CAPACITY,
            store.validateAndPin(peerId(newcomer), newcomer),
        )
        assertEquals(
            PeerIdentityDecision.ACCEPT_PINNED,
            store.validateAndPin(existingPeerId, existing),
        )
        assertEquals(4_096, storage.values.size)
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

    private fun keys(seed: Int): PeerIdentityKeys = PeerIdentityKeys(
        signingPublicKey = ByteArray(32) { (seed + it).toByte() },
        noisePublicKey = ByteArray(32) { (seed * 3 + it).toByte() },
    )

    private fun peerId(keys: PeerIdentityKeys): String =
        MeshProtocol.hex(MeshProtocol.peerIdFromNoiseKey(keys.noisePublicKey))

    private class FakePeerTrustStorage : PeerTrustStorage {
        val values = linkedMapOf<String, String>()

        override fun getString(key: String): String? = values[key]
        override fun contains(key: String): Boolean = values.containsKey(key)
        override fun putString(key: String, value: String): Boolean {
            values[key] = value
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
