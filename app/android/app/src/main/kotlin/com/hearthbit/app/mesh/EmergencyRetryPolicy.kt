package com.hearthbit.app.mesh

internal object EmergencyRetryPolicy {
    fun rebuild(
        packet: MeshProtocol.Packet,
        localSenderId: ByteArray,
        now: Long,
        sign: (MeshProtocol.Packet) -> MeshProtocol.Packet,
    ): MeshProtocol.Packet? {
        if (!MeshProtocol.isEmergencyPublicPacket(packet)) return null
        if (!packet.senderId.contentEquals(localSenderId)) return null
        val timestamp = nextTimestamp(packet.timestamp, now) ?: return null
        return sign(
            packet.copy(
                ttl = MeshProtocol.TTL,
                timestamp = timestamp,
                signature = null,
                isRsr = false,
            ),
        ).takeIf { it.signature != null }
    }

    fun nextTimestamp(previous: Long, now: Long): Long? {
        if (previous == Long.MAX_VALUE) return null
        return maxOf(now, previous + 1)
    }
}
