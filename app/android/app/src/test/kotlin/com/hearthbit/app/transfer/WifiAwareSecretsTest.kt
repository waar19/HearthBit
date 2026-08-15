package com.hearthbit.app.transfer

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class WifiAwareSecretsTest {
    @Test
    fun `derivations are stable and transfer specific`() {
        val first = WifiAwareSecrets.discoveryToken("transfer-a")
        val repeated = WifiAwareSecrets.discoveryToken("transfer-a")
        val second = WifiAwareSecrets.discoveryToken("transfer-b")

        assertArrayEquals(first, repeated)
        assertFalse(first.contentEquals(second))
        assertNotEquals(
            WifiAwareSecrets.passphrase("transfer-a"),
            WifiAwareSecrets.passphrase("transfer-b"),
        )
    }

    @Test
    fun `observable discovery token cannot equal the data path passphrase`() {
        val tokenHex = WifiAwareSecrets.discoveryToken("secret-transfer")
            .joinToString(separator = "") { "%02x".format(it) }
        val passphrase = WifiAwareSecrets.passphrase("secret-transfer")

        assertNotEquals(tokenHex, passphrase.removePrefix("hbt-"))
        assertTrue(passphrase.length in 8..63)
    }

    @Test
    fun `blank transfer id is rejected`() {
        assertThrows(IllegalArgumentException::class.java) {
            WifiAwareSecrets.discoveryToken(" ")
        }
        assertThrows(IllegalArgumentException::class.java) {
            WifiAwareSecrets.passphrase("")
        }
    }
}
