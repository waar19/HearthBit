package com.hearthbit.app.mesh

import java.security.SecureRandom

internal object RadarConsentProtocol {
    const val VERSION: Byte = 1
    const val ACTION_GRANT: Byte = 1
    const val ACTION_REVOKE: Byte = 2
    const val ACTION_RSSI_REPORT: Byte = 3
    const val NONCE_SIZE = 16
    const val PAYLOAD_SIZE = 1 + 1 + Long.SIZE_BYTES + NONCE_SIZE
    const val RSSI_REPORT_PAYLOAD_SIZE = 1 + 1 + 1 + Long.SIZE_BYTES + NONCE_SIZE
    const val MANUAL_DURATION_MS = 15 * 60 * 1_000L
    const val SOS_DURATION_MS = 30 * 60 * 1_000L
    const val MAX_GRANT_DURATION_MS = 30 * 60 * 1_000L
    const val CLOCK_SKEW_MS = 2 * 60 * 1_000L

    data class Consent(
        val action: Byte,
        val expiresAt: Long,
        val nonce: ByteArray,
    )

    data class RssiReport(
        val rssi: Int,
        val measuredAt: Long,
        val nonce: ByteArray,
    )

    fun grant(expiresAt: Long): ByteArray =
        encode(ACTION_GRANT, expiresAt, randomNonce())

    fun revoke(): ByteArray =
        encode(ACTION_REVOKE, 0, randomNonce())

    fun rssiReport(rssi: Int, measuredAt: Long): ByteArray {
        require(isValidRssi(rssi))
        return ByteArray(RSSI_REPORT_PAYLOAD_SIZE).also { output ->
            output[0] = VERSION
            output[1] = ACTION_RSSI_REPORT
            output[2] = rssi.toByte()
            writeLong(output, offset = 3, value = measuredAt)
            randomNonce().copyInto(output, destinationOffset = 11)
        }
    }

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

    fun decodeRssiReport(payload: ByteArray): RssiReport? {
        if (payload.size != RSSI_REPORT_PAYLOAD_SIZE ||
            payload[0] != VERSION ||
            payload[1] != ACTION_RSSI_REPORT
        ) {
            return null
        }
        val rssi = payload[2].toInt()
        if (!isValidRssi(rssi)) return null
        return RssiReport(
            rssi = rssi,
            measuredAt = readLong(payload, offset = 3),
            nonce = payload.copyOfRange(11, RSSI_REPORT_PAYLOAD_SIZE),
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

    fun isValidReport(
        report: RssiReport,
        packetTimestamp: Long,
        now: Long = System.currentTimeMillis(),
    ): Boolean =
        hasValidTimestamp(packetTimestamp, now) &&
            hasValidTimestamp(report.measuredAt, now)

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
            writeLong(output, offset = 2, value = expiresAt)
            nonce.copyInto(output, destinationOffset = 10)
        }
    }

    private fun writeLong(output: ByteArray, offset: Int, value: Long) {
        for (index in 0 until Long.SIZE_BYTES) {
            output[offset + index] =
                ((value ushr (56 - index * 8)) and 0xFF).toByte()
        }
    }

    private fun readLong(input: ByteArray, offset: Int): Long {
        var value = 0L
        for (index in 0 until Long.SIZE_BYTES) {
            value = (value shl 8) or (input[offset + index].toLong() and 0xFF)
        }
        return value
    }

    private fun isValidRssi(rssi: Int): Boolean = rssi in -127..20

    private fun randomNonce(): ByteArray =
        ByteArray(NONCE_SIZE).also(SecureRandom()::nextBytes)

    private fun saturatedAdd(value: Long, increment: Long): Long =
        if (value > Long.MAX_VALUE - increment) Long.MAX_VALUE else value + increment

    private fun saturatedSubtract(value: Long, decrement: Long): Long =
        if (value < Long.MIN_VALUE + decrement) Long.MIN_VALUE else value - decrement
}
