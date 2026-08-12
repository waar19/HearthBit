package com.hearthbit.app.transfer

import java.io.ByteArrayOutputStream

/**
 * Codec del HearthBit Transfer Protocol (HBT) v1.
 *
 * Formato: `[versión u8][tipo u8][TLV...]` con TLV `[tag u8][len u16][valor]`
 * big-endian y tags en orden ascendente. Debe producir exactamente los mismos
 * bytes que el codec Dart (`transfer_protocol.dart`) y el Swift
 * (`HearthBitTransferProtocol.swift`). Ver `docs/transfer-protocol.md`.
 */
internal object TransferProtocol {
    const val VERSION: Int = 0x01

    const val TYPE_OFFER = 0x01
    const val TYPE_ACCEPT = 0x02
    const val TYPE_REJECT = 0x03
    const val TYPE_TRANSPORT_HINT = 0x04
    const val TYPE_PROGRESS = 0x05
    const val TYPE_COMPLETE = 0x06
    const val TYPE_CANCEL = 0x07
    const val TYPE_RESUME_REQUEST = 0x08
    const val TYPE_DATA_CHUNK = 0x10
    const val TYPE_DATA_ACK = 0x11

    const val TAG_TRANSFER_ID = 0x01
    const val TAG_FILE_NAME = 0x02
    const val TAG_MIME_TYPE = 0x03
    const val TAG_FILE_SIZE = 0x04
    const val TAG_SHA256 = 0x05
    const val TAG_CHUNK_SIZE = 0x06
    const val TAG_TRANSPORTS = 0x07
    const val TAG_EPHEMERAL_KEY = 0x08
    const val TAG_EXPIRES_AT = 0x09
    const val TAG_SENDER_PEER_ID = 0x0A
    const val TAG_SIGNATURE = 0x0B
    const val TAG_TRANSPORT = 0x0C
    const val TAG_ENDPOINT = 0x0D
    const val TAG_TOKEN = 0x0E
    const val TAG_CHUNK_INDEX = 0x0F
    const val TAG_CHUNK_DATA = 0x10
    const val TAG_CHUNK_BITMAP = 0x11
    const val TAG_REASON = 0x12
    const val TAG_RECEIVED_COUNT = 0x14
}

internal class TransferFrame(
    val type: Int,
    val tags: MutableMap<Int, ByteArray> = mutableMapOf(),
) {
    fun encode(): ByteArray {
        val output = ByteArrayOutputStream()
        output.write(TransferProtocol.VERSION)
        output.write(type)
        for (tag in tags.keys.sorted()) {
            val value = tags.getValue(tag)
            require(value.size <= 0xFFFF) { "TLV $tag exceeds 65535 bytes" }
            output.write(tag)
            output.write(value.size ushr 8)
            output.write(value.size and 0xFF)
            output.write(value)
        }
        return output.toByteArray()
    }

    /** Bytes cubiertos por la firma Ed25519 (sin el TLV SIGNATURE). */
    fun signedBytes(): ByteArray {
        val unsigned = TransferFrame(type, tags.toMutableMap())
        unsigned.tags.remove(TransferProtocol.TAG_SIGNATURE)
        return unsigned.encode()
    }

    fun utf8(tag: Int): String? = tags[tag]?.toString(Charsets.UTF_8)

    fun u8(tag: Int): Int? = tags[tag]?.takeIf { it.size == 1 }?.let { it[0].toInt() and 0xFF }

    fun u32(tag: Int): Long? = tags[tag]?.takeIf { it.size == 4 }?.let { value ->
        value.fold(0L) { acc, byte -> (acc shl 8) or (byte.toLong() and 0xFF) }
    }

    fun u64(tag: Int): Long? = tags[tag]?.takeIf { it.size == 8 }?.let { value ->
        value.fold(0L) { acc, byte -> (acc shl 8) or (byte.toLong() and 0xFF) }
    }

    fun setUtf8(tag: Int, value: String) {
        tags[tag] = value.toByteArray(Charsets.UTF_8)
    }

    fun setU8(tag: Int, value: Int) {
        tags[tag] = byteArrayOf((value and 0xFF).toByte())
    }

    fun setU32(tag: Int, value: Long) {
        tags[tag] = ByteArray(4) { index -> ((value ushr ((3 - index) * 8)) and 0xFF).toByte() }
    }

    fun setU64(tag: Int, value: Long) {
        tags[tag] = ByteArray(8) { index -> ((value ushr ((7 - index) * 8)) and 0xFF).toByte() }
    }

    companion object {
        fun decode(input: ByteArray): TransferFrame? {
            if (input.size < 2 || input[0].toInt() != TransferProtocol.VERSION) return null
            val frame = TransferFrame(input[1].toInt() and 0xFF)
            var offset = 2
            while (offset + 3 <= input.size) {
                val tag = input[offset].toInt() and 0xFF
                val length =
                    ((input[offset + 1].toInt() and 0xFF) shl 8) or
                        (input[offset + 2].toInt() and 0xFF)
                offset += 3
                if (offset + length > input.size) return null
                frame.tags[tag] = input.copyOfRange(offset, offset + length)
                offset += length
            }
            return if (offset == input.size) frame else null
        }
    }
}
