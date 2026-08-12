package com.emergencycom.emergency_com.mesh

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.UUID

internal object MeshProtocol {
    const val VERSION: Byte = 1
    const val TYPE_ANNOUNCE: Byte = 0x01
    const val TYPE_MESSAGE: Byte = 0x02
    const val TYPE_NOISE_HANDSHAKE: Byte = 0x10
    const val TYPE_NOISE_ENCRYPTED: Byte = 0x11
    const val TTL: Byte = 7

    const val NOISE_PRIVATE_MESSAGE: Byte = 0x01

    val broadcastRecipient = ByteArray(8) { 0xFF.toByte() }

    data class Packet(
        val version: Byte = VERSION,
        val type: Byte,
        val ttl: Byte,
        val timestamp: Long,
        val senderId: ByteArray,
        val recipientId: ByteArray? = null,
        val payload: ByteArray,
        val signature: ByteArray? = null,
    ) {
        fun canonicalForSigning(): ByteArray = encode(
            copy(ttl = 0, signature = null),
            padded = false,
        )
    }

    data class PublicMessage(
        val id: String,
        val sender: String,
        val content: String,
        val timestamp: Long,
        val senderPeerId: String?,
        val channel: String?,
    )

    data class Announcement(
        val nickname: String,
        val noisePublicKey: ByteArray,
        val signingPublicKey: ByteArray,
    )

    data class PrivateMessage(val id: String, val content: String)

    fun encode(packet: Packet, padded: Boolean = true): ByteArray {
        require(packet.senderId.size == 8)
        require(packet.recipientId == null || packet.recipientId.size == 8)
        require(packet.payload.size <= 0xFFFF)
        require(packet.signature == null || packet.signature.size == 64)

        var flags = 0
        if (packet.recipientId != null) flags = flags or 0x01
        if (packet.signature != null) flags = flags or 0x02

        val size = 14 + 8 + (packet.recipientId?.size ?: 0) +
            packet.payload.size + (packet.signature?.size ?: 0)
        val buffer = ByteBuffer.allocate(size).order(ByteOrder.BIG_ENDIAN)
        buffer.put(packet.version)
        buffer.put(packet.type)
        buffer.put(packet.ttl)
        buffer.putLong(packet.timestamp)
        buffer.put(flags.toByte())
        buffer.putShort(packet.payload.size.toShort())
        buffer.put(packet.senderId)
        packet.recipientId?.let(buffer::put)
        buffer.put(packet.payload)
        packet.signature?.let(buffer::put)
        return if (padded) pad(buffer.array()) else buffer.array()
    }

    fun decode(input: ByteArray): Packet? {
        return decodeRaw(input) ?: decodeRaw(unpad(input))
    }

    private fun decodeRaw(input: ByteArray): Packet? {
        if (input.size < 22) return null
        return runCatching {
            val buffer = ByteBuffer.wrap(input).order(ByteOrder.BIG_ENDIAN)
            val version = buffer.get()
            if (version != 1.toByte() && version != 2.toByte()) return null
            val type = buffer.get()
            val ttl = buffer.get()
            val timestamp = buffer.long
            val flags = buffer.get().toInt() and 0xFF
            val payloadLength = if (version >= 2) buffer.int else buffer.short.toInt() and 0xFFFF
            val sender = ByteArray(8).also(buffer::get)
            val recipient = if (flags and 0x01 != 0) ByteArray(8).also(buffer::get) else null

            if (version >= 2 && flags and 0x08 != 0) {
                val routeCount = buffer.get().toInt() and 0xFF
                val routeBytes = routeCount * 8
                if (buffer.remaining() < routeBytes) return null
                buffer.position(buffer.position() + routeBytes)
            }
            if (flags and 0x04 != 0) return null
            val signatureSize = if (flags and 0x02 != 0) 64 else 0
            if (payloadLength < 0 || buffer.remaining() < payloadLength + signatureSize) return null
            val payload = ByteArray(payloadLength).also(buffer::get)
            val signature = if (signatureSize > 0) ByteArray(64).also(buffer::get) else null
            Packet(version, type, ttl, timestamp, sender, recipient, payload, signature)
        }.getOrNull()
    }

    fun encodePublicMessage(
        nickname: String,
        peerId: String,
        content: String,
        channel: String? = null,
        id: String = UUID.randomUUID().toString().uppercase(),
        timestamp: Long = System.currentTimeMillis(),
    ): Pair<String, ByteArray> {
        var flags = 0x10
        if (channel != null) flags = flags or 0x40
        val idBytes = id.toByteArray(Charsets.UTF_8).take(255).toByteArray()
        val senderBytes = nickname.toByteArray(Charsets.UTF_8).take(255).toByteArray()
        val contentBytes = content.toByteArray(Charsets.UTF_8).take(65535).toByteArray()
        val peerBytes = peerId.toByteArray(Charsets.UTF_8).take(255).toByteArray()
        val channelBytes = channel?.toByteArray(Charsets.UTF_8)?.take(255)?.toByteArray()
        val size = 1 + 8 + 1 + idBytes.size + 1 + senderBytes.size + 2 +
            contentBytes.size + 1 + peerBytes.size +
            if (channelBytes != null) 1 + channelBytes.size else 0
        val buffer = ByteBuffer.allocate(size).order(ByteOrder.BIG_ENDIAN)
        buffer.put(flags.toByte())
        buffer.putLong(timestamp)
        putByteString(buffer, idBytes)
        putByteString(buffer, senderBytes)
        buffer.putShort(contentBytes.size.toShort())
        buffer.put(contentBytes)
        putByteString(buffer, peerBytes)
        channelBytes?.let { putByteString(buffer, it) }
        return id to buffer.array()
    }

