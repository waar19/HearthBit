package com.hearthbit.app.mesh

internal data class MemoryPruningCandidate(
    val key: String,
    val lastSeenAt: Long,
    val protected: Boolean = false,
)

/**
 * Poda por antigüedad y, después, por LRU. Los elementos protegidos nunca se
 * seleccionan, aunque temporalmente impidan cumplir el límite.
 */
internal object MeshMemoryPruningPolicy {
    const val MAX_AGE_MS = 24 * 60 * 60 * 1_000L
    const val MAX_ENTRIES = 256

    fun keysToEvict(
        candidates: Collection<MemoryPruningCandidate>,
        now: Long,
        maximumAgeMs: Long = MAX_AGE_MS,
        maximumEntries: Int = MAX_ENTRIES,
    ): Set<String> {
        require(maximumAgeMs >= 0L)
        require(maximumEntries >= 0)

        val evicted = linkedSetOf<String>()
        candidates.asSequence()
            .filterNot(MemoryPruningCandidate::protected)
            .filter { now - it.lastSeenAt > maximumAgeMs }
            .sortedWith(compareBy(MemoryPruningCandidate::lastSeenAt, MemoryPruningCandidate::key))
            .mapTo(evicted, MemoryPruningCandidate::key)

        val overflow = (candidates.size - evicted.size - maximumEntries).coerceAtLeast(0)
        if (overflow == 0) return evicted

        candidates.asSequence()
            .filterNot(MemoryPruningCandidate::protected)
            .filterNot { it.key in evicted }
            .sortedWith(compareBy(MemoryPruningCandidate::lastSeenAt, MemoryPruningCandidate::key))
            .take(overflow)
            .mapTo(evicted, MemoryPruningCandidate::key)
        return evicted
    }
}
