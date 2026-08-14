package com.hearthbit.app.mesh

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NoiseReplayWindowTest {
    @Test
    fun `duplicate within window is rejected`() {
        val window = NoiseReplayWindow()
        window.recordAuthenticated(100)

        assertFalse(window.canAccept(100))
        assertTrue(window.canAccept(99))
        window.recordAuthenticated(99)
        assertFalse(window.canAccept(99))
    }

    @Test
    fun `old nonce stays rejected after more than 1024 messages`() {
        val window = NoiseReplayWindow()
        repeat(1_025) { nonce ->
            assertTrue(window.canAccept(nonce.toLong()))
            window.recordAuthenticated(nonce.toLong())
        }

        assertFalse(window.canAccept(0))
        assertFalse(window.canAccept(1))
        assertTrue(window.canAccept(1_025))
    }

    @Test
    fun `out of order messages are accepted once inside window`() {
        val window = NoiseReplayWindow()
        window.recordAuthenticated(1_100)

        assertTrue(window.canAccept(100))
        window.recordAuthenticated(100)
        assertFalse(window.canAccept(100))
        assertFalse(window.canAccept(76))
    }

    @Test
    fun `wire nonce is constrained to UInt32`() {
        val window = NoiseReplayWindow()

        assertFalse(window.canAccept(-1))
        assertTrue(window.canAccept(UInt.MAX_VALUE.toLong()))
        assertFalse(window.canAccept(UInt.MAX_VALUE.toLong() + 1))
    }
}
