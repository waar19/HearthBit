package com.hearthbit.app.mesh

import java.security.MessageDigest

internal data class PeerIdentityKeys(
    val signingPublicKey: ByteArray,
    val noisePublicKey: ByteArray,
)

internal enum class PeerIdentityDecision {
    FIRST_BINDING,
    ACCEPT_PINNED,
    ACCEPT_AUTHENTICATED_ROTATION,
    REJECT_UNAUTHENTICATED_ROTATION,
    REJECT_INVALID_IDENTITY,
    REJECT_CAPACITY,
    REJECT_REPLAY,
    REJECT_COLLISION,
    ;

    val accepted: Boolean
        get() = this == FIRST_BINDING ||
            this == ACCEPT_PINNED ||
            this == ACCEPT_AUTHENTICATED_ROTATION
}

internal object PeerIdentityPolicy {
    fun evaluate(
        pinned: PeerIdentityKeys?,
        announced: PeerIdentityKeys,
        authenticatedRotation: Boolean = false,
    ): PeerIdentityDecision {
        if (pinned == null) return PeerIdentityDecision.FIRST_BINDING
        val signingMatches = MessageDigest.isEqual(
            pinned.signingPublicKey,
            announced.signingPublicKey,
        )
        val noiseMatches = MessageDigest.isEqual(
            pinned.noisePublicKey,
            announced.noisePublicKey,
        )
        if (signingMatches && noiseMatches) return PeerIdentityDecision.ACCEPT_PINNED
        return if (authenticatedRotation) {
            PeerIdentityDecision.ACCEPT_AUTHENTICATED_ROTATION
        } else {
            PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION
        }
    }
}
