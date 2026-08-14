package com.hearthbit.app.mesh

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PeerReachabilityPolicyTest {
    private val now = 1_000_000L

    @Test
    fun `mantiene online un peer dentro de cuatro minutos`() {
        assertTrue(
            PeerReachabilityPolicy.isOnline(
                now - PeerReachabilityPolicy.WINDOW_MS,
                now,
            ),
        )
        assertTrue(PeerReachabilityPolicy.isOnline(now - 90_000L, now))
    }

    @Test
    fun `marca offline y exige nueva epoca despues de la ventana`() {
        val stale = now - PeerReachabilityPolicy.WINDOW_MS - 1

        assertFalse(PeerReachabilityPolicy.isOnline(stale, now))
        assertFalse(
            PeerReachabilityPolicy.isSecure(
                stale,
                noiseEstablished = true,
                now = now,
            ),
        )
        assertTrue(PeerReachabilityPolicy.requiresTransportRekey(stale, now))
    }

    @Test
    fun `no reinicia peers nuevos ni anuncios normales`() {
        assertFalse(PeerReachabilityPolicy.requiresTransportRekey(null, now))
        assertFalse(
            PeerReachabilityPolicy.requiresTransportRekey(
                now - PeerReachabilityPolicy.WINDOW_MS,
                now,
            ),
        )
    }
}
