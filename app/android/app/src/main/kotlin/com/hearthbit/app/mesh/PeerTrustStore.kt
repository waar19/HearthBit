package com.hearthbit.app.mesh

import android.content.Context
import android.util.Base64
import java.security.MessageDigest

internal interface PeerTrustStorage {
    fun getString(key: String): String?
    fun contains(key: String): Boolean
    fun putString(key: String, value: String): Boolean
    fun keys(): Set<String>
    fun clear(): Boolean
}

/**
 * Pins the first valid ANNOUNCE (TOFU) across process restarts.
 *
 * A normal Noise transport rekey keeps both static identity keys and is
 * accepted. There is currently no wire message proving an identity-key
 * rotation with the previously pinned Ed25519 key, so changed keys are
 * rejected. The existing panic wipe is the explicit local re-pairing path.
 */
internal class PeerTrustStore private constructor(
    private val storage: PeerTrustStorage,
) {
    constructor(context: Context) : this(
        SecurePeerTrustStorage(KeystoreSecureStore.open(context, PREFERENCES)),
    )

    internal constructor(storage: PeerTrustStorage, testOnly: Unit = Unit) : this(storage)

    @Synchronized
    fun validateAndPin(
        peerId: String,
        announced: PeerIdentityKeys,
        authenticatedRotation: Boolean = false,
    ): PeerIdentityDecision {
        if (!peerId.matches(PEER_ID_PATTERN) ||
            announced.noisePublicKey.size != PUBLIC_KEY_SIZE ||
            announced.signingPublicKey.size != PUBLIC_KEY_SIZE ||
            MeshProtocol.hex(MeshProtocol.peerIdFromNoiseKey(announced.noisePublicKey)) != peerId
        ) {
            return PeerIdentityDecision.REJECT_INVALID_IDENTITY
        }
        val storageKey = key(peerId)
        val stored = runCatching { storage.getString(storageKey) }.getOrElse {
            return PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION
        }
        if (stored == null && storage.contains(storageKey)) {
            return PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION
        }
        val pinned = stored?.let(::decode)?.keys
        if (stored != null && pinned == null) {
            return PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION
        }
        if (stored == null && trustEntryCount() >= MAX_TRUSTED_PEERS) {
            return PeerIdentityDecision.REJECT_CAPACITY
        }
        val decision = PeerIdentityPolicy.evaluate(
            pinned = pinned,
            announced = announced,
            authenticatedRotation = authenticatedRotation,
        )
        if (decision.accepted) {
            check(storage.putString(storageKey, encode(announced, decision)))
        }
        return decision
    }

    @Synchronized
    fun pinnedKeys(peerId: String): PeerIdentityKeys? {
        if (!peerId.matches(PEER_ID_PATTERN)) return null
        return storage.getString(key(peerId))?.let(::decode)?.keys
    }

    fun clear() {
        check(storage.clear())
    }

    private fun trustEntryCount(): Int = storage.keys().count { it.startsWith(KEY_PREFIX) }

    private fun encode(keys: PeerIdentityKeys, decision: PeerIdentityDecision): String {
        val noise = Base64.encodeToString(keys.noisePublicKey, Base64.NO_WRAP)
        val signing = Base64.encodeToString(keys.signingPublicKey, Base64.NO_WRAP)
        val noiseFingerprint = fingerprint(keys.noisePublicKey)
        val signingFingerprint = fingerprint(keys.signingPublicKey)
        val trust = when (decision) {
            PeerIdentityDecision.FIRST_BINDING -> "tofu"
            PeerIdentityDecision.ACCEPT_PINNED -> "pinned"
            PeerIdentityDecision.ACCEPT_AUTHENTICATED_ROTATION -> "rotated"
            PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION,
            PeerIdentityDecision.REJECT_INVALID_IDENTITY,
            PeerIdentityDecision.REJECT_CAPACITY,
            -> error("Rejected trust state")
        }
        return listOf(
            FORMAT_VERSION,
            trust,
            noise,
            signing,
            noiseFingerprint,
            signingFingerprint,
        ).joinToString(SEPARATOR)
    }

    private fun decode(value: String): Record? = runCatching {
        val fields = value.split(SEPARATOR)
        if (fields.size != FIELD_COUNT || fields[0] != FORMAT_VERSION) return null
        val noise = Base64.decode(fields[2], Base64.NO_WRAP)
        val signing = Base64.decode(fields[3], Base64.NO_WRAP)
        if (noise.size != PUBLIC_KEY_SIZE || signing.size != PUBLIC_KEY_SIZE) return null
        if (fields[4] != fingerprint(noise) || fields[5] != fingerprint(signing)) return null
        Record(
            keys = PeerIdentityKeys(signingPublicKey = signing, noisePublicKey = noise),
            trustState = fields[1],
        )
    }.getOrNull()

    private fun fingerprint(key: ByteArray): String =
        MeshProtocol.hex(MessageDigest.getInstance("SHA-256").digest(key))

    private fun key(peerId: String): String = KEY_PREFIX + peerId

    private data class Record(
        val keys: PeerIdentityKeys,
        val trustState: String,
    )

    private companion object {
        const val PREFERENCES = "hearthbit_peer_trust"
        const val FORMAT_VERSION = "1"
        const val SEPARATOR = ":"
        const val FIELD_COUNT = 6
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
    override fun keys(): Set<String> = store.keys()
    override fun clear(): Boolean = store.clear()
}
