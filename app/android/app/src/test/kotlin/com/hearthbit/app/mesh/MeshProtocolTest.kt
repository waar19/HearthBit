package com.hearthbit.app.mesh

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import java.security.MessageDigest

class MeshProtocolTest {
    @Test
    fun `codifica la cabecera v1 compatible con BitChat`() {
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_MESSAGE,
            ttl = 7,
            timestamp = 1,
            senderId = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8),
            payload = "abc".toByteArray(),
        )

        val encoded = MeshProtocol.encode(packet, padded = false)

        assertEquals(
            "01020700000000000000010000030102030405060708616263",
            MeshProtocol.hex(encoded),
        )
        val decoded = MeshProtocol.decode(encoded)
        assertNotNull(decoded)
        decoded!!
        assertEquals(packet.type, decoded.type)
        assertArrayEquals(packet.senderId, decoded.senderId)
        assertArrayEquals(packet.payload, decoded.payload)
    }

    @Test
    fun `la carga de mensajes coincide con el formato binario BitChat`() {
        val (_, payload) = MeshProtocol.encodePublicMessage(
            nickname = "Ana",
            peerId = "0102030405060708",
            content = "Estoy bien",
            id = "test-id",
            timestamp = 1234,
        )

        val decoded = MeshProtocol.decodePublicMessage(payload)
        assertNotNull(decoded)
        decoded!!
        assertEquals("test-id", decoded.id)
        assertEquals("Ana", decoded.sender)
        assertEquals("Estoy bien", decoded.content)
        assertEquals("0102030405060708", decoded.senderPeerId)
    }

    @Test
    fun `mensajes publicos actuales usan UTF-8 y aceptan el legado`() {
        val currentPayload = MeshProtocol.encodeInteropPublicMessage("Todo bien")
        assertArrayEquals("Todo bien".toByteArray(), currentPayload)

        val current = MeshProtocol.decodeCompatiblePublicMessage(
            payload = currentPayload,
            id = "packet-id",
            sender = "Ana",
            timestamp = 1234,
            senderPeerId = "0102030405060708",
        )
        assertEquals("packet-id", current.id)
        assertEquals("Todo bien", current.content)
        assertEquals("Ana", current.sender)

        val (_, legacyPayload) = MeshProtocol.encodePublicMessage(
            nickname = "Luis",
            peerId = "1112131415161718",
            content = "Formato anterior",
            id = "legacy-id",
            timestamp = 4321,
        )
        val legacy = MeshProtocol.decodeCompatiblePublicMessage(
            payload = legacyPayload,
            id = "ignored",
            sender = "ignored",
            timestamp = 0,
            senderPeerId = "ignored",
        )
        assertEquals("legacy-id", legacy.id)
        assertEquals("Formato anterior", legacy.content)
    }

    @Test
    fun `decodifica cargas comprimidas como BitChat actual`() {
        val payload = ByteArray(180) { (it % 6).toByte() }
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_ANNOUNCE,
            ttl = 7,
            timestamp = 1,
            senderId = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8),
            payload = payload,
        )

        val encoded = MeshProtocol.encode(packet, padded = false)
        assertEquals(0x04, encoded[11].toInt() and 0x04)

        val decoded = MeshProtocol.decode(encoded)
        assertNotNull(decoded)
        assertArrayEquals(payload, decoded!!.payload)
    }

    @Test
    fun `la forma canonica para firma fija TTL y usa padding BitChat`() {
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_ANNOUNCE,
            ttl = 7,
            timestamp = 1,
            senderId = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8),
            payload = ByteArray(120) { 0x2A },
            signature = ByteArray(64) { 1 },
        )

        val canonical = packet.canonicalForSigning()
        assertEquals(256, canonical.size)
        assertEquals(0, canonical[2].toInt())
        assertEquals(0, canonical[11].toInt() and 0x02)
        assertEquals(0x04, canonical[11].toInt() and 0x04)
    }

    @Test
    fun `la forma canonica coincide con el golden BitChat actual`() {
        val announcement = byteArrayOf(0x01, 0x03) +
            "bob".toByteArray() +
            byteArrayOf(0x02, 0x20) +
            ByteArray(32) { 0x11 } +
            byteArrayOf(0x03, 0x20) +
            ByteArray(32) { 0x22 }
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_ANNOUNCE,
            ttl = 7,
            timestamp = 0x0102030405060708,
            senderId = ByteArray(8) { (0x10 + it).toByte() },
            payload = announcement,
        )

        val canonical = packet.canonicalForSigning()
        val digest = MessageDigest.getInstance("SHA-256").digest(canonical)

        assertEquals(256, canonical.size)
        assertEquals(
            "db232b00f54f6c161ab71e8756af799b2165d9f021cd4309aeb9ab203f2028af",
            MeshProtocol.hex(digest),
        )
    }

    @Test
    fun `padding BLE solo se aplica a Noise`() {
        val base = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_ANNOUNCE,
            ttl = 7,
            timestamp = 1,
            senderId = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8),
            payload = "hola".toByteArray(),
        )

        assertEquals(26, MeshProtocol.encodeForBle(base).size)
        assertEquals(
            256,
            MeshProtocol.encodeForBle(base.copy(type = MeshProtocol.TYPE_NOISE_HANDSHAKE)).size,
        )
    }

    @Test
    fun `announcement tolera TLV de capacidades y gossip`() {
        val base = MeshProtocol.encodeAnnouncement(
            nickname = "Ana",
            noisePublicKey = ByteArray(32) { 2 },
            signingPublicKey = ByteArray(32) { 3 },
        )
        val extended = base +
            byteArrayOf(0x05, 0x02, 0x01, 0x00) +
            byteArrayOf(0x04, 0x08, 1, 2, 3, 4, 5, 6, 7, 8)

        val decoded = MeshProtocol.decodeAnnouncement(extended)
        assertNotNull(decoded)
        assertEquals("Ana", decoded!!.nickname)
    }
}
