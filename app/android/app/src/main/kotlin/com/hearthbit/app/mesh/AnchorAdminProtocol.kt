package com.hearthbit.app.mesh

import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.crypto.Mac
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

internal object AnchorAdminProtocol {
    const val VERSION: Byte = 0x01
    const val STATUS_GET: Byte = 0x01
    const val CHALLENGE_GET: Byte = 0x02
    const val SET_PASSWORD: Byte = 0x03
    const val CHANGE_PASSWORD: Byte = 0x04
    const val RENAME: Byte = 0x05
    const val REBOOT: Byte = 0x06
    const val FACTORY_RESET: Byte = 0x07

    const val STATUS_OK = 0
    const val STATUS_LOCKED = 6
    const val SALT_SIZE = 16
    const val NONCE_SIZE = 16
    const val VERIFIER_SIZE = 32
    const val MIN_PASSWORD_LENGTH = 10
    const val MAX_PASSWORD_LENGTH = 128
    const val MAX_NICKNAME_LENGTH = 31

    data class Response(
        val command: Byte,
        val requestId: Int,
        val status: Int,
        val body: ByteArray,
    )

    data class Challenge(
        val claimed: Boolean,
        val salt: ByteArray,
        val nonce: ByteArray,
        val iterations: Int,
        val retryAfterSeconds: Long,
    )

    data class Status(
        val claimed: Boolean,
        val firmwareVersion: Long,
        val protocolVersion: Long,
        val uptimeMs: Long,
        val bootCount: Long,
        val packetsReceived: Long,
        val packetsForwarded: Long,
        val packetsStored: Long,
        val packetsDelivered: Long,
        val packetsDeduplicated: Long,
        val packetsExpired: Long,
        val packetsRejected: Long,
        val lastActivityUptimeMs: Long,
        val mailboxUsed: Int,
        val mailboxCapacity: Int,
        val mailboxAvailable: Boolean,
        val clockValid: Boolean,
        val clockAuthoritative: Boolean,
        val nickname: String,
        val freeHeap: Long?,
        val minFreeHeap: Long?,
    )

    fun request(command: Byte, requestId: Int): ByteArray =
        ByteBuffer.allocate(6)
            .order(ByteOrder.BIG_ENDIAN)
            .put(VERSION)
            .put(command)
            .putInt(requestId)
            .array()

    fun requestId(bytes: ByteArray): Int? =
        if (bytes.size >= 6 && bytes[0] == VERSION) {
            ByteBuffer.wrap(bytes, 2, 4).order(ByteOrder.BIG_ENDIAN).int
        } else {
            null
        }

