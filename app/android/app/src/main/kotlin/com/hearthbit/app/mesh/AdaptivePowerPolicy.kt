package com.hearthbit.app.mesh

internal object AdaptivePowerPolicy {
    const val BATTERY_THRESHOLD_PERCENT = 20
    const val SCAN_BURST_MS = 10_000L
    const val SCAN_PAUSE_MS = 50_000L

    fun shouldSavePower(batteryPercent: Int): Boolean =
        batteryPercent.coerceIn(0, 100) < BATTERY_THRESHOLD_PERCENT
}
