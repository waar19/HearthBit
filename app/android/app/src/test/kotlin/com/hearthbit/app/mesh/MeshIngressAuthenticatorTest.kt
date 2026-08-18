package com.hearthbit.app.mesh

import com.hearthbit.noise.southernstorm.protocol.Noise
import org.bouncycastle.crypto.generators.Ed25519KeyPairGenerator
import org.bouncycastle.crypto.params.Ed25519KeyGenerationParameters
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.SecureRandom

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
    fun `unknown signed peer is rejected and never relayed`() {
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

        assertEquals(MeshIngressDisposition.REJECT, result.disposition)
        assertFalse(result.relayAllowed)
        assertFalse(result.localProcessingAllowed)
    }

    @Test
    fun `fragment of signed type from unknown peer is rejected before relay`() {
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_FRAGMENT,
            ttl = MeshProtocol.TTL,
            timestamp = 1,
            senderId = ByteArray(8) { 0x56 },
            payload = MeshProtocol.encodeFragmentPayload(
                MeshProtocol.FragmentPayload(
                    fragmentId = ByteArray(MeshProtocol.FRAGMENT_ID_SIZE) { 0x12 },
                    index = 0,
                    total = 2,
                    originalType = MeshProtocol.TYPE_MESSAGE,
                    data = byteArrayOf(1),
                ),
            ),
        )

        val result = authenticator(emptyMap(), validSignatureKey = ByteArray(32))
            .authenticate(packet, "AA:BB:CC:DD:EE:FF")

        assertEquals(MeshIngressDisposition.REJECT, result.disposition)
        assertFalse(result.relayAllowed)
    }

    @Test
    fun `unknown ingress limiter is isolated per source and resets after window`() {
        val limiter = UnknownIngressRateLimiter(maximumPackets = 2, windowMs = 100)

        assertTrue(limiter.allow("source-a", now = 1_000))
        assertTrue(limiter.allow("source-a", now = 1_001))
        assertFalse(limiter.allow("source-a", now = 1_002))
        assertTrue(limiter.allow("source-b", now = 1_002))
        assertTrue(limiter.allow("source-a", now = 1_100))
    }

    @Test
    fun `unknown ingress rate limit exposes explicit rejection reason`() {
        val noise = ByteArray(32) { it.toByte() }
        val signing = ByteArray(32) { 0x31 }
        val packet = announcement(noise, signing)
        val authenticator = authenticator(
            pins = emptyMap(),
            validSignatureKey = signing,
            unknownRateLimiter = UnknownIngressRateLimiter(maximumPackets = 1),
        )

        val accepted = authenticator.authenticate(packet, "source-a")
        val limited = authenticator.authenticate(packet, "source-a")
        val counters = MeshPacketCounters()
        counters.recordIngressRejection(limited.rateLimited)

        assertEquals(MeshIngressDisposition.ACCEPT, accepted.disposition)
        assertFalse(accepted.rateLimited)
        assertEquals(MeshIngressDisposition.REJECT, limited.disposition)
        assertTrue(limited.rateLimited)
        assertFalse(limited.relayAllowed)
        assertEquals(1L, counters.snapshot()["packetsDroppedRateLimit"])
        assertEquals(0L, counters.snapshot()["packetsRejected"])
    }

    @Test
    fun `tipos legacy requieren firma de peer autenticado`() {
        val noise = ByteArray(32) { (it + 2).toByte() }
        val signing = ByteArray(32) { 0x66 }
        val senderId = MeshProtocol.peerIdFromNoiseKey(noise)
        val pins = mapOf(
            MeshProtocol.hex(senderId) to PeerIdentityKeys(signing, noise),
        )
        val authenticator = authenticator(pins, validSignatureKey = signing)

        listOf(
            MeshProtocol.TYPE_LEGACY_HBT_CAPABILITY,
            MeshProtocol.TYPE_LEGACY_EMERGENCY_ACK,
        ).forEach { legacyType ->
            val result = authenticator.authenticate(
                MeshProtocol.Packet(
                    type = legacyType,
                    ttl = MeshProtocol.TTL,
                    timestamp = 1,
                    senderId = senderId,
                    recipientId = ByteArray(8) { 0x77 },
                    payload = byteArrayOf(1),
                    signature = ByteArray(64),
                ),
            )

            assertEquals(MeshIngressDisposition.ACCEPT, result.disposition)
            assertTrue(result.localProcessingAllowed)
        }
    }

    @Test
    fun `announcement older than standard window is rejected`() {
        val now = 1_000_000L
        val noise = ByteArray(32) { it.toByte() }
        val signing = ByteArray(32) { 0x21 }
        val packet = announcement(
            noise,
            signing,
            timestamp = now - AnnouncementClockPolicy.STANDARD_WINDOW_MS - 1,
            ttl = 1,
        )

        val result = authenticator(emptyMap(), signing, now).authenticate(packet)

        assertEquals(MeshIngressDisposition.REJECT, result.disposition)
    }

    @Test
    fun `announcement beyond future window is rejected even with emergency marker`() {
        val now = 1_000_000L
        val noise = ByteArray(32) { it.toByte() }
        val signing = ByteArray(32) { 0x22 }
        val packet = announcement(
            noise,
            signing,
            timestamp = now + AnnouncementClockPolicy.STANDARD_WINDOW_MS + 1,
            ttl = MeshProtocol.TTL,
            emergencyPreannounce = true,
        )

        val result = authenticator(emptyMap(), signing, now).authenticate(packet)

        assertEquals(MeshIngressDisposition.REJECT, result.disposition)
    }

    @Test
    fun `standard announcement accepts past and future boundaries`() {
        val now = 1_000_000L
        val noise = ByteArray(32) { it.toByte() }
        val signing = ByteArray(32) { 0x23 }
        val authenticator = authenticator(emptyMap(), signing, now)

        listOf(
            now - AnnouncementClockPolicy.STANDARD_WINDOW_MS,
            now + AnnouncementClockPolicy.STANDARD_WINDOW_MS,
        ).forEach { timestamp ->
            val result = authenticator.authenticate(
                announcement(noise, signing, timestamp = timestamp, ttl = 1),
            )
            assertEquals(MeshIngressDisposition.ACCEPT, result.disposition)
        }
    }

    @Test
    fun `current announcement is accepted`() {
        val now = 1_000_000L
        val noise = ByteArray(32) { it.toByte() }
        val signing = ByteArray(32) { 0x24 }

        val result = authenticator(emptyMap(), signing, now).authenticate(
            announcement(noise, signing, timestamp = now, ttl = 1),
        )

        assertEquals(MeshIngressDisposition.ACCEPT, result.disposition)
    }

    @Test
    fun `signed emergency marker accepts up to 24 hours late only`() {
        val now = 100_000_000L
        val noise = ByteArray(32) { it.toByte() }
        val signing = ByteArray(32) { 0x25 }
        val authenticator = authenticator(emptyMap(), signing, now)

        val boundary = authenticator.authenticate(
            announcement(
                noise,
                signing,
                timestamp = now - AnnouncementClockPolicy.EMERGENCY_PAST_WINDOW_MS,
                ttl = MeshProtocol.TTL,
                emergencyPreannounce = true,
            ),
        )
        val tooOld = authenticator.authenticate(
            announcement(
                noise,
                signing,
                timestamp = now - AnnouncementClockPolicy.EMERGENCY_PAST_WINDOW_MS - 1,
                ttl = MeshProtocol.TTL,
                emergencyPreannounce = true,
            ),
        )

        assertEquals(MeshIngressDisposition.ACCEPT, boundary.disposition)
        assertEquals(MeshIngressDisposition.REJECT, tooOld.disposition)
    }

    @Test
    fun `mutating signed ttl from one to seven never extends clock window`() {
        val now = 100_000_000L
        val noise = ByteArray(32) { it.toByte() }
        val signing = ByteArray(32) { 0x26 }
        val oldSignedAtTtlOne = announcement(
            noise,
            signing,
            timestamp = now - AnnouncementClockPolicy.STANDARD_WINDOW_MS - 1,
            ttl = 1,
        )

        val mutated = oldSignedAtTtlOne.copy(ttl = MeshProtocol.TTL)
        val result = authenticator(emptyMap(), signing, now).authenticate(mutated)

        assertEquals(MeshIngressDisposition.REJECT, result.disposition)
    }

    @Test
    fun `unknown emergency marker value does not extend clock window`() {
        val now = 100_000_000L
        val noise = ByteArray(32) { it.toByte() }
        val signing = ByteArray(32) { 0x27 }
        val invalidMarker = byteArrayOf(0xF1.toByte(), 0x01, 0x02)
        val packet = announcement(
            noise,
            signing,
            timestamp = now - AnnouncementClockPolicy.STANDARD_WINDOW_MS - 1,
            ttl = MeshProtocol.TTL,
            extraPayload = invalidMarker,
        )

        val result = authenticator(emptyMap(), signing, now).authenticate(packet)

        assertEquals(MeshIngressDisposition.REJECT, result.disposition)
    }

    @Test
    fun `emergency marker never accepts announcement thirty minutes ahead`() {
        val now = 100_000_000L
        val noise = ByteArray(32) { it.toByte() }
        val signing = ByteArray(32) { 0x28 }
        val packet = announcement(
            noise,
            signing,
            timestamp = now + 30 * 60 * 1_000L,
            emergencyPreannounce = true,
        )

        val result = authenticator(emptyMap(), signing, now).authenticate(packet)

        assertEquals(MeshIngressDisposition.REJECT, result.disposition)
    }

    @Test
    fun `clock policy handles long extremes without overflow`() {
        assertTrue(
            AnnouncementClockPolicy.accepts(
                timestampMs = Long.MIN_VALUE,
                emergencyPreannounce = true,
                nowMs = Long.MIN_VALUE,
            ),
        )
        assertFalse(
            AnnouncementClockPolicy.accepts(
                timestampMs = Long.MAX_VALUE,
                emergencyPreannounce = true,
                nowMs = Long.MIN_VALUE,
            ),
        )
    }

    @Test
    fun `key rotation requires old pin both signatures clock and matching old peer`() {
        val oldNoise = ByteArray(32) { (it + 1).toByte() }
        val oldSigning = ByteArray(32) { (it + 33).toByte() }
        val oldPeer = MeshProtocol.peerIdFromNoiseKey(oldNoise)
        val oldPeerHex = MeshProtocol.hex(oldPeer)
        val now = 1_700_000_000_000L
        val dh = Noise.createDH("25519")
        dh.generateKeyPair()
        val newNoise = ByteArray(32).also { dh.getPublicKey(it, 0) }
        dh.destroy()
        val signingGenerator = Ed25519KeyPairGenerator()
        signingGenerator.init(Ed25519KeyGenerationParameters(SecureRandom()))
        val newSigning =
            (signingGenerator.generateKeyPair().public as Ed25519PublicKeyParameters).encoded
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_KEY_ROTATION,
            ttl = MeshProtocol.TTL,
            timestamp = now,
            senderId = oldPeer,
            payload = KeyRotationProtocol.encode(
                oldPeer,
                newNoise,
                newSigning,
                now,
                3,
                ByteArray(64) { 7 },
            ),
            signature = ByteArray(64) { 9 },
        )
        var rotated = false
        val authenticator = MeshIngressAuthenticator(
            trustLookup = {
                if (it == oldPeerHex) {
                    PeerTrustLookup.Pinned(PeerIdentityKeys(oldSigning, oldNoise))
                } else {
                    PeerTrustLookup.Unknown
                }
            },
            validateAndPin = { _, _ -> PeerIdentityDecision.REJECT_UNAUTHENTICATED_ROTATION },
            rotatePin = { peerId, _, sequence ->
                rotated = peerId == oldPeerHex && sequence == 3L
                PeerIdentityDecision.ACCEPT_AUTHENTICATED_ROTATION
            },
            verifySignature = { _, key -> key.contentEquals(oldSigning) },
            verifyBytes = { _, signature, key ->
                signature.contentEquals(ByteArray(64) { 7 }) && key.contentEquals(oldSigning)
            },
            nowMs = { now },
        )

        val accepted = authenticator.authenticate(packet)
        assertEquals(MeshIngressDisposition.ACCEPT, accepted.disposition)
        assertTrue(rotated)
        assertEquals(3L, accepted.keyRotation?.sequence)
        assertEquals(
            MeshIngressDisposition.REJECT,
            authenticator.authenticate(packet.copy(senderId = ByteArray(8) { 1 })).disposition,
        )
        assertEquals(
            MeshIngressDisposition.REJECT,
            authenticator.authenticate(
                packet.copy(timestamp = now - KeyRotationProtocol.CLOCK_WINDOW_MS - 1),
            ).disposition,
        )
    }

    private fun authenticator(
        pins: Map<String, PeerIdentityKeys>,
        validSignatureKey: ByteArray,
        now: Long = 1,
        unknownRateLimiter: UnknownIngressRateLimiter = UnknownIngressRateLimiter(),
    ) = MeshIngressAuthenticator(
        trustLookup = { peerId ->
            pins[peerId]?.let(PeerTrustLookup::Pinned) ?: PeerTrustLookup.Unknown
        },
        validateAndPin = { peerId, announced ->
            val existing = pins[peerId]
            PeerIdentityPolicy.evaluate(existing, announced)
        },
        verifySignature = { _, key -> key.contentEquals(validSignatureKey) },
        nowMs = { now },
        unknownRateLimiter = unknownRateLimiter,
    )

    private fun announcement(
        noise: ByteArray,
        signing: ByteArray,
        timestamp: Long = 1,
        ttl: Byte = MeshProtocol.TTL,
        emergencyPreannounce: Boolean = false,
        extraPayload: ByteArray = byteArrayOf(),
    ): MeshProtocol.Packet =
        MeshProtocol.Packet(
            type = MeshProtocol.TYPE_ANNOUNCE,
            ttl = ttl,
            timestamp = timestamp,
            senderId = MeshProtocol.peerIdFromNoiseKey(noise),
            payload = MeshProtocol.encodeAnnouncement(
                "peer",
                noise,
                signing,
                emergencyPreannounce,
            ) + extraPayload,
            signature = ByteArray(64),
        )

    private fun <T> Boolean.then(value: T): T? = value.takeIf { this }
}
