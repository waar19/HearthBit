package com.hearthbit.app.mesh

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NoiseReplayPolicyTest {
    @Test
    fun `acepta Noise cuando aun no hay anuncio de referencia`() {
        assertTrue(NoiseReplayPolicy.isCurrent(packetTimestamp = 100L, latestAnnouncementTimestamp = null))
    }

    @Test
    fun `rechaza paquetes de una epoca anterior al ultimo anuncio`() {
        assertFalse(NoiseReplayPolicy.isCurrent(packetTimestamp = 99L, latestAnnouncementTimestamp = 100L))
        assertTrue(NoiseReplayPolicy.isCurrent(packetTimestamp = 100L, latestAnnouncementTimestamp = 100L))
        assertTrue(NoiseReplayPolicy.isCurrent(packetTimestamp = 101L, latestAnnouncementTimestamp = 100L))
    }
}
