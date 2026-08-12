package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.bouncycastle.crypto.generators.Ed25519KeyPairGenerator
import org.bouncycastle.crypto.params.Ed25519KeyGenerationParameters
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import java.security.SecureRandom

class RadarConsentProtocolTest {
    @Test
    fun `concesion valida dura como maximo veinte minutos`() {
        val now = 1_000_000L
        val payload = RadarConsentProtocol.grant(
            now + RadarConsentProtocol.MANUAL_DURATION_MS,
        )
        val consent = RadarConsentProtocol.decode(payload)

        assertNotNull(consent)
        assertEquals(RadarConsentProtocol.ACTION_GRANT, consent!!.action)
        assertTrue(RadarConsentProtocol.isValidGrant(consent, now, now))
    }

    @Test
    fun `rechaza concesion expirada futura excesiva y reloj desviado`() {
        val now = 10_000_000L
        val expired = requireNotNull(
            RadarConsentProtocol.decode(RadarConsentProtocol.grant(now - 1)),
        )
        val excessive = requireNotNull(
            RadarConsentProtocol.decode(
                RadarConsentProtocol.grant(
                    now + RadarConsentProtocol.MAX_GRANT_DURATION_MS +
                        RadarConsentProtocol.CLOCK_SKEW_MS + 1,
                ),
            ),
        )
        val valid = requireNotNull(
            RadarConsentProtocol.decode(
                RadarConsentProtocol.grant(
                    now + RadarConsentProtocol.MANUAL_DURATION_MS,
                ),
            ),
        )

        assertFalse(RadarConsentProtocol.isValidGrant(expired, now, now))
        assertFalse(RadarConsentProtocol.isValidGrant(excessive, now, now))
        assertFalse(
            RadarConsentProtocol.isValidGrant(
                valid,
                now - RadarConsentProtocol.CLOCK_SKEW_MS - 1,
                now,
            ),
        )
    }

    @Test
    fun `revocaciones usan nonce unico y formato estricto`() {
        val first = requireNotNull(
            RadarConsentProtocol.decode(RadarConsentProtocol.revoke()),
        )
        val second = requireNotNull(
            RadarConsentProtocol.decode(RadarConsentProtocol.revoke()),
        )

        assertEquals(RadarConsentProtocol.ACTION_REVOKE, first.action)
        assertEquals(0L, first.expiresAt)
        assertNotEquals(first.nonce.toList(), second.nonce.toList())
        assertNull(RadarConsentProtocol.decode(ByteArray(3)))
        assertNull(
            RadarConsentProtocol.decode(
                RadarConsentProtocol.revoke().also { it[0] = 99 },
            ),
        )
    }

    @Test
    fun `una firma no autoriza una carga modificada`() {
        val generator = Ed25519KeyPairGenerator().apply {
            init(Ed25519KeyGenerationParameters(SecureRandom()))
        }
        val pair = generator.generateKeyPair()
        val privateKey = pair.private as Ed25519PrivateKeyParameters
        val publicKey = pair.public as Ed25519PublicKeyParameters
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_RADAR_CONTROL,
            ttl = 1,
            timestamp = 1_000,
            senderId = ByteArray(8) { 1 },
            payload = RadarConsentProtocol.grant(2_000),
        )
        val canonical = packet.canonicalForSigning()
        val signer = Ed25519Signer().apply {
            init(true, privateKey)
            update(canonical, 0, canonical.size)
        }
        val signed = packet.copy(signature = signer.generateSignature())
        val modified = signed.copy(
            payload = signed.payload.copyOf().also { it[2] = (it[2].toInt() xor 1).toByte() },
        )

        assertTrue(verify(signed, publicKey))
        assertFalse(verify(modified, publicKey))
    }

    private fun verify(
        packet: MeshProtocol.Packet,
        key: Ed25519PublicKeyParameters,
    ): Boolean {
        val signature = packet.signature ?: return false
        val canonical = packet.canonicalForSigning()
        return Ed25519Signer().run {
            init(false, key)
            update(canonical, 0, canonical.size)
            verifySignature(signature)
        }
    }
}
