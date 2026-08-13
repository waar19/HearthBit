package com.hearthbit.app.mesh

internal enum class MeshScanHealthAction {
    NONE,
    START,
    RESTART,
}

internal object MeshScanHealthPolicy {
    const val WATCHDOG_INTERVAL_MS = 60_000L
    const val CONTINUOUS_SCAN_CYCLE_MS = 20 * 60_000L
    const val STALE_SCAN_RESULT_MS = 3 * 60_000L
    const val MINIMUM_SCAN_START_INTERVAL_MS = 7_000L

    fun actionFor(
        shouldScanContinuously: Boolean,
        isScanning: Boolean,
        now: Long,
        scanStartedAt: Long,
        lastResultAt: Long,
        expectsKnownPeer: Boolean,
    ): MeshScanHealthAction {
        if (!shouldScanContinuously) return MeshScanHealthAction.NONE
        if (!isScanning || scanStartedAt <= 0L) return MeshScanHealthAction.START
        if (now - scanStartedAt >= CONTINUOUS_SCAN_CYCLE_MS) {
            return MeshScanHealthAction.RESTART
        }

        val lastEvidenceAt = maxOf(scanStartedAt, lastResultAt)
        if (expectsKnownPeer && now - lastEvidenceAt >= STALE_SCAN_RESULT_MS) {
            return MeshScanHealthAction.RESTART
        }
        return MeshScanHealthAction.NONE
    }

    fun retryDelayMs(attempt: Int, now: Long, lastScanStartAt: Long): Long {
        val boundedAttempt = attempt.coerceIn(1, 5)
        val backoff = MINIMUM_SCAN_START_INTERVAL_MS * boundedAttempt
        val rateLimitRemainder =
            (MINIMUM_SCAN_START_INTERVAL_MS - (now - lastScanStartAt)).coerceAtLeast(0L)
        return maxOf(backoff, rateLimitRemainder)
    }
}

internal object MeshKeepAlivePolicy {
    private const val NORMAL_INTERVAL_MS = 30_000L
    private const val SAVING_INTERVAL_MS = 90_000L

    fun intervalMs(profile: PowerProfile, hasActiveLink: Boolean): Long? {
        if (!hasActiveLink) return null
        return when (profile) {
            PowerProfile.PERFORMANCE,
            PowerProfile.BALANCED,
            -> NORMAL_INTERVAL_MS

            PowerProfile.POWER_SAVER,
            PowerProfile.CRITICAL,
            PowerProfile.SURVIVAL,
            -> SAVING_INTERVAL_MS
        }
    }
}
