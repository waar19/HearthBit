package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Test

class AdaptivePowerPolicyTest {
    @Test
    fun `charging uses performance unless survival is forced`() {
        assertEquals(
            PowerProfile.PERFORMANCE,
            profile(battery = 70, charging = true, screenOn = true),
        )
        assertEquals(
            PowerProfile.SURVIVAL,
            profile(battery = 70, charging = true, screenOn = true, survival = true),
        )
    }

    @Test
    fun `healthy unplugged battery uses balanced profile`() {
        assertEquals(
            PowerProfile.BALANCED,
            profile(battery = 41, charging = false, screenOn = true),
        )
        assertEquals(
            PowerProfile.BALANCED,
            profile(battery = 100, charging = false, screenOn = true),
        )
    }

    @Test
    fun `screen off or medium battery uses power saver`() {
        assertEquals(
            PowerProfile.POWER_SAVER,
            profile(battery = 80, charging = false, screenOn = false),
        )
        assertEquals(
            PowerProfile.POWER_SAVER,
            profile(battery = 40, charging = false, screenOn = true),
        )
        assertEquals(
            PowerProfile.POWER_SAVER,
            profile(battery = 20, charging = false, screenOn = true),
        )
    }

    @Test
    fun `battery from ten through nineteen uses critical profile`() {
        assertEquals(PowerProfile.CRITICAL, profile(battery = 10))
        assertEquals(PowerProfile.CRITICAL, profile(battery = 19))
    }

    @Test
    fun `battery below ten uses survival and values are clamped`() {
        assertEquals(PowerProfile.SURVIVAL, profile(battery = 9))
        assertEquals(PowerProfile.SURVIVAL, profile(battery = -10))
        assertEquals(PowerProfile.BALANCED, profile(battery = 150))
    }

    @Test
    fun `critical profile limits links and uses a longer pause`() {
        assertEquals(3, PowerProfile.CRITICAL.maximumClientConnections)
        assertEquals(5_000L, PowerProfile.CRITICAL.scanBurstMs)
        assertEquals(115_000L, PowerProfile.CRITICAL.scanPauseMs)
        assertEquals(null, PowerProfile.SURVIVAL.scanMode)
    }

    private fun profile(
        battery: Int,
        charging: Boolean = false,
        screenOn: Boolean = true,
        survival: Boolean = false,
    ): PowerProfile = AdaptivePowerPolicy.profileFor(
        batteryPercent = battery,
        isCharging = charging,
        screenOn = screenOn,
        survivalMode = survival,
    )
}
