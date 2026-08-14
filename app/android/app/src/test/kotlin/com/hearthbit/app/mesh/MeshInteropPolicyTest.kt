package com.hearthbit.app.mesh

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshInteropPolicyTest {
    @Test
    fun `private mode hides external chat but preserves external sos`() {
        assertFalse(
            MeshInteropPolicy.shouldProcessPublicMessage(
                privateMode = true,
                hearthbitVerified = false,
                emergency = false,
            ),
        )
        assertTrue(
            MeshInteropPolicy.shouldProcessPublicMessage(
                privateMode = true,
                hearthbitVerified = false,
                emergency = true,
            ),
        )
        assertTrue(
            MeshInteropPolicy.isExternalEmergency(
                privateMode = true,
                hearthbitVerified = false,
                emergency = true,
            ),
        )
    }

    @Test
    fun `interop or verified HearthBit peers keep normal messages`() {
        assertTrue(
            MeshInteropPolicy.shouldProcessPublicMessage(
                privateMode = false,
                hearthbitVerified = false,
                emergency = false,
            ),
        )
        assertTrue(
            MeshInteropPolicy.shouldProcessPublicMessage(
                privateMode = true,
                hearthbitVerified = true,
                emergency = false,
            ),
        )
        assertFalse(
            MeshInteropPolicy.isExternalEmergency(
                privateMode = true,
                hearthbitVerified = true,
                emergency = true,
            ),
        )
    }

    @Test
    fun `private identity only reaches proven links except public sos`() {
        assertFalse(
            MeshInteropPolicy.canSendIdentityToLink(
                privateMode = true,
                hearthbitProven = false,
                emergencyException = false,
            ),
        )
        assertTrue(
            MeshInteropPolicy.canSendIdentityToLink(
                privateMode = true,
                hearthbitProven = true,
                emergencyException = false,
            ),
        )
        assertTrue(
            MeshInteropPolicy.canSendIdentityToLink(
                privateMode = true,
                hearthbitProven = false,
                emergencyException = true,
            ),
        )
    }

    @Test
    fun `anonymous link proof is exact and carries no peer identity`() {
        val proof = HearthBitLinkProof.bytes()

        assertTrue(HearthBitLinkProof.matches(proof))
        assertFalse(HearthBitLinkProof.matches(proof + byteArrayOf(0)))
        assertFalse(HearthBitLinkProof.matches("HB-LINK2".toByteArray()))
        assertTrue(proof.size < MeshAdvertisePlan.PEER_ID_BYTES + 1)
    }
}
