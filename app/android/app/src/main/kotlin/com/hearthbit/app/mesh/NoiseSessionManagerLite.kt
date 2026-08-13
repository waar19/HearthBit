package com.hearthbit.app.mesh

internal data class NoiseHandshakeResult(
    val response: ByteArray?,
    val establishedNow: Boolean,
)

internal class NoiseSessionManagerLite(
    private val localPeerId: String,
    private val localPrivateKey: ByteArray,
) {
    private val sessions = mutableMapOf<String, NoiseSessionLite>()
    private val responderCandidates = mutableMapOf<String, NoiseSessionLite>()

    @Synchronized
    fun initiate(peerId: String): ByteArray? {
        if (sessions[peerId] != null || responderCandidates[peerId] != null) return null
        val session = NoiseSessionLite(peerId.hexToPeerId(), true, localPrivateKey)
        sessions[peerId] = session
        return try {
            session.start()
        } catch (error: Exception) {
            sessions.remove(peerId)
            session.close()
            throw error.asNoiseHandshakeFailure()
        }
    }

    @Synchronized
    fun process(
        peerId: String,
        claimedPeerId: ByteArray,
        message: ByteArray,
    ): NoiseHandshakeResult {
        val isMessageOne = message.size == HANDSHAKE_MESSAGE_ONE_SIZE
        var session = responderCandidates[peerId]
        var candidate = session != null

        if (candidate && isMessageOne) {
            responderCandidates.remove(peerId)?.close()
            session = newResponder(claimedPeerId).also { responderCandidates[peerId] = it }
        }

        if (session == null) {
            session = sessions[peerId]
            if (session?.handshaking == true && session.initiator && isMessageOne) {
                if (localPeerId > peerId) {
                    sessions.remove(peerId)?.close()
                    session = null
                } else {
                    return NoiseHandshakeResult(response = null, establishedNow = false)
                }
            }

            when {
                session == null -> {
                    session = newResponder(claimedPeerId)
                    sessions[peerId] = session
                }
                session.established && isMessageOne -> {
                    session = newResponder(claimedPeerId)
                    responderCandidates[peerId] = session
                    candidate = true
                }
                session.established -> {
                    throw NoiseHandshakeFailure.State(
                        "Unexpected Noise handshake continuation for an established session",
                    )
                }
                session.handshaking && !session.initiator && isMessageOne -> {
                    sessions.remove(peerId)?.close()
                    session = newResponder(claimedPeerId)
                    sessions[peerId] = session
                }
            }
        }

        return try {
            val response = session.processHandshake(message)
            val establishedNow = session.established
            if (establishedNow && candidate) {
                responderCandidates.remove(peerId, session)
                sessions.put(peerId, session)?.takeIf { it !== session }?.close()
            }
            NoiseHandshakeResult(response, establishedNow)
        } catch (error: Exception) {
            if (candidate) {
                responderCandidates.remove(peerId, session)
            } else {
                sessions.remove(peerId, session)
            }
            session.close()
            throw error.asNoiseHandshakeFailure()
        }
    }

    @Synchronized
    fun isEstablished(peerId: String): Boolean = sessions[peerId]?.established == true

    @Synchronized
    fun encrypt(peerId: String, plaintext: ByteArray): ByteArray {
        val session = sessions[peerId]?.takeIf(NoiseSessionLite::established)
            ?: throw NoiseHandshakeFailure.State("Noise session is not established")
        return session.encrypt(plaintext)
    }

    @Synchronized
    fun decrypt(peerId: String, ciphertext: ByteArray): ByteArray {
        val session = sessions[peerId]?.takeIf(NoiseSessionLite::established)
            ?: throw NoiseHandshakeFailure.State("Noise session is not established")
        return session.decrypt(ciphertext)
    }

    @Synchronized
    fun invalidate(peerId: String) {
        sessions.remove(peerId)?.close()
        responderCandidates.remove(peerId)?.close()
    }

    @Synchronized
    fun close() {
        sessions.values.forEach(NoiseSessionLite::close)
        responderCandidates.values.forEach(NoiseSessionLite::close)
        sessions.clear()
        responderCandidates.clear()
    }

    private fun newResponder(claimedPeerId: ByteArray) =
        NoiseSessionLite(claimedPeerId, false, localPrivateKey)

    private fun String.hexToPeerId(): ByteArray {
        if (length != 16) throw NoiseHandshakeFailure.State("Invalid peer ID")
        return chunked(2).map {
            it.toIntOrNull(16)?.toByte()
                ?: throw NoiseHandshakeFailure.State("Invalid peer ID")
        }.toByteArray()
    }

    private companion object {
        const val HANDSHAKE_MESSAGE_ONE_SIZE = 32
    }
}

internal sealed class NoiseHandshakeFailure(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause) {
    class IdentityMismatch(cause: Throwable? = null) :
        NoiseHandshakeFailure("Noise identity does not match the announced peer", cause)

    class State(message: String, cause: Throwable? = null) :
        NoiseHandshakeFailure(message, cause)

    class Protocol(cause: Throwable) :
        NoiseHandshakeFailure("Noise handshake failed", cause)
}

private fun Exception.asNoiseHandshakeFailure(): NoiseHandshakeFailure = when (this) {
    is NoiseHandshakeFailure -> this
    is IllegalStateException -> NoiseHandshakeFailure.State(message ?: "Invalid Noise state", this)
    else -> NoiseHandshakeFailure.Protocol(this)
}
