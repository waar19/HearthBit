package com.hearthbit.app.relay

import com.hearthbit.app.mesh.MeshNodeRole

internal object RelayNodeRolePolicy {
    fun resolve(configuredRole: String): MeshNodeRole {
        val role = requireNotNull(MeshNodeRole.fromWireName(configuredRole)) {
            "Rol de infraestructura no válido: $configuredRole"
        }
        require(
            role == MeshNodeRole.INFRA_RELAY ||
                role == MeshNodeRole.INFRA_DATA_ANCHOR,
        ) {
            "La aplicación relay no puede usar el rol ${role.wireName}"
        }
        return role
    }
}
