package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Test

class EmergencyTransportEscalationTest {
    @Test
    fun `reporta solo portadoras que aceptaron el SOS`() {
        assertEquals(
            listOf("ble", "wifiDirect", "wifiAware"),
            EmergencyTransportEscalation.channels(
                ble = true,
                lan = false,
                wifiDirect = true,
                wifiAware = true,
            ),
        )
    }
}
