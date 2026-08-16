package com.hearthbit.app.mesh

import java.util.UUID

internal object MeshEngineConstants {
    /** Techo del plano de control BLE; los blobs van por otros transportes. */
    const val MAX_TRANSFER_FRAME = 2_048

    /** Cadencia de lectura RSSI sobre GATT conectado en modo radar. */
    const val RADAR_READ_INTERVAL_MS = 500L
    const val BEACON_REPLAY_WINDOW_MS = 10 * 60_000L
    const val EMERGENCY_ACK_WINDOW_MS = 48 * 60 * 60 * 1_000L
    const val MAX_PENDING_BEACON_REQUESTS = 1

    const val ADVERTISE_TIMEOUT_MS = 10_000L
    const val MAX_ADVERTISE_RETRIES = 1
    const val MAX_PENDING_GATT_WRITES = 256
    const val MAX_BLE_CONNECTIONS = 8
    const val BLE_LINK_COST = 10
    const val LAN_LINK_COST = 2
    const val DEFAULT_GATT_VALUE_SIZE =
        MeshPacketFragmenter.DEFAULT_ATT_MTU - MeshPacketFragmenter.ATT_PROTOCOL_OVERHEAD
    const val SYNC_REQUEST_COOLDOWN_MS = 60_000L
    const val SYNC_STORE_CAPACITY = 80
    const val SYNC_MAX_REPLAY = 40
    const val SYNC_RATE_MAX_RESPONSES = 8
    const val SYNC_RATE_WINDOW_MS = 30_000L
    const val SYNC_ANNOUNCE_WINDOW_MS = 15 * 60 * 1_000L
    const val SYNC_MESSAGE_WINDOW_MS = 6 * 60 * 60 * 1_000L
    const val SYNC_FUTURE_SKEW_MS = 15 * 60 * 1_000L
    const val ROLE_TRANSITION_DELAY_MS = 750L
    const val GENERIC_PRESENCE_EMIT_INTERVAL_MS = 1_000L
    const val HANDSHAKE_RETRY_THROTTLE_MS = 5_000L
    const val HANDSHAKE_CLEANUP_INTERVAL_MS = 10_000L
    const val RECOVERY_SCAN_BURST_MS = 15_000L
    const val SCAN_REARM_DELAY_MS = 750L
    const val MAX_SCAN_RETRY_ATTEMPTS = 5
    const val AUTO_RECONNECT_WINDOW_MS = 12 * 60_000L
    const val MAX_AUTO_RECONNECTS = 3
    const val MIN_OVERFLOW_CANDIDATE_RSSI = -90
    const val IOS_OVERFLOW_TYPE: Byte = 0x01
    const val MAX_REMEMBERED_SESSION_PEERS = 256
    const val PRIVATE_ANNOUNCE_TTL: Byte = 1
    const val RELATIONSHIP_PREFERENCES = "hearthbit_mesh_relationships"
    const val RELATIONSHIP_SECURE_STORE = "hearthbit_mesh_relationships_secure"
    const val KEY_SESSION_PEERS = "session_peers"
    const val KEY_IOS_OVERFLOW_BIT = "ios_overflow_service_bit"

    const val LOG_TAG = "HearthBitMesh"
    val IDENTITY_PACKET_TYPES = setOf(
        MeshProtocol.TYPE_ANNOUNCE,
        MeshProtocol.TYPE_HBT_CAPABILITY,
        MeshProtocol.TYPE_EMERGENCY_CAPABILITY,
        MeshProtocol.TYPE_NODE_CAPABILITY,
    )

    val SERVICE_UUID: UUID =
        UUID.fromString("F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C")
    val CHARACTERISTIC_UUID: UUID =
        UUID.fromString("A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D")
    val CLIENT_CONFIGURATION_UUID: UUID =
        UUID.fromString("00002902-0000-1000-8000-00805F9B34FB")
}
