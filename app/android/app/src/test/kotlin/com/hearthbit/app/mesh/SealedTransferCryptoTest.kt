package com.hearthbit.app.mesh

import org.bouncycastle.math.ec.rfc7748.X25519
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.security.SecureRandom

class SealedTransferCryptoTest {
    @Test
    fun `X25519 sellado deriva el mismo secreto en ambos extremos`() {
        val senderPrivate = ByteArray(32)
        val receiverPrivate = ByteArray(32)
        X25519.generatePrivateKey(SecureRandom(), senderPrivate)
        X25519.generatePrivateKey(SecureRandom(), receiverPrivate)
        val senderPublic = ByteArray(32)
        val receiverPublic = ByteArray(32)
        X25519.generatePublicKey(senderPrivate, 0, senderPublic, 0)
        X25519.generatePublicKey(receiverPrivate, 0, receiverPublic, 0)

        assertArrayEquals(
            SealedTransferCrypto.deriveSharedSecret(senderPrivate, receiverPublic),
            SealedTransferCrypto.deriveSharedSecret(receiverPrivate, senderPublic),
        )
        assertThrows(IllegalArgumentException::class.java) {
            SealedTransferCrypto.deriveSharedSecret(ByteArray(31), receiverPublic)
        }
    }
}
