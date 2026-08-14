package com.hearthbit.app.mesh

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.SecureRandom

internal object RangingControlProtocol {
    const val VERSION: Byte = 1
    const val NONCE_SIZE = 16
    const val FIXED_SIZE = 38
    const val MAX_OPAQUE_BYTES = 1024
    const val CLOCK_SKEW_MS = 2 * 60 * 1_000L

    const val ACTION_CAPABILITIES: Byte = 1
    const val ACTION_REQUEST: Byte = 2
    const val ACTION_ACCEPT: Byte = 3
    const val ACTION_ACOUSTIC_READY: Byte = 4
    const val ACTION_ACOUSTIC_CHIRP: Byte = 5
    const val ACTION_ACOUSTIC_OBSERVATION: Byte = 6
    const val ACTION_RESULT: Byte = 7
    const val ACTION_STOP: Byte = 8
    const val ACTION_ERROR: Byte = 9
    const val ACTION_OOB_DATA: Byte = 10

    const val TECHNOLOGY_NONE: Byte = 0
    const val TECHNOLOGY_BLE_CS: Byte = 1
    const val TECHNOLOGY_WIFI_NAN_RTT: Byte = 2
    const val TECHNOLOGY_BLE_RSSI: Byte = 3
    const val TECHNOLOGY_ACOUSTIC: Byte = 4

    data class Control(
        val action: Byte,
        val technology: Byte,
        val sessionNonce: ByteArray,
        val round: Int,
        val value: Double,
        val errorMeters: Float,
        val confidence: Float,
        val opaqueData: ByteArray,
    )

    fun encode(control: Control): ByteArray {
        require(control.action in ACTION_CAPABILITIES..ACTION_OOB_DATA)
        require(control.technology in TECHNOLOGY_NONE..TECHNOLOGY_ACOUSTIC)
        require(control.sessionNonce.size == NONCE_SIZE)
        require(control.round in 0..255)
        require(control.value.isFinite())
        require(control.errorMeters.isFinite() && control.errorMeters >= 0)
        require(control.confidence.isFinite() && control.confidence in 0f..1f)
        require(control.opaqueData.size <= MAX_OPAQUE_BYTES)
        return ByteBuffer.allocate(FIXED_SIZE + control.opaqueData.size)
            .order(ByteOrder.BIG_ENDIAN)
            .put(VERSION)
            .put(control.action)
            .put(control.technology)
            .put(control.round.toByte())
            .put(control.sessionNonce)
            .putDouble(control.value)
            .putFloat(control.errorMeters)
            .putFloat(control.confidence)
            .putShort(control.opaqueData.size.toShort())
            .put(control.opaqueData)
            .array()
    }

    fun decode(payload: ByteArray): Control? {
        if (payload.size < FIXED_SIZE || payload[0] != VERSION) return null
        return runCatching {
            val input = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
            input.get()
            val action = input.get()
            val technology = input.get()
            val round = input.get().toInt() and 0xFF
            val nonce = ByteArray(NONCE_SIZE).also(input::get)
            val value = input.double
            val error = input.float
            val confidence = input.float
            val opaqueLength = input.short.toInt() and 0xFFFF
            if (action !in ACTION_CAPABILITIES..ACTION_OOB_DATA ||
                technology !in TECHNOLOGY_NONE..TECHNOLOGY_ACOUSTIC ||
                opaqueLength > MAX_OPAQUE_BYTES ||
                payload.size != FIXED_SIZE + opaqueLength ||
                !value.isFinite() ||
                !error.isFinite() ||
                error < 0 ||
                !confidence.isFinite() ||
                confidence !in 0f..1f
            ) {
                return null
            }
            Control(
                action = action,
                technology = technology,
                sessionNonce = nonce,
                round = round,
                value = value,
                errorMeters = error,
                confidence = confidence,
                opaqueData = ByteArray(opaqueLength).also(input::get),
            )
        }.getOrNull()
    }

    fun randomNonce(): ByteArray = ByteArray(NONCE_SIZE).also(SecureRandom()::nextBytes)

    fun hasValidTimestamp(timestamp: Long, now: Long = System.currentTimeMillis()): Boolean =
        timestamp in (now - CLOCK_SKEW_MS)..(now + CLOCK_SKEW_MS)
}
