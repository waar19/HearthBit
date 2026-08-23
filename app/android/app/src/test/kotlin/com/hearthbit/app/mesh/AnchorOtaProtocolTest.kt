package com.hearthbit.app.mesh

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class AnchorOtaProtocolTest {
    @Test
    fun `validates bundle and serves requested chunks`() {
        val image = ByteArray(1_000) { it.toByte() }
        val manifestBytes = manifestFor(image, version = 8, chunkSize = 384)
        val manifest = AnchorOtaProtocol.validateBundle(
            manifestBytes,
            image,
            currentVersion = 7,
        )

        assertEquals(8L, manifest.version)
        assertEquals(3, manifest.chunkCount)
        val request = ByteBuffer.allocate(8)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(8)
            .putInt(2)
            .array()
        val chunk = AnchorOtaProtocol.chunkFor(manifest, image, request)
        requireNotNull(chunk)
        assertEquals(2L, chunk.index)
        assertEquals(1_000, chunk.bytesSent)
        assertEquals(240, chunk.payload.size)
        assertArrayEquals(request, chunk.payload.copyOfRange(0, 8))
        assertArrayEquals(image.copyOfRange(768, 1_000), chunk.payload.copyOfRange(8, 240))
    }

    @Test
    fun `rejects stale corrupt and out of range data`() {
        val image = ByteArray(500) { it.toByte() }
        val manifestBytes = manifestFor(image, version = 8, chunkSize = 384)

        assertThrows(IllegalArgumentException::class.java) {
            AnchorOtaProtocol.validateBundle(manifestBytes, image, currentVersion = 8)
        }
        assertThrows(IllegalArgumentException::class.java) {
            AnchorOtaProtocol.validateBundle(
                manifestBytes,
                image.copyOf().also { it[0] = 99 },
                currentVersion = 7,
            )
        }
        assertNull(AnchorOtaProtocol.parseManifest(manifestBytes.copyOf(109)))

        val manifest = requireNotNull(AnchorOtaProtocol.parseManifest(manifestBytes))
        val invalidRequest = ByteBuffer.allocate(8)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(8)
            .putInt(2)
            .array()
        assertNull(AnchorOtaProtocol.chunkFor(manifest, image, invalidRequest))
        assertNull(AnchorOtaProtocol.parseStatus(byteArrayOf()))
        assertEquals(0xE1, AnchorOtaProtocol.parseStatus(byteArrayOf(0xE1.toByte())))
    }

    private fun manifestFor(image: ByteArray, version: Int, chunkSize: Int): ByteArray {
        val bytes = ByteArray(AnchorOtaProtocol.MANIFEST_LENGTH)
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        buffer.put("BOTA".toByteArray(Charsets.US_ASCII))
        buffer.putInt(version)
        buffer.putInt(image.size)
        buffer.put(MessageDigest.getInstance("SHA-256").digest(image))
        buffer.putShort(chunkSize.toShort())
        return bytes
    }
}
