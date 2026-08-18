package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshRecoveryPolicyTest {
    @Test
    fun `tercer fallo de descifrado solicita renegociacion`() {
        val tracker = NoiseFailureRecoveryTracker()

        assertEquals(NoiseRecoveryAction.NONE, tracker.recordFailure("peer", true))
        assertEquals(NoiseRecoveryAction.NONE, tracker.recordFailure("peer", true))
        assertEquals(NoiseRecoveryAction.RENEGOTIATE, tracker.recordFailure("peer", true))
    }

    @Test
    fun `descifrado exitoso reinicia el contador`() {
        val tracker = NoiseFailureRecoveryTracker()

        tracker.recordFailure("peer", true)
        tracker.recordFailure("peer", true)
        tracker.recordSuccess("peer")

        assertEquals(NoiseRecoveryAction.NONE, tracker.recordFailure("peer", true))
    }

    @Test
    fun `ciphertext sin sesion solicita handshake inmediato`() {
        val tracker = NoiseFailureRecoveryTracker()

        assertEquals(
            NoiseRecoveryAction.RENEGOTIATE,
            tracker.recordFailure("peer", hadEstablishedSession = false),
        )
    }

    @Test
    fun `conexion cliente nunca excede el limite efectivo`() {
        assertTrue(ConnectionPriorityPolicy.canOpenClientConnection(3, 1, knownPeer = false))
        assertTrue(ConnectionPriorityPolicy.canOpenClientConnection(3, 2, knownPeer = false))
        assertTrue(ConnectionPriorityPolicy.canOpenClientConnection(3, 2, knownPeer = true))
        assertFalse(ConnectionPriorityPolicy.canOpenClientConnection(3, 3, knownPeer = true))
        assertFalse(ConnectionPriorityPolicy.canOpenClientConnection(0, 0, knownPeer = true))
    }
}
