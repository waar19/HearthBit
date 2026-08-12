package com.hearthbit.app.transfer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

private const val GOLDEN_OFFER_HEX =
    "010101001000112233445566778899aabbccddeeff020008666f746f2e6a7067" +
        "03000a696d6167652f6a706567040008000000000010000005002001020304050607" +
        "08090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f2006000400010000" +
        "07000400000007080020a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7" +
        "b8b9babbbcbdbebf0900080000019af232b2000a000811223344556677880b0040" +
        "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" +
        "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

private const val GOLDEN_SIGNED_HEX =
    "010101001000112233445566778899aabbccddeeff020008666f746f2e6a7067" +
        "03000a696d6167652f6a706567040008000000000010000005002001020304050607" +
        "08090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f2006000400010000" +
        "07000400000007080020a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7" +
        "b8b9babbbcbdbebf0900080000019af232b2000a00081122334455667788"

private const val GOLDEN_CHUNK_HEX =
    "011001001000112233445566778899aabbccddeeff0f000400000003100004deadbeef"

private fun ByteArray.toHex() = joinToString("") { "%02x".format(it) }

private fun String.fromHex(): ByteArray =
    chunked(2).map { it.toInt(16).toByte() }.toByteArray()

private fun goldenOffer(): TransferFrame {
    val frame = TransferFrame(TransferProtocol.TYPE_OFFER)
    frame.tags[TransferProtocol.TAG_TRANSFER_ID] =
        ByteArray(16) { index -> ((index * 0x11) and 0xFF).toByte() }
    frame.setUtf8(TransferProtocol.TAG_FILE_NAME, "foto.jpg")
    frame.setUtf8(TransferProtocol.TAG_MIME_TYPE, "image/jpeg")
    frame.setU64(TransferProtocol.TAG_FILE_SIZE, 1_048_576L)
    frame.tags[TransferProtocol.TAG_SHA256] = ByteArray(32) { index -> (index + 1).toByte() }
    frame.setU32(TransferProtocol.TAG_CHUNK_SIZE, 65_536L)
    frame.setU32(TransferProtocol.TAG_TRANSPORTS, 7L)
    frame.tags[TransferProtocol.TAG_EPHEMERAL_KEY] =
        ByteArray(32) { index -> (0xA0 + index).toByte() }
    frame.setU64(TransferProtocol.TAG_EXPIRES_AT, 1_765_000_000_000L)
    frame.tags[TransferProtocol.TAG_SENDER_PEER_ID] =
        byteArrayOf(0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88.toByte())
    frame.tags[TransferProtocol.TAG_SIGNATURE] = ByteArray(64) { 0xEE.toByte() }
    return frame
}

class TransferProtocolTest {
    @Test
    fun `la oferta golden coincide con el vector Dart`() {
        assertEquals(GOLDEN_OFFER_HEX, goldenOffer().encode().toHex())
    }

    @Test
    fun `los bytes firmados excluyen el TLV de firma`() {
        assertEquals(GOLDEN_SIGNED_HEX, goldenOffer().signedBytes().toHex())
    }

    @Test
    fun `el chunk golden coincide con el vector Dart`() {
        val frame = TransferFrame(TransferProtocol.TYPE_DATA_CHUNK)
        frame.tags[TransferProtocol.TAG_TRANSFER_ID] =
            ByteArray(16) { index -> ((index * 0x11) and 0xFF).toByte() }
        frame.setU32(TransferProtocol.TAG_CHUNK_INDEX, 3L)
        frame.tags[TransferProtocol.TAG_CHUNK_DATA] =
            byteArrayOf(0xDE.toByte(), 0xAD.toByte(), 0xBE.toByte(), 0xEF.toByte())
        assertEquals(GOLDEN_CHUNK_HEX, frame.encode().toHex())
    }

    @Test
    fun `decodifica la oferta golden con todos los campos`() {
        val frame = TransferFrame.decode(GOLDEN_OFFER_HEX.fromHex())
        assertNotNull(frame)
        frame!!
        assertEquals(TransferProtocol.TYPE_OFFER, frame.type)
        assertEquals("foto.jpg", frame.utf8(TransferProtocol.TAG_FILE_NAME))
        assertEquals("image/jpeg", frame.utf8(TransferProtocol.TAG_MIME_TYPE))
        assertEquals(1_048_576L, frame.u64(TransferProtocol.TAG_FILE_SIZE))
        assertEquals(65_536L, frame.u32(TransferProtocol.TAG_CHUNK_SIZE))
        assertEquals(7L, frame.u32(TransferProtocol.TAG_TRANSPORTS))
        assertEquals(1_765_000_000_000L, frame.u64(TransferProtocol.TAG_EXPIRES_AT))
        assertEquals(32, frame.tags.getValue(TransferProtocol.TAG_SHA256).size)
        assertEquals(64, frame.tags.getValue(TransferProtocol.TAG_SIGNATURE).size)
    }

    @Test
    fun `rechaza versiones desconocidas y tramas truncadas`() {
        val bad = GOLDEN_OFFER_HEX.fromHex()
        bad[0] = 0x02
        assertNull(TransferFrame.decode(bad))
        assertNull(TransferFrame.decode(GOLDEN_OFFER_HEX.fromHex().copyOfRange(0, 10)))
    }
}
