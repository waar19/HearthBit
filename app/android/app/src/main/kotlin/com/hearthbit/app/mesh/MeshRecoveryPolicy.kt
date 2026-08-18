package com.hearthbit.app.mesh

internal enum class NoiseRecoveryAction {
    NONE,
    RENEGOTIATE,
}

internal class NoiseFailureRecoveryTracker(
    private val failureThreshold: Int = 3,
) {
    private val failuresByPeer = mutableMapOf<String, Int>()

    init {
        require(failureThreshold > 0)
    }

    @Synchronized
    fun recordFailure(peerId: String, hadEstablishedSession: Boolean): NoiseRecoveryAction {
        if (!hadEstablishedSession) {
            failuresByPeer.remove(peerId)
            return NoiseRecoveryAction.RENEGOTIATE
        }
        val failures = (failuresByPeer[peerId] ?: 0) + 1
        if (failures >= failureThreshold) {
            failuresByPeer.remove(peerId)
            return NoiseRecoveryAction.RENEGOTIATE
        }
        failuresByPeer[peerId] = failures
        return NoiseRecoveryAction.NONE
    }

    @Synchronized
    fun recordSuccess(peerId: String) {
        failuresByPeer.remove(peerId)
    }

    @Synchronized
    fun clear(peerId: String) {
        failuresByPeer.remove(peerId)
    }

    @Synchronized
    fun clear() {
        failuresByPeer.clear()
    }
}

internal object ConnectionPriorityPolicy {
    /**
     * La selección de vecinos ya ordena y reemplaza por relación/RSSI. Esta
     * comprobación final evita exceder el máximo ante callbacks concurrentes.
     */
    fun canOpenClientConnection(
        maximumConnections: Int,
        activeConnections: Int,
        @Suppress("UNUSED_PARAMETER") knownPeer: Boolean,
    ): Boolean = maximumConnections > 0 && activeConnections < maximumConnections
}
