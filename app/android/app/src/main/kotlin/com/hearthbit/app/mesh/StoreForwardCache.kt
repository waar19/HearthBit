package com.hearthbit.app.mesh

import android.content.Context
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

internal class StoreForwardCache(context: Context) {
    private val legacyPreferences = context.getSharedPreferences(
        LEGACY_PREFERENCES,
        Context.MODE_PRIVATE,
    )
    private val preferences = EncryptedSharedPreferences.create(
        context,
        ENCRYPTED_PREFERENCES,
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    init {
        val legacyEntries = legacyPreferences.getStringSet(KEY_ENTRIES, emptySet()).orEmpty()
        if (legacyEntries.isNotEmpty() &&
            preferences.getStringSet(KEY_ENTRIES, emptySet()).isNullOrEmpty()
        ) {
            preferences.edit().putStringSet(KEY_ENTRIES, legacyEntries).commit()
        }
        legacyPreferences.edit().clear().commit()
    }

    @Synchronized
    fun put(packet: MeshProtocol.Packet) {
        if (!isReplaySafe(packet)) return
        val emergency = MeshProtocol.isEmergencyPublicPacket(packet)
        val recipient = packet.recipientId
        if (!emergency &&
            (recipient == null || recipient.contentEquals(MeshProtocol.broadcastRecipient))
        ) {
            return
        }
        val now = System.currentTimeMillis()
        val entries = readValid(now).toMutableList()
        val encoded = Base64.encodeToString(
            MeshProtocol.encode(packet, padded = false),
            Base64.NO_WRAP,
        )
        if (entries.none { it.encoded == encoded }) {
            entries += Entry(
                now + if (emergency) EMERGENCY_LIFETIME_MS else LIFETIME_MS,
                encoded,
            )
        }
        write(
            entries.sortedWith(
                compareBy<Entry> { entry -> isEmergency(entry) }
                    .thenBy(Entry::expiry),
            ).takeLast(MAX_ENTRIES),
        )
    }

    @Synchronized
    fun forRecipient(recipient: ByteArray): List<MeshProtocol.Packet> {
        val now = System.currentTimeMillis()
        val entries = readValid(now)
        write(entries)
        return entries.mapNotNull {
            runCatching { Base64.decode(it.encoded, Base64.NO_WRAP) }
                .getOrNull()
                ?.let(MeshProtocol::decode)
        }.filter {
            isReplaySafe(it) && it.recipientId?.contentEquals(recipient) == true
        }
    }

    /**
     * Destinatarios que deben conservar metadatos de peer mientras exista un
     * paquete pendiente de entrega en la caché.
     */
    @Synchronized
    fun pendingRecipientPeerIds(now: Long = System.currentTimeMillis()): Set<String> {
        val entries = readValid(now)
        return entries.asSequence()
            .mapNotNull { entry ->
                runCatching { Base64.decode(entry.encoded, Base64.NO_WRAP) }
                    .getOrNull()
                    ?.let(MeshProtocol::decode)
            }
            .filter { isReplaySafe(it) }
            .mapNotNull { it.recipientId }
            .filterNot { it.contentEquals(MeshProtocol.broadcastRecipient) }
            .map(MeshProtocol::hex)
            .toSet()
    }

    @Synchronized
    fun emergencyBroadcasts(now: Long = System.currentTimeMillis()): List<MeshProtocol.Packet> =
        readValid(now).mapNotNull(::decode).filter(MeshProtocol::isEmergencyPublicPacket)

    @Synchronized
    fun emergencyByHash(canonicalHash: String): MeshProtocol.Packet? {
        val normalized = canonicalHash.lowercase()
        return emergencyBroadcasts().firstOrNull {
            MeshProtocol.hex(MeshProtocol.emergencyCanonicalHash(it)) == normalized
        }
    }

    @Synchronized
    fun entryCount(now: Long = System.currentTimeMillis()): Int = readValid(now).size

    fun clear() {
        preferences.edit().clear().commit()
        legacyPreferences.edit().clear().commit()
    }

    private fun readValid(now: Long): List<Entry> = preferences
        .getStringSet(KEY_ENTRIES, emptySet())
        .orEmpty()
        .mapNotNull { value ->
            val separator = value.indexOf(':')
            if (separator <= 0) return@mapNotNull null
            val expiry = value.substring(0, separator).toLongOrNull() ?: return@mapNotNull null
            if (expiry <= now) return@mapNotNull null
            Entry(expiry, value.substring(separator + 1))
        }
        .sortedBy(Entry::expiry)

    private fun write(entries: List<Entry>) {
        preferences.edit().putStringSet(
            KEY_ENTRIES,
            entries.mapTo(mutableSetOf()) { "${it.expiry}:${it.encoded}" },
        ).apply()
    }

    private data class Entry(val expiry: Long, val encoded: String)

    private fun decode(entry: Entry): MeshProtocol.Packet? =
        runCatching { Base64.decode(entry.encoded, Base64.NO_WRAP) }
            .getOrNull()
            ?.let(MeshProtocol::decode)

    private fun isEmergency(entry: Entry): Boolean =
        decode(entry)?.let(MeshProtocol::isEmergencyPublicPacket) == true

    private fun isReplaySafe(packet: MeshProtocol.Packet): Boolean =
        packet.type != MeshProtocol.TYPE_NOISE_HANDSHAKE &&
            packet.type != MeshProtocol.TYPE_NOISE_ENCRYPTED &&
            packet.type != MeshProtocol.TYPE_BEACON_CONTROL

    private companion object {
        const val LEGACY_PREFERENCES = "hearthbit_store_forward"
        const val ENCRYPTED_PREFERENCES = "hearthbit_store_forward_encrypted"
        const val KEY_ENTRIES = "packets"
        const val MAX_ENTRIES = 100
        const val LIFETIME_MS = 12 * 60 * 60 * 1_000L
        const val EMERGENCY_LIFETIME_MS = 24 * 60 * 60 * 1_000L
    }
}
