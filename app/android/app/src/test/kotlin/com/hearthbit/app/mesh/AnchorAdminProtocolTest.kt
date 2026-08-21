package com.hearthbit.app.mesh

import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AnchorAdminProtocolTest {
    @Test
    fun `request and response preserve command and request id`() {
        val request = AnchorAdminProtocol.request(
            AnchorAdminProtocol.STATUS_GET,
            0x12345678,
        )
        assertArrayEquals(
            byteArrayOf(1, 1, 0x12, 0x34, 0x56, 0x78),
            request,
        )
        assertEquals(0x12345678, AnchorAdminProtocol.requestId(request))
        assertNull(AnchorAdminProtocol.requestId(byteArrayOf(1, 1, 0)))

        val response = AnchorAdminProtocol.parseResponse(
            byteArrayOf(1, 0x81.toByte(), 0x12, 0x34, 0x56, 0x78, 0),
        )
        assertNotNull(response)
        assertEquals(AnchorAdminProtocol.STATUS_GET, response?.command)
        assertEquals(0x12345678, response?.requestId)
        assertEquals(0, response?.status)
    }

    @Test
    fun `authenticated request signs header nonce and data`() {
        val verifier = ByteArray(32) { (it + 1).toByte() }
        val nonce = ByteArray(16) { (0xA0 + it).toByte() }
        val data = AnchorAdminProtocol.renameData("Anchor Norte")
        val request = AnchorAdminProtocol.authenticatedRequest(
            AnchorAdminProtocol.RENAME,
            7,
            nonce,
            data,
            verifier,
        )
        val signed = request.copyOfRange(0, request.size - 32)
        val mac = Mac.getInstance("HmacSHA256").apply {
            init(SecretKeySpec(verifier, "HmacSHA256"))
        }
        assertArrayEquals(mac.doFinal(signed), request.copyOfRange(signed.size, request.size))
        assertArrayEquals(nonce, request.copyOfRange(6, 22))
        assertArrayEquals(data, request.copyOfRange(22, signed.size))
    }

    @Test
    fun `challenge and status parse strict firmware layout`() {
        val challengeBody = ByteBuffer.allocate(41)
            .order(ByteOrder.BIG_ENDIAN)
            .put(1)
            .put(ByteArray(16) { it.toByte() })
            .put(ByteArray(16) { (it + 16).toByte() })
            .putInt(120_000)
            .putInt(30)
            .array()
        val challenge = AnchorAdminProtocol.parseChallenge(challengeBody)
        assertTrue(challenge?.claimed == true)
        assertEquals(120_000, challenge?.iterations)
        assertEquals(30L, challenge?.retryAfterSeconds)

        val nickname = "Anchor Norte".toByteArray()
        val statusBody = ByteBuffer.allocate(97 + nickname.size)
            .order(ByteOrder.BIG_ENDIAN)
            .put(1)
            .putInt(6)
            .putInt(1)
            .apply { repeat(10) { putLong((it + 1).toLong()) } }
            .putShort(12)
            .putShort(128)
            .put(1)
            .put(1)
            .put(0)
            .put(nickname.size.toByte())
            .put(nickname)
            .array()
        val status = AnchorAdminProtocol.parseStatus(statusBody)
        assertNotNull(status)
        assertEquals(6L, status?.firmwareVersion)
        assertEquals(1L, status?.uptimeMs)
        assertEquals(10L, status?.lastActivityUptimeMs)
        assertEquals(12, status?.mailboxUsed)
        assertEquals("Anchor Norte", status?.nickname)
        assertTrue(status?.clockValid == true)
        assertFalse(status?.clockAuthoritative == true)
    }

    @Test
    fun `pbkdf verifier is deterministic and malformed frames are rejected`() {
        val password = "rescate-seguro".toCharArray()
        val salt = ByteArray(16) { (it * 3).toByte() }
        val first = AnchorAdminProtocol.deriveVerifier(password, salt, 120_000)
        val second = AnchorAdminProtocol.deriveVerifier(password, salt, 120_000)
        assertArrayEquals(first, second)
        assertEquals(32, first.size)
        assertNull(AnchorAdminProtocol.parseResponse(byteArrayOf(1, 1, 0)))
        assertNull(AnchorAdminProtocol.parseChallenge(ByteArray(40)))
        assertNull(AnchorAdminProtocol.parseStatus(ByteArray(96)))
    }
}
