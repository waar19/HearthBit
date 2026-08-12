package com.hearthbit.app.relay

internal enum class RelayMode {
    DUAL_ROLE,
    CENTRAL_ONLY,
    UNAVAILABLE,
}

internal object RelayModePolicy {
    fun select(
        hasBleHardware: Boolean,
        hasGattCentral: Boolean,
        supportsAdvertising: Boolean,
    ): RelayMode = when {
        !hasBleHardware || !hasGattCentral -> RelayMode.UNAVAILABLE
        supportsAdvertising -> RelayMode.DUAL_ROLE
        else -> RelayMode.CENTRAL_ONLY
    }
}
