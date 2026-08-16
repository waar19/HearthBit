package com.hearthbit.app.mesh

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.math.ec.rfc7748.X25519

internal object KeyRotationProtocol {
    const val VERSION: Byte = 0x01
    const val PAYLOAD_SIZE = 153
    const val CLOCK_WINDOW_MS = 10 * 60 * 1_000L
    private const val PEER_ID_SIZE = 8
    private const val PUBLIC_KEY_SIZE = 32
    private const val SIGNATURE_SIZE = 64
    private val DOMAIN = "HearthBitKeyRotationV1".toByteArray(Charsets.US_ASCII)

    data class Rotation(
        val oldPeerId: ByteArray,
        val newNoisePublicKey: ByteArray,
        val newSigningPublicKey: ByteArray,
        val timestamp: Long,
        val sequence: Long,
        val authorizationSignature: ByteArray,
    ) {
        val newPeerId: ByteArray
            get() = MeshProtocol.peerIdFromNoiseKey(newNoisePublicKey)

        fun authorizationBytes(): ByteArray =
            DOMAIN + encodeUnsigned(
                oldPeerId = oldPeerId,
                newNoisePublicKey = newNoisePublicKey,
                newSigningPublicKey = newSigningPublicKey,
                timestamp = timestamp,
                sequence = sequence,
            )
    }

    fun encode(
        oldPeerId: ByteArray,
        newNoisePublicKey: ByteArray,
        newSigningPublicKey: ByteArray,
        timestamp: Long,
        sequence: Long,
        authorizationSignature: ByteArray,
    ): ByteArray {
        require(authorizationSignature.size == SIGNATURE_SIZE)
        return encodeUnsigned(
            oldPeerId,
            newNoisePublicKey,
            newSigningPublicKey,
            timestamp,
            sequence,
        ) + authorizationSignature
    }

    fun decode(payload: ByteArray): Rotation? = runCatching {
        if (payload.size != PAYLOAD_SIZE) return null
        val reader = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
        if (reader.get() != VERSION) return null
        val oldPeerId = ByteArray(PEER_ID_SIZE).also(reader::get)
        val noise = ByteArray(PUBLIC_KEY_SIZE).also(reader::get)
        val signing = ByteArray(PUBLIC_KEY_SIZE).also(reader::get)
        val timestamp = reader.long
        val sequence = reader.long
        val signature = ByteArray(SIGNATURE_SIZE).also(reader::get)
        if (sequence <= 0L ||
            !isValidNoiseKey(noise) ||
            !isValidSigningKey(signing)
        ) {
            return null
        }
        Rotation(oldPeerId, noise, signing, timestamp, sequence, signature)
    }.getOrNull()

    fun timestampIsCurrent(timestamp: Long, now: Long): Boolean {
        if (timestamp < 0L || now < 0L) return false
        val delta = if (timestamp >= now) timestamp - now else now - timestamp
        return delta <= CLOCK_WINDOW_MS
    }

    private fun encodeUnsigned(
        oldPeerId: ByteArray,
        newNoisePublicKey: ByteArray,
        newSigningPublicKey: ByteArray,
        timestamp: Long,
        sequence: Long,
    ): ByteArray {
        require(oldPeerId.size == PEER_ID_SIZE)
        require(newNoisePublicKey.size == PUBLIC_KEY_SIZE)
        require(newSigningPublicKey.size == PUBLIC_KEY_SIZE)
        require(timestamp >= 0L)
        require(sequence > 0L)
        return ByteBuffer.allocate(PAYLOAD_SIZE - SIGNATURE_SIZE)
            .order(ByteOrder.BIG_ENDIAN)
            .put(VERSION)
            .put(oldPeerId)
            .put(newNoisePublicKey)
            .put(newSigningPublicKey)
            .putLong(timestamp)
            .putLong(sequence)
            .array()
    }

    private fun isValidNoiseKey(key: ByteArray): Boolean = runCatching {
        X25519.calculateAgreement(
            VALIDATION_PRIVATE_KEY,
            0,
            key,
            0,
            ByteArray(PUBLIC_KEY_SIZE),
            0,
        )
    }.getOrDefault(false)

    private fun isValidSigningKey(key: ByteArray): Boolean = runCatching {
        Ed25519PublicKeyParameters(key, 0)
        key.any { it != 0.toByte() }
    }.getOrDefault(false)

    private val VALIDATION_PRIVATE_KEY = ByteArray(PUBLIC_KEY_SIZE) { (it + 1).toByte() }
}
