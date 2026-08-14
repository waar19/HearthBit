package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshAdvertisePlanTest {
    @Test
    fun `el anuncio principal cabe en el PDU legado`() {
        assertEquals(21, MeshAdvertisePlan.ADVERTISEMENT_BYTES)
        assertTrue(
            MeshAdvertisePlan.ADVERTISEMENT_BYTES <=
                MeshAdvertisePlan.LEGACY_PDU_LIMIT_BYTES,
        )
    }

    @Test
    fun `la respuesta de escaneo cabe en el PDU legado`() {
        assertEquals(26, MeshAdvertisePlan.SCAN_RESPONSE_BYTES)
        assertTrue(
            MeshAdvertisePlan.SCAN_RESPONSE_BYTES <=
                MeshAdvertisePlan.LEGACY_PDU_LIMIT_BYTES,
        )
        assertEquals(27, MeshAdvertisePlan.PRIVATE_SCAN_RESPONSE_BYTES)
        assertTrue(
            MeshAdvertisePlan.PRIVATE_SCAN_RESPONSE_BYTES <=
                MeshAdvertisePlan.LEGACY_PDU_LIMIT_BYTES,
        )
    }

    @Test
    fun `la distribucion anterior excedia el limite y justifica el reparto`() {
        assertTrue(
            MeshAdvertisePlan.LEGACY_SINGLE_PDU_BYTES >
                MeshAdvertisePlan.LEGACY_PDU_LIMIT_BYTES,
        )
    }

    @Test
    fun `el peerId anunciado conserva los 8 bytes del protocolo BitChat`() {
        assertEquals(8, MeshAdvertisePlan.PEER_ID_BYTES)
    }
}
