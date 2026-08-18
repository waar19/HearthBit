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
    fun `radar reconnect bypasses accumulated backoff`() {
        assertEquals(0L, ReconnectBackoffPolicy.delayMs(50, urgent = true))
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

    @Test
    fun `neighbor selection prioritizes known relationship before rssi`() {
        val selection = BleNeighborSelectionPolicy.select(
            maximumConnections = 8,
            active = emptyList(),
            discovered = listOf(
                neighbor("unknown", rssi = -35),
                neighbor("known", rssi = -70, known = true),
            ),
        )

        assertEquals("known", selection?.connectAddress)
        assertEquals(null, selection?.replaceAddress)
    }

    @Test
    fun `neighbor replacement requires rssi hysteresis`() {
        val active = listOf(neighbor("weak", rssi = -70))

        assertEquals(
            null,
            BleNeighborSelectionPolicy.select(
                maximumConnections = 1,
                active = active,
                discovered = listOf(neighbor("candidate", rssi = -63)),
            ),
        )
        assertEquals(
            BleNeighborSelection("candidate", "weak"),
            BleNeighborSelectionPolicy.select(
                maximumConnections = 1,
                active = active,
                discovered = listOf(neighbor("candidate", rssi = -62)),
            ),
        )
    }

    @Test
    fun `known relationship replaces unknown before comparing rssi`() {
        assertEquals(
            BleNeighborSelection("known", "unknown"),
            BleNeighborSelectionPolicy.select(
                maximumConnections = 1,
                active = listOf(neighbor("unknown", rssi = -35)),
                discovered = listOf(neighbor("known", rssi = -90, known = true)),
            ),
        )
    }

    @Test
    fun `unknown neighbor cannot replace known or protected link`() {
        assertEquals(
            null,
            BleNeighborSelectionPolicy.select(
                maximumConnections = 1,
                active = listOf(neighbor("known", rssi = -90, known = true)),
                discovered = listOf(neighbor("unknown", rssi = -30)),
            ),
        )
        assertEquals(
            null,
            BleNeighborSelectionPolicy.select(
                maximumConnections = 1,
                active = listOf(neighbor("transfer", rssi = -90, protected = true)),
                discovered = listOf(neighbor("candidate", rssi = -30, known = true)),
            ),
        )
    }

    @Test
    fun `server limit rejects excess unknown and admits known deterministically`() {
        val active = listOf(
            serverCandidate("BB", known = false),
            serverCandidate("AA", known = false),
            serverCandidate("known", known = true),
        )

        assertEquals(
            ServerConnectionAdmission(accepted = false),
            ServerConnectionLimitPolicy.admit(
                maximumConnections = 3,
                active = active,
                incoming = serverCandidate("new-unknown", known = false),
            ),
        )
        assertEquals(
            ServerConnectionAdmission(accepted = true, replaceAddress = "AA"),
            ServerConnectionLimitPolicy.admit(
                maximumConnections = 3,
                active = active,
                incoming = serverCandidate("new-known", known = true),
            ),
        )
    }

    @Test
    fun `server limit does not evict protected unknown link`() {
        val admission = ServerConnectionLimitPolicy.admit(
            maximumConnections = 1,
            active = listOf(serverCandidate("busy", known = false, protected = true)),
            incoming = serverCandidate("known", known = true),
        )

        assertFalse(admission.accepted)
        assertEquals(null, admission.replaceAddress)
    }

    private fun neighbor(
        address: String,
        rssi: Int,
        known: Boolean = false,
        protected: Boolean = false,
    ) = BleNeighborCandidate(
        address = address,
        rssi = rssi,
        knownRelationship = known,
        protected = protected,
    )

    private fun serverCandidate(
        address: String,
        known: Boolean,
        protected: Boolean = false,
    ) = ServerConnectionCandidate(
        address = address,
        knownRelationship = known,
        protected = protected,
    )
}
