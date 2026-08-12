package com.hearthbit.app.relay

import android.content.Context
import android.os.PowerManager

internal object VehicleOperationGate {
    private const val PREFERENCES = "relay_runtime"
    private const val ACTIVE_SESSION = "vehicle_session_active"

    fun setSessionActive(context: Context, active: Boolean) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(ACTIVE_SESSION, active)
            .apply()
    }

    fun permitsRelay(context: Context): Boolean {
        val sessionActive = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(ACTIVE_SESSION, false)
        val displayInteractive = context.getSystemService(PowerManager::class.java)?.isInteractive == true
        return sessionActive && displayInteractive
    }
}
