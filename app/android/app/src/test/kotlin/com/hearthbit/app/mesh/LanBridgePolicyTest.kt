package com.hearthbit.app.mesh

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertTrue
import org.junit.Test

class LanBridgePolicyTest {
    @Test
    fun `normaliza un gateway id hexadecimal`() {
        assertEquals(
            "abcdef0123456789abcdef0123456789",
            LanBridgePolicy.validateGatewayId("ABCDEF0123456789ABCDEF0123456789"),
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun `rechaza gateway id ambiguo`() {
        LanBridgePolicy.validateGatewayId("gateway-local")
    }

    @Test
    fun `conserva el frame opaco mediante una copia defensiva`() {
        val frame = byteArrayOf(1, 2, 7, 4)

        val accepted = LanBridgePolicy.validateFrame(frame, 4)
        frame[2] = 1

        assertNotSame(frame, accepted)
        assertArrayEquals(byteArrayOf(1, 2, 7, 4), accepted)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `rechaza frames sobre el limite negociado`() {
        LanBridgePolicy.validateFrame(byteArrayOf(1, 2, 3), 2)
    }

    @Test
    fun `solo un stop explicito limpia el puente LAN`() {
        assertFalse(LanBridgePolicy.shouldClearOnStop(notify = false))
        assertTrue(LanBridgePolicy.shouldClearOnStop(notify = true))
    }
}
