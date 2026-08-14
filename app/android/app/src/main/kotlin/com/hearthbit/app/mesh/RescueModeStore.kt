package com.hearthbit.app.mesh

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

internal data class RescueModeState(
    val active: Boolean,
    val description: String,
    val startedAt: Long,
    val lastPingAt: Long,
    val expiresAt: Long,
    val intervalMs: Long,
    val pingCount: Long,
) {
    fun asMap(now: Long = System.currentTimeMillis()): Map<String, Any?> {
        val expected = if (active && startedAt > 0L) {
            ((minOf(now, expiresAt) - startedAt).coerceAtLeast(0L) / intervalMs) + 1
        } else {
            0L
        }
        return mapOf(
            "active" to active,
            "description" to description,
            "startedAt" to startedAt,
            "lastPingAt" to lastPingAt,
            "expiresAt" to expiresAt,
            "intervalMs" to intervalMs,
            "expectedPings" to expected,
            "executedPings" to pingCount,
        )
    }
}

/**
 * Estado cifrado del modo rescate. El servicio foreground es su único
 * planificador; Flutter configura y refleja el estado, pero no mantiene timers.
 */
internal class RescueModeStore(context: Context) {
    private val preferences = EncryptedSharedPreferences.create(
        context,
        PREFERENCES,
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    @Synchronized
    fun read(now: Long = System.currentTimeMillis()): RescueModeState {
        val expiresAt = preferences.getLong(KEY_EXPIRES_AT, 0L)
        val active = preferences.getBoolean(KEY_ACTIVE, false) && expiresAt > now
        if (!active && preferences.getBoolean(KEY_ACTIVE, false)) {
            disable()
        }
        return RescueModeState(
            active = active,
            description = preferences.getString(KEY_DESCRIPTION, "").orEmpty(),
            startedAt = preferences.getLong(KEY_STARTED_AT, 0L),
            lastPingAt = preferences.getLong(KEY_LAST_PING_AT, 0L),
            expiresAt = expiresAt,
            intervalMs = preferences.getLong(KEY_INTERVAL_MS, DEFAULT_INTERVAL_MS)
                .coerceIn(MIN_INTERVAL_MS, MAX_INTERVAL_MS),
            pingCount = preferences.getLong(KEY_PING_COUNT, 0L),
        )
    }

    @Synchronized
    fun configure(
        description: String,
        startedAt: Long,
        lastPingAt: Long,
        expiresAt: Long,
        intervalMs: Long,
        now: Long = System.currentTimeMillis(),
    ): RescueModeState {
        val safeStartedAt = startedAt.takeIf { it in 1..now } ?: now
        val safeExpiresAt = expiresAt
            .takeIf { it > now }
            ?.coerceAtMost(safeStartedAt + MAX_LIFETIME_MS)
            ?: (safeStartedAt + MAX_LIFETIME_MS)
        preferences.edit()
            .putBoolean(KEY_ACTIVE, true)
            .putString(KEY_DESCRIPTION, description.trim().take(MAX_DESCRIPTION_LENGTH))
            .putLong(KEY_STARTED_AT, safeStartedAt)
            .putLong(KEY_LAST_PING_AT, lastPingAt.coerceAtLeast(0L))
            .putLong(KEY_EXPIRES_AT, safeExpiresAt)
            .putLong(KEY_INTERVAL_MS, intervalMs.coerceIn(MIN_INTERVAL_MS, MAX_INTERVAL_MS))
            .putLong(KEY_PING_COUNT, if (lastPingAt > 0L) 1L else 0L)
            .commit()
        return read(now)
    }

    @Synchronized
    fun recordPing(timestamp: Long) {
        preferences.edit()
            .putLong(KEY_LAST_PING_AT, timestamp)
            .putLong(KEY_PING_COUNT, preferences.getLong(KEY_PING_COUNT, 0L) + 1)
            .apply()
    }

    @Synchronized
    fun disable() {
        preferences.edit().clear().commit()
    }

    companion object {
        private const val PREFERENCES = "hearthbit_rescue_mode_secure_v1"
        private const val KEY_ACTIVE = "active"
        private const val KEY_DESCRIPTION = "description"
        private const val KEY_STARTED_AT = "started_at"
        private const val KEY_LAST_PING_AT = "last_ping_at"
        private const val KEY_EXPIRES_AT = "expires_at"
        private const val KEY_INTERVAL_MS = "interval_ms"
        private const val KEY_PING_COUNT = "ping_count"
        private const val MAX_DESCRIPTION_LENGTH = 500
        private const val MIN_INTERVAL_MS = 30_000L
        private const val DEFAULT_INTERVAL_MS = 120_000L
        private const val MAX_INTERVAL_MS = 15 * 60_000L
        private const val MAX_LIFETIME_MS = 24 * 60 * 60_000L
    }
}
