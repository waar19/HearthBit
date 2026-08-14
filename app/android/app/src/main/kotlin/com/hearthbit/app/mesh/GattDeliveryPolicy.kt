package com.hearthbit.app.mesh

internal data class GattQueuedFrame(
    val bytes: ByteArray,
    val critical: Boolean,
    var failedAttempts: Int = 0,
)

internal sealed class GattDeliveryOutcome {
    data object Advance : GattDeliveryOutcome()
    data class Retry(val delayMs: Long, val attempt: Int) : GattDeliveryOutcome()
    data class Failed(val frame: GattQueuedFrame) : GattDeliveryOutcome()
}

internal class GattDeliveryQueue(
    private val capacity: Int,
    private val criticalOverflow: Int = DEFAULT_CRITICAL_OVERFLOW,
    private val maxRetries: Int = DEFAULT_MAX_RETRIES,
    private val maxCriticalBurst: Int = DEFAULT_MAX_CRITICAL_BURST,
) {
    private val critical = ArrayDeque<GattQueuedFrame>()
    private val normal = ArrayDeque<GattQueuedFrame>()
    private var current: GattQueuedFrame? = null
    private var consecutiveCritical = 0

    init {
        require(capacity > 0)
        require(criticalOverflow >= 0)
        require(maxRetries >= 0)
        require(maxCriticalBurst > 0)
    }

    val size: Int get() = critical.size + normal.size

    fun enqueue(frames: List<ByteArray>, isCritical: Boolean): Boolean {
        if (frames.isEmpty()) return true
        if (isCritical) {
            while (size + frames.size > capacity && normal.isNotEmpty()) {
                val candidate = normal.last()
                if (candidate === current) break
                normal.removeLast()
            }
            if (size + frames.size > capacity + criticalOverflow) return false
            frames.forEach { critical.addLast(GattQueuedFrame(it.copyOf(), critical = true)) }
            return true
        }
        if (size + frames.size > capacity) return false
        frames.forEach { normal.addLast(GattQueuedFrame(it.copyOf(), critical = false)) }
        return true
    }

    fun next(): GattQueuedFrame? {
        current?.let { return it }
        current = when {
            critical.isNotEmpty() &&
                (normal.isEmpty() || consecutiveCritical < maxCriticalBurst) -> critical.first()
            normal.isNotEmpty() -> normal.first()
            critical.isNotEmpty() -> critical.first()
            else -> null
        }
        return current
    }

    fun complete(success: Boolean): GattDeliveryOutcome {
        val frame = checkNotNull(current) { "No GATT frame is in flight" }
        if (success) {
            removeCurrent(frame)
            consecutiveCritical = if (frame.critical) consecutiveCritical + 1 else 0
            return GattDeliveryOutcome.Advance
        }
        frame.failedAttempts++
        if (frame.failedAttempts <= maxRetries) {
            return GattDeliveryOutcome.Retry(
                delayMs = retryDelay(frame.failedAttempts),
                attempt = frame.failedAttempts,
            )
        }
        removeCurrent(frame)
        consecutiveCritical = if (frame.critical) consecutiveCritical + 1 else 0
        return GattDeliveryOutcome.Failed(frame)
    }

    private fun removeCurrent(frame: GattQueuedFrame) {
        val removed = if (frame.critical) critical.removeFirst() else normal.removeFirst()
        check(removed === frame)
        current = null
    }

    private fun retryDelay(attempt: Int): Long =
        (BASE_RETRY_DELAY_MS shl (attempt - 1)).coerceAtMost(MAX_RETRY_DELAY_MS)

    private companion object {
        const val DEFAULT_CRITICAL_OVERFLOW = 64
        const val DEFAULT_MAX_RETRIES = 3
        const val DEFAULT_MAX_CRITICAL_BURST = 8
        const val BASE_RETRY_DELAY_MS = 200L
        const val MAX_RETRY_DELAY_MS = 2_000L
    }
}

internal object GattFramePriority {
    fun forOriginalPacket(encodedPacket: ByteArray): LinkPriority =
        if (isCritical(encodedPacket)) LinkPriority.CRITICAL else LinkPriority.STANDARD

    fun isCritical(encodedFrame: ByteArray): Boolean {
        val packet = MeshProtocol.decode(encodedFrame) ?: return false
        val effectiveType = if (packet.type == MeshProtocol.TYPE_FRAGMENT) {
            MeshProtocol.decodeFragmentPayload(packet.payload)?.originalType ?: return false
        } else {
            packet.type
        }
        return when (effectiveType) {
            MeshProtocol.TYPE_MESSAGE ->
                packet.type == MeshProtocol.TYPE_FRAGMENT ||
                    MeshProtocol.isEmergencyPublicPacket(packet)
            MeshProtocol.TYPE_EMERGENCY_CAPABILITY,
            MeshProtocol.TYPE_EMERGENCY_ACK,
            MeshProtocol.TYPE_RADAR_CONTROL,
            MeshProtocol.TYPE_BEACON_CONTROL,
            MeshProtocol.TYPE_RANGING_CONTROL,
            -> true
            else -> false
        }
    }
}
