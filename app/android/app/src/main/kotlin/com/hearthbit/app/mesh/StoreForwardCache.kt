package com.hearthbit.app.mesh

import android.content.Context
import android.util.Base64

internal class StoreForwardCache(context: Context) {
    private val preferences = context.getSharedPreferences(
        "hearthbit_store_forward",
        Context.MODE_PRIVATE,
    )

    @Synchronized
    fun put(packet: MeshProtocol.Packet) {
        if (!isReplaySafe(packet)) return
        val recipient = packet.recipientId ?: return
        if (recipient.contentEquals(MeshProtocol.broadcastRecipient)) return
        val now = System.currentTimeMillis()
        val entries = readValid(now).toMutableList()
        val encoded = Base64.encodeToString(
            MeshProtocol.encode(packet, padded = false),
            Base64.NO_WRAP,
        )
        if (entries.none { it.encoded == encoded }) {
            entries += Entry(now + LIFETIME_MS, encoded)
        }
        write(entries.takeLast(MAX_ENTRIES))
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

    fun clear() {
        preferences.edit().clear().apply()
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

    private fun isReplaySafe(packet: MeshProtocol.Packet): Boolean =
        packet.type != MeshProtocol.TYPE_NOISE_HANDSHAKE &&
            packet.type != MeshProtocol.TYPE_NOISE_ENCRYPTED &&
            packet.type != MeshProtocol.TYPE_BEACON_CONTROL

    private companion object {
        const val KEY_ENTRIES = "packets"
        const val MAX_ENTRIES = 100
        const val LIFETIME_MS = 12 * 60 * 60 * 1_000L
    }
}
