package com.hearthbit.app.mesh

/**
 * Decide sobre qué enlaces GATT leer RSSI durante el radar de rescate.
 *
 * Algunos enlaces quedan "zombis": el stack acepta `readRemoteRssi()` pero
 * nunca entrega el callback (observado en campo con iOS tras rotación de
 * dirección). Este planificador acumula strikes por dirección, aparta las
 * no-responsivas con reintento espaciado, habilita lecturas tentativas
 * cuando no queda ningún enlace mapeado utilizable y avisa cuando el radar
 * lleva demasiado tiempo sin producir ninguna muestra.
 */
internal class RadarReadPlanner(
    private val unresponsiveAfterStrikes: Int = UNRESPONSIVE_AFTER_STRIKES,
    private val retryUnresponsiveAfterMs: Long = RETRY_UNRESPONSIVE_AFTER_MS,
    private val maxTentativeReads: Int = MAX_TENTATIVE_READS,
    private val diagnosticAfterMs: Long = DIAGNOSTIC_AFTER_MS,
) {
    data class Plan(
        /** Direcciones mapeadas al objetivo que vale la pena leer ahora. */
        val mapped: List<String>,
        /** Direcciones sin resolver para lecturas tentativas. */
        val tentative: List<String>,
    )

    private val strikes = HashMap<String, Int>()
    private val unresponsiveRetryAt = HashMap<String, Long>()
    private var started = false
    private var startedAt = 0L
    private var lastSampleAt = 0L
    private var lastDiagnosticAt = 0L

    @Synchronized
    fun start(now: Long) {
        clear()
        started = true
        startedAt = now
    }

    @Synchronized
    fun clear() {
        strikes.clear()
        unresponsiveRetryAt.clear()
        started = false
        startedAt = 0L
        lastSampleAt = 0L
        lastDiagnosticAt = 0L
    }

    @Synchronized
    fun plan(
        now: Long,
        mappedAddresses: Collection<String>,
        unresolvedReadyAddresses: Collection<String>,
    ): Plan {
        val mapped = mappedAddresses.filter { isReadable(it, now) }
        val tentative = if (mapped.isEmpty()) {
            unresolvedReadyAddresses
                .filter { isReadable(it, now) }
                .take(maxTentativeReads)
        } else {
            emptyList()
        }
        return Plan(mapped, tentative)
    }

    /**
     * Registra un intento de lectura. Devuelve true si la dirección acaba de
     * quedar marcada como no-responsiva (para que el llamador lo registre).
     */
    @Synchronized
    fun recordReadAttempt(address: String, accepted: Boolean, now: Long): Boolean {
        val weight = if (accepted) 1 else 2
        val total = (strikes[address] ?: 0) + weight
        strikes[address] = total
        if (total < unresponsiveAfterStrikes) return false
        strikes.remove(address)
        val alreadyMarked = unresponsiveRetryAt.containsKey(address)
        unresponsiveRetryAt[address] = now + retryUnresponsiveAfterMs
        return !alreadyMarked
    }

    /** Un callback RSSI exitoso rehabilita la dirección. */
    @Synchronized
    fun recordCallbackSuccess(address: String) {
        strikes.remove(address)
        unresponsiveRetryAt.remove(address)
    }

    /** Una lectura del objetivo llegó a la interfaz; reinicia el diagnóstico. */
    @Synchronized
    fun recordSampleEmitted(now: Long) {
        lastSampleAt = now
    }

    /**
     * true cuando el radar lleva demasiado sin muestras y toca avisar a la UI.
     * Se auto-limita para no repetir el aviso en cada ciclo.
     */
    @Synchronized
    fun diagnosticDue(now: Long): Boolean {
        if (!started) return false
        val reference = maxOf(startedAt, lastSampleAt, lastDiagnosticAt)
        if (now - reference < diagnosticAfterMs) return false
        lastDiagnosticAt = now
        return true
    }

    private fun isReadable(address: String, now: Long): Boolean {
        val retryAt = unresponsiveRetryAt[address] ?: return true
        if (now < retryAt) return false
        // Reintento espaciado: una sola lectura y vuelve a esperar.
        unresponsiveRetryAt[address] = now + retryUnresponsiveAfterMs
        return true
    }

    companion object {
        /** ~3 s a una lectura cada 500 ms. */
        const val UNRESPONSIVE_AFTER_STRIKES = 6
        const val RETRY_UNRESPONSIVE_AFTER_MS = 10_000L
        const val MAX_TENTATIVE_READS = 3
        const val DIAGNOSTIC_AFTER_MS = 10_000L
    }
}
