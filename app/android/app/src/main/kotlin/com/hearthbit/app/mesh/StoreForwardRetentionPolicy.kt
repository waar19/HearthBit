package com.hearthbit.app.mesh

internal data class StoreForwardRetentionItem<T>(
    val expiry: Long,
    val value: T,
    val emergency: Boolean,
    val replaySafe: Boolean,
)

internal object StoreForwardRetentionPolicy {
    const val MAX_ENTRIES = 100
    const val NORMAL_LIFETIME_MS = 12 * 60 * 60 * 1_000L
    const val EMERGENCY_LIFETIME_MS = 24 * 60 * 60 * 1_000L

    fun expiryAt(now: Long, emergency: Boolean): Long =
        saturatedAdd(
            now,
            if (emergency) EMERGENCY_LIFETIME_MS else NORMAL_LIFETIME_MS,
        )

    fun <T> retain(
        entries: List<StoreForwardRetentionItem<T>>,
        now: Long,
    ): List<StoreForwardRetentionItem<T>> = entries
        .asSequence()
        .filter { it.expiry > now && it.replaySafe }
        .sortedWith(
            compareBy<StoreForwardRetentionItem<T>> { it.emergency }
                .thenBy { it.expiry },
        )
        .toList()
        .takeLast(MAX_ENTRIES)

    fun isPacketReplaySafe(packetType: Byte, fragmentedOriginalType: Byte? = null): Boolean {
        val effectiveType = if (packetType == MeshProtocol.TYPE_FRAGMENT) {
            fragmentedOriginalType ?: packetType
        } else {
            packetType
        }
        return effectiveType != MeshProtocol.TYPE_NOISE_HANDSHAKE &&
            effectiveType != MeshProtocol.TYPE_NOISE_ENCRYPTED &&
            effectiveType != MeshProtocol.TYPE_BEACON_CONTROL &&
            effectiveType != MeshProtocol.TYPE_RANGING_CONTROL
    }

    private fun saturatedAdd(value: Long, increment: Long): Long =
        if (value > Long.MAX_VALUE - increment) Long.MAX_VALUE else value + increment
}
