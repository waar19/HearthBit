package com.hearthbit.app.mesh

import android.content.Context
import java.security.MessageDigest
import java.util.Base64

internal interface PeerTrustStorage {
    fun getString(key: String): String?
    fun contains(key: String): Boolean
    fun putString(key: String, value: String): Boolean
    fun swapString(oldKey: String, newKey: String, value: String): Boolean
    fun replaceString(oldKey: String, newKey: String, value: String): Boolean
    fun keys(): Set<String>
    fun clear(): Boolean
}

internal sealed interface PeerTrustLookup {
    data class Pinned(val keys: PeerIdentityKeys) : PeerTrustLookup
    data object Unknown : PeerTrustLookup
    data object Invalid : PeerTrustLookup
}

/**
 * Pins the first valid ANNOUNCE (TOFU) across process restarts.
 *
 * A normal Noise transport rekey keeps both static identity keys and is
 * accepted. Identity changes are accepted only through KEY_ROTATION, signed
 * by the previously pinned Ed25519 key; conflicting ANNOUNCE packets remain
 * rejected.
 */
internal class PeerTrustStore private constructor(
    private val storage: PeerTrustStorage,
    private val maximumTrustedPeers: Int,
) {
    constructor(context: Context) : this(
        SecurePeerTrustStorage(KeystoreSecureStore.open(context, PREFERENCES)),
        MAX_TRUSTED_PEERS,
    )

    internal constructor(
        storage: PeerTrustStorage,
        maximumTrustedPeers: Int = MAX_TRUSTED_PEERS,
        testOnly: Unit = Unit,
    ) : this(storage, maximumTrustedPeers) {
        require(maximumTrustedPeers > 0)
    }

    @Synchronized
    fun validateAndPin(
        peerId: String,
        announced: PeerIdentityKeys,
        authenticatedRotation: Boolean = false,
        protectedPeerIds: Set<String> = emptySet(),
    ): PeerIdentityDecision {
        if (!peerId.matches(PEER_ID_PATTERN) ||
            announced.noisePublicKey.size != PUBLIC_KEY_SIZE ||
            announced.signingPublicKey.size != PUBLIC_KEY_SIZE ||
            announced.noisePublicKey.all { it == 0.toByte() } ||
            announced.signingPublicKey.all { it == 0.toByte() } ||
            MeshProtocol.hex(MeshProtocol.peerIdFromNoiseKey(announced.noisePublicKey)) != peerId
        ) {
            return PeerIdentityDecision.REJECT_INVALID_IDENTITY
        }
        val storageKey = key(peerId)
        val stored = runCatching { storage.getString(storageKey) }.getOrElse {
            return PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION
        }
        val contains = runCatching { storage.contains(storageKey) }.getOrElse {
            return PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION
        }
        if (stored == null && contains) {
            return PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION
        }
        val pinned = stored?.let(::decode)?.keys
        if (stored != null && pinned == null) {
            return PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION
        }
        val decision = PeerIdentityPolicy.evaluate(
            pinned = pinned,
            announced = announced,
            authenticatedRotation = authenticatedRotation,
        )
        var evictionCandidate: StoredPin? = null
        if (decision == PeerIdentityDecision.FIRST_BINDING) {
            val trustCount = runCatching(::trustEntryCount).getOrElse {
                return PeerIdentityDecision.REJECT_CAPACITY
            }
            if (trustCount >= maximumTrustedPeers) {
                evictionCandidate = selectEvictionCandidate(
                    validatingStorageKey = storageKey,
                    protectedPeerIds = protectedPeerIds,
                ) ?: return PeerIdentityDecision.REJECT_CAPACITY
            }
        }
        if (decision.accepted) {
            val encoded = encode(announced, decision, 0L)
            val persisted = runCatching {
                evictionCandidate?.let { candidate ->
                    storage.swapString(candidate.storageKey, storageKey, encoded)
                } ?: storage.putString(storageKey, encoded)
            }.getOrDefault(false)
            if (!persisted) {
                return if (decision == PeerIdentityDecision.FIRST_BINDING) {
                    PeerIdentityDecision.REJECT_CAPACITY
                } else {
                    PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION
                }
            }
        }
        return decision
    }

    @Synchronized
    fun rotate(
        oldPeerId: String,
        replacement: PeerIdentityKeys,
        sequence: Long,
    ): PeerIdentityDecision {
        if (!oldPeerId.matches(PEER_ID_PATTERN) ||
            replacement.noisePublicKey.size != PUBLIC_KEY_SIZE ||
            replacement.signingPublicKey.size != PUBLIC_KEY_SIZE ||
            replacement.noisePublicKey.all { it == 0.toByte() } ||
            replacement.signingPublicKey.all { it == 0.toByte() } ||
            sequence <= 0L
        ) {
            return PeerIdentityDecision.REJECT_INVALID_IDENTITY
        }
        val oldStorageKey = key(oldPeerId)
        val oldStored = runCatching { storage.getString(oldStorageKey) }.getOrNull()
            ?: return PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION
        val oldRecord = decode(oldStored)
            ?: return PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION
        if (sequence <= oldRecord.lastRotationSequence) return PeerIdentityDecision.REJECT_REPLAY

        val newPeerId = MeshProtocol.hex(MeshProtocol.peerIdFromNoiseKey(replacement.noisePublicKey))
        if (newPeerId == oldPeerId) return PeerIdentityDecision.REJECT_INVALID_IDENTITY
        val newStorageKey = key(newPeerId)
        if (runCatching { storage.contains(newStorageKey) }.getOrDefault(true)) {
            return PeerIdentityDecision.REJECT_COLLISION
        }
        val collidesWithAnotherPeer = runCatching {
            storage.keys()
                .asSequence()
                .filter { it.startsWith(KEY_PREFIX) && it != oldStorageKey }
                .mapNotNull { storage.getString(it)?.let(::decode) }
                .any { record ->
                    MessageDigest.isEqual(
                        record.keys.signingPublicKey,
                        replacement.signingPublicKey,
                    ) || MessageDigest.isEqual(
                        record.keys.noisePublicKey,
                        replacement.noisePublicKey,
                    )
                }
        }.getOrDefault(true)
        if (collidesWithAnotherPeer) return PeerIdentityDecision.REJECT_COLLISION
        val encoded = encode(
            replacement,
            PeerIdentityDecision.ACCEPT_AUTHENTICATED_ROTATION,
            sequence,
        )
        return if (runCatching {
                storage.replaceString(oldStorageKey, newStorageKey, encoded)
            }.getOrDefault(false)
        ) {
            PeerIdentityDecision.ACCEPT_AUTHENTICATED_ROTATION
        } else {
            PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION
        }
    }

    @Synchronized
    fun lookup(peerId: String): PeerTrustLookup {
        if (!peerId.matches(PEER_ID_PATTERN)) return PeerTrustLookup.Invalid
        val storageKey = key(peerId)
        val stored = runCatching { storage.getString(storageKey) }
            .getOrElse { return PeerTrustLookup.Invalid }
        if (stored == null) {
            val contains = runCatching { storage.contains(storageKey) }
                .getOrElse { return PeerTrustLookup.Invalid }
            return if (contains) PeerTrustLookup.Invalid else PeerTrustLookup.Unknown
        }
        val record = decode(stored) ?: return PeerTrustLookup.Invalid
        if (MeshProtocol.hex(MeshProtocol.peerIdFromNoiseKey(record.keys.noisePublicKey)) != peerId) {
            return PeerTrustLookup.Invalid
        }
        return PeerTrustLookup.Pinned(record.keys)
    }

    fun clear() {
        check(storage.clear())
    }

    private fun trustEntryCount(): Int = storage.keys()
        .asSequence()
        .mapNotNull(::decodeBoundPin)
        .count()

    private fun selectEvictionCandidate(
        validatingStorageKey: String,
        protectedPeerIds: Set<String>,
    ): StoredPin? = runCatching {
        storage.keys()
            .asSequence()
            .filter { it.startsWith(KEY_PREFIX) && it != validatingStorageKey }
            .sorted()
            .mapNotNull { storageKey ->
                val peerId = storageKey.removePrefix(KEY_PREFIX)
                if (peerId in protectedPeerIds || !peerId.matches(PEER_ID_PATTERN)) {
                    return@mapNotNull null
                }
                decodeBoundPin(storageKey)
            }
            .firstOrNull()
    }.getOrNull()

    private fun decodeBoundPin(storageKey: String): StoredPin? {
        if (!storageKey.startsWith(KEY_PREFIX)) return null
        val peerId = storageKey.removePrefix(KEY_PREFIX)
        if (!peerId.matches(PEER_ID_PATTERN)) return null
        val encoded = storage.getString(storageKey) ?: return null
        val record = decode(encoded) ?: return null
        val boundPeerId = MeshProtocol.hex(
            MeshProtocol.peerIdFromNoiseKey(record.keys.noisePublicKey),
        )
        return if (boundPeerId == peerId) StoredPin(storageKey) else null
    }

    private fun encode(
        keys: PeerIdentityKeys,
        decision: PeerIdentityDecision,
        lastRotationSequence: Long,
    ): String {
        val noise = Base64.getEncoder().encodeToString(keys.noisePublicKey)
        val signing = Base64.getEncoder().encodeToString(keys.signingPublicKey)
        val noiseFingerprint = fingerprint(keys.noisePublicKey)
        val signingFingerprint = fingerprint(keys.signingPublicKey)
        val trust = when (decision) {
            PeerIdentityDecision.FIRST_BINDING -> "tofu"
            PeerIdentityDecision.ACCEPT_PINNED -> "pinned"
            PeerIdentityDecision.ACCEPT_AUTHENTICATED_ROTATION -> "rotated"
            PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION,
            PeerIdentityDecision.REJECT_INVALID_IDENTITY,
            PeerIdentityDecision.REJECT_CAPACITY,
            PeerIdentityDecision.REJECT_REPLAY,
            PeerIdentityDecision.REJECT_COLLISION,
            -> error("Rejected trust state")
        }
        return listOf(
            FORMAT_VERSION,
            trust,
            noise,
            signing,
            noiseFingerprint,
            signingFingerprint,
            lastRotationSequence.toString(),
        ).joinToString(SEPARATOR)
    }

    private fun decode(value: String): Record? = runCatching {
        val fields = value.split(SEPARATOR)
        val legacy = fields.size == LEGACY_FIELD_COUNT && fields[0] == LEGACY_FORMAT_VERSION
        val current = fields.size == FIELD_COUNT && fields[0] == FORMAT_VERSION
        if (!legacy && !current) {
            return null
        }
        val noise = Base64.getDecoder().decode(fields[2])
        val signing = Base64.getDecoder().decode(fields[3])
        if (noise.size != PUBLIC_KEY_SIZE || signing.size != PUBLIC_KEY_SIZE) return null
        if (fields[4] != fingerprint(noise) || fields[5] != fingerprint(signing)) return null
        val sequence = fields.getOrNull(6)?.toLongOrNull() ?: 0L
        if (sequence < 0L) return null
        Record(
            keys = PeerIdentityKeys(signingPublicKey = signing, noisePublicKey = noise),
            trustState = fields[1],
            lastRotationSequence = sequence,
        )
    }.getOrNull()

    private fun fingerprint(key: ByteArray): String =
        MeshProtocol.hex(MessageDigest.getInstance("SHA-256").digest(key))

    private fun key(peerId: String): String = KEY_PREFIX + peerId

    private data class Record(
        val keys: PeerIdentityKeys,
        val trustState: String,
        val lastRotationSequence: Long,
    )

    private data class StoredPin(
        val storageKey: String,
    )

    private companion object {
        const val PREFERENCES = "hearthbit_peer_trust"
        const val FORMAT_VERSION = "2"
        const val LEGACY_FORMAT_VERSION = "1"
        const val SEPARATOR = ":"
        const val LEGACY_FIELD_COUNT = 6
        const val FIELD_COUNT = 7
        const val PUBLIC_KEY_SIZE = 32
        const val MAX_TRUSTED_PEERS = 4_096
        const val KEY_PREFIX = "peer_"
        val PEER_ID_PATTERN = Regex("^[0-9a-f]{16}$")
    }
}

private class SecurePeerTrustStorage(
    private val store: KeystoreSecureStore,
) : PeerTrustStorage {
    override fun getString(key: String): String? = store.getString(key)
    override fun contains(key: String): Boolean = store.contains(key)
    override fun putString(key: String, value: String): Boolean = store.putString(key, value)
    override fun swapString(oldKey: String, newKey: String, value: String): Boolean =
        store.swapString(oldKey, newKey, value)
    override fun replaceString(oldKey: String, newKey: String, value: String): Boolean =
        store.replaceString(oldKey, newKey, value)
    override fun keys(): Set<String> = store.keys()
    override fun clear(): Boolean = store.clear()
}
