package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Test

class AdaptivePowerPolicyTest {
    @Test
    fun `charging only uses performance for explicit rescue work`() {
        assertEquals(
            PowerProfile.BALANCED,
            profile(battery = 70, charging = true, screenOn = true),
        )
        assertEquals(
            PowerProfile.PERFORMANCE,
            profile(
                battery = 70,
                charging = true,
                screenOn = true,
                highPerformance = true,
            ),
        )
        assertEquals(
            PowerProfile.SURVIVAL,
            profile(battery = 70, charging = true, screenOn = true, survival = true),
        )
        assertEquals(
            PowerProfile.POWER_SAVER,
            profile(
                battery = 70,
                charging = true,
                screenOn = true,
                systemPowerSave = true,
            ),
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
    fun `screen off medium battery or system saver uses power saver`() {
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
        assertEquals(
            PowerProfile.POWER_SAVER,
            profile(battery = 80, systemPowerSave = true),
        )
    }

    @Test
    fun `rescue work stays at least balanced even with critical battery`() {
        assertEquals(
            PowerProfile.BALANCED,
            profile(
                battery = 50,
                screenOn = false,
                systemPowerSave = true,
                highPerformance = true,
            ),
        )
        assertEquals(
            PowerProfile.BALANCED,
            profile(battery = 20, screenOn = false, highPerformance = true),
        )
        assertEquals(
            PowerProfile.BALANCED,
            profile(battery = 10, screenOn = false, highPerformance = true),
        )
        assertEquals(
            PowerProfile.BALANCED,
            profile(battery = 0, systemPowerSave = true, highPerformance = true),
        )
        assertEquals(
            PowerProfile.PERFORMANCE,
            profile(battery = 5, charging = true, highPerformance = true),
        )
        assertEquals(
            PowerProfile.SURVIVAL,
            profile(
                battery = 5,
                charging = true,
                survival = true,
                highPerformance = true,
            ),
        )
    }

    @Test
    fun `battery at ten and below uses critical without enabling survival`() {
        assertEquals(PowerProfile.CRITICAL, profile(battery = 10))
        assertEquals(PowerProfile.CRITICAL, profile(battery = 9))
        assertEquals(PowerProfile.CRITICAL, profile(battery = -10))
        assertEquals(PowerProfile.POWER_SAVER, profile(battery = 11))
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
        systemPowerSave: Boolean = false,
        survival: Boolean = false,
        highPerformance: Boolean = false,
    ): PowerProfile = AdaptivePowerPolicy.profileFor(
        batteryPercent = battery,
        isCharging = charging,
        screenOn = screenOn,
        systemPowerSave = systemPowerSave,
        survivalMode = survival,
        highPerformanceRequested = highPerformance,
    )
}
