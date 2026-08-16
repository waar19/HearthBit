package com.hearthbit.app.mesh

internal object EmergencyTransportEscalation {
    fun channels(
        ble: Boolean,
        lan: Boolean,
        wifiDirect: Boolean,
        wifiAware: Boolean,
    ): List<String> = buildList {
        if (ble) add("ble")
        if (lan) add("lan")
        if (wifiDirect) add("wifiDirect")
        if (wifiAware) add("wifiAware")
    }
}
