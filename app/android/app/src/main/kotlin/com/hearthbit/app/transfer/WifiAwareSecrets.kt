package com.hearthbit.app.transfer

import java.nio.charset.StandardCharsets
import java.security.MessageDigest

/**
 * Deriva credenciales independientes para descubrir y proteger una
 * transferencia Wi-Fi Aware.
 *
 * [transferId] se negocia dentro de la sesión Noise y nunca se publica. La
 * separación por dominio impide usar el token observable para reconstruir la
 * passphrase WPA3 del data path.
 */
internal object WifiAwareSecrets {
    private const val DISCOVERY_DOMAIN = "hearthbit-aware-discovery-v1:"
    private const val PASSPHRASE_DOMAIN = "hearthbit-aware-psk-v1:"
    private const val DISCOVERY_BYTES = 16
    private const val PASSPHRASE_HEX_CHARS = 32

    fun discoveryToken(transferId: String): ByteArray =
        digest(DISCOVERY_DOMAIN, transferId).copyOf(DISCOVERY_BYTES)

    fun passphrase(transferId: String): String =
        "hbt-" + digest(PASSPHRASE_DOMAIN, transferId)
            .joinToString(separator = "") { "%02x".format(it) }
            .take(PASSPHRASE_HEX_CHARS)

    private fun digest(domain: String, transferId: String): ByteArray {
        require(transferId.isNotBlank()) { "transferId must not be blank" }
        return MessageDigest.getInstance("SHA-256").digest(
            "$domain$transferId".toByteArray(StandardCharsets.UTF_8),
        )
    }
}
