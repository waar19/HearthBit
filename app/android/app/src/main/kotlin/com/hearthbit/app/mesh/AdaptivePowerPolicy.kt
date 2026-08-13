package com.hearthbit.app.mesh

import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanSettings

internal enum class PowerProfile(
    val wireName: String,
    val scanMode: Int?,
    val scanBurstMs: Long,
    val scanPauseMs: Long,
    val advertiseMode: Int,
    val advertiseTxPower: Int,
    val maximumClientConnections: Int,
) {
    PERFORMANCE(
        wireName = "performance",
        scanMode = ScanSettings.SCAN_MODE_LOW_LATENCY,
        scanBurstMs = 0L,
        scanPauseMs = 0L,
        advertiseMode = AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY,
        advertiseTxPower = AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM,
        maximumClientConnections = Int.MAX_VALUE,
    ),
    BALANCED(
        wireName = "balanced",
        scanMode = ScanSettings.SCAN_MODE_BALANCED,
        scanBurstMs = 0L,
        scanPauseMs = 0L,
        advertiseMode = AdvertiseSettings.ADVERTISE_MODE_BALANCED,
        advertiseTxPower = AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM,
        maximumClientConnections = Int.MAX_VALUE,
    ),
    POWER_SAVER(
        wireName = "powerSaver",
        scanMode = ScanSettings.SCAN_MODE_LOW_POWER,
        scanBurstMs = 10_000L,
        scanPauseMs = 50_000L,
        advertiseMode = AdvertiseSettings.ADVERTISE_MODE_LOW_POWER,
        advertiseTxPower = AdvertiseSettings.ADVERTISE_TX_POWER_LOW,
        maximumClientConnections = Int.MAX_VALUE,
    ),
    CRITICAL(
        wireName = "critical",
        scanMode = ScanSettings.SCAN_MODE_LOW_POWER,
        scanBurstMs = 5_000L,
        scanPauseMs = 115_000L,
        advertiseMode = AdvertiseSettings.ADVERTISE_MODE_LOW_POWER,
        advertiseTxPower = AdvertiseSettings.ADVERTISE_TX_POWER_LOW,
        maximumClientConnections = 3,
    ),
    SURVIVAL(
        wireName = "survival",
        scanMode = null,
        scanBurstMs = 0L,
        scanPauseMs = 0L,
        advertiseMode = AdvertiseSettings.ADVERTISE_MODE_LOW_POWER,
        advertiseTxPower = AdvertiseSettings.ADVERTISE_TX_POWER_LOW,
        maximumClientConnections = 0,
    );

    val usesDutyCycle: Boolean get() = scanBurstMs > 0L && scanPauseMs > 0L
    val savesPower: Boolean get() = this != PERFORMANCE && this != BALANCED
}

internal object AdaptivePowerPolicy {
    fun profileFor(
        batteryPercent: Int,
        isCharging: Boolean,
        screenOn: Boolean,
        survivalMode: Boolean,
    ): PowerProfile {
        val battery = batteryPercent.coerceIn(0, 100)
        return when {
            survivalMode || battery < 10 -> PowerProfile.SURVIVAL
            isCharging -> PowerProfile.PERFORMANCE
            battery < 20 -> PowerProfile.CRITICAL
            battery <= 40 || !screenOn -> PowerProfile.POWER_SAVER
            else -> PowerProfile.BALANCED
        }
    }
}