    fun decodePublicMessage(payload: ByteArray): PublicMessage? = runCatching {
        if (payload.size < 13) return null
        val buffer = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
        val flags = buffer.get().toInt() and 0xFF
        val timestamp = buffer.long
        val id = getByteString(buffer)
        val sender = getByteString(buffer)
        val contentLength = buffer.short.toInt() and 0xFFFF
        if (buffer.remaining() < contentLength) return null
        val content = ByteArray(contentLength).also(buffer::get).toString(Charsets.UTF_8)
        if (flags and 0x04 != 0) getByteString(buffer)
        if (flags and 0x08 != 0) getByteString(buffer)
        val senderPeerId = if (flags and 0x10 != 0) getByteString(buffer) else null
        if (flags and 0x20 != 0) {
            val count = buffer.get().toInt() and 0xFF
            repeat(count) { getByteString(buffer) }
        }
        val channel = if (flags and 0x40 != 0) getByteString(buffer) else null
        if (flags and 0x80 != 0) return null
        PublicMessage(id, sender, content, timestamp, senderPeerId, channel)
    }.getOrNull()

    fun encodeAnnouncement(
        nickname: String,
        noisePublicKey: ByteArray,
        signingPublicKey: ByteArray,
    ): ByteArray {
        val nicknameBytes = nickname.toByteArray(Charsets.UTF_8).take(31).toByteArray()
        return buildList {
            add(0x01)
            add(nicknameBytes.size)
            addAll(nicknameBytes.map(Byte::toInt))
            add(0x02)
            add(noisePublicKey.size)
            addAll(noisePublicKey.map(Byte::toInt))
            add(0x03)
            add(signingPublicKey.size)
            addAll(signingPublicKey.map(Byte::toInt))
        }.map(Int::toByte).toByteArray()
    }

    fun decodeAnnouncement(payload: ByteArray): Announcement? = runCatching {
        var offset = 0
        var nickname: String? = null
        var noiseKey: ByteArray? = null
        var signingKey: ByteArray? = null
        while (offset + 2 <= payload.size) {
            val type = payload[offset++].toInt() and 0xFF
            val length = payload[offset++].toInt() and 0xFF
            if (offset + length > payload.size) return null
            val value = payload.copyOfRange(offset, offset + length)
            offset += length
            when (type) {
                0x01 -> nickname = value.toString(Charsets.UTF_8)
                0x02 -> noiseKey = value
                0x03 -> signingKey = value
            }
        }
        if (nickname == null || noiseKey?.size != 32 || signingKey?.size != 32) return null
        Announcement(nickname, noiseKey, signingKey)
    }.getOrNull()

    fun encodePrivateMessage(id: String, content: String): ByteArray {
        val idBytes = id.toByteArray().take(255).toByteArray()
        val contentBytes = content.toByteArray().take(255).toByteArray()
        return buildList {
            add(0x00)
            add(idBytes.size)
            addAll(idBytes.map(Byte::toInt))
            add(0x01)
            add(contentBytes.size)
            addAll(contentBytes.map(Byte::toInt))
        }.map(Int::toByte).toByteArray()
    }

    fun decodePrivateMessage(input: ByteArray): PrivateMessage? = runCatching {
        var offset = 0
        var id: String? = null
        var content: String? = null
        while (offset + 2 <= input.size) {
            val type = input[offset++].toInt() and 0xFF
            val length = input[offset++].toInt() and 0xFF
            if (offset + length > input.size) return null
            val value = input.copyOfRange(offset, offset + length).toString(Charsets.UTF_8)
            offset += length
            when (type) {
                0x00 -> id = value
                0x01 -> content = value
            }
        }
        if (id == null || content == null) null else PrivateMessage(id, content)
    }.getOrNull()

    fun peerIdFromNoiseKey(publicKey: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(publicKey).copyOfRange(0, 8)

    fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }

    fun fingerprint(packet: Packet): String {
        val canonical = encode(packet.copy(ttl = 0), padded = false)
        return hex(MessageDigest.getInstance("SHA-256").digest(canonical).copyOfRange(0, 12))
    }

    private fun putByteString(buffer: ByteBuffer, bytes: ByteArray) {
        buffer.put(bytes.size.toByte())
        buffer.put(bytes)
    }

    private fun getByteString(buffer: ByteBuffer): String {
        val length = buffer.get().toInt() and 0xFF
        require(buffer.remaining() >= length)
        return ByteArray(length).also(buffer::get).toString(Charsets.UTF_8)
    }

    private fun pad(input: ByteArray): ByteArray {
        val target = listOf(256, 512, 1024, 2048).firstOrNull { input.size + 16 <= it } ?: return input
        val padding = target - input.size
        if (padding !in 1..255) return input
        return input.copyOf(target).also { output ->
            for (index in input.size until output.size) output[index] = padding.toByte()
        }
    }

    private fun unpad(input: ByteArray): ByteArray {
        if (input.isEmpty()) return input
        val length = input.last().toInt() and 0xFF
        if (length !in 1..input.size) return input
        val start = input.size - length
        if ((start until input.size).any { input[it] != length.toByte() }) return input
        return input.copyOfRange(0, start)
    }
}
