package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StoreForwardRetentionPolicyTest {
    @Test
    fun `retention is capped at one hundred newest entries`() {
        val retained = StoreForwardRetentionPolicy.retain(
            entries = (0..100).map { index ->
                item("normal-$index", expiry = 1_000L + index)
            },
            now = 0L,
        )

        assertEquals(100, retained.size)
        assertFalse(retained.any { it.value == "normal-0" })
        assertTrue(retained.any { it.value == "normal-100" })
    }

    @Test
    fun `emergency and normal entries receive twenty four and twelve hours`() {
        val now = 1_000L

        assertEquals(
            now + 12 * 60 * 60 * 1_000L,
            StoreForwardRetentionPolicy.expiryAt(now, emergency = false),
        )
        assertEquals(
            now + 24 * 60 * 60 * 1_000L,
            StoreForwardRetentionPolicy.expiryAt(now, emergency = true),
        )
    }

    @Test
    fun `emergency entry evicts normal traffic when cache is saturated`() {
        val entries = (0 until 100).map { index ->
            item("normal-$index", expiry = 1_000L + index)
        } + item("emergency", expiry = 500L, emergency = true)

        val retained = StoreForwardRetentionPolicy.retain(entries, now = 0L)

        assertEquals(100, retained.size)
        assertTrue(retained.any { it.value == "emergency" })
        assertFalse(retained.any { it.value == "normal-0" })
    }

    @Test
    fun `expired and non replay safe entries are discarded`() {
        val retained = StoreForwardRetentionPolicy.retain(
            entries = listOf(
                item("expired", expiry = 100L),
                item("noise", expiry = 200L, replaySafe = false),
                item("valid", expiry = 200L),
            ),
            now = 100L,
        )

        assertEquals(listOf("valid"), retained.map { it.value })
    }

    @Test
    fun `noise beacon ranging and their fragments are not replay safe`() {
        val blockedTypes = listOf(
            MeshProtocol.TYPE_NOISE_HANDSHAKE,
            MeshProtocol.TYPE_NOISE_ENCRYPTED,
            MeshProtocol.TYPE_BEACON_CONTROL,
            MeshProtocol.TYPE_RANGING_CONTROL,
        )

        blockedTypes.forEach { type ->
            assertFalse(StoreForwardRetentionPolicy.isPacketReplaySafe(type))
            assertFalse(
                StoreForwardRetentionPolicy.isPacketReplaySafe(
                    packetType = MeshProtocol.TYPE_FRAGMENT,
                    fragmentedOriginalType = type,
                ),
            )
        }
        assertTrue(StoreForwardRetentionPolicy.isPacketReplaySafe(MeshProtocol.TYPE_MESSAGE))
    }

    private fun item(
        value: String,
        expiry: Long,
        emergency: Boolean = false,
        replaySafe: Boolean = true,
    ) = StoreForwardRetentionItem(
        expiry = expiry,
        value = value,
        emergency = emergency,
        replaySafe = replaySafe,
    )
}
