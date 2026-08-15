package com.hearthbit.app.mesh

import com.bitchat.android.noise.southernstorm.protocol.CipherState
import com.bitchat.android.noise.southernstorm.protocol.HandshakeState

internal class NoiseSessionLite(
    private val claimedPeerId: ByteArray,
    internal val initiator: Boolean,
    private val localPrivateKey: ByteArray,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    private var handshake: HandshakeState? = null
    private var sendCipher: CipherState? = null
    private var receiveCipher: CipherState? = null
    private var patternCount = 0
    private var sendNonce = 0L
    private var receivedMessages = 0L
    private val replayWindow = NoiseReplayWindow()
    private var establishedAt = 0L

    var lastActivityAt: Long = nowMillis()
        private set

    var established: Boolean = false
        private set

    val handshaking: Boolean
        get() = handshake != null && !established

    fun isStale(now: Long, timeoutMs: Long): Boolean =
        handshaking && now - lastActivityAt >= timeoutMs

    fun isTransportExpired(now: Long = nowMillis()): Boolean =
        established &&
            (
                sendNonce >= MAX_TRANSPORT_MESSAGES ||
                    receivedMessages >= MAX_TRANSPORT_MESSAGES ||
                    now - establishedAt >= MAX_TRANSPORT_AGE_MS
                )

    fun start(): ByteArray {
        if (!initiator || handshake != null || established) {
            throw NoiseHandshakeFailure.State("Noise initiator is in an invalid state")
        }
        initialize(HandshakeState.INITIATOR)
        return try {
            writeHandshake().also { touch() }
        } catch (error: NoiseHandshakeFailure) {
            throw error
        } catch (error: Exception) {
            throw NoiseHandshakeFailure.Protocol(error)
        }
    }

    fun processHandshake(message: ByteArray): ByteArray? {
        if (established) {
            throw NoiseHandshakeFailure.State("Noise session is already established")
        }
        if (handshake == null) {
            if (initiator) {
                throw NoiseHandshakeFailure.State("Noise initiator was not started")
            }
            initialize(HandshakeState.RESPONDER)
        }
        return try {
            val state = checkNotNull(handshake)
            val payload = ByteArray(256)
            state.readMessage(message, 0, message.size, payload, 0)
            patternCount++
            touch()
            when (state.action) {
                HandshakeState.WRITE_MESSAGE -> writeHandshake().also { completeIfReady() }
                HandshakeState.SPLIT -> {
                    completeIfReady()
                    null
                }
                HandshakeState.FAILED -> throw NoiseHandshakeFailure.Protocol(
                    IllegalStateException("Noise XX rejected the handshake"),
                )
                else -> null
            }
        } catch (error: NoiseHandshakeFailure) {
            throw error
        } catch (error: Exception) {
            throw NoiseHandshakeFailure.Protocol(error)
        }
    }

    fun encrypt(plaintext: ByteArray): ByteArray {
        check(established)
        require(sendNonce < MAX_TRANSPORT_MESSAGES) { "Noise transport requires rekey" }
        val cipher = checkNotNull(sendCipher)
        cipher.setNonce(sendNonce)
        val ciphertext = ByteArray(plaintext.size + cipher.macLength)
        val length = cipher.encryptWithAd(
            null,
            plaintext,
            0,
            ciphertext,
            0,
            plaintext.size,
        )
        val nonce = sendNonce++
        touch()
        return ByteArray(4 + length).also { output ->
            output[0] = (nonce ushr 24).toByte()
            output[1] = (nonce ushr 16).toByte()
            output[2] = (nonce ushr 8).toByte()
            output[3] = nonce.toByte()
            ciphertext.copyInto(output, 4, 0, length)
        }
    }

    fun decrypt(input: ByteArray): ByteArray {
        check(established)
        require(input.size >= 20)
        require(receivedMessages < MAX_TRANSPORT_MESSAGES) {
            "Noise transport requires rekey"
        }
        val nonce =
            ((input[0].toLong() and 0xFF) shl 24) or
                ((input[1].toLong() and 0xFF) shl 16) or
                ((input[2].toLong() and 0xFF) shl 8) or
                (input[3].toLong() and 0xFF)
        check(replayWindow.canAccept(nonce)) { "Repeated or stale Noise nonce" }
        val cipher = checkNotNull(receiveCipher)
        cipher.setNonce(nonce)
        val ciphertext = input.copyOfRange(4, input.size)
        val plaintext = ByteArray(ciphertext.size)
        val length = cipher.decryptWithAd(
            null,
            ciphertext,
            0,
            plaintext,
            0,
            ciphertext.size,
        )
        replayWindow.recordAuthenticated(nonce)
        receivedMessages += 1
        touch()
        return plaintext.copyOf(length)
    }

    fun close() {
        handshake?.destroy()
        sendCipher?.destroy()
        receiveCipher?.destroy()
        handshake = null
        sendCipher = null
        receiveCipher = null
        established = false
        replayWindow.clear()
        establishedAt = 0L
        sendNonce = 0L
        receivedMessages = 0L
    }

    private fun initialize(role: Int) {
        val state = HandshakeState(PROTOCOL, role)
        if (state.needsLocalKeyPair()) {
            checkNotNull(state.localKeyPair).setPrivateKey(localPrivateKey, 0)
        }
        state.start()
        handshake = state
    }

    private fun writeHandshake(): ByteArray {
        val state = checkNotNull(handshake)
        val output = ByteArray(256)
        val length = state.writeMessage(output, 0, null, 0, 0)
        patternCount++
        return output.copyOf(length)
    }

    private fun completeIfReady() {
        if (patternCount < 3 || established) return
        val state = checkNotNull(handshake)
        check(state.hasRemotePublicKey())
        val remoteDh = checkNotNull(state.remotePublicKey)
        val remotePublic = ByteArray(32)
        remoteDh.getPublicKey(remotePublic, 0)
        if (!MeshProtocol.peerIdFromNoiseKey(remotePublic).contentEquals(claimedPeerId)) {
            throw NoiseHandshakeFailure.IdentityMismatch()
        }
        val pair = state.split()
        sendCipher = pair.sender
        receiveCipher = pair.receiver
        state.destroy()
        handshake = null
        established = true
        establishedAt = nowMillis()
        touch()
    }

    private fun touch() {
        lastActivityAt = nowMillis()
    }

    private companion object {
        const val PROTOCOL = "Noise_XX_25519_ChaChaPoly_SHA256"
        const val MAX_TRANSPORT_MESSAGES = 1L shl 20
        const val MAX_TRANSPORT_AGE_MS = 60 * 60 * 1_000L
    }
}
