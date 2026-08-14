package com.hearthbit.app.mesh

internal enum class MeshIngressDisposition {
    ACCEPT,
    RELAY_ONLY_UNKNOWN,
    DEFER_FRAGMENT,
    REJECT,
}

internal data class MeshIngressAuthentication(
    val disposition: MeshIngressDisposition,
    val announcement: MeshProtocol.Announcement? = null,
) {
    val relayAllowed: Boolean
        get() = disposition != MeshIngressDisposition.REJECT

    val localProcessingAllowed: Boolean
        get() = disposition == MeshIngressDisposition.ACCEPT ||
            disposition == MeshIngressDisposition.DEFER_FRAGMENT
}

/**
 * Authenticates relay-relevant identity before duplicate tracking or local
 * state changes. Unknown signed senders may traverse the live mesh but cannot
 * be processed or persisted until a valid ANNOUNCE establishes their pin.
 */
internal class MeshIngressAuthenticator(
    private val pinnedKeys: (String) -> PeerIdentityKeys?,
    private val validateAndPin: (String, PeerIdentityKeys) -> PeerIdentityDecision,
    private val verifySignature: (MeshProtocol.Packet, ByteArray) -> Boolean,
) {
    fun authenticate(packet: MeshProtocol.Packet): MeshIngressAuthentication {
        val senderHex = MeshProtocol.hex(packet.senderId)
        if (packet.type == MeshProtocol.TYPE_FRAGMENT) {
            return MeshIngressAuthentication(MeshIngressDisposition.DEFER_FRAGMENT)
        }
        if (packet.type == MeshProtocol.TYPE_ANNOUNCE) {
            val announcement = MeshProtocol.decodeAnnouncement(packet.payload)
                ?: return rejected()
            val announcedKeys = PeerIdentityKeys(
                signingPublicKey = announcement.signingPublicKey,
                noisePublicKey = announcement.noisePublicKey,
            )
            if (!MeshProtocol.peerIdFromNoiseKey(announcement.noisePublicKey)
                    .contentEquals(packet.senderId) ||
                !verifySignature(packet, announcement.signingPublicKey) ||
                !validateAndPin(senderHex, announcedKeys).accepted
            ) {
                return rejected()
            }
            return MeshIngressAuthentication(
                disposition = MeshIngressDisposition.ACCEPT,
                announcement = announcement,
            )
        }
        if (!requiresPublicSignature(packet.type)) {
            return MeshIngressAuthentication(MeshIngressDisposition.ACCEPT)
        }
        val pinned = pinnedKeys(senderHex)
            ?: return MeshIngressAuthentication(MeshIngressDisposition.RELAY_ONLY_UNKNOWN)
        return if (verifySignature(packet, pinned.signingPublicKey)) {
            MeshIngressAuthentication(MeshIngressDisposition.ACCEPT)
        } else {
            rejected()
        }
    }

    private fun rejected() = MeshIngressAuthentication(MeshIngressDisposition.REJECT)

    private fun requiresPublicSignature(type: Byte): Boolean = when (type) {
        MeshProtocol.TYPE_MESSAGE,
        MeshProtocol.TYPE_COURIER_ENVELOPE,
        MeshProtocol.TYPE_REQUEST_SYNC,
        MeshProtocol.TYPE_RADAR_CONTROL,
        MeshProtocol.TYPE_HBT_CAPABILITY,
        MeshProtocol.TYPE_NODE_CAPABILITY,
        MeshProtocol.TYPE_BEACON_CONTROL,
        MeshProtocol.TYPE_RANGING_CONTROL,
        MeshProtocol.TYPE_EMERGENCY_CAPABILITY,
        MeshProtocol.TYPE_EMERGENCY_ACK,
        -> true
        else -> false
    }
}
