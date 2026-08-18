package com.hearthbit.app.mesh

import android.content.Context

internal interface EmergencyFingerprintStorage {
    fun getStringSet(key: String): Set<String>
    fun putStringSet(key: String, value: Set<String>): Boolean
    fun clear(): Boolean
}

internal class EmergencyFingerprintCache private constructor(
    private val storage: EmergencyFingerprintStorage,
    private val maximumEntries: Int,
) {
    constructor(context: Context) : this(
        SecureEmergencyFingerprintStorage(
            KeystoreSecureStore.open(context, PREFERENCES),
        ),
        MAX_ENTRIES,
    )

    internal constructor(
        storage: EmergencyFingerprintStorage,
        maximumEntries: Int = MAX_ENTRIES,
        testOnly: Unit = Unit,
    ) : this(storage, maximumEntries) {
        require(maximumEntries > 0)
    }

    @Synchronized
    fun seenOrRemember(
        fingerprint: String,
        now: Long = System.currentTimeMillis(),
    ): Boolean {
        val normalized = fingerprint.lowercase()
        val valid = storage.getStringSet(KEY_ENTRIES)
            .mapNotNull(::decode)
            .filter { now - it.timestamp <= LIFETIME_MS }
            .sortedBy(Entry::timestamp)
            .toMutableList()
        val duplicate = valid.any { it.fingerprint == normalized }
        if (!duplicate) valid += Entry(now, normalized)
        check(
            storage.putStringSet(
                KEY_ENTRIES,
                valid.takeLast(maximumEntries)
                    .mapTo(mutableSetOf()) { "${it.timestamp}:${it.fingerprint}" },
            ),
        )
        return duplicate
    }

    fun clear() {
        check(storage.clear())
    }

    private fun decode(value: String): Entry? {
        val separator = value.indexOf(':')
        if (separator <= 0) return null
        val timestamp = value.substring(0, separator).toLongOrNull() ?: return null
        val fingerprint = value.substring(separator + 1)
        if (!fingerprint.matches(Regex("^[0-9a-f]{64}$"))) return null
        return Entry(timestamp, fingerprint)
    }

    private data class Entry(val timestamp: Long, val fingerprint: String)

    companion object {
        private const val PREFERENCES = "hearthbit_emergency_fingerprints"
        const val KEY_ENTRIES = "entries"
        const val MAX_ENTRIES = 2_048
        const val LIFETIME_MS = 24 * 60 * 60 * 1_000L
    }
}

private class SecureEmergencyFingerprintStorage(
    private val store: KeystoreSecureStore,
) : EmergencyFingerprintStorage {
    override fun getStringSet(key: String): Set<String> = store.getStringSet(key)
    override fun putStringSet(key: String, value: Set<String>): Boolean =
        store.putStringSet(key, value)
    override fun clear(): Boolean = store.clear()
}
