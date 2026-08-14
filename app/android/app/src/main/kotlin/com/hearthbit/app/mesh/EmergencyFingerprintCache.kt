package com.hearthbit.app.mesh

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

internal class EmergencyFingerprintCache(context: Context) {
    private val preferences = EncryptedSharedPreferences.create(
        context,
        "hearthbit_emergency_fingerprints",
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    @Synchronized
    fun seenOrRemember(
        fingerprint: String,
        now: Long = System.currentTimeMillis(),
    ): Boolean {
        val normalized = fingerprint.lowercase()
        val valid = preferences.getStringSet(KEY_ENTRIES, emptySet())
            .orEmpty()
            .mapNotNull(::decode)
            .filter { now - it.timestamp <= LIFETIME_MS }
            .sortedBy(Entry::timestamp)
            .toMutableList()
        val duplicate = valid.any { it.fingerprint == normalized }
        if (!duplicate) valid += Entry(now, normalized)
        preferences.edit().putStringSet(
            KEY_ENTRIES,
            valid.takeLast(MAX_ENTRIES)
                .mapTo(mutableSetOf()) { "${it.timestamp}:${it.fingerprint}" },
        ).commit()
        return duplicate
    }

    fun clear() {
        preferences.edit().clear().commit()
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

    private companion object {
        const val KEY_ENTRIES = "entries"
        const val MAX_ENTRIES = 512
        const val LIFETIME_MS = 24 * 60 * 60 * 1_000L
    }
}
