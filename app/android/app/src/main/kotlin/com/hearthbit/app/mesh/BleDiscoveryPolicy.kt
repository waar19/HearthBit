package com.hearthbit.app.mesh

internal object ReconnectBackoffPolicy {
    private val delaysMs = longArrayOf(1_000L, 2_000L, 4_000L, 8_000L, 16_000L, 30_000L)

    const val MAX_FAILED_ATTEMPTS = 6
    const val COOLDOWN_MS = 120_000L

    fun delayMs(failedAttempts: Int, urgent: Boolean = false): Long =
        if (urgent) 0L else delaysMs[failedAttempts.coerceIn(0, delaysMs.lastIndex)]

    fun shouldEnterCooldown(failedAttempts: Int): Boolean =
        failedAttempts >= MAX_FAILED_ATTEMPTS
}

internal data class OverflowDiscoverySettings(
    val maximumCandidates: Int,
    val cooldownMs: Long,
)

internal object OverflowDiscoveryPolicy {
    const val NORMAL_MAXIMUM_CANDIDATES = 1
    const val URGENT_MAXIMUM_CANDIDATES = 2
    const val NORMAL_COOLDOWN_MS = 5 * 60_000L
    const val URGENT_COOLDOWN_MS = 60_000L

    fun shouldConsiderCandidate(
        hasDisconnectedKnownPeer: Boolean,
        radarActive: Boolean,
        rescueActive: Boolean,
    ): Boolean = hasDisconnectedKnownPeer || radarActive || rescueActive

    fun settings(radarActive: Boolean, rescueActive: Boolean): OverflowDiscoverySettings =
        if (radarActive || rescueActive) {
            OverflowDiscoverySettings(
                maximumCandidates = URGENT_MAXIMUM_CANDIDATES,
                cooldownMs = URGENT_COOLDOWN_MS,
            )
        } else {
            OverflowDiscoverySettings(
                maximumCandidates = NORMAL_MAXIMUM_CANDIDATES,
                cooldownMs = NORMAL_COOLDOWN_MS,
            )
        }
}
