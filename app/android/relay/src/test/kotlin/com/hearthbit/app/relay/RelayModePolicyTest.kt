package com.hearthbit.app.relay

import com.hearthbit.app.BuildConfig
import com.hearthbit.app.mesh.MeshNodeRole
import com.hearthbit.app.mesh.MeshStartupRolePolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class RelayModePolicyTest {
    @Test
    fun `uses dual role when advertising is supported`() {
        assertEquals(
            RelayMode.DUAL_ROLE,
            RelayModePolicy.select(
                hasBleHardware = true,
                hasGattCentral = true,
                supportsAdvertising = true,
            ),
        )
    }

    @Test
    fun `falls back to central when advertising is unavailable`() {
        assertEquals(
            RelayMode.CENTRAL_ONLY,
            RelayModePolicy.select(
                hasBleHardware = true,
                hasGattCentral = true,
                supportsAdvertising = false,
            ),
        )
    }

    @Test
    fun `rejects devices without BLE central support`() {
        assertEquals(
            RelayMode.UNAVAILABLE,
            RelayModePolicy.select(
                hasBleHardware = true,
                hasGattCentral = false,
                supportsAdvertising = true,
            ),
        )
    }

    @Test
    fun `tv and automotive flavors start as infrastructure relays`() {
        val configuredRole = RelayNodeRolePolicy.resolve(BuildConfig.MESH_NODE_ROLE)

        when (BuildConfig.TARGET_KIND) {
            "tv" -> assertEquals(MeshNodeRole.INFRA_RELAY, configuredRole)
            "automotive" -> assertEquals(MeshNodeRole.INFRA_RELAY, configuredRole)
            else -> throw AssertionError("Flavor relay inesperado: ${BuildConfig.TARGET_KIND}")
        }
        assertNotEquals(MeshNodeRole.PHONE_RELAY, configuredRole)
        assertEquals(
            MeshNodeRole.INFRA_RELAY,
            MeshStartupRolePolicy.resolve(
                persistedRole = MeshNodeRole.PHONE_RELAY,
                requiredRole = configuredRole,
            ),
        )
    }

    @Test
    fun `infrastructure data anchor remains configurable`() {
        assertEquals(
            MeshNodeRole.INFRA_DATA_ANCHOR,
            RelayNodeRolePolicy.resolve("INFRA_DATA_ANCHOR"),
        )
    }

    @Test
    fun `relay application rejects phone roles`() {
        assertThrows(IllegalArgumentException::class.java) {
            RelayNodeRolePolicy.resolve("PHONE_RELAY")
        }
    }

    @Test
    fun `mobile application keeps its phone relay role`() {
        assertEquals(
            MeshNodeRole.PHONE_RELAY,
            MeshStartupRolePolicy.resolve(
                persistedRole = MeshNodeRole.PHONE_RELAY,
                requiredRole = null,
            ),
        )
    }
}
