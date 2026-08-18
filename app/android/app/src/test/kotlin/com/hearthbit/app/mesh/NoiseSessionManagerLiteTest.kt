package com.hearthbit.app.mesh

import com.hearthbit.noise.southernstorm.protocol.Noise
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.security.MessageDigest

class NoiseSessionManagerLiteTest {
    private val managers = mutableListOf<NoiseSessionManagerLite>()

    @After
    fun tearDown() {
        managers.forEach(NoiseSessionManagerLite::close)
    }

    @Test
    fun `reinicio XX reemplaza de forma segura una sesion establecida`() {
        val alice = identity()
        val bob = identity()
        val aliceManager = manager(alice)
        val originalBobManager = manager(bob)
        completeHandshake(aliceManager, alice, originalBobManager, bob)

        val restartedBobManager = manager(bob)
        val message1 = restartedBobManager.initiate(alice.peerId)!!
        val message2 = aliceManager.process(bob.peerId, bob.peerIdBytes, message1).response!!

        assertTrue(aliceManager.isEstablished(bob.peerId))
        val oldTransportPayload = "old transport remains usable".toByteArray()
        assertArrayEquals(
            oldTransportPayload,
            originalBobManager.decrypt(
                alice.peerId,
                aliceManager.encrypt(bob.peerId, oldTransportPayload),
            ),
        )

        val message3 = restartedBobManager.process(
            alice.peerId,
            alice.peerIdBytes,
            message2,
        ).response!!
        val completion = aliceManager.process(bob.peerId, bob.peerIdBytes, message3)

        assertTrue(completion.establishedNow)
        val replacementPayload = "replacement transport".toByteArray()
        assertArrayEquals(
            replacementPayload,
            aliceManager.decrypt(
                bob.peerId,
                restartedBobManager.encrypt(alice.peerId, replacementPayload),
            ),
        )
    }

    @Test
    fun `nuevo inicio XX reinicia una sesion respondedora incompleta`() {
        val alice = identity()
        val bob = identity()
        val aliceManager = manager(alice)
        val abandonedBobManager = manager(bob)
        val abandonedMessage1 = abandonedBobManager.initiate(alice.peerId)!!
        assertNotNull(
            aliceManager.process(bob.peerId, bob.peerIdBytes, abandonedMessage1).response,
        )

        val restartedBobManager = manager(bob)
        val restartedMessage1 = restartedBobManager.initiate(alice.peerId)!!
        val restartedMessage2 = aliceManager.process(
            bob.peerId,
            bob.peerIdBytes,
            restartedMessage1,
        ).response!!
        val restartedMessage3 = restartedBobManager.process(
            alice.peerId,
            alice.peerIdBytes,
            restartedMessage2,
        ).response!!

        assertTrue(
            aliceManager.process(bob.peerId, bob.peerIdBytes, restartedMessage3).establishedNow,
        )
        assertTrue(restartedBobManager.isEstablished(alice.peerId))
    }

    @Test
    fun `inicios simultaneos usan desempate estable por peer ID`() {
        val alice = identity()
        val bob = identity()
        val aliceManager = manager(alice)
        val bobManager = manager(bob)
        val aliceMessage1 = aliceManager.initiate(bob.peerId)!!
        val bobMessage1 = bobManager.initiate(alice.peerId)!!

        val aliceResult = aliceManager.process(bob.peerId, bob.peerIdBytes, bobMessage1)
        val bobResult = bobManager.process(alice.peerId, alice.peerIdBytes, aliceMessage1)

        val initiator: NoiseSessionManagerLite
        val initiatorIdentity: TestIdentity
        val responder: NoiseSessionManagerLite
        val responderIdentity: TestIdentity
        val message2: ByteArray
        if (alice.peerId < bob.peerId) {
            assertNull(aliceResult.response)
            initiator = aliceManager
            initiatorIdentity = alice
            responder = bobManager
            responderIdentity = bob
            message2 = bobResult.response!!
        } else {
            assertNull(bobResult.response)
            initiator = bobManager
            initiatorIdentity = bob
            responder = aliceManager
            responderIdentity = alice
            message2 = aliceResult.response!!
        }

        val message3 = initiator.process(
            responderIdentity.peerId,
            responderIdentity.peerIdBytes,
            message2,
        ).response!!
        assertTrue(
            responder.process(
                initiatorIdentity.peerId,
                initiatorIdentity.peerIdBytes,
                message3,
            ).establishedNow,
        )
        assertTrue(aliceManager.isEstablished(bob.peerId))
        assertTrue(bobManager.isEstablished(alice.peerId))
    }

    @Test
    fun `rechazo de identidad no elimina el transporte establecido`() {
        val alice = identity()
        val bob = identity()
        val attacker = identity()
        val aliceManager = manager(alice)
        val bobManager = manager(bob)
        completeHandshake(aliceManager, alice, bobManager, bob)

        val attackerManager = manager(attacker)
        val message1 = attackerManager.initiate(alice.peerId)!!
        val message2 = aliceManager.process(bob.peerId, bob.peerIdBytes, message1).response!!
        val message3 = attackerManager.process(
            alice.peerId,
            alice.peerIdBytes,
            message2,
        ).response!!

        try {
            aliceManager.process(bob.peerId, bob.peerIdBytes, message3)
            fail("Se esperaba un rechazo de identidad")
        } catch (_: NoiseHandshakeFailure.IdentityMismatch) {
            // Esperado.
        }

        assertTrue(aliceManager.isEstablished(bob.peerId))
        val payload = "trusted transport survives".toByteArray()
        assertArrayEquals(
            payload,
            bobManager.decrypt(alice.peerId, aliceManager.encrypt(bob.peerId, payload)),
        )
    }

