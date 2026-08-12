package com.hearthbit.app.relay

import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager

internal data class BleCapabilities(
    val mode: RelayMode,
    val bluetoothEnabled: Boolean,
    val supportsAdvertising: Boolean,
)

internal class BleCapabilityDetector(private val context: Context) {
    fun detect(): BleCapabilities {
        val hasBle = context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)
        val adapter = context.getSystemService(BluetoothManager::class.java)?.adapter
        val enabled = runCatching { adapter?.isEnabled == true }.getOrDefault(false)
        val hasCentral = adapter != null && runCatching {
            adapter.bluetoothLeScanner
            true
        }.getOrDefault(false)
        val supportsAdvertising = adapter != null &&
            runCatching {
                adapter.isMultipleAdvertisementSupported &&
                    adapter.bluetoothLeAdvertiser != null
            }.getOrDefault(false)

        return BleCapabilities(
            mode = RelayModePolicy.select(hasBle, hasCentral, supportsAdvertising),
            bluetoothEnabled = enabled,
            supportsAdvertising = supportsAdvertising,
        )
    }
}
