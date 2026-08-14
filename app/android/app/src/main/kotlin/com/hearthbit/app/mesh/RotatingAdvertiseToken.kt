package com.hearthbit.app.mesh

import java.nio.ByteBuffer
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Pseudónimo efímero para descubrimiento BLE.
 *
 * El marcador permite a HearthBit distinguirlo del peerId estático de BitChat.
 * El HMAC impide derivar o correlacionar ventanas conociendo el peerId público.
 */
internal object RotatingAdvertiseToken {
    const val MARKER: Byte = 0xA5.toByte()
    const val ROTATION_MS: Long = 15 * 60 * 1_000L
    const val TOKEN_BYTES = 8

    fun serviceData(secret: ByteArray, nowMs: Long): ByteArray {
        require(secret.size >= 16) { "Advertise token secret is too short" }
        val epoch = Math.floorDiv(nowMs, ROTATION_MS)
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        val digest = mac.doFinal(
            ByteBuffer.allocate(Long.SIZE_BYTES).putLong(epoch).array(),
        )
        return byteArrayOf(MARKER) + digest.copyOf(TOKEN_BYTES)
    }

    fun isPrivateToken(value: ByteArray?): Boolean =
        value?.size == TOKEN_BYTES + 1 && value.first() == MARKER

    fun delayUntilRotation(nowMs: Long): Long {
        val remainder = Math.floorMod(nowMs, ROTATION_MS)
        return (ROTATION_MS - remainder).coerceAtLeast(1L)
    }
}
