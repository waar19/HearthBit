package com.hearthbit.app.mesh

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import java.util.zip.Deflater
import java.util.zip.Inflater

internal object MeshProtocol {
    const val VERSION: Byte = 1
    const val TYPE_ANNOUNCE: Byte = 0x01
    const val TYPE_MESSAGE: Byte = 0x02
    const val TYPE_COURIER_ENVELOPE: Byte = 0x04
    const val TYPE_NOISE_HANDSHAKE: Byte = 0x10
    const val TYPE_NOISE_ENCRYPTED: Byte = 0x11
    const val TYPE_FRAGMENT: Byte = 0x20
    const val TYPE_REQUEST_SYNC: Byte = 0x21
    const val TYPE_RADAR_CONTROL: Byte = 0x23
    const val TYPE_HBT_CAPABILITY: Byte = 0x24
    const val TYPE_NODE_CAPABILITY: Byte = 0x25
    const val TTL: Byte = 7
    const val HBT_VERSION: Byte = 0x01

    const val NOISE_PRIVATE_MESSAGE: Byte = 0x01

    /** Trama HBT (HearthBit Transfer) encapsulada dentro de la sesión Noise. */
    const val NOISE_TRANSFER_FRAME: Byte = 0x30

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
        val route: List<ByteArray> = emptyList(),
        val isRsr: Boolean = false,
    ) {
        fun canonicalForSigning(): ByteArray = encode(
            copy(ttl = 0, signature = null, isRsr = false),
            padded = true,
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
        val supportsTransfers: Boolean,
        val isInfrastructure: Boolean,
    )

    data class PrivateMessage(val id: String, val content: String)

    data class SyncRequest(
        val p: Int,
        val m: Long,
        val filter: ByteArray,
        val typeFlags: Long = SYNC_FLAG_ANNOUNCE or SYNC_FLAG_MESSAGE,
        val since: Long? = null,
    )

    data class CourierEnvelope(
        val recipientTag: ByteArray,
        val expiry: Long,
        val ciphertext: ByteArray,
        val copies: Int,
        val prekeyId: Long?,
    )

    fun encode(packet: Packet, padded: Boolean = true): ByteArray {
        require(packet.senderId.size == 8)
        require(packet.recipientId == null || packet.recipientId.size == 8)
        require(packet.version == 1.toByte() || packet.version == 2.toByte())
        require(packet.version >= 2 || packet.route.isEmpty())
        require(packet.route.size <= 255 && packet.route.all { it.size == 8 })
        require(packet.payload.size <= MAX_PAYLOAD_LENGTH)
        require(packet.version >= 2 || packet.payload.size <= 0xFFFF)
        require(packet.signature == null || packet.signature.size == 64)

        var payload = packet.payload
        var originalPayloadSize: Int? = null
        if (shouldCompress(payload)) {
            compress(payload)?.let { compressed ->
                originalPayloadSize = payload.size
                payload = compressed
            }
        }
        var flags = 0
        if (packet.recipientId != null) flags = flags or 0x01
        if (packet.signature != null) flags = flags or 0x02
        if (originalPayloadSize != null) flags = flags or 0x04
        if (packet.version >= 2 && packet.route.isNotEmpty()) flags = flags or 0x08
        if (packet.isRsr) flags = flags or 0x10

        val payloadSizeField = if (originalPayloadSize == null) {
            0
        } else if (packet.version >= 2) {
            4
        } else {
            2
        }
        val headerSize = if (packet.version >= 2) 16 else 14
        val payloadDataSize = payloadSizeField + payload.size
        val size = headerSize + 8 + (packet.recipientId?.size ?: 0) +
            (if (packet.route.isEmpty()) 0 else 1 + packet.route.size * 8) +
            payloadDataSize + (packet.signature?.size ?: 0)
        val buffer = ByteBuffer.allocate(size).order(ByteOrder.BIG_ENDIAN)
        buffer.put(packet.version)
        buffer.put(packet.type)
        buffer.put(packet.ttl)
        buffer.putLong(packet.timestamp)
        buffer.put(flags.toByte())
        if (packet.version >= 2) {
            buffer.putInt(payloadDataSize)
        } else {
            buffer.putShort(payloadDataSize.toShort())
        }
        buffer.put(packet.senderId)
        packet.recipientId?.let(buffer::put)
        if (packet.version >= 2 && packet.route.isNotEmpty()) {
            buffer.put(packet.route.size.toByte())
            packet.route.forEach(buffer::put)
        }
        originalPayloadSize?.let { originalSize ->
            if (packet.version >= 2) {
                buffer.putInt(originalSize)
            } else {
                buffer.putShort(originalSize.toShort())
            }
        }
        buffer.put(payload)
        packet.signature?.let(buffer::put)
        return if (padded) pad(buffer.array()) else buffer.array()
    }

    /**
     * BitChat solo aplica padding en el transporte BLE a tramas Noise. Los
     * paquetes públicos siguen usando padding en su forma canónica firmada.
     */
    fun encodeForBle(packet: Packet): ByteArray = encode(
        packet,
        padded = packet.type == TYPE_NOISE_HANDSHAKE ||
            packet.type == TYPE_NOISE_ENCRYPTED,
    )

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

            val route = if (version >= 2 && flags and 0x08 != 0) {
                val routeCount = buffer.get().toInt() and 0xFF
                val routeBytes = routeCount * 8
                if (buffer.remaining() < routeBytes) return null
                List(routeCount) { ByteArray(8).also(buffer::get) }
            } else {
                emptyList()
            }
            val isCompressed = flags and 0x04 != 0
            val signatureSize = if (flags and 0x02 != 0) 64 else 0
            if (payloadLength < 0 || buffer.remaining() < payloadLength + signatureSize) return null
            val payloadData = ByteArray(payloadLength).also(buffer::get)
            val payload = if (isCompressed) {
                val originalSizeField = if (version >= 2) 4 else 2
                if (payloadData.size <= originalSizeField) return null
                val compressedBuffer = ByteBuffer.wrap(payloadData).order(ByteOrder.BIG_ENDIAN)
                val originalSize = if (version >= 2) {
                    compressedBuffer.int
                } else {
                    compressedBuffer.short.toInt() and 0xFFFF
                }
                if (originalSize !in 1..MAX_PAYLOAD_LENGTH) return null
                val compressed = ByteArray(compressedBuffer.remaining()).also(compressedBuffer::get)
                decompress(compressed, originalSize) ?: return null
            } else {
                payloadData
            }
            val signature = if (signatureSize > 0) ByteArray(64).also(buffer::get) else null
            Packet(
                version = version,
                type = type,
                ttl = ttl,
                timestamp = timestamp,
                senderId = sender,
                recipientId = recipient,
                payload = payload,
                signature = signature,
                route = route,
                isRsr = flags and 0x10 != 0,
            )
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

    /** BitChat 2.x usa UTF-8 directo para mensajes públicos de la malla. */
    fun encodeInteropPublicMessage(content: String): ByteArray =
        content.toByteArray(Charsets.UTF_8)

    /**
     * Acepta el formato UTF-8 actual y el payload estructurado emitido por
     * clientes BitChat antiguos.
     */
    fun decodeCompatiblePublicMessage(
        payload: ByteArray,
        id: String,
        sender: String,
        timestamp: Long,
        senderPeerId: String,
    ): PublicMessage = decodePublicMessage(payload) ?: PublicMessage(
        id = id,
        sender = sender,
        content = payload.toString(Charsets.UTF_8),
        timestamp = timestamp,
        senderPeerId = senderPeerId,
        channel = if (payload.size >= SOS_PREFIX.size &&
            SOS_PREFIX.indices.all { payload[it] == SOS_PREFIX[it] }
        ) {
            "sos"
        } else {
            null
        },
    )

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
            // TLV de capacidades actual de BitChat. Cero anuncia que HearthBit
            // usa su propio HBT para archivos privados, no Private Media 0x20.
            add(0x05)
            add(0x01)
            add(0x00)
        }.map(Int::toByte).toByteArray()
    }

    fun decodeAnnouncement(payload: ByteArray): Announcement? = runCatching {
        var offset = 0
        var nickname: String? = null
        var noiseKey: ByteArray? = null
        var signingKey: ByteArray? = null
        var supportsTransfers = false
        var isInfrastructure = false
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
                HBT_CAPABILITY_TLV -> {
                    supportsTransfers = value.size == 1 &&
                        value[0] == HBT_VERSION
                }
                INFRASTRUCTURE_TLV -> {
                    isInfrastructure = value.isNotEmpty() &&
                        (value[0].toInt() and 0x01) != 0
                }
            }
        }
        if (nickname == null || noiseKey?.size != 32 || signingKey?.size != 32) return null
        Announcement(nickname, noiseKey, signingKey, supportsTransfers, isInfrastructure)
    }.getOrNull()

    fun packetId(packet: Packet): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(packet.type)
        digest.update(packet.senderId)
        digest.update(ByteBuffer.allocate(8).order(ByteOrder.BIG_ENDIAN).putLong(packet.timestamp).array())
        digest.update(packet.payload)
        return digest.digest().copyOf(16)
    }

    fun encodeSyncRequest(packets: Collection<Packet>): ByteArray {
        val ids = packets.map(::packetId).take(SYNC_MAX_ELEMENTS)
        val m = if (ids.isEmpty()) 1L else ids.size.toLong() shl SYNC_GCS_P
        val buckets = ids.map { gcsBucket(it, m) }.distinct().sorted()
        val filter = gcsEncode(buckets, SYNC_GCS_P)
        return ByteArrayOutputStream().apply {
            writeSyncTlv(0x01, byteArrayOf(SYNC_GCS_P.toByte()))
            writeSyncTlv(
                0x02,
                ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(m.toInt()).array(),
            )
            writeSyncTlv(0x03, filter)
            writeSyncTlv(
                0x04,
                byteArrayOf((SYNC_FLAG_ANNOUNCE or SYNC_FLAG_MESSAGE).toByte()),
            )
        }.toByteArray()
    }

    fun decodeSyncRequest(payload: ByteArray): SyncRequest? = runCatching {
        var offset = 0
        var p: Int? = null
        var m: Long? = null
        var filter: ByteArray? = null
        var typeFlags: Long? = null
        var since: Long? = null
        while (offset + 3 <= payload.size) {
            val type = payload[offset++].toInt() and 0xFF
            val length = ((payload[offset++].toInt() and 0xFF) shl 8) or
                (payload[offset++].toInt() and 0xFF)
            if (offset + length > payload.size) return null
            val value = payload.copyOfRange(offset, offset + length)
            offset += length
            when (type) {
                0x01 -> if (length == 1) p = value[0].toInt() and 0xFF
                0x02 -> if (length == 4) {
                    m = ByteBuffer.wrap(value).order(ByteOrder.BIG_ENDIAN).int.toLong() and
                        0xFFFF_FFFFL
                }
                0x03 -> {
                    if (length > SYNC_MAX_ACCEPT_BYTES) return null
                    filter = value
                }
                0x04 -> {
                    var flags = 0L
                    value.take(8).forEachIndexed { index, byte ->
                        flags = flags or ((byte.toLong() and 0xFF) shl (index * 8))
                    }
                    typeFlags = flags
                }
                0x05 -> if (length == 8) {
                    since = ByteBuffer.wrap(value).order(ByteOrder.BIG_ENDIAN).long
                }
            }
        }
        val validP = p ?: return null
        val validM = m ?: return null
        val validFilter = filter ?: return null
        if (validP !in 1..32 || validM <= 0) return null
        SyncRequest(
            validP,
            validM,
            validFilter,
            typeFlags ?: (SYNC_FLAG_ANNOUNCE or SYNC_FLAG_MESSAGE),
            since,
        )
    }.getOrNull()

    fun decodeGcs(request: SyncRequest): LongArray {
        val values = ArrayList<Long>()
        var bitOffset = 0
        var accumulator = 0L
        fun readBit(): Int? {
            if (bitOffset >= request.filter.size * 8) return null
            val byte = request.filter[bitOffset / 8].toInt() and 0xFF
            return ((byte ushr (7 - bitOffset++ % 8)) and 1)
        }
        while (values.size < SYNC_MAX_DECODED_ELEMENTS) {
            var quotient = 0L
            var bit = readBit() ?: break
            while (bit == 1) {
                quotient++
                bit = readBit() ?: return values.toLongArray()
            }
            var remainder = 0L
            repeat(request.p) {
                remainder = (remainder shl 1) or
                    (readBit() ?: return values.toLongArray()).toLong()
            }
            accumulator += (quotient shl request.p) + remainder + 1
            if (accumulator >= request.m) break
            values += accumulator
        }
        return values.toLongArray()
    }

    fun gcsBucket(packetId: ByteArray, m: Long): Long {
        if (m <= 1) return 0
        val digest = MessageDigest.getInstance("SHA-256").digest(packetId)
        var hash = 0L
        repeat(8) { hash = (hash shl 8) or (digest[it].toLong() and 0xFF) }
        val value = (hash and Long.MAX_VALUE) % m
        return if (value == 0L) 1 else value
    }

    fun gcsContains(sortedValues: LongArray, candidate: Long): Boolean =
        sortedValues.binarySearch(candidate) >= 0

    fun encodeCourierEnvelope(
        recipientNoiseKey: ByteArray,
        ciphertext: ByteArray,
        now: Long = System.currentTimeMillis(),
        expiry: Long = now + COURIER_LIFETIME_MS,
        copies: Int = COURIER_DEFAULT_COPIES,
    ): ByteArray {
        require(recipientNoiseKey.size == 32)
        require(ciphertext.isNotEmpty() && ciphertext.size <= 0xFFFF)
        require(expiry > now && expiry <= now + COURIER_MAX_LIFETIME_MS)
        val day = Math.floorDiv(now, DAY_MS)
        return ByteArrayOutputStream().apply {
            writeSyncTlv(0x01, courierTag(recipientNoiseKey, day))
            writeSyncTlv(
                0x02,
                ByteBuffer.allocate(8).order(ByteOrder.BIG_ENDIAN).putLong(expiry).array(),
            )
            writeSyncTlv(0x03, ciphertext)
            if (copies > 1) writeSyncTlv(0x04, byteArrayOf(copies.coerceAtMost(8).toByte()))
        }.toByteArray()
    }

    fun decodeCourierEnvelope(payload: ByteArray): CourierEnvelope? = runCatching {
        var offset = 0
        var tag: ByteArray? = null
        var expiry: Long? = null
        var ciphertext: ByteArray? = null
        var copies = 1
        var prekeyId: Long? = null
        while (offset + 3 <= payload.size) {
            val type = payload[offset++].toInt() and 0xFF
            val length = ((payload[offset++].toInt() and 0xFF) shl 8) or
                (payload[offset++].toInt() and 0xFF)
            if (offset + length > payload.size) return null
            val value = payload.copyOfRange(offset, offset + length)
            offset += length
            when (type) {
                0x01 -> if (length == 16) tag = value else return null
                0x02 -> if (length == 8) {
                    expiry = ByteBuffer.wrap(value).order(ByteOrder.BIG_ENDIAN).long
                } else {
                    return null
                }
                0x03 -> if (value.isNotEmpty()) ciphertext = value else return null
                0x04 -> if (length == 1) copies =
                    (value[0].toInt() and 0xFF).coerceIn(1, 8) else return null
                0x05 -> if (length == 4) {
                    prekeyId = ByteBuffer.wrap(value).order(ByteOrder.BIG_ENDIAN)
                        .int.toLong() and 0xFFFF_FFFFL
                } else {
                    return null
                }
            }
        }
        CourierEnvelope(tag ?: return null, expiry ?: return null, ciphertext ?: return null, copies, prekeyId)
    }.getOrNull()

    fun courierEnvelopeIsFor(
        envelope: CourierEnvelope,
        noisePublicKey: ByteArray,
        now: Long = System.currentTimeMillis(),
    ): Boolean {
        if (envelope.expiry <= now || envelope.expiry > now + COURIER_MAX_LIFETIME_MS) return false
        val day = Math.floorDiv(now, DAY_MS)
        return (day - 1..day + 1).any {
            MessageDigest.isEqual(envelope.recipientTag, courierTag(noisePublicKey, it))
        }
    }

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
        val canonical = encode(packet.copy(ttl = 0, isRsr = false), padded = false)
        return hex(MessageDigest.getInstance("SHA-256").digest(canonical).copyOfRange(0, 12))
    }

    private fun putByteString(buffer: ByteBuffer, bytes: ByteArray) {
        buffer.put(bytes.size.toByte())
        buffer.put(bytes)
    }

    private fun ByteArrayOutputStream.writeSyncTlv(type: Int, value: ByteArray) {
        require(value.size <= 0xFFFF)
        write(type)
        write(value.size ushr 8)
        write(value.size)
        write(value)
    }

    private fun gcsEncode(sorted: List<Long>, p: Int): ByteArray {
        val output = ByteArrayOutputStream()
        var currentByte = 0
        var bitCount = 0
        fun writeBit(bit: Int) {
            currentByte = (currentByte shl 1) or (bit and 1)
            bitCount++
            if (bitCount == 8) {
                output.write(currentByte)
                currentByte = 0
                bitCount = 0
            }
        }
        var previous = 0L
        sorted.forEach { value ->
            val delta = value - previous
            previous = value
            val encoded = delta - 1
            repeat((encoded ushr p).toInt()) { writeBit(1) }
            writeBit(0)
            for (shift in p - 1 downTo 0) writeBit((encoded ushr shift).toInt())
        }
        if (bitCount > 0) output.write(currentByte shl (8 - bitCount))
        return output.toByteArray()
    }

    private fun courierTag(noisePublicKey: ByteArray, epochDay: Long): ByteArray {
        val message = COURIER_TAG_CONTEXT.toByteArray(Charsets.UTF_8) +
            ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(epochDay.toInt()).array()
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(noisePublicKey, "HmacSHA256"))
        return mac.doFinal(message).copyOf(16)
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

    private fun shouldCompress(input: ByteArray): Boolean {
        if (input.size < COMPRESSION_THRESHOLD) return false
        val uniqueRatio = input.toSet().size.toDouble() / minOf(input.size, 256).toDouble()
        return uniqueRatio < 0.9
    }

    private fun compress(input: ByteArray): ByteArray? = runCatching {
        val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, true)
        try {
            deflater.setInput(input)
            deflater.finish()
            val output = ByteArrayOutputStream(input.size)
            val buffer = ByteArray(1_024)
            while (!deflater.finished()) {
                val count = deflater.deflate(buffer)
                if (count <= 0) return null
                output.write(buffer, 0, count)
            }
            output.toByteArray().takeIf { it.isNotEmpty() && it.size < input.size }
        } finally {
            deflater.end()
        }
    }.getOrNull()

    private fun decompress(input: ByteArray, expectedSize: Int): ByteArray? =
        inflateExact(input, expectedSize, nowrap = true)
            ?: inflateExact(input, expectedSize, nowrap = false)

    private fun inflateExact(input: ByteArray, expectedSize: Int, nowrap: Boolean): ByteArray? =
        runCatching {
            val inflater = Inflater(nowrap)
            try {
                inflater.setInput(input)
                val output = ByteArray(expectedSize)
                var offset = 0
                while (!inflater.finished() && offset < output.size) {
                    val count = inflater.inflate(output, offset, output.size - offset)
                    if (count <= 0) return null
                    offset += count
                }
                output.takeIf {
                    offset == expectedSize && inflater.finished() && inflater.remaining == 0
                }
            } finally {
                inflater.end()
            }
        }.getOrNull()

    private const val COMPRESSION_THRESHOLD = 100
    private const val MAX_PAYLOAD_LENGTH = 10_485_760
    private const val HBT_CAPABILITY_TLV = 0xF0
    private const val INFRASTRUCTURE_TLV = 0xB1
    const val SYNC_FLAG_ANNOUNCE = 1L shl 0
    const val SYNC_FLAG_MESSAGE = 1L shl 1
    private const val SYNC_GCS_P = 7
    private const val SYNC_MAX_ELEMENTS = 355
    private const val SYNC_MAX_DECODED_ELEMENTS = 1024
    private const val SYNC_MAX_ACCEPT_BYTES = 1024
    private const val DAY_MS = 86_400_000L
    private const val COURIER_LIFETIME_MS = 12 * 60 * 60 * 1_000L
    private const val COURIER_MAX_LIFETIME_MS = 25 * 60 * 60 * 1_000L
    private const val COURIER_DEFAULT_COPIES = 4
    private const val COURIER_TAG_CONTEXT = "bitchat-courier-tag-v1"
    private val SOS_PREFIX = "SOS|".toByteArray(Charsets.UTF_8)
}
