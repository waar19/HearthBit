package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BleDiscoveryPolicyTest {
    @Test
    fun `reconnect uses bounded exponential delays`() {
        assertEquals(1_000L, ReconnectBackoffPolicy.delayMs(0))
        assertEquals(2_000L, ReconnectBackoffPolicy.delayMs(1))
        assertEquals(4_000L, ReconnectBackoffPolicy.delayMs(2))
        assertEquals(8_000L, ReconnectBackoffPolicy.delayMs(3))
        assertEquals(16_000L, ReconnectBackoffPolicy.delayMs(4))
        assertEquals(30_000L, ReconnectBackoffPolicy.delayMs(5))
        assertEquals(30_000L, ReconnectBackoffPolicy.delayMs(50))
    }

    @Test
    fun `six failed reconnects trigger a two minute cooldown`() {
        assertFalse(ReconnectBackoffPolicy.shouldEnterCooldown(5))
        assertTrue(ReconnectBackoffPolicy.shouldEnterCooldown(6))
        assertEquals(120_000L, ReconnectBackoffPolicy.COOLDOWN_MS)
    }

    @Test
    fun `radar and rescue may inspect first contact overflow candidates`() {
        assertFalse(
            OverflowDiscoveryPolicy.shouldConsiderCandidate(
                hasDisconnectedKnownPeer = false,
                radarActive = false,
                rescueActive = false,
            ),
        )
        assertTrue(
            OverflowDiscoveryPolicy.shouldConsiderCandidate(
                hasDisconnectedKnownPeer = false,
                radarActive = true,
                rescueActive = false,
            ),
        )
        assertTrue(
            OverflowDiscoveryPolicy.shouldConsiderCandidate(
                hasDisconnectedKnownPeer = false,
                radarActive = false,
                rescueActive = true,
            ),
        )
    }

    @Test
    fun `urgent discovery allows two candidates with a shorter cooldown`() {
        val normal = OverflowDiscoveryPolicy.settings(
            radarActive = false,
            rescueActive = false,
        )
        val urgent = OverflowDiscoveryPolicy.settings(
            radarActive = true,
            rescueActive = false,
        )

        assertEquals(1, normal.maximumCandidates)
        assertEquals(5 * 60_000L, normal.cooldownMs)
        assertEquals(2, urgent.maximumCandidates)
        assertEquals(60_000L, urgent.cooldownMs)
    }
}
