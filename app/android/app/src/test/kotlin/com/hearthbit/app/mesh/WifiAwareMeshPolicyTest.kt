package com.hearthbit.app.mesh

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WifiAwareMeshPolicyTest {
    @Test
    fun `solo activa Aware compatible durante rescate`() {
        assertTrue(WifiAwareMeshPolicy.shouldRun(rescueActive = true, supported = true))
        assertFalse(WifiAwareMeshPolicy.shouldRun(rescueActive = false, supported = true))
        assertFalse(WifiAwareMeshPolicy.shouldRun(rescueActive = true, supported = false))
    }

    @Test
    fun `follow up admite exclusivamente frames cortos`() {
        assertTrue(WifiAwareMeshPolicy.acceptsFrame(ByteArray(255) { 1 }))
        assertFalse(WifiAwareMeshPolicy.acceptsFrame(ByteArray(0)))
        assertFalse(WifiAwareMeshPolicy.acceptsFrame(ByteArray(256) { 1 }))
    }
}
