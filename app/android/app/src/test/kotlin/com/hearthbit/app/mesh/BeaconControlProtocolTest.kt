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
    fun `beacon packet is directed signed and accepts only ttl one or two`() {
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_BEACON_CONTROL,
            ttl = BeaconControlProtocol.INITIAL_TTL.toByte(),
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
        assertEquals(2.toByte(), decoded.ttl)
        assertNotNull(decoded.recipientId)
        assertNotNull(decoded.signature)
        assertFalse(BeaconControlProtocol.isValidTtl(0))
        assertTrue(BeaconControlProtocol.isValidTtl(1))
        assertTrue(BeaconControlProtocol.isValidTtl(2))
        assertFalse(BeaconControlProtocol.isValidTtl(3))
    }

    @Test
    fun `beacon control relays exactly once only toward another directed recipient`() {
        assertTrue(
            MeshRelayPolicy.shouldRelay(
                MeshNodeRole.PHONE_RELAY,
                MeshProtocol.TYPE_BEACON_CONTROL,
                ttl = 2,
                addressedToLocalNode = false,
                hasDirectedRecipient = true,
            ),
        )
        listOf(
            Triple(1, false, true),
            Triple(2, true, true),
            Triple(2, false, false),
            Triple(3, false, true),
        ).forEach { (ttl, local, directed) ->
            assertFalse(
                MeshRelayPolicy.shouldRelay(
                    MeshNodeRole.PHONE_RELAY,
                    MeshProtocol.TYPE_BEACON_CONTROL,
                    ttl = ttl,
                    addressedToLocalNode = local,
                    hasDirectedRecipient = directed,
                ),
            )
        }
        assertFalse(
            MeshRelayPolicy.shouldRelay(
                MeshNodeRole.PHONE_RELAY,
                MeshProtocol.TYPE_RANGING_CONTROL,
                ttl = 2,
                addressedToLocalNode = false,
            ),
        )
    }

    @Test
    fun `solo autoacepta en emergencia o radar para una relacion verificada`() {
        val now = 5_000L

        assertFalse(
            BeaconControlProtocol.shouldAutoAccept(
                rescueModeActive = true,
                localRadarConsentUntil = 0,
                hearthbitVerified = false,
                knownRelationship = true,
                now = now,
            ),
        )
        assertFalse(
            BeaconControlProtocol.shouldAutoAccept(
                rescueModeActive = true,
                localRadarConsentUntil = 0,
                hearthbitVerified = true,
                knownRelationship = false,
                now = now,
            ),
        )
        assertTrue(
            BeaconControlProtocol.shouldAutoAccept(
                rescueModeActive = true,
                localRadarConsentUntil = 0,
                hearthbitVerified = true,
                knownRelationship = true,
                now = now,
            ),
        )
        assertTrue(
            BeaconControlProtocol.shouldAutoAccept(
                rescueModeActive = false,
                localRadarConsentUntil = now + 1,
                hearthbitVerified = true,
                knownRelationship = true,
                now = now,
            ),
        )
        assertFalse(
            BeaconControlProtocol.shouldAutoAccept(
                rescueModeActive = false,
                localRadarConsentUntil = now,
                hearthbitVerified = true,
                knownRelationship = true,
                now = now,
            ),
        )
    }

    private fun assertNotNullAndReturn(
        value: BeaconControlProtocol.Control?,
    ): BeaconControlProtocol.Control {
        assertNotNull(value)
        return requireNotNull(value)
    }
}
