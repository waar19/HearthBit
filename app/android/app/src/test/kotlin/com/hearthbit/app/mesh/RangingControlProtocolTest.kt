package com.hearthbit.app.mesh

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RangingControlProtocolTest {
    @Test
    fun `round trips signed ranging payload fields`() {
        val control = RangingControlProtocol.Control(
            action = RangingControlProtocol.ACTION_RESULT,
            technology = RangingControlProtocol.TECHNOLOGY_ACOUSTIC,
            sessionNonce = ByteArray(16) { it.toByte() },
            round = 2,
            value = 3.25,
            errorMeters = 0.15f,
            confidence = 0.88f,
            opaqueData = byteArrayOf(1, 2, 3),
        )

        val decoded = requireNotNull(
            RangingControlProtocol.decode(RangingControlProtocol.encode(control)),
        )

        assertEquals(control.action, decoded.action)
        assertEquals(control.technology, decoded.technology)
        assertEquals(control.round, decoded.round)
        assertEquals(control.value, decoded.value, 0.0001)
        assertEquals(control.errorMeters, decoded.errorMeters, 0.0001f)
        assertEquals(control.confidence, decoded.confidence, 0.0001f)
        assertArrayEquals(control.sessionNonce, decoded.sessionNonce)
        assertArrayEquals(control.opaqueData, decoded.opaqueData)
    }

    @Test
    fun `rejects truncated or oversized payloads`() {
        assertNull(RangingControlProtocol.decode(ByteArray(10)))
        val oversized = ByteArray(
            RangingControlProtocol.FIXED_SIZE +
                RangingControlProtocol.MAX_OPAQUE_BYTES + 1,
        )
        oversized[0] = RangingControlProtocol.VERSION
        assertNull(RangingControlProtocol.decode(oversized))
    }

    @Test
    fun `rejects ranging control from a stale transport epoch`() {
        val now = 1_000_000L
        assertEquals(true, RangingControlProtocol.hasValidTimestamp(now, now))
        assertEquals(
            false,
            RangingControlProtocol.hasValidTimestamp(
                now - RangingControlProtocol.CLOCK_SKEW_MS - 1,
                now,
            ),
        )
    }
}
