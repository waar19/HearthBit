package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshIngressAuthenticatorTest {
    @Test
    fun `conflicting self signed announcement cannot relay or mutate local state`() {
        val noise = ByteArray(32) { it.toByte() }
        val pinnedSigning = ByteArray(32) { 0x11 }
        val attackerSigning = ByteArray(32) { 0x22 }
        val peerId = MeshProtocol.hex(MeshProtocol.peerIdFromNoiseKey(noise))
        val pins = mutableMapOf(
            peerId to PeerIdentityKeys(pinnedSigning, noise),
        )
        val authenticator = authenticator(pins, validSignatureKey = attackerSigning)
        val packet = announcement(noise, attackerSigning)

        val result = authenticator.authenticate(packet)

        assertEquals(MeshIngressDisposition.REJECT, result.disposition)
        assertFalse(result.relayAllowed)
        assertFalse(result.localProcessingAllowed)
        assertEquals(pinnedSigning.toList(), pins[peerId]!!.signingPublicKey.toList())
        val addressToPeerMutation = result.localProcessingAllowed.then(peerId)
        val syncMutation = result.localProcessingAllowed.then(packet)
        assertNull(addressToPeerMutation)
        assertNull(syncMutation)
    }

    @Test
    fun `invalid signed message from pinned peer cannot relay`() {
        val noise = ByteArray(32) { (it + 1).toByte() }
        val signing = ByteArray(32) { 0x33 }
        val peerIdBytes = MeshProtocol.peerIdFromNoiseKey(noise)
        val pins = mapOf(
            MeshProtocol.hex(peerIdBytes) to PeerIdentityKeys(signing, noise),
        )
        val authenticator = authenticator(pins, validSignatureKey = ByteArray(32) { 0x44 })
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_MESSAGE,
            ttl = MeshProtocol.TTL,
            timestamp = 1,
            senderId = peerIdBytes,
            payload = "hello".toByteArray(),
            signature = ByteArray(64),
        )

        val result = authenticator.authenticate(packet)

        assertEquals(MeshIngressDisposition.REJECT, result.disposition)
        assertFalse(result.relayAllowed)
        assertFalse(result.localProcessingAllowed)
    }

    @Test
    fun `unknown signed peer is relay only and never trusted implicitly`() {
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_MESSAGE,
            ttl = MeshProtocol.TTL,
            timestamp = 1,
            senderId = ByteArray(8) { 0x55 },
            payload = "hello".toByteArray(),
            signature = ByteArray(64),
        )
        val authenticator = authenticator(emptyMap(), validSignatureKey = ByteArray(32))

        val result = authenticator.authenticate(packet)

        assertEquals(MeshIngressDisposition.RELAY_ONLY_UNKNOWN, result.disposition)
        assertTrue(result.relayAllowed)
        assertFalse(result.localProcessingAllowed)
    }

    private fun authenticator(
        pins: Map<String, PeerIdentityKeys>,
        validSignatureKey: ByteArray,
    ) = MeshIngressAuthenticator(
        pinnedKeys = pins::get,
        validateAndPin = { peerId, announced ->
            val existing = pins[peerId]
            PeerIdentityPolicy.evaluate(existing, announced)
        },
        verifySignature = { _, key -> key.contentEquals(validSignatureKey) },
    )

    private fun announcement(noise: ByteArray, signing: ByteArray): MeshProtocol.Packet =
        MeshProtocol.Packet(
            type = MeshProtocol.TYPE_ANNOUNCE,
            ttl = MeshProtocol.TTL,
            timestamp = 1,
            senderId = MeshProtocol.peerIdFromNoiseKey(noise),
            payload = MeshProtocol.encodeAnnouncement("peer", noise, signing),
            signature = ByteArray(64),
        )

    private fun <T> Boolean.then(value: T): T? = value.takeIf { this }
}
