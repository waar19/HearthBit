package com.hearthbit.app.mesh

internal data class MeshPeer(
    val id: String,
    val nickname: String,
    val signingPublicKey: ByteArray,
    val noisePublicKey: ByteArray,
    var supportsTransfers: Boolean,
    var role: MeshNodeRole = MeshNodeRole.PHONE_RELAY,
    var hasLongRangeTrunk: Boolean = false,
    var lastSeen: Long = System.currentTimeMillis(),
    var supportsEmergencyAck: Boolean = false,
    var hearthbitVerified: Boolean = supportsTransfers,
)

internal data class PendingPrivateMessage(val id: String, val content: String)

internal data class RemoteRadarConsent(val expiresAt: Long, val source: String)

internal data class PendingBeaconRequest(
    val peerId: String,
    val nickname: String,
    val control: BeaconControlProtocol.Control,
)

internal data class OutgoingBeaconRequest(
    val peerId: String,
    val expiresAt: Long,
    val flags: Int,
)
