package com.hearthbit.app.mesh

/**
 * Cola FIFO acotada por peer y globalmente.
 *
 * La protección es preferencial: al necesitar espacio se elige primero el
 * trabajo más antiguo de peers no protegidos. Si todos están protegidos, se
 * conserva la cota expulsando de forma determinista el trabajo más antiguo.
 */
internal class BoundedPeerPendingQueue<T>(
    private val maximumPeers: Int = DEFAULT_MAXIMUM_PEERS,
    private val maximumItemsPerPeer: Int = DEFAULT_MAXIMUM_ITEMS_PER_PEER,
    private val maximumItems: Int = DEFAULT_MAXIMUM_ITEMS,
) {
    private data class Entry<T>(
        val sequence: Long,
        val value: T,
    )

    private data class PeerQueue<T>(
        val entries: ArrayDeque<Entry<T>> = ArrayDeque(),
    )

    private val lock = Any()
    private val queues = mutableMapOf<String, PeerQueue<T>>()
    private var nextSequence = 0L
    private var itemCount = 0

    init {
        require(maximumPeers > 0)
        require(maximumItemsPerPeer > 0)
        require(maximumItems > 0)
    }

    val size: Int
        get() = synchronized(lock) { itemCount }

    val peerCount: Int
        get() = synchronized(lock) {
            pruneEmptyQueues()
            queues.size
        }

    fun offer(
        peerId: String,
        value: T,
        protectedPeerIds: Set<String> = emptySet(),
    ): Boolean = synchronized(lock) {
        require(peerId.isNotBlank())
        pruneEmptyQueues()

        val sequence = nextSequence++
        val queue = queues.getOrPut(peerId) { PeerQueue() }
        queue.entries.addLast(Entry(sequence, value))
        itemCount++

        if (queue.entries.size > maximumItemsPerPeer) {
            queue.entries.removeFirst()
            itemCount--
        }

        while (queues.size > maximumPeers) {
            evictOldestPeer(protectedPeerIds)
        }
        while (itemCount > maximumItems) {
            evictOldestItem(protectedPeerIds)
        }
        pruneEmptyQueues()

        queues[peerId]?.entries?.any { it.sequence == sequence } == true
    }

    fun drain(peerId: String): List<T> = synchronized(lock) {
        val queue = queues.remove(peerId) ?: return@synchronized emptyList()
        itemCount -= queue.entries.size
        queue.entries.map(Entry<T>::value)
    }

    fun hasPending(peerId: String): Boolean = synchronized(lock) {
        queues[peerId]?.entries?.isNotEmpty() == true
    }

    fun peerIds(): Set<String> = synchronized(lock) {
        pruneEmptyQueues()
        queues.keys.toSet()
    }

    fun clear() {
        synchronized(lock) {
            queues.clear()
            itemCount = 0
            nextSequence = 0L
        }
    }

    private fun evictOldestPeer(protectedPeerIds: Set<String>) {
        val candidate = oldestPeer(
            queues.entries.filterNot { it.key in protectedPeerIds },
        ) ?: oldestPeer(queues.entries)
        if (candidate != null) {
            queues.remove(candidate.key)
            itemCount -= candidate.value.entries.size
        }
    }

    private fun evictOldestItem(protectedPeerIds: Set<String>) {
        val candidate = oldestItem(
            queues.entries.filterNot { it.key in protectedPeerIds },
        ) ?: oldestItem(queues.entries)
        if (candidate != null) {
            candidate.value.entries.removeFirst()
            itemCount--
        }
    }

    private fun oldestPeer(
        candidates: Collection<Map.Entry<String, PeerQueue<T>>>,
    ): Map.Entry<String, PeerQueue<T>>? =
        candidates.minWithOrNull(
            compareBy<Map.Entry<String, PeerQueue<T>>>(
                { it.value.entries.first().sequence },
                { it.key },
            ),
        )

    private fun oldestItem(
        candidates: Collection<Map.Entry<String, PeerQueue<T>>>,
    ): Map.Entry<String, PeerQueue<T>>? =
        candidates
            .filter { it.value.entries.isNotEmpty() }
            .minWithOrNull(
                compareBy<Map.Entry<String, PeerQueue<T>>>(
                    { it.value.entries.first().sequence },
                    { it.key },
                ),
            )

    private fun pruneEmptyQueues() {
        queues.entries.removeIf { it.value.entries.isEmpty() }
    }

    private companion object {
        const val DEFAULT_MAXIMUM_PEERS = 256
        const val DEFAULT_MAXIMUM_ITEMS_PER_PEER = 64
        const val DEFAULT_MAXIMUM_ITEMS = 1_024
    }
}
