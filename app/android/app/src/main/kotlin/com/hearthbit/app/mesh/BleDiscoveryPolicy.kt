package com.hearthbit.app.mesh

internal object ReconnectBackoffPolicy {
    private val delaysMs = longArrayOf(1_000L, 2_000L, 4_000L, 8_000L, 16_000L, 30_000L)

    const val MAX_FAILED_ATTEMPTS = 6
    const val COOLDOWN_MS = 120_000L

    fun delayMs(failedAttempts: Int, urgent: Boolean = false): Long =
        if (urgent) 0L else delaysMs[failedAttempts.coerceIn(0, delaysMs.lastIndex)]

    fun shouldEnterCooldown(failedAttempts: Int): Boolean =
        failedAttempts >= MAX_FAILED_ATTEMPTS
}

internal data class BleNeighborCandidate(
    val address: String,
    val rssi: Int,
    val knownRelationship: Boolean,
    val protected: Boolean = false,
)

internal data class BleNeighborSelection(
    val connectAddress: String,
    val replaceAddress: String? = null,
)

internal object BleNeighborSelectionPolicy {
    const val SELECTION_WINDOW_MS = 750L
    const val REPLACEMENT_DELAY_MS = 250L
    const val RSSI_HYSTERESIS_DB = 8

    /**
     * Prioriza relaciones conocidas y, dentro de la misma clase, mejor RSSI.
     * Un reemplazo solo ocurre si mejora al vecino elegible por el margen de
     * histéresis. Los vecinos protegidos nunca se consideran para expulsión.
     */
    fun select(
        maximumConnections: Int,
        active: Collection<BleNeighborCandidate>,
        discovered: Collection<BleNeighborCandidate>,
    ): BleNeighborSelection? {
        if (maximumConnections <= 0) return null
        val activeAddresses = active.mapTo(mutableSetOf(), BleNeighborCandidate::address)
        val orderedCandidates = discovered
            .asSequence()
            .filter { it.address !in activeAddresses }
            .sortedWith(candidateComparator)
            .toList()
        if (orderedCandidates.isEmpty()) return null
        if (active.size < maximumConnections) {
            return BleNeighborSelection(connectAddress = orderedCandidates.first().address)
        }

        orderedCandidates.forEach { candidate ->
            val victim = active
                .asSequence()
                .filterNot(BleNeighborCandidate::protected)
                .filterNot { it.knownRelationship && !candidate.knownRelationship }
                .filter {
                    candidate.knownRelationship != it.knownRelationship ||
                        candidate.rssi >= it.rssi + RSSI_HYSTERESIS_DB
                }
                .sortedWith(victimComparator)
                .firstOrNull()
            if (victim != null) {
                return BleNeighborSelection(
                    connectAddress = candidate.address,
                    replaceAddress = victim.address,
                )
            }
        }
        return null
    }

    private val candidateComparator =
        compareByDescending<BleNeighborCandidate> { it.knownRelationship }
            .thenByDescending { it.rssi }
            .thenBy { it.address }

    private val victimComparator =
        compareBy<BleNeighborCandidate> { it.knownRelationship }
            .thenBy { it.rssi }
            .thenBy { it.address }
}

internal data class ServerConnectionCandidate(
    val address: String,
    val knownRelationship: Boolean,
    val protected: Boolean = false,
)

internal data class ServerConnectionAdmission(
    val accepted: Boolean,
    val replaceAddress: String? = null,
)

internal object ServerConnectionLimitPolicy {
    fun admit(
        maximumConnections: Int,
        active: Collection<ServerConnectionCandidate>,
        incoming: ServerConnectionCandidate,
    ): ServerConnectionAdmission {
        if (maximumConnections <= 0) return ServerConnectionAdmission(accepted = false)
        if (active.any { it.address == incoming.address }) {
            return ServerConnectionAdmission(accepted = true)
        }
        if (active.size < maximumConnections) {
            return ServerConnectionAdmission(accepted = true)
        }
        if (!incoming.knownRelationship) {
            return ServerConnectionAdmission(accepted = false)
        }
        val victim = active
            .asSequence()
            .filterNot(ServerConnectionCandidate::knownRelationship)
            .filterNot(ServerConnectionCandidate::protected)
            .minByOrNull(ServerConnectionCandidate::address)
            ?: return ServerConnectionAdmission(accepted = false)
        return ServerConnectionAdmission(accepted = true, replaceAddress = victim.address)
    }
}

internal data class OverflowDiscoverySettings(
    val maximumCandidates: Int,
    val cooldownMs: Long,
)

internal object OverflowDiscoveryPolicy {
    const val NORMAL_MAXIMUM_CANDIDATES = 1
    const val URGENT_MAXIMUM_CANDIDATES = 2
    const val NORMAL_COOLDOWN_MS = 5 * 60_000L
    const val URGENT_COOLDOWN_MS = 60_000L

    fun shouldConsiderCandidate(
        hasDisconnectedKnownPeer: Boolean,
        radarActive: Boolean,
        rescueActive: Boolean,
    ): Boolean = hasDisconnectedKnownPeer || radarActive || rescueActive

    fun settings(radarActive: Boolean, rescueActive: Boolean): OverflowDiscoverySettings =
        if (radarActive || rescueActive) {
            OverflowDiscoverySettings(
                maximumCandidates = URGENT_MAXIMUM_CANDIDATES,
                cooldownMs = URGENT_COOLDOWN_MS,
            )
        } else {
            OverflowDiscoverySettings(
                maximumCandidates = NORMAL_MAXIMUM_CANDIDATES,
                cooldownMs = NORMAL_COOLDOWN_MS,
            )
        }
}
