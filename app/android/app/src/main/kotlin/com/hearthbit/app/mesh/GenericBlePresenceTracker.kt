package com.hearthbit.app.mesh

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Convierte anuncios BLE no-HearthBit en presencia anónima. La clave nace en
 * memoria y los identificadores visibles rotan; nunca recibe ni conserva MAC
 * o nombre Bluetooth.
 */
internal class GenericBlePresenceTracker(
    private val sessionSecret: ByteArray = ByteArray(32).also(SecureRandom()::nextBytes),
    private val rotationMs: Long = DEFAULT_ROTATION_MS,
    private val staleAfterMs: Long = DEFAULT_STALE_AFTER_MS,
    private val emitIntervalMs: Long = DEFAULT_EMIT_INTERVAL_MS,
    private val maxObservations: Int = DEFAULT_MAX_OBSERVATIONS,
) {
    data class Presence(
        val localId: String,
        val rssi: Int,
        val lastSeen: Long,
    ) {
        fun toEventMap(): Map<String, Any?> = mapOf(
            "id" to localId,
            "role" to MeshNodeRole.PHONE_BEACON.wireName,
            "kind" to "genericBle",
            "chatAvailable" to false,
            "rssi" to rssi,
            "lastSeen" to lastSeen,
        )
    }

    private data class Observation(
        var localId: String,
        var rssi: Int,
        var lastSeen: Long,
    )

    private val observations = LinkedHashMap<String, Observation>()
    private var lastEmittedAt: Long? = null

    init {
        require(sessionSecret.isNotEmpty())
        require(rotationMs > 0)
        require(staleAfterMs > 0)
        require(emitIntervalMs >= 0)
        require(maxObservations > 0)
    }

    /**
     * [advertisementMaterial] debe contener solo datos de servicio/fabricante,
     * nunca dirección ni nombre. Devuelve snapshot solo cuando la UI necesita
     * refrescarse.
     */
    @Synchronized
    fun observe(advertisementMaterial: ByteArray, rssi: Int, now: Long): List<Presence>? {
        if (!record(advertisementMaterial, rssi, now)) return null
        val previous = lastEmittedAt
        val shouldEmit = previous == null || now - previous >= emitIntervalMs
        if (!shouldEmit) return null
        lastEmittedAt = now
        return snapshot(now)
    }

    /**
     * Registra una observación sin construir el snapshot para Flutter. El motor
     * usa este camino caliente y agrupa las emisiones en el hilo principal.
     */
    @Synchronized
    fun record(advertisementMaterial: ByteArray, rssi: Int, now: Long): Boolean {
        if (advertisementMaterial.isEmpty()) return false
        prune(now)
        val trackingDigest = hmac(byteArrayOf(TRACKING_DOMAIN) + advertisementMaterial)
        val trackingKey = trackingDigest.toHex()
        val localId = rotatingId(trackingDigest, now)
        val existing = observations[trackingKey]
        if (existing == null) {
            observations[trackingKey] = Observation(localId, rssi, now)
        } else {
            existing.localId = localId
            existing.rssi = rssi
            existing.lastSeen = now
        }
        while (observations.size > maxObservations) {
            val oldest = observations.minByOrNull { it.value.lastSeen }?.key ?: break
            observations.remove(oldest)
        }
        return true
    }

    @Synchronized
    fun snapshot(now: Long): List<Presence> {
        prune(now)
        return observations.values
            .map { Presence(it.localId, it.rssi, it.lastSeen) }
            .sortedByDescending(Presence::lastSeen)
    }

    @Synchronized
    fun clear() {
        observations.clear()
        lastEmittedAt = null
    }

    private fun prune(now: Long) {
        observations.entries.removeIf { now - it.value.lastSeen > staleAfterMs }
    }

    private fun rotatingId(trackingDigest: ByteArray, now: Long): String {
        val epoch = Math.floorDiv(now, rotationMs)
        val epochBytes = ByteBuffer.allocate(Long.SIZE_BYTES)
            .order(ByteOrder.BIG_ENDIAN)
            .putLong(epoch)
            .array()
        return hmac(byteArrayOf(IDENTIFIER_DOMAIN) + epochBytes + trackingDigest)
            .copyOfRange(0, LOCAL_ID_BYTES)
            .toHex()
    }

    private fun hmac(value: ByteArray): ByteArray {
        val mac = Mac.getInstance(HMAC_ALGORITHM)
        mac.init(SecretKeySpec(sessionSecret, HMAC_ALGORITHM))
        return mac.doFinal(value)
    }

    private fun ByteArray.toHex(): String =
        joinToString(separator = "") { "%02x".format(it) }

    companion object {
        const val DEFAULT_ROTATION_MS = 15 * 60_000L
        const val DEFAULT_STALE_AFTER_MS = 45_000L
        const val DEFAULT_EMIT_INTERVAL_MS = 5_000L
        const val DEFAULT_MAX_OBSERVATIONS = 64
        private const val LOCAL_ID_BYTES = 12
        private const val HMAC_ALGORITHM = "HmacSHA256"
        private const val TRACKING_DOMAIN: Byte = 0x01
        private const val IDENTIFIER_DOMAIN: Byte = 0x02
    }
}
