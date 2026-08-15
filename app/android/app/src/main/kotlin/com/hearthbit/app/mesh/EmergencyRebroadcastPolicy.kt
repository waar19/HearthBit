package com.hearthbit.app.mesh

internal object EmergencyRebroadcastPolicy {
    const val INTERVAL_MS = 60_000L

    fun shouldSchedule(
        running: Boolean,
        rescueActive: Boolean,
        role: MeshNodeRole,
        powerProfile: PowerProfile,
    ): Boolean =
        running &&
            rescueActive &&
            role != MeshNodeRole.PHONE_BEACON &&
            powerProfile != PowerProfile.SURVIVAL

    fun selectLocalSos(
        packets: Iterable<MeshProtocol.Packet>,
        localSenderId: ByteArray,
        startedAt: Long,
    ): MeshProtocol.Packet? {
        if (startedAt <= 0L) return null
        return packets
            .asSequence()
            .filter { packet ->
                packet.timestamp >= startedAt &&
                    packet.senderId.contentEquals(localSenderId) &&
                    MeshProtocol.isSosPublicPacket(packet)
            }
            .maxByOrNull(MeshProtocol.Packet::timestamp)
    }
}
