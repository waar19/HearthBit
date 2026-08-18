package com.hearthbit.app.mesh

/**
 * Presupuesto global de frames open-emergency nuevos. Las relaciones conocidas
 * y desconocidas consumen ventanas independientes.
 */
internal class OpenEmergencyRateLimiter(
    private val knownMaximumPackets: Int = DEFAULT_KNOWN_MAXIMUM_PACKETS,
    private val unknownMaximumPackets: Int = DEFAULT_UNKNOWN_MAXIMUM_PACKETS,
    private val windowMs: Long = DEFAULT_WINDOW_MS,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private data class Window(var startedAt: Long, var packets: Int)

    private var knownWindow: Window? = null
    private var unknownWindow: Window? = null
    private var knownRateLimited = 0L
    private var unknownRateLimited = 0L

    init {
        require(knownMaximumPackets > 0)
        require(unknownMaximumPackets > 0)
        require(windowMs > 0)
    }

    @Synchronized
    fun allow(
        knownRelationship: Boolean,
        now: Long = clock(),
    ): Boolean {
        val current = if (knownRelationship) knownWindow else unknownWindow
        val maximum = if (knownRelationship) knownMaximumPackets else unknownMaximumPackets
        if (current == null || now < current.startedAt || now - current.startedAt >= windowMs) {
            val replacement = Window(startedAt = now, packets = 1)
            if (knownRelationship) {
                knownWindow = replacement
            } else {
                unknownWindow = replacement
            }
            return true
        }
        if (current.packets >= maximum) {
            if (knownRelationship) {
                knownRateLimited += 1
            } else {
                unknownRateLimited += 1
            }
            return false
        }
        current.packets += 1
        return true
    }

    /** Contadores acumulados durante la vida de esta instancia. */
    @Synchronized
    fun operationalCounters(): Map<String, Long> = mapOf(
        "openSosRateLimitedKnown" to knownRateLimited,
        "openSosRateLimitedUnknown" to unknownRateLimited,
    )

    @Synchronized
    fun clear() {
        knownWindow = null
        unknownWindow = null
    }

    @Synchronized
    fun reset() {
        clear()
        knownRateLimited = 0L
        unknownRateLimited = 0L
    }

    companion object {
        const val DEFAULT_KNOWN_MAXIMUM_PACKETS = 600
        const val DEFAULT_UNKNOWN_MAXIMUM_PACKETS = 240
        const val DEFAULT_WINDOW_MS = 60_000L
    }
}
