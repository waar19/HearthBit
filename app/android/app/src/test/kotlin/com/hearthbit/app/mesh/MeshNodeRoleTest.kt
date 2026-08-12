package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshNodeRoleTest {
    @Test
    fun `cada rol conserva su politica en el paquete dedicado`() {
        MeshNodeRole.entries.forEach { role ->
            val decoded = NodeCapabilityProtocol.decode(
                NodeCapabilityProtocol.encode(role),
            )

            assertNotNull(decoded)
            assertEquals(role, decoded!!.role)
            assertEquals(role.capabilityFlags, decoded.flags)
        }
    }

    @Test
    fun `rechaza capacidades truncadas o de version desconocida`() {
        assertEquals(null, NodeCapabilityProtocol.decode(byteArrayOf(1, 1)))
        assertEquals(
            null,
            NodeCapabilityProtocol.decode(byteArrayOf(2, 1, 0)),
        )
        assertEquals(
            null,
            NodeCapabilityProtocol.decode(byteArrayOf(1, 99, 0)),
        )
    }

    @Test
    fun `phone beacon nunca retransmite ni origina chat`() {
        assertFalse(MeshNodeRole.PHONE_BEACON.relaysPackets)
        assertFalse(MeshNodeRole.PHONE_BEACON.canOriginateChat)
        assertFalse(
            MeshRelayPolicy.shouldRelay(
                MeshNodeRole.PHONE_BEACON,
                MeshProtocol.TYPE_MESSAGE,
                ttl = 7,
                addressedToLocalNode = false,
            ),
        )
    }

    @Test
    fun `relays reenvian trafico salvo noise dirigido al propio nodo`() {
        listOf(
            MeshNodeRole.PHONE_RELAY,
            MeshNodeRole.INFRA_RELAY,
            MeshNodeRole.INFRA_DATA_ANCHOR,
        ).forEach { role ->
            assertTrue(
                MeshRelayPolicy.shouldRelay(
                    role,
                    MeshProtocol.TYPE_MESSAGE,
                    ttl = 7,
                    addressedToLocalNode = false,
                ),
            )
            assertFalse(
                MeshRelayPolicy.shouldRelay(
                    role,
                    MeshProtocol.TYPE_NOISE_ENCRYPTED,
                    ttl = 7,
                    addressedToLocalNode = true,
                ),
            )
            assertTrue(
                MeshRelayPolicy.shouldRelay(
                    role,
                    MeshProtocol.TYPE_NOISE_ENCRYPTED,
                    ttl = 7,
                    addressedToLocalNode = false,
                ),
            )
            assertFalse(
                MeshRelayPolicy.shouldRelay(
                    role,
                    MeshProtocol.TYPE_MESSAGE,
                    ttl = 1,
                    addressedToLocalNode = false,
                ),
            )
        }
    }
}
