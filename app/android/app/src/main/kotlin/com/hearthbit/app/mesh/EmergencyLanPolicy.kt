package com.hearthbit.app.mesh

internal object EmergencyLanPolicy {
    fun isOpenEmergencyLanPacket(packet: MeshProtocol.Packet): Boolean =
        when (packet.type) {
            MeshProtocol.TYPE_ANNOUNCE ->
                MeshProtocol.decodeAnnouncement(packet.payload)?.emergencyPreannounce == true
            MeshProtocol.TYPE_MESSAGE ->
                MeshProtocol.isEmergencyPublicPacketPayload(
                    packet.payload.toString(Charsets.UTF_8),
                )
            MeshProtocol.TYPE_EMERGENCY_ACK,
            MeshProtocol.TYPE_LEGACY_EMERGENCY_ACK,
            -> true
            else -> false
        }
}
