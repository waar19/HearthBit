package com.hearthbit.app.mesh

internal object PeerReachabilityPolicy {
    const val WINDOW_MS = 4 * 60_000L

    fun isOnline(lastSeen: Long?, now: Long): Boolean =
        lastSeen != null && now - lastSeen <= WINDOW_MS

    fun isSecure(lastSeen: Long?, noiseEstablished: Boolean, now: Long): Boolean =
        noiseEstablished && isOnline(lastSeen, now)

    fun requiresTransportRekey(previousLastSeen: Long?, now: Long): Boolean =
        previousLastSeen != null && !isOnline(previousLastSeen, now)
}
