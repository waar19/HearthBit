package com.hearthbit.app.mesh

import java.security.SecureRandom

internal object RadarConsentProtocol {
    const val VERSION: Byte = 1
    const val ACTION_GRANT: Byte = 1
    const val ACTION_REVOKE: Byte = 2
    const val NONCE_SIZE = 16
    const val PAYLOAD_SIZE = 1 + 1 + Long.SIZE_BYTES + NONCE_SIZE
    const val MANUAL_DURATION_MS = 15 * 60 * 1_000L
    const val SOS_DURATION_MS = 30 * 60 * 1_000L
    const val MAX_GRANT_DURATION_MS = 30 * 60 * 1_000L
    const val CLOCK_SKEW_MS = 2 * 60 * 1_000L

    data class Consent(
        val action: Byte,
        val expiresAt: Long,
        val nonce: ByteArray,
    )

    fun grant(expiresAt: Long): ByteArray =
        encode(ACTION_GRANT, expiresAt, randomNonce())

    fun revoke(): ByteArray =
        encode(ACTION_REVOKE, 0, randomNonce())

    fun decode(payload: ByteArray): Consent? {
        if (payload.size != PAYLOAD_SIZE || payload[0] != VERSION) return null
        val action = payload[1]
        if (action != ACTION_GRANT && action != ACTION_REVOKE) return null
        var expiresAt = 0L
        for (index in 0 until Long.SIZE_BYTES) {
            expiresAt = (expiresAt shl 8) or (payload[2 + index].toLong() and 0xFF)
        }
        if (action == ACTION_REVOKE && expiresAt != 0L) return null
        return Consent(
            action = action,
            expiresAt = expiresAt,
            nonce = payload.copyOfRange(10, PAYLOAD_SIZE),
        )
    }

    fun isValidGrant(
        consent: Consent,
        packetTimestamp: Long,
        now: Long = System.currentTimeMillis(),
    ): Boolean {
        if (consent.action != ACTION_GRANT) return false
        if (!hasValidTimestamp(packetTimestamp, now)) return false
        if (consent.expiresAt <= now) return false
        return consent.expiresAt <= saturatedAdd(
            saturatedAdd(now, MAX_GRANT_DURATION_MS),
            CLOCK_SKEW_MS,
        )
    }

    fun hasValidTimestamp(timestamp: Long, now: Long = System.currentTimeMillis()): Boolean =
        timestamp in saturatedSubtract(now, CLOCK_SKEW_MS)..saturatedAdd(now, CLOCK_SKEW_MS)

    fun sosConsentExpiresAt(
        packetTimestamp: Long,
        now: Long = System.currentTimeMillis(),
    ): Long = minOf(
        saturatedAdd(packetTimestamp, SOS_DURATION_MS),
        saturatedAdd(now, SOS_DURATION_MS),
    )

    private fun encode(action: Byte, expiresAt: Long, nonce: ByteArray): ByteArray {
        require(nonce.size == NONCE_SIZE)
        return ByteArray(PAYLOAD_SIZE).also { output ->
            output[0] = VERSION
            output[1] = action
            for (index in 0 until Long.SIZE_BYTES) {
                output[2 + index] =
                    ((expiresAt ushr (56 - index * 8)) and 0xFF).toByte()
            }
            nonce.copyInto(output, destinationOffset = 10)
        }
    }

    private fun randomNonce(): ByteArray =
        ByteArray(NONCE_SIZE).also(SecureRandom()::nextBytes)

    private fun saturatedAdd(value: Long, increment: Long): Long =
        if (value > Long.MAX_VALUE - increment) Long.MAX_VALUE else value + increment

    private fun saturatedSubtract(value: Long, decrement: Long): Long =
        if (value < Long.MIN_VALUE + decrement) Long.MIN_VALUE else value - decrement
}
