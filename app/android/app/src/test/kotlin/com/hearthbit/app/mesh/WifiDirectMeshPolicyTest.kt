package com.hearthbit.app.mesh

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class WifiDirectMeshPolicyTest {
    @Test
    fun `se activa en rescate o cuando BLE esta degradado`() {
        assertTrue(WifiDirectMeshPolicy.shouldRun(rescueActive = true, degraded = false))
        assertTrue(WifiDirectMeshPolicy.shouldRun(rescueActive = false, degraded = true))
        assertFalse(WifiDirectMeshPolicy.shouldRun(rescueActive = false, degraded = false))
    }

    @Test
    fun `hello de emergencia conserva el limite negociado`() {
        val hello = WifiDirectEmergencyFraming.buildHello(
            gatewayId = ByteArray(16) { it.toByte() },
            maximumFrameSize = 1_024,
        )

        assertEquals(25, hello.size)
        assertEquals(1_024, WifiDirectEmergencyFraming.parseMaximumFrameSize(hello))
        assertThrows(IllegalArgumentException::class.java) {
            WifiDirectEmergencyFraming.parseMaximumFrameSize(hello.copyOf().also { it[0] = 0 })
        }
    }
}
