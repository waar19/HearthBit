package com.hearthbit.app.mesh

import com.hearthbit.app.transfer.TransferFrame
import com.hearthbit.app.transfer.TransferProtocol
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.security.MessageDigest

class ConformanceFixtureTest {
    @Test
    fun `decodifica frames positivos v1 v2 compresion y rechaza negativos`() {
        val v1 = requireNotNull(MeshProtocol.decode(fixtures.bytes("packet.v1.message")))
        assertEquals(1, v1.version.toInt())
        assertEquals(2, v1.type.toInt())
        assertEquals(7, v1.ttl.toInt())
        assertArrayEquals("abc".toByteArray(), v1.payload)

        val v2 = requireNotNull(MeshProtocol.decode(fixtures.bytes("packet.v2.route_signed")))
        assertEquals(2, v2.version.toInt())
        assertEquals(2, v2.route.size)
        assertArrayEquals(MeshProtocol.broadcastRecipient, v2.recipientId)
        assertEquals(64, v2.signature?.size)

        listOf("packet.v1.raw_deflate", "packet.v1.zlib_read").forEach { id ->
            val decoded = requireNotNull(MeshProtocol.decode(fixtures.bytes(id)))
            assertArrayEquals(ByteArray(180) { (it % 6).toByte() }, decoded.payload)
        }

        fixtures.ids("packet.invalid.").forEach { id ->
            assertNull("$id debe rechazarse", MeshProtocol.decode(fixtures.bytes(id)))
        }
    }

    @Test
    fun `la forma canonica usa el golden compartido`() {
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
            signature = ByteArray(64),
        )
        val canonical = packet.canonicalForSigning()

