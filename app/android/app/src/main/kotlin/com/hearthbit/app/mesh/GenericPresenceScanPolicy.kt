package com.hearthbit.app.mesh

internal enum class GenericPresenceScanPhase {
    SCANNING,
    PAUSED,
}

/**
 * Ciclo fijo del escaneo BLE sin filtro. No depende del perfil adaptativo de
 * la malla para que habilitar presencias tenga el mismo coste en todo perfil.
 */
internal object GenericPresenceScanPolicy {
    const val SCAN_DURATION_MS = 10_000L
    const val PAUSE_DURATION_MS = 50_000L

    fun nextPhase(
        current: GenericPresenceScanPhase,
        enabled: Boolean,
        engineRunning: Boolean,
    ): GenericPresenceScanPhase? {
        if (!enabled || !engineRunning) return null
        return when (current) {
            GenericPresenceScanPhase.SCANNING -> GenericPresenceScanPhase.PAUSED
            GenericPresenceScanPhase.PAUSED -> GenericPresenceScanPhase.SCANNING
        }
    }

    fun durationMs(phase: GenericPresenceScanPhase): Long = when (phase) {
        GenericPresenceScanPhase.SCANNING -> SCAN_DURATION_MS
        GenericPresenceScanPhase.PAUSED -> PAUSE_DURATION_MS
    }
}
