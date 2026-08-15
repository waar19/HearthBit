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

internal object AnnouncementClockPolicy {
    const val STANDARD_WINDOW_MS = 10 * 60 * 1_000L
    const val EMERGENCY_PAST_WINDOW_MS = 24 * 60 * 60 * 1_000L

    fun accepts(
        timestampMs: Long,
        emergencyPreannounce: Boolean,
        nowMs: Long,
    ): Boolean {
        if (timestampMs > nowMs) {
            val latestAccepted = if (nowMs > Long.MAX_VALUE - STANDARD_WINDOW_MS) {
                Long.MAX_VALUE
            } else {
                nowMs + STANDARD_WINDOW_MS
            }
            return timestampMs <= latestAccepted
        }

        val pastWindow = if (emergencyPreannounce) {
            EMERGENCY_PAST_WINDOW_MS
        } else {
            STANDARD_WINDOW_MS
        }
        val earliestAccepted = if (nowMs < Long.MIN_VALUE + pastWindow) {
            Long.MIN_VALUE
        } else {
            nowMs - pastWindow
        }
        return timestampMs >= earliestAccepted
    }
}

/**
 * Authenticates relay-relevant identity before duplicate tracking or local
 * state changes. Unknown signed senders may traverse the live mesh but cannot
 * be processed or persisted until a valid ANNOUNCE establishes their pin.
 */
internal class MeshIngressAuthenticator(
    private val trustLookup: (String) -> PeerTrustLookup,
    private val validateAndPin: (String, PeerIdentityKeys) -> PeerIdentityDecision,
    private val verifySignature: (MeshProtocol.Packet, ByteArray) -> Boolean,
    private val nowMs: () -> Long = System::currentTimeMillis,
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
                !verifySignature(packet, announcement.signingPublicKey)
            ) {
                return rejected()
            }
            if (!AnnouncementClockPolicy.accepts(
                    packet.timestamp,
                    announcement.emergencyPreannounce,
                    nowMs(),
                ) ||
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
        return when (val trust = trustLookup(senderHex)) {
            PeerTrustLookup.Unknown ->
                MeshIngressAuthentication(MeshIngressDisposition.RELAY_ONLY_UNKNOWN)
            PeerTrustLookup.Invalid -> rejected()
            is PeerTrustLookup.Pinned -> {
                if (verifySignature(packet, trust.keys.signingPublicKey)) {
                    MeshIngressAuthentication(MeshIngressDisposition.ACCEPT)
                } else {
                    rejected()
                }
            }
        }
    }

    private fun rejected() = MeshIngressAuthentication(MeshIngressDisposition.REJECT)

    private fun requiresPublicSignature(type: Byte): Boolean = when (type) {
        MeshProtocol.TYPE_MESSAGE,
        MeshProtocol.TYPE_COURIER_ENVELOPE,
        MeshProtocol.TYPE_REQUEST_SYNC,
        MeshProtocol.TYPE_RADAR_CONTROL,
        MeshProtocol.TYPE_LEGACY_HBT_CAPABILITY,
        MeshProtocol.TYPE_HBT_CAPABILITY,
        MeshProtocol.TYPE_NODE_CAPABILITY,
        MeshProtocol.TYPE_BEACON_CONTROL,
        MeshProtocol.TYPE_RANGING_CONTROL,
        MeshProtocol.TYPE_EMERGENCY_CAPABILITY,
        MeshProtocol.TYPE_LEGACY_EMERGENCY_ACK,
        MeshProtocol.TYPE_EMERGENCY_ACK,
        -> true
        else -> false
    }
}
