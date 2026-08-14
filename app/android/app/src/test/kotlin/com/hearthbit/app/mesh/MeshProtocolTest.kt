package com.hearthbit.app.mesh

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.MessageDigest

class MeshProtocolTest {
    @Test
    fun `ACK de emergencia es versionado y ligado al hash canonico`() {
        val emergency = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_MESSAGE,
            ttl = 7,
            timestamp = 1234,
            senderId = ByteArray(8) { it.toByte() },
            payload = "SOS|Ayuda||".toByteArray(),
            signature = ByteArray(64) { 7 },
        )
        val relayed = emergency.copy(ttl = 2, isRsr = true)

        val originalHash = MeshProtocol.emergencyCanonicalHash(emergency)
        val relayedHash = MeshProtocol.emergencyCanonicalHash(relayed)
        val payload = MeshProtocol.encodeEmergencyAcknowledgement(originalHash)

        assertArrayEquals(originalHash, relayedHash)
        assertArrayEquals(
            originalHash,
            MeshProtocol.decodeEmergencyAcknowledgement(payload),
        )
        assertTrue(MeshProtocol.isEmergencyPublicPacket(emergency))
        assertTrue(
            MeshProtocol.supportsEmergencyAcknowledgements(
                MeshProtocol.encodeEmergencyCapability(),
            ),
        )
    }

    @Test
    fun `FragmentPayload coincide con el formato binario BitChat`() {
        val encoded = MeshProtocol.encodeFragmentPayload(
            MeshProtocol.FragmentPayload(
                fragmentId = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8),
                index = 0x0102,
                total = 0x0304,
                originalType = MeshProtocol.TYPE_MESSAGE,
                data = byteArrayOf(0x55, 0x66),
            ),
        )

        assertEquals(
            "010203040506070801020304025566",
            MeshProtocol.hex(encoded),
        )
        val decoded = MeshProtocol.decodeFragmentPayload(encoded)
        assertNotNull(decoded)
        decoded!!
        assertArrayEquals(byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8), decoded.fragmentId)
        assertEquals(0x0102, decoded.index)
        assertEquals(0x0304, decoded.total)
        assertEquals(MeshProtocol.TYPE_MESSAGE, decoded.originalType)
        assertArrayEquals(byteArrayOf(0x55, 0x66), decoded.data)
    }

    @Test
    fun `FragmentPayload rechaza truncar contadores UInt16`() {
        assertThrows(IllegalArgumentException::class.java) {
            MeshProtocol.encodeFragmentPayload(
                MeshProtocol.FragmentPayload(
                    fragmentId = ByteArray(8),
                    index = 0,
                    total = 65_536,
                    originalType = MeshProtocol.TYPE_MESSAGE,
                    data = byteArrayOf(1),
                ),
            )
        }
    }

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
    fun `fingerprint de relay ignora TTL RSR y padding`() {
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_NOISE_ENCRYPTED,
            ttl = 7,
            timestamp = 1,
            senderId = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8),
            payload = ByteArray(40) { it.toByte() },
        )
        val live = MeshProtocol.encode(packet, padded = false)
        val replay = MeshProtocol.encode(
            packet.copy(ttl = 2, isRsr = true),
            padded = true,
        )

        assertEquals(
            MeshProtocol.relayFingerprint(live),
            MeshProtocol.relayFingerprint(replay),
        )
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
    fun `announcement compatible no emite extension HBT desconocida`() {
        val base = MeshProtocol.encodeAnnouncement(
            nickname = "Ana",
            noisePublicKey = ByteArray(32) { 2 },
            signingPublicKey = ByteArray(32) { 3 },
        )

        assertEquals(76, base.size)
        assertArrayEquals(byteArrayOf(0x05, 0x01, 0x00), base.takeLast(3).toByteArray())
        assertEquals(false, MeshProtocol.decodeAnnouncement(base)!!.supportsTransfers)
    }

    @Test
    fun `announcement tolera extension HBT de builds intermedios`() {
        val base = MeshProtocol.encodeAnnouncement(
            nickname = "Ana",
            noisePublicKey = ByteArray(32) { 2 },
            signingPublicKey = ByteArray(32) { 3 },
        )
        val extended = base +
            byteArrayOf(0x05, 0x02, 0x01, 0x00) +
            byteArrayOf(0x04, 0x08, 1, 2, 3, 4, 5, 6, 7, 8) +
            byteArrayOf(0xF0.toByte(), 0x01, MeshProtocol.HBT_VERSION)

        val decoded = MeshProtocol.decodeAnnouncement(extended)
        assertNotNull(decoded)
        assertEquals("Ana", decoded!!.nickname)
        assertEquals(true, decoded.supportsTransfers)
    }

    @Test
    fun `paquete de capacidad HBT sobrevive ida y vuelta`() {
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_HBT_CAPABILITY,
            ttl = MeshProtocol.TTL,
            timestamp = 1234,
            senderId = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8),
            payload = byteArrayOf(MeshProtocol.HBT_VERSION),
        )

        val decoded = MeshProtocol.decode(MeshProtocol.encodeForBle(packet))

        assertNotNull(decoded)
        assertEquals(MeshProtocol.TYPE_HBT_CAPABILITY, decoded!!.type)
        assertArrayEquals(byteArrayOf(MeshProtocol.HBT_VERSION), decoded.payload)
    }

    @Test
    fun `announcement sin HBT identifica clientes BitChat`() {
        val legacy = byteArrayOf(0x01, 0x03) +
            "Bob".toByteArray() +
            byteArrayOf(0x02, 0x20) +
            ByteArray(32) { 2 } +
            byteArrayOf(0x03, 0x20) +
            ByteArray(32) { 3 }

        val decoded = MeshProtocol.decodeAnnouncement(legacy)

        assertNotNull(decoded)
        assertEquals(false, decoded!!.supportsTransfers)
    }

    @Test
    fun `v2 conserva la ruta y el flag RSR`() {
        val route = listOf(
            ByteArray(8) { (0x10 + it).toByte() },
            ByteArray(8) { (0x20 + it).toByte() },
        )
        val packet = MeshProtocol.Packet(
            version = 2,
            type = MeshProtocol.TYPE_MESSAGE,
            ttl = 7,
            timestamp = 1,
            senderId = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8),
            payload = "abc".toByteArray(),
            route = route,
            isRsr = true,
        )

        val encoded = MeshProtocol.encode(packet, padded = false)
        val decoded = MeshProtocol.decode(encoded)

        assertEquals(0x18, encoded[11].toInt() and 0x18)
        assertNotNull(decoded)
        assertEquals(2, decoded!!.route.size)
        assertArrayEquals(route[0], decoded.route[0])
        assertArrayEquals(route[1], decoded.route[1])
        assertTrue(decoded.isRsr)
        assertArrayEquals(packet.canonicalForSigning(), decoded.canonicalForSigning())
    }

    @Test
    fun `GCS de REQUEST_SYNC coincide en ida y vuelta`() {
        val packets = listOf(
            MeshProtocol.Packet(
                type = MeshProtocol.TYPE_ANNOUNCE,
                ttl = 7,
                timestamp = 10,
                senderId = ByteArray(8) { 1 },
                payload = byteArrayOf(1, 2, 3),
                signature = ByteArray(64),
            ),
            MeshProtocol.Packet(
                type = MeshProtocol.TYPE_MESSAGE,
                ttl = 7,
                timestamp = 20,
                senderId = ByteArray(8) { 2 },
                payload = "mensaje".toByteArray(),
                signature = ByteArray(64),
            ),
        )

        val request = MeshProtocol.decodeSyncRequest(MeshProtocol.encodeSyncRequest(packets))

        assertNotNull(request)
        request!!
        assertEquals(7, request.p)
        assertEquals(256L, request.m)
        assertEquals("80a780", MeshProtocol.hex(request.filter))
        assertEquals(
            "ae4957e8d0f5471154cea28a49c463f9",
            MeshProtocol.hex(MeshProtocol.packetId(packets[0])),
        )
        assertEquals(
            "9d60512dfc3037e980c7cac61577fca5",
            MeshProtocol.hex(MeshProtocol.packetId(packets[1])),
        )
        val decodedBuckets = MeshProtocol.decodeGcs(request)
        packets.forEach {
            assertTrue(
                MeshProtocol.gcsContains(
                    decodedBuckets,
                    MeshProtocol.gcsBucket(MeshProtocol.packetId(it), request.m),
                ),
            )
        }
    }

    @Test
    fun `Courier mantiene el ciphertext opaco y rota etiqueta diaria`() {
        val recipientKey = ByteArray(32) { it.toByte() }
        val ciphertext = ByteArray(96) { (it * 3).toByte() }
        val now = 1_725_000_000_000L
        val payload = MeshProtocol.encodeCourierEnvelope(
            recipientNoiseKey = recipientKey,
            ciphertext = ciphertext,
            now = now,
            expiry = now + 60_000,
        )

        val envelope = MeshProtocol.decodeCourierEnvelope(payload)

        assertNotNull(envelope)
        envelope!!
        assertArrayEquals(ciphertext, envelope.ciphertext)
        assertTrue(MeshProtocol.courierEnvelopeIsFor(envelope, recipientKey, now))
        assertFalse(
            MeshProtocol.courierEnvelopeIsFor(
                envelope,
                ByteArray(32) { (it + 1).toByte() },
                now,
            ),
        )
        assertFalse(MeshProtocol.courierEnvelopeIsFor(envelope, recipientKey, now + 60_000))
    }
}