        assertArrayEquals(fixtures.bytes("signature.canonical.v1_announce"), canonical)
        assertEquals(0, canonical[2].toInt())
        assertEquals(
            "db232b00f54f6c161ab71e8756af799b2165d9f021cd4309aeb9ab203f2028af",
            MeshProtocol.hex(MessageDigest.getInstance("SHA-256").digest(canonical)),
        )
    }

    @Test
    fun `fragmentos compartidos validan formato limites y fuera de orden`() {
        val valid = requireNotNull(
            MeshProtocol.decodeFragmentPayload(fixtures.bytes("fragment.payload.valid")),
        )
        assertEquals(0x0102, valid.index)
        assertEquals(0x0304, valid.total)
        assertArrayEquals(byteArrayOf(0x55, 0x66), valid.data)
        assertNull(
            MeshProtocol.decodeFragmentPayload(fixtures.bytes("fragment.invalid.total_zero")),
        )
        assertNull(
            MeshProtocol.decodeFragmentPayload(
                fixtures.bytes("fragment.invalid.index_equal_total"),
            ),
        )

        val reassembler = MeshFragmentReassembler()
        val second = requireNotNull(
            MeshProtocol.decode(fixtures.bytes("fragment.reassemble.out_of_order.1")),
        )
        val first = requireNotNull(
            MeshProtocol.decode(fixtures.bytes("fragment.reassemble.out_of_order.0")),
        )
        assertNull(reassembler.accept(second))
        val result = requireNotNull(reassembler.accept(first))
        assertEquals(0, result.ttl.toInt())
        assertArrayEquals("abc".toByteArray(), result.payload)
    }

    @Test
    fun `GCS Courier y extensiones consumen fixtures comunes`() {
        val sync = requireNotNull(
            MeshProtocol.decodeSyncRequest(fixtures.bytes("gcs.request.two_packets")),
        )
        assertEquals(7, sync.p)
        assertEquals(256L, sync.m)
        assertArrayEquals(byteArrayOf(0x80.toByte(), 0xA7.toByte(), 0x80.toByte()), sync.filter)
        assertArrayEquals(longArrayOf(130, 210), MeshProtocol.decodeGcs(sync))
        assertNull(MeshProtocol.decodeSyncRequest(fixtures.bytes("gcs.invalid.p_zero")))

        val courier = requireNotNull(
            MeshProtocol.decodeCourierEnvelope(fixtures.bytes("courier.envelope.valid")),
        )
        assertEquals(1_725_000_060_000L, courier.expiry)
        assertEquals(96, courier.ciphertext.size)
        assertEquals(4, courier.copies)
        assertNull(
            MeshProtocol.decodeCourierEnvelope(fixtures.bytes("courier.invalid.truncated")),
        )

        assertArrayEquals(
            byteArrayOf(MeshProtocol.HBT_VERSION),
            fixtures.bytes("extension.hbt_capability.v1"),
        )
        val node = requireNotNull(
            NodeCapabilityProtocol.decode(fixtures.bytes("extension.node_capability.anchor")),
        )
        assertEquals(MeshNodeRole.INFRA_DATA_ANCHOR, node.role)
        assertEquals(1, node.flags.toInt())
        val radar = requireNotNull(
            RadarConsentProtocol.decode(fixtures.bytes("extension.radar_grant")),
        )
        assertEquals(RadarConsentProtocol.ACTION_GRANT, radar.action)
        val extension = requireNotNull(
            MeshProtocol.decodeExtensionEnvelope(fixtures.bytes("extension.envelope.hbit")),
        )
        assertEquals("HBIT", extension.namespace)
        assertEquals(1, extension.subtype)
        assertArrayEquals(byteArrayOf(1), extension.payload)
        assertNull(
            MeshProtocol.decodeExtensionEnvelope(fixtures.bytes("extension.envelope.truncated")),
        )
    }

    @Test
    fun `HBT usa el codec de produccion con positivos y negativos`() {
        val offerBytes = fixtures.bytes("hbt.offer.v1")
        val offer = requireNotNull(TransferFrame.decode(offerBytes))
        assertEquals(TransferProtocol.TYPE_OFFER, offer.type)
        assertEquals("foto.jpg", offer.utf8(TransferProtocol.TAG_FILE_NAME))
        assertEquals(1_048_576L, offer.u64(TransferProtocol.TAG_FILE_SIZE))
        assertArrayEquals(fixtures.bytes("hbt.offer.signed_bytes"), offer.signedBytes())

        val chunk = requireNotNull(TransferFrame.decode(fixtures.bytes("hbt.chunk.v1")))
        assertEquals(3L, chunk.u32(TransferProtocol.TAG_CHUNK_INDEX))
        assertArrayEquals(
            byteArrayOf(0xDE.toByte(), 0xAD.toByte(), 0xBE.toByte(), 0xEF.toByte()),
            chunk.tags[TransferProtocol.TAG_CHUNK_DATA],
        )
        assertNull(TransferFrame.decode(fixtures.bytes("hbt.invalid.version")))
        assertNull(TransferFrame.decode(fixtures.bytes("hbt.invalid.truncated")))
    }

    @Test
    fun `manifiesto fija commit upstream`() {
        assertTrue(fixtures.manifest.contains("5156f7de89ec9f6a3429630d90f709b68f6fd7fd"))
        assertFalse(fixtures.ids("").isEmpty())
    }

    private companion object {
        val fixtures = ConformanceFixtures.load()
    }
}

private class ConformanceFixtures private constructor(
    private val root: Path,
    val manifest: String,
    private val paths: Map<String, String>,
) {
    fun bytes(id: String): ByteArray {
        val relative = requireNotNull(paths[id]) { "Fixture desconocido: $id" }
        val hex = String(
            Files.readAllBytes(root.resolve(relative)),
            Charsets.US_ASCII,
        ).filterNot(Char::isWhitespace)
        require(hex.length % 2 == 0) { "Hex impar en $id" }
        return ByteArray(hex.length / 2) { index ->
            hex.substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
    }

    fun ids(prefix: String): List<String> = paths.keys.filter { it.startsWith(prefix) }.sorted()

    companion object {
        private val entry = Regex(
            """"id"\s*:\s*"([^"]+)".*"blob"\s*:\s*"([^"]+)"""",
        )

        fun load(): ConformanceFixtures {
            val start = Paths.get(System.getProperty("user.dir")).toAbsolutePath()
            val root = generateSequence(start) { it.parent }
                .map { it.resolve("tests").resolve("conformance") }
                .firstOrNull { Files.isDirectory(it) }
                ?: error("No se encontro tests/conformance desde $start")
            val manifest = String(
                Files.readAllBytes(root.resolve("fixtures.v1.json")),
                Charsets.UTF_8,
            )
            val paths = manifest.lineSequence().mapNotNull { line ->
                entry.find(line)?.destructured?.let { (id, blob) -> id to blob }
            }.toMap()
            return ConformanceFixtures(root, manifest, paths)
        }
    }
}
