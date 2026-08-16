package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EmergencyLanPolicyTest {
    @Test
    fun `accepts emergency preannounce announcement`() {
        val payload = MeshProtocol.encodeAnnouncement(
            nickname = "alice",
            noisePublicKey = ByteArray(32),
            signingPublicKey = ByteArray(32),
            emergencyPreannounce = true,
        )
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_ANNOUNCE,
            ttl = 7,
            timestamp = 1L,
            senderId = ByteArray(8),
            payload = payload,
        )

        assertTrue(EmergencyLanPolicy.isOpenEmergencyLanPacket(packet))
    }

    @Test
    fun `accepts emergency public message and ack types`() {
        val message = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_MESSAGE,
            ttl = 7,
            timestamp = 1L,
            senderId = ByteArray(8),
            payload = MeshProtocol.encodeInteropPublicMessage("SOS|help||"),
        )
        val ack = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_EMERGENCY_ACK,
            ttl = 7,
            timestamp = 1L,
            senderId = ByteArray(8),
            payload = ByteArray(32),
        )

        assertTrue(EmergencyLanPolicy.isOpenEmergencyLanPacket(message))
        assertTrue(EmergencyLanPolicy.isOpenEmergencyLanPacket(ack))
    }

    @Test
    fun `rejects regular chat traffic`() {
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_MESSAGE,
            ttl = 7,
            timestamp = 1L,
            senderId = ByteArray(8),
            payload = MeshProtocol.encodeInteropPublicMessage("hello"),
        )

        assertFalse(EmergencyLanPolicy.isOpenEmergencyLanPacket(packet))
    }
}
