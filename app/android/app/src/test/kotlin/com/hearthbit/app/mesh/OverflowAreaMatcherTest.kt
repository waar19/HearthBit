package com.hearthbit.app.mesh

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OverflowAreaMatcherTest {
    @Test
    fun `extrae mascara de anuncio Apple overflow`() {
        val mask = ByteArray(16)
        mask[3] = 0x20
        val payload = byteArrayOf(0x01) + mask

        assertArrayEquals(mask, OverflowAreaMatcher.extractMask(payload))
    }

    @Test
    fun `rechaza datos Apple que no son overflow`() {
        assertNull(OverflowAreaMatcher.extractMask(byteArrayOf(0x02) + ByteArray(16)))
        assertNull(OverflowAreaMatcher.extractMask(byteArrayOf(0x01, 0x00)))
    }

    @Test
    fun `consulta y aprende un unico bit de servicio`() {
        val mask = ByteArray(16)
        mask[5] = 0x04

        assertTrue(OverflowAreaMatcher.hasAnyService(mask))
        assertTrue(OverflowAreaMatcher.matchesBit(mask, 42))
        assertFalse(OverflowAreaMatcher.matchesBit(mask, 41))
        assertEquals(42, OverflowAreaMatcher.singleSetBit(mask))
    }

    @Test
    fun `no aprende cuando varios servicios comparten el anuncio`() {
        val mask = ByteArray(16)
        mask[0] = 0x01
        mask[15] = 0x80.toByte()

        assertNull(OverflowAreaMatcher.singleSetBit(mask))
    }
}
