package com.hearthbit.app.mesh

internal enum class MeshNodeRole(
    val wireName: String,
    val code: Byte,
    val relaysPackets: Boolean,
    val canOriginateChat: Boolean,
    val storesDirectedPackets: Boolean,
) {
    PHONE_RELAY("PHONE_RELAY", 0x01, true, true, true),
    PHONE_BEACON("PHONE_BEACON", 0x02, false, false, false),
    INFRA_RELAY("INFRA_RELAY", 0x03, true, false, false),
    INFRA_DATA_ANCHOR("INFRA_DATA_ANCHOR", 0x04, true, false, true);

    val capabilityFlags: Byte
        get() {
            var flags = 0
            if (relaysPackets) flags = flags or FLAG_RELAY
            if (canOriginateChat) flags = flags or FLAG_CHAT
            if (storesDirectedPackets) flags = flags or FLAG_STORE
            if (this == PHONE_BEACON) flags = flags or FLAG_PRESENCE_ONLY
            return flags.toByte()
        }

    companion object {
        private const val FLAG_RELAY = 0x01
        private const val FLAG_CHAT = 0x02
        private const val FLAG_STORE = 0x04
        private const val FLAG_PRESENCE_ONLY = 0x08

        fun fromWireName(value: String?): MeshNodeRole? =
            entries.firstOrNull { it.wireName == value }

        fun fromCode(value: Byte): MeshNodeRole? =
            entries.firstOrNull { it.code == value }
    }
}

internal object MeshStartupRolePolicy {
    fun resolve(
        persistedRole: MeshNodeRole,
        requiredRole: MeshNodeRole?,
    ): MeshNodeRole = requiredRole ?: persistedRole
}

internal object NodeCapabilityProtocol {
    const val VERSION: Byte = 0x01
    const val FLAG_LONG_RANGE_TRUNK = 0x10

    data class Capability(
        val role: MeshNodeRole,
        val flags: Byte,
    ) {
        val hasLongRangeTrunk: Boolean
            get() = flags.toInt() and FLAG_LONG_RANGE_TRUNK != 0
    }

    fun encode(
        role: MeshNodeRole,
        hasLongRangeTrunk: Boolean = false,
    ): ByteArray {
        val flags = role.capabilityFlags.toInt() or
            if (hasLongRangeTrunk) FLAG_LONG_RANGE_TRUNK else 0
        return byteArrayOf(VERSION, role.code, flags.toByte())
    }

    fun decode(payload: ByteArray): Capability? {
        if (payload.size != 3 || payload[0] != VERSION) return null
        val role = MeshNodeRole.fromCode(payload[1]) ?: return null
        return Capability(role, payload[2])
    }
}

internal object MeshRelayPolicy {
    fun shouldRelay(
        role: MeshNodeRole,
        packetType: Byte,
        ttl: Int,
        addressedToLocalNode: Boolean,
    ): Boolean {
        if (!role.relaysPackets || ttl <= 1) return false
        return when (packetType) {
            MeshProtocol.TYPE_BEACON_CONTROL -> false
            MeshProtocol.TYPE_NOISE_HANDSHAKE,
            MeshProtocol.TYPE_NOISE_ENCRYPTED,
            -> !addressedToLocalNode
            else -> true
        }
    }
}
