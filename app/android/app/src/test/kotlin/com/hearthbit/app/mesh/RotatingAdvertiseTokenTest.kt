package com.hearthbit.app.mesh

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RotatingAdvertiseTokenTest {
    private val secret = ByteArray(32) { it.toByte() }

    @Test
    fun `token remains stable inside one rotation window`() {
        val first = RotatingAdvertiseToken.serviceData(secret, 1_000L)
        val second = RotatingAdvertiseToken.serviceData(
            secret,
            RotatingAdvertiseToken.ROTATION_MS - 1,
        )

        assertArrayEquals(first, second)
        assertTrue(RotatingAdvertiseToken.isPrivateToken(first))
    }

    @Test
    fun `token changes across windows and secrets`() {
        val first = RotatingAdvertiseToken.serviceData(secret, 0L)
        val next = RotatingAdvertiseToken.serviceData(
            secret,
            RotatingAdvertiseToken.ROTATION_MS,
        )
        val otherSecret = RotatingAdvertiseToken.serviceData(
            ByteArray(32) { (it + 1).toByte() },
            0L,
        )

        assertNotEquals(first.toList(), next.toList())
        assertNotEquals(first.toList(), otherSecret.toList())
        assertFalse(RotatingAdvertiseToken.isPrivateToken(secret.copyOf(8)))
    }

    @Test
    fun `rotation delay reaches next boundary`() {
        assertTrue(RotatingAdvertiseToken.delayUntilRotation(0L) > 0)
        assertTrue(
            RotatingAdvertiseToken.delayUntilRotation(
                RotatingAdvertiseToken.ROTATION_MS - 1,
            ) <= 1L,
        )
    }
}