    @Test
    fun `fallo de protocolo no se clasifica como identidad rechazada`() {
        val alice = identity()
        val bob = identity()
        val aliceManager = manager(alice)

        try {
            aliceManager.process(bob.peerId, bob.peerIdBytes, byteArrayOf(1, 2, 3))
            fail("Se esperaba un fallo de protocolo")
        } catch (error: NoiseHandshakeFailure) {
            assertFalse(error is NoiseHandshakeFailure.IdentityMismatch)
            assertTrue(error is NoiseHandshakeFailure.Protocol)
        }
    }

    @Test
    fun `invalidar enlace directo obliga a negociar una nueva sesion`() {
        val alice = identity()
        val bob = identity()
        val aliceManager = manager(alice)
        val bobManager = manager(bob)
        completeHandshake(aliceManager, alice, bobManager, bob)

        aliceManager.invalidate(bob.peerId)
        bobManager.invalidate(alice.peerId)

        assertFalse(aliceManager.isEstablished(bob.peerId))
        assertFalse(bobManager.isEstablished(alice.peerId))
        completeHandshake(aliceManager, alice, bobManager, bob)
        assertTrue(aliceManager.isEstablished(bob.peerId))
        assertTrue(bobManager.isEstablished(alice.peerId))
    }

    @Test
    fun `handshake incompleto stale se limpia y permite reintento`() {
        val alice = identity()
        val bob = identity()
        var now = 1_000L
        val aliceManager = manager(alice, nowMillis = { now })

        assertNotNull(aliceManager.initiate(bob.peerId))
        assertNull(aliceManager.initiate(bob.peerId))
        assertTrue(aliceManager.hasSession(bob.peerId))

        now += 20_001L
        assertTrue(aliceManager.cleanupStaleHandshakes().contains(bob.peerId))
        assertFalse(aliceManager.hasSession(bob.peerId))
        assertNotNull(aliceManager.initiate(bob.peerId))
    }

    @Test
    fun `replay antiguo sigue rechazado despues de mas de 1024 mensajes`() {
        val alice = identity()
        val bob = identity()
        val aliceManager = manager(alice)
        val bobManager = manager(bob)
        completeHandshake(aliceManager, alice, bobManager, bob)
        var firstCiphertext: ByteArray? = null

        repeat(1_025) { nonce ->
            val plaintext = "message-$nonce".toByteArray()
            val ciphertext = aliceManager.encrypt(bob.peerId, plaintext)
            if (nonce == 0) firstCiphertext = ciphertext.copyOf()
            assertArrayEquals(plaintext, bobManager.decrypt(alice.peerId, ciphertext))
        }

        try {
            bobManager.decrypt(alice.peerId, checkNotNull(firstCiphertext))
            fail("Se esperaba rechazo del nonce fuera de la ventana")
        } catch (_: IllegalStateException) {
            // El watermark no permite reabrir un nonce ya fuera de ventana.
        }
    }

    @Test
    fun `transporte Noise expira exactamente al cumplir una hora`() {
        val alice = identity()
        val bob = identity()
        var now = 10_000L
        val aliceManager = manager(alice, nowMillis = { now })
        val bobManager = manager(bob, nowMillis = { now })
        completeHandshake(aliceManager, alice, bobManager, bob)
        val establishedAt = now

        now = establishedAt + 60 * 60 * 1_000L - 1
        assertNotNull(aliceManager.encrypt(bob.peerId, byteArrayOf(1)))

        now = establishedAt + 60 * 60 * 1_000L
        try {
            aliceManager.encrypt(bob.peerId, byteArrayOf(2))
            fail("Se esperaba rekey al cumplir una hora")
        } catch (_: NoiseHandshakeFailure.SessionExpired) {
            // Frontera exacta del perfil.
        }
        assertFalse(aliceManager.isEstablished(bob.peerId))
    }

    private fun completeHandshake(
        initiator: NoiseSessionManagerLite,
        initiatorIdentity: TestIdentity,
        responder: NoiseSessionManagerLite,
        responderIdentity: TestIdentity,
    ) {
        val message1 = initiator.initiate(responderIdentity.peerId)!!
        val message2 = responder.process(
            initiatorIdentity.peerId,
            initiatorIdentity.peerIdBytes,
            message1,
        ).response!!
        val message3 = initiator.process(
            responderIdentity.peerId,
            responderIdentity.peerIdBytes,
            message2,
        ).response!!
        assertTrue(
            responder.process(
                initiatorIdentity.peerId,
                initiatorIdentity.peerIdBytes,
                message3,
            ).establishedNow,
        )
    }

    private fun manager(
        identity: TestIdentity,
        nowMillis: () -> Long = System::currentTimeMillis,
    ): NoiseSessionManagerLite =
        NoiseSessionManagerLite(
            identity.peerId,
            identity.privateKey,
            nowMillis,
        ).also(managers::add)

    private fun identity(): TestIdentity {
        val dh = Noise.createDH("25519")
        return try {
            dh.generateKeyPair()
            val privateKey = ByteArray(32)
            val publicKey = ByteArray(32)
            dh.getPrivateKey(privateKey, 0)
            dh.getPublicKey(publicKey, 0)
            val peerIdBytes = MessageDigest.getInstance("SHA-256").digest(publicKey).copyOf(8)
            TestIdentity(privateKey, peerIdBytes)
        } finally {
            dh.destroy()
        }
    }

    private data class TestIdentity(
        val privateKey: ByteArray,
        val peerIdBytes: ByteArray,
    ) {
        val peerId: String = MeshProtocol.hex(peerIdBytes)
    }
}
