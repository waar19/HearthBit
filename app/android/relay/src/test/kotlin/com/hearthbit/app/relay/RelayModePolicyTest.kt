package com.hearthbit.app.relay

import org.junit.Assert.assertEquals
import org.junit.Test

class RelayModePolicyTest {
    @Test
    fun `uses dual role when advertising is supported`() {
        assertEquals(
            RelayMode.DUAL_ROLE,
            RelayModePolicy.select(
                hasBleHardware = true,
                hasGattCentral = true,
                supportsAdvertising = true,
            ),
        )
    }

    @Test
    fun `falls back to central when advertising is unavailable`() {
        assertEquals(
            RelayMode.CENTRAL_ONLY,
            RelayModePolicy.select(
                hasBleHardware = true,
                hasGattCentral = true,
                supportsAdvertising = false,
            ),
        )
    }

    @Test
    fun `rejects devices without BLE central support`() {
        assertEquals(
            RelayMode.UNAVAILABLE,
            RelayModePolicy.select(
                hasBleHardware = true,
                hasGattCentral = false,
                supportsAdvertising = true,
            ),
        )
    }
}
