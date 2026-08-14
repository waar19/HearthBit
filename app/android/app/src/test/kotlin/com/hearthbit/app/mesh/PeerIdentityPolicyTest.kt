package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Test

class PeerIdentityPolicyTest {
    private val original = PeerIdentityKeys(
        signingPublicKey = ByteArray(32) { 0x11 },
        noisePublicKey = ByteArray(32) { 0x22 },
    )

    @Test
    fun `first valid announcement establishes trust`() {
        assertEquals(
            PeerIdentityDecision.FIRST_BINDING,
            PeerIdentityPolicy.evaluate(null, original),
        )
    }

    @Test
    fun `pinned keys remain accepted`() {
        assertEquals(
            PeerIdentityDecision.ACCEPT_PINNED,
            PeerIdentityPolicy.evaluate(
                original,
                original.copy(
                    signingPublicKey = original.signingPublicKey.copyOf(),
                    noisePublicKey = original.noisePublicKey.copyOf(),
                ),
            ),
        )
    }

    @Test
    fun `signing or Noise rotations require authentication`() {
        val changedSigning = original.copy(signingPublicKey = ByteArray(32) { 0x33 })
        val changedNoise = original.copy(noisePublicKey = ByteArray(32) { 0x44 })

        assertEquals(
            PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION,
            PeerIdentityPolicy.evaluate(original, changedSigning),
        )
        assertEquals(
            PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION,
            PeerIdentityPolicy.evaluate(original, changedNoise),
        )
    }

    @Test
    fun `authenticated rotation has an explicit policy path`() {
        val rotated = PeerIdentityKeys(
            signingPublicKey = ByteArray(32) { 0x55 },
            noisePublicKey = ByteArray(32) { 0x66 },
        )

        assertEquals(
            PeerIdentityDecision.ACCEPT_AUTHENTICATED_ROTATION,
            PeerIdentityPolicy.evaluate(original, rotated, authenticatedRotation = true),
        )
    }
}
