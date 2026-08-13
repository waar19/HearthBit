package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BeaconControlProtocolTest {
    private val nonce = ByteArray(BeaconControlProtocol.NONCE_SIZE) { it.toByte() }

    @Test
    fun `request grant revoke and stop use strict fixed payload`() {
        val now = 1_000_000L
        val flags = BeaconControlProtocol.FLAG_FLASH or BeaconControlProtocol.FLAG_VIBRATE
        val request = BeaconControlProtocol.decode(
            BeaconControlProtocol.request(now + 60_000, flags, nonce),
        )
        val grant = BeaconControlProtocol.decode(
            BeaconControlProtocol.grant(now + 60_000, flags, nonce),
        )
        val revoke = BeaconControlProtocol.decode(BeaconControlProtocol.revoke(nonce))
        val stop = BeaconControlProtocol.decode(BeaconControlProtocol.stop(nonce))

        assertEquals(BeaconControlProtocol.PAYLOAD_SIZE, BeaconControlProtocol.request(now + 1, flags).size)
        assertEquals(BeaconControlProtocol.ACTION_REQUEST, request?.action)
        assertEquals(BeaconControlProtocol.ACTION_GRANT, grant?.action)
        assertEquals(BeaconControlProtocol.ACTION_REVOKE, revoke?.action)
        assertEquals(BeaconControlProtocol.ACTION_STOP, stop?.action)
        assertEquals(nonce.toList(), request?.nonce?.toList())
        assertNull(BeaconControlProtocol.decode(ByteArray(BeaconControlProtocol.PAYLOAD_SIZE - 1)))
    }

    @Test
    fun `rejects unknown flags terminal data and expiration beyond five minutes`() {
        val now = 10_000_000L
        val validBytes = BeaconControlProtocol.request(
            now + BeaconControlProtocol.MAX_DURATION_MS,
            BeaconControlProtocol.FLAG_SOUND,
            nonce,
        )
        val valid = assertNotNullAndReturn(BeaconControlProtocol.decode(validBytes))

        assertTrue(BeaconControlProtocol.isValid(valid, now, now))
        assertFalse(
            BeaconControlProtocol.isValid(
                valid.copy(expiresAt = now + BeaconControlProtocol.MAX_DURATION_MS + 1),
                now,
                now,
            ),
        )
        assertNull(
            BeaconControlProtocol.decode(
                validBytes.copyOf().also { it[it.lastIndex] = 0x08 },
            ),
        )
        assertNull(
            BeaconControlProtocol.decode(
                BeaconControlProtocol.stop(nonce).also { it[9] = 1 },
            ),
        )
    }

    @Test
    fun `beacon packet is directed signed ttl one and never relayed`() {
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_BEACON_CONTROL,
            ttl = 1,
            timestamp = 1_000,
            senderId = ByteArray(8) { 1 },
            recipientId = ByteArray(8) { 2 },
            payload = BeaconControlProtocol.request(
                2_000,
                BeaconControlProtocol.FLAG_FLASH,
                nonce,
            ),
            signature = ByteArray(64) { 3 },
        )
        val decoded = requireNotNull(MeshProtocol.decode(MeshProtocol.encode(packet, padded = false)))

        assertEquals(0x26.toByte(), decoded.type)
        assertEquals(1.toByte(), decoded.ttl)
        assertNotNull(decoded.recipientId)
        assertNotNull(decoded.signature)
        assertFalse(
            MeshRelayPolicy.shouldRelay(
                MeshNodeRole.PHONE_RELAY,
                MeshProtocol.TYPE_BEACON_CONTROL,
                ttl = 7,
                addressedToLocalNode = false,
            ),
        )
    }

    @Test
    fun `solo autoacepta si el consentimiento local ya estaba activo`() {
        val now = 5_000L

        assertFalse(BeaconControlProtocol.shouldAutoAccept(0, now))
        assertFalse(BeaconControlProtocol.shouldAutoAccept(now, now))
        assertTrue(BeaconControlProtocol.shouldAutoAccept(now + 1, now))
    }

    private fun assertNotNullAndReturn(
        value: BeaconControlProtocol.Control?,
    ): BeaconControlProtocol.Control {
        assertNotNull(value)
        return requireNotNull(value)
    }
}
