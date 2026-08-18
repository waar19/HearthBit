package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EmergencyFingerprintCacheTest {
    @Test
    fun `production capacity is two thousand forty eight`() {
        assertEquals(2_048, EmergencyFingerprintCache.MAX_ENTRIES)
    }

    @Test
    fun `capacity retains the newest fingerprints`() {
        val storage = FakeEmergencyFingerprintStorage()
        val cache = EmergencyFingerprintCache(storage, maximumEntries = 3)
        val fingerprints = (1..4).map(::fingerprint)

        fingerprints.forEachIndexed { index, fingerprint ->
            assertFalse(cache.seenOrRemember(fingerprint, now = index.toLong() + 1L))
        }

        val persisted = storage.values.getValue(EmergencyFingerprintCache.KEY_ENTRIES)
        assertEquals(3, persisted.size)
        assertTrue(persisted.none { it.endsWith(fingerprints.first()) })
        assertTrue(persisted.any { it.endsWith(fingerprints.last()) })
    }

    private fun fingerprint(value: Int): String = value.toString(16).padStart(64, '0')

    private class FakeEmergencyFingerprintStorage : EmergencyFingerprintStorage {
        val values = mutableMapOf<String, Set<String>>()

        override fun getStringSet(key: String): Set<String> = values[key].orEmpty()

        override fun putStringSet(key: String, value: Set<String>): Boolean {
            values[key] = value.toSet()
            return true
        }

        override fun clear(): Boolean {
            values.clear()
            return true
        }
    }
}
