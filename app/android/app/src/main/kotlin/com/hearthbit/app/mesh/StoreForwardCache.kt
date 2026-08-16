package com.hearthbit.app.mesh

import android.content.Context
import android.util.Base64

internal class StoreForwardCache(context: Context) {
    private val legacyPreferences = context.getSharedPreferences(
        LEGACY_PREFERENCES,
        Context.MODE_PRIVATE,
    )
    private val preferences = KeystoreSecureStore.open(context, ENCRYPTED_PREFERENCES)

    init {
        val legacyEntries = legacyPreferences.getStringSet(KEY_ENTRIES, emptySet()).orEmpty()
        if (legacyEntries.isNotEmpty() &&
            preferences.getStringSet(KEY_ENTRIES).isEmpty()
        ) {
            check(preferences.putStringSet(KEY_ENTRIES, legacyEntries))
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
                StoreForwardRetentionPolicy.expiryAt(now, emergency),
                encoded,
            )
        }
        write(
            retain(entries, now),
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
    fun latestLocalSos(
        localSenderId: ByteArray,
        startedAt: Long,
        now: Long = System.currentTimeMillis(),
    ): MeshProtocol.Packet? = EmergencyRebroadcastPolicy.selectLocalSos(
        packets = emergencyBroadcasts(now),
        localSenderId = localSenderId,
        startedAt = startedAt,
    )

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
        preferences.clear()
        legacyPreferences.edit().clear().commit()
    }

    private fun readValid(now: Long): List<Entry> = retain(
        preferences
            .getStringSet(KEY_ENTRIES, emptySet())
            .orEmpty()
            .mapNotNull { value ->
                val separator = value.indexOf(':')
                if (separator <= 0) return@mapNotNull null
                val expiry = value.substring(0, separator).toLongOrNull()
                    ?: return@mapNotNull null
                Entry(expiry, value.substring(separator + 1))
            },
        now,
    ).sortedBy(Entry::expiry)

    private fun retain(entries: List<Entry>, now: Long): List<Entry> =
        StoreForwardRetentionPolicy.retain(
            entries.map { entry ->
                val packet = decode(entry)
                StoreForwardRetentionItem(
                    expiry = entry.expiry,
                    value = entry,
                    emergency = packet?.let(MeshProtocol::isEmergencyPublicPacket) == true,
                    replaySafe = packet?.let(::isReplaySafe) == true,
                )
            },
            now,
        ).map { it.value }

    private fun write(entries: List<Entry>) {
        check(
            preferences.putStringSet(
                KEY_ENTRIES,
                entries.mapTo(mutableSetOf()) { "${it.expiry}:${it.encoded}" },
            ),
        )
    }

    private data class Entry(val expiry: Long, val encoded: String)

    private fun decode(entry: Entry): MeshProtocol.Packet? =
        runCatching { Base64.decode(entry.encoded, Base64.NO_WRAP) }
            .getOrNull()
            ?.let(MeshProtocol::decode)

    private fun isReplaySafe(packet: MeshProtocol.Packet): Boolean {
        val fragmentOriginalType = if (packet.type == MeshProtocol.TYPE_FRAGMENT) {
            MeshProtocol.decodeFragmentPayload(packet.payload)?.originalType
        } else {
            null
        }
        return StoreForwardRetentionPolicy.isPacketReplaySafe(
            packetType = packet.type,
            fragmentedOriginalType = fragmentOriginalType,
        )
    }

    private companion object {
        const val LEGACY_PREFERENCES = "hearthbit_store_forward"
        const val ENCRYPTED_PREFERENCES = "hearthbit_store_forward_encrypted"
        const val KEY_ENTRIES = "packets"
    }
}
