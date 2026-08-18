package com.hearthbit.app.mesh

internal fun interface RelayDampingCancellation {
    fun cancel()
}

internal fun interface RelayDampingScheduler {
    fun schedule(delayMs: Long, task: () -> Unit): RelayDampingCancellation
}

internal class RelayDampingCoordinator(
    private val localSalt: () -> String,
    private val scheduler: RelayDampingScheduler,
    private val maximumPendingRelays: Int = MAXIMUM_PENDING_RELAYS,
) {
    private data class SourceKey(val value: String?)

    private data class PendingRelay(
        val emergency: Boolean,
        val relay: () -> Unit,
        val sources: MutableSet<SourceKey>,
        var cancellation: RelayDampingCancellation? = null,
    )

    private val pending = LinkedHashMap<String, PendingRelay>()
    private var scheduled = 0L
    private var expired = 0L
    private var suppressed = 0L

    init {
        require(maximumPendingRelays > 0)
    }

    @Synchronized
    fun schedule(
        fingerprint: String,
        emergency: Boolean,
        initialSource: String?,
        relay: () -> Unit,
    ): Boolean {
        if (pending.containsKey(fingerprint)) return false
        if (pending.size >= maximumPendingRelays) {
            val iterator = pending.entries.iterator()
            if (iterator.hasNext()) {
                val evicted = iterator.next().value
                iterator.remove()
                evicted.cancellation?.cancel()
            }
        }

        val pendingRelay = PendingRelay(
            emergency = emergency,
            relay = relay,
            sources = mutableSetOf(SourceKey(initialSource)),
        )
        pending[fingerprint] = pendingRelay
        return try {
            val delayMs = RelayDampingPolicy.jitterMs(
                fingerprint = fingerprint,
                localSalt = localSalt(),
                emergency = emergency,
            )
            pendingRelay.cancellation = scheduler.schedule(delayMs) {
                expire(fingerprint, pendingRelay)
            }
            scheduled += 1
            true
        } catch (error: Throwable) {
            pending.remove(fingerprint, pendingRelay)
            throw error
        }
    }

    @Synchronized
    fun observeDuplicate(fingerprint: String, source: String?): Boolean {
        val relay = pending[fingerprint] ?: return false
        return relay.sources.add(SourceKey(source))
    }

    @Synchronized
    fun isPending(fingerprint: String): Boolean = pending.containsKey(fingerprint)

    fun clear() {
        val cancellations = synchronized(this) {
            pending.values.mapNotNull(PendingRelay::cancellation).also {
                pending.clear()
            }
        }
        cancellations.forEach(RelayDampingCancellation::cancel)
    }

    @Synchronized
    internal fun pendingCount(): Int = pending.size

    /** Contadores acumulados durante la vida de esta instancia. */
    @Synchronized
    fun operationalCounters(): Map<String, Long> = mapOf(
        "relayDampingSuppressed" to suppressed,
        "relayDampingScheduled" to scheduled,
        "relayDampingExpired" to expired,
    )

    private fun expire(fingerprint: String, expected: PendingRelay) {
        val relay = synchronized(this) {
            val current = pending[fingerprint]
            if (current !== expected) return@synchronized null
            pending.remove(fingerprint)
            expired += 1
            val shouldRelay = RelayDampingPolicy.shouldRelay(
                additionalCopies = current.sources.size - 1,
                emergency = current.emergency,
            )
            if (!shouldRelay) {
                suppressed += 1
            }
            current.relay.takeIf { shouldRelay }
        }
        relay?.invoke()
    }

    companion object {
        const val MAXIMUM_PENDING_RELAYS = 1_024
    }
}
