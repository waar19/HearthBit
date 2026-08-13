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
     * En perfiles limitados reserva el último slot saliente para una relación
     * conocida. Nunca excede el máximo y no afecta conexiones GATT entrantes.
     */
    fun canOpenClientConnection(
        maximumConnections: Int,
        activeConnections: Int,
        knownPeer: Boolean,
    ): Boolean {
        if (maximumConnections <= 0 || activeConnections >= maximumConnections) return false
        if (knownPeer || maximumConnections == Int.MAX_VALUE) return true
        return activeConnections < maximumConnections - 1
    }
}
