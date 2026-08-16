package com.hearthbit.app.mesh

import org.bouncycastle.math.ec.rfc7748.X25519

internal object SealedTransferCrypto {
    fun deriveSharedSecret(privateKey: ByteArray, publicKey: ByteArray): ByteArray {
        require(privateKey.size == 32 && publicKey.size == 32)
        return ByteArray(32).also { output ->
            check(
                X25519.calculateAgreement(privateKey, 0, publicKey, 0, output, 0),
            ) { "invalid_x25519_shared_secret" }
        }
    }
}
