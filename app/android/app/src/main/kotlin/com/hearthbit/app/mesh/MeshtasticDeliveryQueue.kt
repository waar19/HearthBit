package com.hearthbit.app.mesh

internal enum class MeshtasticQueueOfferResult {
    ENQUEUED,
    EVICTED_STANDARD,
    REJECTED_FULL,
}

/**
 * Bounded priority queue for serialized Meshtastic BLE writes.
 *
 * Frames remain FIFO within their priority. Critical traffic can replace the
 * oldest standard frame when full, but can never exceed [capacity].
 */
internal class MeshtasticDeliveryQueue(
    private val capacity: Int,
    private val maxCriticalBurst: Int = DEFAULT_MAX_CRITICAL_BURST,
) {
    private val lock = Any()
    private val critical = ArrayDeque<ByteArray>()
    private val standard = ArrayDeque<ByteArray>()
    private var consecutiveCritical = 0

    init {
        require(capacity > 0)
        require(maxCriticalBurst > 0)
    }

    val size: Int
        get() = synchronized(lock) { critical.size + standard.size }

    fun offer(frame: ByteArray, priority: LinkPriority): MeshtasticQueueOfferResult =
        synchronized(lock) {
            when (priority) {
                LinkPriority.STANDARD -> {
                    if (currentSize() >= capacity) {
                        MeshtasticQueueOfferResult.REJECTED_FULL
                    } else {
                        standard.addLast(frame.copyOf())
                        MeshtasticQueueOfferResult.ENQUEUED
                    }
                }

                LinkPriority.CRITICAL -> {
                    val result = when {
                        currentSize() < capacity -> MeshtasticQueueOfferResult.ENQUEUED
                        standard.isNotEmpty() -> {
                            standard.removeFirst()
                            MeshtasticQueueOfferResult.EVICTED_STANDARD
                        }

                        else -> MeshtasticQueueOfferResult.REJECTED_FULL
                    }
                    if (result != MeshtasticQueueOfferResult.REJECTED_FULL) {
                        critical.addLast(frame.copyOf())
                    }
                    result
                }
            }
        }

    fun poll(): ByteArray? = synchronized(lock) {
        when {
            critical.isNotEmpty() &&
                (standard.isEmpty() || consecutiveCritical < maxCriticalBurst) -> {
                consecutiveCritical++
                critical.removeFirst()
            }

            standard.isNotEmpty() -> {
                consecutiveCritical = 0
                standard.removeFirst()
            }

            critical.isNotEmpty() -> {
                consecutiveCritical++
                critical.removeFirst()
            }

            else -> null
        }
    }

    fun clear() {
        synchronized(lock) {
            critical.clear()
            standard.clear()
            consecutiveCritical = 0
        }
    }

    private fun currentSize(): Int = critical.size + standard.size

    private companion object {
        const val DEFAULT_MAX_CRITICAL_BURST = 8
    }
}