    fun authenticatedRequest(
        command: Byte,
        requestId: Int,
        nonce: ByteArray,
        data: ByteArray,
        verifier: ByteArray,
    ): ByteArray {
        require(nonce.size == NONCE_SIZE)
        require(verifier.size == VERIFIER_SIZE)
        val signed = ByteBuffer.allocate(6 + NONCE_SIZE + data.size)
            .order(ByteOrder.BIG_ENDIAN)
            .put(VERSION)
            .put(command)
            .putInt(requestId)
            .put(nonce)
            .put(data)
            .array()
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(verifier, "HmacSHA256"))
        return signed + mac.doFinal(signed)
    }

    fun deriveVerifier(password: CharArray, salt: ByteArray, iterations: Int): ByteArray {
        require(
            String(password).toByteArray(Charsets.UTF_8).size in
                MIN_PASSWORD_LENGTH..MAX_PASSWORD_LENGTH,
        )
        require(salt.size == SALT_SIZE)
        require(iterations in 10_000..2_000_000)
        val spec = PBEKeySpec(password, salt, iterations, VERIFIER_SIZE * 8)
        return try {
            SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                .generateSecret(spec)
                .encoded
        } finally {
            spec.clearPassword()
        }
    }

    fun renameData(nickname: String): ByteArray {
        require(nickname.all { it.code in 0x20..0x7E })
        val bytes = nickname.toByteArray(Charsets.US_ASCII)
        require(bytes.size in 1..MAX_NICKNAME_LENGTH)
        return byteArrayOf(bytes.size.toByte()) + bytes
    }

    fun parseResponse(bytes: ByteArray): Response? {
        if (bytes.size < 7 || bytes[0] != VERSION || bytes[1].toInt() and 0x80 == 0) {
            return null
        }
        val requestId = ByteBuffer.wrap(bytes, 2, 4).order(ByteOrder.BIG_ENDIAN).int
        return Response(
            command = (bytes[1].toInt() and 0x7F).toByte(),
            requestId = requestId,
            status = bytes[6].toInt() and 0xFF,
            body = bytes.copyOfRange(7, bytes.size),
        )
    }

    fun parseChallenge(body: ByteArray): Challenge? {
        if (body.size != 1 + SALT_SIZE + NONCE_SIZE + 4 + 4) return null
        val buffer = ByteBuffer.wrap(body).order(ByteOrder.BIG_ENDIAN)
        val claimed = buffer.get().toInt() != 0
        val salt = ByteArray(SALT_SIZE).also(buffer::get)
        val nonce = ByteArray(NONCE_SIZE).also(buffer::get)
        val iterations = buffer.int
        val retryAfter = buffer.int.toLong() and 0xFFFF_FFFFL
        if (iterations !in 10_000..2_000_000) return null
        return Challenge(claimed, salt, nonce, iterations, retryAfter)
    }

    fun parseStatus(body: ByteArray): Status? {
        val fixedLength = 1 + 4 + 4 + (8 * 10) + 2 + 2 + 3 + 1
        if (body.size < fixedLength) return null
        val buffer = ByteBuffer.wrap(body).order(ByteOrder.BIG_ENDIAN)
        val claimed = buffer.get().toInt() != 0
        val firmwareVersion = buffer.int.toLong() and 0xFFFF_FFFFL
        val protocolVersion = buffer.int.toLong() and 0xFFFF_FFFFL
        val values = LongArray(10) { buffer.long }
        val mailboxUsed = buffer.short.toInt() and 0xFFFF
        val mailboxCapacity = buffer.short.toInt() and 0xFFFF
        val mailboxAvailable = buffer.get().toInt() != 0
        val clockValid = buffer.get().toInt() != 0
        val clockAuthoritative = buffer.get().toInt() != 0
        val nicknameLength = buffer.get().toInt() and 0xFF
        if (nicknameLength > buffer.remaining()) return null
        val nicknameBytes = ByteArray(nicknameLength).also(buffer::get)
        val freeHeap: Long?
        val minFreeHeap: Long?
        when (buffer.remaining()) {
            0 -> {
                freeHeap = null
                minFreeHeap = null
            }
            8 -> {
                freeHeap = buffer.int.toLong() and 0xFFFF_FFFFL
                minFreeHeap = buffer.int.toLong() and 0xFFFF_FFFFL
            }
            else -> return null
        }
        return Status(
            claimed = claimed,
            firmwareVersion = firmwareVersion,
            protocolVersion = protocolVersion,
            uptimeMs = values[0],
            bootCount = values[1],
            packetsReceived = values[2],
            packetsForwarded = values[3],
            packetsStored = values[4],
            packetsDelivered = values[5],
            packetsDeduplicated = values[6],
            packetsExpired = values[7],
            packetsRejected = values[8],
            lastActivityUptimeMs = values[9],
            mailboxUsed = mailboxUsed,
            mailboxCapacity = mailboxCapacity,
            mailboxAvailable = mailboxAvailable,
            clockValid = clockValid,
            clockAuthoritative = clockAuthoritative,
            nickname = nicknameBytes.toString(Charsets.US_ASCII),
            freeHeap = freeHeap,
            minFreeHeap = minFreeHeap,
        )
    }
}

internal data class PendingAnchorAdminOperation(
    val peerId: String,
    val command: Byte,
    val password: CharArray?,
    val newPassword: CharArray?,
    val value: String?,
) {
    fun clearSecrets() {
        password?.fill('\u0000')
        newPassword?.fill('\u0000')
    }
}
