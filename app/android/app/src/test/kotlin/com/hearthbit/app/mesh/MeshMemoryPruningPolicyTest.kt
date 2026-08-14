package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshMemoryPruningPolicyTest {
    private val now = MeshMemoryPruningPolicy.MAX_AGE_MS * 2

    @Test
    fun `expulsa elementos no vistos por mas de veinticuatro horas`() {
        val evicted = MeshMemoryPruningPolicy.keysToEvict(
            candidates = listOf(
                candidate("boundary", now - MeshMemoryPruningPolicy.MAX_AGE_MS),
                candidate("stale", now - MeshMemoryPruningPolicy.MAX_AGE_MS - 1),
                candidate("recent", now - 1),
            ),
            now = now,
        )

        assertEquals(setOf("stale"), evicted)
    }

    @Test
    fun `aplica el limite de doscientos cincuenta y seis por LRU`() {
        val candidates = (0..MeshMemoryPruningPolicy.MAX_ENTRIES).map { index ->
            candidate("peer-$index", index.toLong())
        }
        val evicted = MeshMemoryPruningPolicy.keysToEvict(
            candidates = candidates,
            now = MeshMemoryPruningPolicy.MAX_ENTRIES.toLong(),
            maximumAgeMs = Long.MAX_VALUE,
        )

        assertEquals(setOf("peer-0"), evicted)
    }

    @Test
    fun `nunca expulsa elementos protegidos`() {
        val evicted = MeshMemoryPruningPolicy.keysToEvict(
            candidates = listOf(
                candidate("active-link", 0, protected = true),
                candidate("active-session", 1, protected = true),
                candidate("pending-message", 2, protected = true),
                candidate("evictable", 3),
            ),
            now = now,
            maximumEntries = 0,
        )

        assertTrue("evictable" in evicted)
        assertFalse("active-link" in evicted)
        assertFalse("active-session" in evicted)
        assertFalse("pending-message" in evicted)
    }

    private fun candidate(
        key: String,
        lastSeenAt: Long,
        protected: Boolean = false,
    ) = MemoryPruningCandidate(key, lastSeenAt, protected)
}
