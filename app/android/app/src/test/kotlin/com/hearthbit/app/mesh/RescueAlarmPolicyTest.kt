package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RescueAlarmPolicyTest {
    @Test
    fun `native rescue default matches five minute channel contract`() {
        assertEquals(300_000L, RescueModeStore.DEFAULT_INTERVAL_MS)
    }

    @Test
    fun `sticky restart immediately resumes overdue persisted ping`() {
        val dueAt = RescueAlarmPolicy.nextDue(
            lastPingAt = 1_000L,
            intervalMs = 500L,
            now = 1_600L,
        )

        assertEquals(1_500L, dueAt)
        assertTrue(
            RescueAlarmPolicy.shouldPing(
                active = true,
                expiresAt = 10_000L,
                nextDueAt = dueAt,
                now = 1_600L,
            ),
        )
    }

    @Test
    fun `sticky restart schedules future persisted ping without duplicating it`() {
        val dueAt = RescueAlarmPolicy.nextDue(
            lastPingAt = 1_500L,
            intervalMs = 500L,
            now = 1_500L,
        )

        assertEquals(2_000L, dueAt)
        assertFalse(
            RescueAlarmPolicy.shouldPing(
                active = true,
                expiresAt = 10_000L,
                nextDueAt = dueAt,
                now = 1_500L,
            ),
        )
        assertEquals(
            2_000L,
            RescueAlarmPolicy.nextWakeAt(
                active = true,
                expiresAt = 10_000L,
                nextDueAt = dueAt,
                now = 1_500L,
            ),
        )
    }

    @Test
    fun `sticky restart ignores expired persisted rescue`() {
        assertFalse(
            RescueAlarmPolicy.shouldPing(
                active = true,
                expiresAt = 2_000L,
                nextDueAt = 1_500L,
                now = 2_000L,
            ),
        )
        assertNull(
            RescueAlarmPolicy.nextWakeAt(
                active = true,
                expiresAt = 2_000L,
                nextDueAt = 1_500L,
                now = 2_000L,
            ),
        )
    }

    @Test
    fun `radio unavailable retry is capped and respects expiration`() {
        assertEquals(
            70_000L,
            RescueAlarmPolicy.retryWhenRadioUnavailable(
                now = 10_000L,
                intervalMs = 120_000L,
                expiresAt = 200_000L,
            ),
        )
        assertEquals(
            40_000L,
            RescueAlarmPolicy.retryWhenRadioUnavailable(
                now = 10_000L,
                intervalMs = 30_000L,
                expiresAt = 200_000L,
            ),
        )
        assertEquals(
            20_000L,
            RescueAlarmPolicy.retryWhenRadioUnavailable(
                now = 10_000L,
                intervalMs = 120_000L,
                expiresAt = 20_000L,
            ),
        )
    }

    @Test
    fun `timestamp arithmetic saturates instead of overflowing`() {
        assertEquals(
            Long.MAX_VALUE,
            RescueAlarmPolicy.nextDue(
                lastPingAt = Long.MAX_VALUE - 10L,
                intervalMs = 50L,
                now = Long.MAX_VALUE - 20L,
            ),
        )
        assertEquals(
            Long.MAX_VALUE,
            RescueAlarmPolicy.retryWhenRadioUnavailable(
                now = Long.MAX_VALUE - 10L,
                intervalMs = 60_000L,
                expiresAt = Long.MAX_VALUE,
            ),
        )
    }
}
