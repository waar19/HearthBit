package com.hearthbit.app.mesh

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OpenEmergencyRateLimiterTest {
    @Test
    fun `accepts a burst of one hundred SOS frames`() {
        val limiter = OpenEmergencyRateLimiter()

        repeat(100) {
            assertTrue(limiter.allow(knownRelationship = false, now = 1_000L))
        }
    }

    @Test
    fun `unknown relationships stop at two hundred forty frames`() {
        val limiter = OpenEmergencyRateLimiter()

        repeat(240) {
            assertTrue(limiter.allow(knownRelationship = false, now = 1_000L))
        }
        assertFalse(limiter.allow(knownRelationship = false, now = 1_000L))
        assertTrue(
            limiter.operationalCounters() == mapOf(
                "openEmergencyRateLimitedKnown" to 0L,
                "openEmergencyRateLimitedUnknown" to 1L,
            ),
        )
    }

    @Test
    fun `known relationship budget remains independent`() {
        val limiter = OpenEmergencyRateLimiter(
            knownMaximumPackets = 3,
            unknownMaximumPackets = 2,
        )

        assertTrue(limiter.allow(knownRelationship = false, now = 1_000L))
        assertTrue(limiter.allow(knownRelationship = false, now = 1_000L))
        assertFalse(limiter.allow(knownRelationship = false, now = 1_000L))
        repeat(3) {
            assertTrue(limiter.allow(knownRelationship = true, now = 1_000L))
        }
        assertFalse(limiter.allow(knownRelationship = true, now = 1_000L))
        assertTrue(
            limiter.operationalCounters() == mapOf(
                "openEmergencyRateLimitedKnown" to 1L,
                "openEmergencyRateLimitedUnknown" to 1L,
            ),
        )
    }

    @Test
    fun `reset and injected clock open fresh windows`() {
        var now = 5_000L
        val limiter = OpenEmergencyRateLimiter(
            knownMaximumPackets = 1,
            unknownMaximumPackets = 1,
            windowMs = 100L,
            clock = { now },
        )

        assertTrue(limiter.allow(knownRelationship = false))
        assertFalse(limiter.allow(knownRelationship = false))
        limiter.reset()
        assertTrue(limiter.operationalCounters().values.all { it == 0L })
        assertTrue(limiter.allow(knownRelationship = false))
        assertFalse(limiter.allow(knownRelationship = false))
        now += 100L
        assertTrue(limiter.allow(knownRelationship = false))
    }
}
