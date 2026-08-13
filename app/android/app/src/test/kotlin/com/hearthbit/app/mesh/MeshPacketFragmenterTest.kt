package com.hearthbit.app.mesh

import java.util.Random
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshPacketFragmenterTest {
    private val sender = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8)
    private val fragmentId = byteArrayOf(9, 8, 7, 6, 5, 4, 3, 2)

    @Test
    fun `calcula el payload ATT disponible desde el MTU`() {
        assertEquals(20, MeshPacketFragmenter.maximumGattValueSize(23))
        assertEquals(182, MeshPacketFragmenter.maximumGattValueSize(185))
        assertEquals(512, MeshPacketFragmenter.maximumGattValueSize(517))
        assertEquals(512, MeshPacketFragmenter.maximumGattValueSize(1_000))
    }

    @Test
    fun `conserva sin cambios un paquete que cabe en el enlace`() {
        val encoded = MeshProtocol.encodeForBle(packet(payloadSize = 8))
        val frames = fragmenter().prepare(encoded, encoded.size)

        assertNotNull(frames)
        assertEquals(1, frames!!.size)
        assertArrayEquals(encoded, frames.single())
    }

    @Test
    fun `fragmenta con formato BitChat y reensambla fuera de orden`() {
        val original = packet(
            payloadSize = 700,
            version = 2,
            recipient = MeshProtocol.broadcastRecipient,
            route = listOf(
                ByteArray(8) { (0x10 + it).toByte() },
                ByteArray(8) { (0x20 + it).toByte() },
            ),
            signature = ByteArray(64) { 0x55 },
        )
        val encoded = MeshProtocol.encodeForBle(original)
        val frames = fragmenter().prepare(encoded, 100)

        assertNotNull(frames)
        assertTrue(frames!!.size > 1)
        val decodedFragments = frames.map { frame ->
            assertTrue(frame.size <= 100)
            val fragment = MeshProtocol.decode(frame)
            assertNotNull(fragment)
            fragment!!
        }
        decodedFragments.forEachIndexed { index, fragment ->
            assertEquals(MeshProtocol.TYPE_FRAGMENT, fragment.type)
            assertNull(fragment.signature)
            assertArrayEquals(fragmentId, fragment.payload.copyOfRange(0, 8))
            assertEquals(index, unsignedShort(fragment.payload, 8))
            assertEquals(decodedFragments.size, unsignedShort(fragment.payload, 10))
            assertEquals(MeshProtocol.TYPE_MESSAGE, fragment.payload[12])
        }

        val reassembler = MeshFragmentReassembler()
        var reassembled: MeshProtocol.Packet? = null
        decodedFragments.reversed().forEach {
            reassembled = reassembler.accept(it) ?: reassembled
        }

        assertNotNull(reassembled)
        reassembled!!
        assertEquals(MeshProtocol.TYPE_MESSAGE, reassembled.type)
        assertEquals(0, reassembled.ttl.toInt())
        assertArrayEquals(original.payload, reassembled.payload)
        assertArrayEquals(original.signature, reassembled.signature)
        assertEquals(original.route.size, reassembled.route.size)
        assertEquals(MeshProtocol.fingerprint(original), MeshProtocol.fingerprint(reassembled))
    }

    @Test
    fun `no fragmenta un fragmento que no cabe`() {
        val existingFragment = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_FRAGMENT,
            ttl = MeshProtocol.TTL,
            timestamp = 1,
            senderId = sender,
            payload = ByteArray(200) { it.toByte() },
        )

        assertNull(fragmenter().prepare(MeshProtocol.encodeForBle(existingFragment), 100))
    }

    @Test
    fun `el padding BLE de Noise no altera el paquete reensamblado`() {
        val original = packet(payloadSize = 40).copy(type = MeshProtocol.TYPE_NOISE_HANDSHAKE)
        val padded = MeshProtocol.encodeForBle(original)
        assertEquals(256, padded.size)

        val frames = fragmenter().prepare(padded, 100)

        assertNotNull(frames)
        assertEquals(1, frames!!.size)
        assertTrue(frames.single().size <= 100)
        val fragment = MeshProtocol.decode(frames.single())!!
        assertEquals(MeshProtocol.TYPE_FRAGMENT, fragment.type)
        val reassembled = MeshFragmentReassembler().accept(fragment)
        assertNotNull(reassembled)
        assertEquals(MeshProtocol.TYPE_NOISE_HANDSHAKE, reassembled!!.type)
        assertArrayEquals(original.payload, reassembled.payload)
    }

    @Test
    fun `admite 256 fragments y rechaza 257`() {
        val random = Random(0xB17C4A7)
        val largestAcceptedPayload =
            MeshPacketFragmenter.MAX_FRAGMENT_DATA_SIZE * MeshPacketFragmenter.MAX_FRAGMENTS - 24
        val acceptedPayload = ByteArray(largestAcceptedPayload).also(random::nextBytes)
        val rejectedPayload = acceptedPayload + 1
        val accepted = MeshProtocol.encodeForBle(
            packet(payload = acceptedPayload, version = 2),
        )
        val rejected = MeshProtocol.encodeForBle(
            packet(payload = rejectedPayload, version = 2),
        )

        val acceptedFrames = fragmenter().prepare(accepted, 512)

        assertNotNull(acceptedFrames)
        assertEquals(256, acceptedFrames!!.size)
        assertTrue(acceptedFrames.all { it.size <= 512 })
        assertNull(fragmenter().prepare(rejected, 512))
    }

    @Test
    fun `usa IDs distintos para envios independientes`() {
        val fragmenter = MeshPacketFragmenter()
        val encoded = MeshProtocol.encodeForBle(packet(payloadSize = 700))

        val first = fragmenter.prepare(encoded, 100)!!
        val second = fragmenter.prepare(encoded, 100)!!
        val firstId = MeshProtocol.decode(first.first())!!.payload.copyOfRange(0, 8)
        val secondId = MeshProtocol.decode(second.first())!!.payload.copyOfRange(0, 8)

        assertFalse(firstId.contentEquals(secondId))
    }

    private fun fragmenter(): MeshPacketFragmenter = MeshPacketFragmenter { fragmentId.copyOf() }

    private fun packet(
        payloadSize: Int = 0,
        payload: ByteArray = ByteArray(payloadSize) { (it * 31).toByte() },
        version: Byte = 1,
        recipient: ByteArray? = null,
        route: List<ByteArray> = emptyList(),
        signature: ByteArray? = null,
    ): MeshProtocol.Packet = MeshProtocol.Packet(
        version = version,
        type = MeshProtocol.TYPE_MESSAGE,
        ttl = MeshProtocol.TTL,
        timestamp = 1234,
        senderId = sender,
        recipientId = recipient,
        payload = payload,
        signature = signature,
        route = route,
    )

    private fun unsignedShort(bytes: ByteArray, offset: Int): Int =
        ((bytes[offset].toInt() and 0xFF) shl 8) or
            (bytes[offset + 1].toInt() and 0xFF)
}
