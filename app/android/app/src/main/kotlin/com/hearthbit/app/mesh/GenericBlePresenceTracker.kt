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
        var lastEmitted: Long,
    )

    private val observations = LinkedHashMap<String, Observation>()

    init {
        require(sessionSecret.isNotEmpty())
        require(rotationMs > 0)
        require(staleAfterMs > 0)
        require(emitIntervalMs >= 0)
    }

    /**
     * [advertisementMaterial] debe contener solo datos de servicio/fabricante,
     * nunca dirección ni nombre. Devuelve snapshot solo cuando la UI necesita
     * refrescarse.
     */
    @Synchronized
    fun observe(advertisementMaterial: ByteArray, rssi: Int, now: Long): List<Presence>? {
        if (advertisementMaterial.isEmpty()) return null
        prune(now)
        val trackingDigest = hmac(byteArrayOf(TRACKING_DOMAIN) + advertisementMaterial)
        val trackingKey = trackingDigest.toHex()
        val localId = rotatingId(trackingDigest, now)
        val existing = observations[trackingKey]
        val shouldEmit = existing == null ||
            existing.localId != localId ||
            now - existing.lastEmitted >= emitIntervalMs
        if (existing == null) {
            observations[trackingKey] = Observation(localId, rssi, now, now)
        } else {
            existing.localId = localId
            existing.rssi = rssi
            existing.lastSeen = now
            if (shouldEmit) existing.lastEmitted = now
        }
        return if (shouldEmit) snapshot(now) else null
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
        private const val LOCAL_ID_BYTES = 12
        private const val HMAC_ALGORITHM = "HmacSHA256"
        private const val TRACKING_DOMAIN: Byte = 0x01
        private const val IDENTIFIER_DOMAIN: Byte = 0x02
    }
}
