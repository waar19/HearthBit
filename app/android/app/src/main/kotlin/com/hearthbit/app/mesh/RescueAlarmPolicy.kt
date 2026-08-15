package com.hearthbit.app.mesh

internal object RescueAlarmPolicy {
    const val MAX_RADIO_RETRY_MS = 60_000L

    fun nextDue(
        lastPingAt: Long,
        intervalMs: Long,
        now: Long,
    ): Long = if (lastPingAt > 0L) {
        saturatedAdd(lastPingAt, intervalMs.coerceAtLeast(0L))
    } else {
        now
    }

    fun shouldPing(
        active: Boolean,
        expiresAt: Long,
        nextDueAt: Long,
        now: Long,
    ): Boolean = active && now < expiresAt && now >= nextDueAt

    fun nextWakeAt(
        active: Boolean,
        expiresAt: Long,
        nextDueAt: Long,
        now: Long,
    ): Long? {
        if (!active || now >= expiresAt) return null
        return minOf(nextDueAt.coerceAtLeast(now), expiresAt)
    }

    fun retryWhenRadioUnavailable(
        now: Long,
        intervalMs: Long,
        expiresAt: Long,
    ): Long? {
        if (now >= expiresAt) return null
        val retryDelay = intervalMs
            .coerceAtLeast(1L)
            .coerceAtMost(MAX_RADIO_RETRY_MS)
        return minOf(saturatedAdd(now, retryDelay), expiresAt)
    }

    private fun saturatedAdd(value: Long, increment: Long): Long {
        if (increment <= 0L) return value
        return if (value > Long.MAX_VALUE - increment) Long.MAX_VALUE else value + increment
    }
}
