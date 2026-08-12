package com.emergencycom.emergency_com.mesh

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

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
}
