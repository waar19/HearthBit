package com.hearthbit.app.mesh

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest

internal object AnchorOtaProtocol {
    const val TYPE_MANIFEST: Byte = 0xA0.toByte()
    const val TYPE_REQUEST: Byte = 0xA1.toByte()
    const val TYPE_CHUNK: Byte = 0xA2.toByte()
    const val TYPE_STATUS: Byte = 0xA3.toByte()

    const val MANIFEST_LENGTH = 110
    const val MINIMUM_CHUNK_SIZE = 64
    const val MAXIMUM_CHUNK_SIZE = 480

    data class Manifest(
        val raw: ByteArray,
        val version: Long,
        val imageSize: Int,
        val digest: ByteArray,
        val chunkSize: Int,
    ) {
        val chunkCount: Int
            get() = (imageSize + chunkSize - 1) / chunkSize
    }

    data class Request(
        val version: Long,
        val chunkIndex: Long,
    )

    data class Chunk(
        val index: Long,
        val payload: ByteArray,
        val bytesSent: Int,
        val totalBytes: Int,
    )

    fun validateBundle(
        manifestBytes: ByteArray,
        image: ByteArray,
        currentVersion: Long,
    ): Manifest {
        val manifest = parseManifest(manifestBytes)
            ?: throw IllegalArgumentException("anchor_ota_invalid_manifest")
        require(manifest.version > currentVersion) { "anchor_ota_version_not_newer" }
        require(manifest.imageSize == image.size) { "anchor_ota_image_size" }
        require(MessageDigest.isEqual(manifest.digest, MessageDigest.getInstance("SHA-256").digest(image))) {
            "anchor_ota_image_digest"
        }
        return manifest
    }

    fun parseManifest(bytes: ByteArray): Manifest? {
        if (bytes.size != MANIFEST_LENGTH ||
            bytes[0] != 'B'.code.toByte() ||
            bytes[1] != 'O'.code.toByte() ||
            bytes[2] != 'T'.code.toByte() ||
            bytes[3] != 'A'.code.toByte()
        ) {
            return null
        }
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        buffer.position(4)
        val version = buffer.int.toLong() and 0xFFFF_FFFFL
        val imageSizeLong = buffer.int.toLong() and 0xFFFF_FFFFL
        val digest = ByteArray(32).also(buffer::get)
        val chunkSize = buffer.short.toInt() and 0xFFFF
        if (version == 0L ||
            imageSizeLong == 0L ||
            imageSizeLong > Int.MAX_VALUE ||
            chunkSize !in MINIMUM_CHUNK_SIZE..MAXIMUM_CHUNK_SIZE
        ) {
            return null
        }
        return Manifest(
            raw = bytes.copyOf(),
            version = version,
            imageSize = imageSizeLong.toInt(),
            digest = digest,
            chunkSize = chunkSize,
        )
    }

    fun parseRequest(payload: ByteArray): Request? {
        if (payload.size != 8) return null
        val buffer = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
        return Request(
            version = buffer.int.toLong() and 0xFFFF_FFFFL,
            chunkIndex = buffer.int.toLong() and 0xFFFF_FFFFL,
        )
    }

    fun chunkFor(manifest: Manifest, image: ByteArray, requestPayload: ByteArray): Chunk? {
        val request = parseRequest(requestPayload) ?: return null
        if (request.version != manifest.version || request.chunkIndex >= manifest.chunkCount.toLong()) {
            return null
        }
        val offset = request.chunkIndex.toInt() * manifest.chunkSize
        val length = minOf(manifest.chunkSize, image.size - offset)
        val payload = ByteBuffer.allocate(8 + length)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(manifest.version.toInt())
            .putInt(request.chunkIndex.toInt())
            .put(image, offset, length)
            .array()
        return Chunk(
            index = request.chunkIndex,
            payload = payload,
            bytesSent = offset + length,
            totalBytes = image.size,
        )
    }

    fun parseStatus(payload: ByteArray): Int? =
        payload.singleOrNull()?.toInt()?.and(0xFF)
}

internal enum class AnchorOtaStage {
    TRANSFERRING,
    REBOOTING,
}

internal data class AnchorOtaTransfer(
    val peerId: String,
    var sourceAddress: String,
    val manifest: AnchorOtaProtocol.Manifest,
    val image: ByteArray,
    var bytesSent: Int = 0,
    var lastChunkIndex: Long? = null,
    var lastChunkResponseAtMs: Long = 0,
    var lastProgressAtMs: Long = System.currentTimeMillis(),
    var lastManifestSentAtMs: Long = System.currentTimeMillis(),
    var stage: AnchorOtaStage = AnchorOtaStage.TRANSFERRING,
)
