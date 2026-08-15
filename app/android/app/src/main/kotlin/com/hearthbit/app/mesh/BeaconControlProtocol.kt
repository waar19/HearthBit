package com.hearthbit.app.mesh

import java.security.SecureRandom

internal object BeaconControlProtocol {
    const val VERSION: Byte = 1
    const val INITIAL_TTL = 2
    const val ACTION_REQUEST: Byte = 1
    const val ACTION_GRANT: Byte = 2
    const val ACTION_REVOKE: Byte = 3
    const val ACTION_STOP: Byte = 4

    const val FLAG_FLASH = 0x01
    const val FLAG_SOUND = 0x02
    const val FLAG_VIBRATE = 0x04
    const val ALLOWED_FLAGS = FLAG_FLASH or FLAG_SOUND or FLAG_VIBRATE

    const val NONCE_SIZE = 16
    const val PAYLOAD_SIZE = 1 + 1 + Long.SIZE_BYTES + NONCE_SIZE + 1
    const val MAX_DURATION_MS = 5 * 60 * 1_000L
    const val CLOCK_SKEW_MS = 2 * 60 * 1_000L

    data class Control(
        val action: Byte,
        val expiresAt: Long,
        val nonce: ByteArray,
        val flags: Int,
    )

    fun request(
        expiresAt: Long,
        flags: Int,
        nonce: ByteArray = randomNonce(),
    ): ByteArray = encode(ACTION_REQUEST, expiresAt, nonce, flags)

    fun grant(expiresAt: Long, flags: Int, nonce: ByteArray): ByteArray =
        encode(ACTION_GRANT, expiresAt, nonce, flags)

    fun revoke(nonce: ByteArray): ByteArray =
        encode(ACTION_REVOKE, 0, nonce, 0)

    fun stop(nonce: ByteArray): ByteArray =
        encode(ACTION_STOP, 0, nonce, 0)

    fun decode(payload: ByteArray): Control? {
        if (payload.size != PAYLOAD_SIZE || payload[0] != VERSION) return null
        val action = payload[1]
        if (action !in setOf(ACTION_REQUEST, ACTION_GRANT, ACTION_REVOKE, ACTION_STOP)) {
            return null
        }
        var expiresAt = 0L
        for (index in 0 until Long.SIZE_BYTES) {
            expiresAt = (expiresAt shl 8) or (payload[2 + index].toLong() and 0xFF)
        }
        val flags = payload.last().toInt() and 0xFF
        if (flags and ALLOWED_FLAGS.inv() != 0) return null
        val terminal = action == ACTION_REVOKE || action == ACTION_STOP
        if (terminal && (expiresAt != 0L || flags != 0)) return null
        if (!terminal && (expiresAt == 0L || flags == 0)) return null
        return Control(
            action = action,
            expiresAt = expiresAt,
            nonce = payload.copyOfRange(10, 10 + NONCE_SIZE),
            flags = flags,
        )
    }

    fun isValid(
        control: Control,
        packetTimestamp: Long,
        now: Long = System.currentTimeMillis(),
    ): Boolean {
        if (!hasValidTimestamp(packetTimestamp, now)) return false
        return when (control.action) {
            ACTION_REQUEST, ACTION_GRANT ->
                control.expiresAt > now && control.expiresAt <= now + MAX_DURATION_MS
            ACTION_REVOKE, ACTION_STOP -> control.expiresAt == 0L && control.flags == 0
            else -> false
        }
    }

    fun hasValidTimestamp(timestamp: Long, now: Long = System.currentTimeMillis()): Boolean =
        timestamp in (now - CLOCK_SKEW_MS)..(now + CLOCK_SKEW_MS)

    fun shouldAutoAccept(localRadarConsentUntil: Long, now: Long = System.currentTimeMillis()): Boolean =
        localRadarConsentUntil > now

    fun isValidTtl(ttl: Int): Boolean = ttl == 1 || ttl == INITIAL_TTL

    fun nonceHex(nonce: ByteArray): String = MeshProtocol.hex(nonce)

    private fun encode(action: Byte, expiresAt: Long, nonce: ByteArray, flags: Int): ByteArray {
        require(nonce.size == NONCE_SIZE)
        require(flags and ALLOWED_FLAGS.inv() == 0)
        return ByteArray(PAYLOAD_SIZE).also { output ->
            output[0] = VERSION
            output[1] = action
            for (index in 0 until Long.SIZE_BYTES) {
                output[2 + index] =
                    ((expiresAt ushr (56 - index * 8)) and 0xFF).toByte()
            }
            nonce.copyInto(output, destinationOffset = 10)
            output[PAYLOAD_SIZE - 1] = flags.toByte()
        }
    }

    private fun randomNonce(): ByteArray =
        ByteArray(NONCE_SIZE).also(SecureRandom()::nextBytes)
}
