package com.hearthbit.app.mesh

import java.security.GeneralSecurityException
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class KeystoreSecureStoreTest {
    @Test
    fun `discard unreadable legacy and finish migration`() {
        var legacyCleared = false
        var migrationComplete = false
        val warnings = mutableListOf<String>()

        val entries = readLegacyOrDiscard(
            namespace = "hearthbit_identity",
            readLegacy = {
                throw GeneralSecurityException("decryption failed")
            },
            clearLegacy = {
                legacyCleared = true
                true
            },
            markComplete = {
                migrationComplete = true
                true
            },
            logWarning = { message, _ -> warnings += message },
        )

        assertNull(entries)
        assertTrue(legacyCleared)
        assertTrue(migrationComplete)
        assertTrue(warnings.single().contains("hearthbit_identity"))
    }

    @Test
    fun `malformed legacy cannot create a migration crash loop`() {
        var legacyCleared = false
        var migrationComplete = false

        val entries = readLegacyOrDiscard(
            namespace = "hearthbit_peer_trust",
            readLegacy = {
                error("El almacén legado no contiene sus keysets")
            },
            clearLegacy = {
                legacyCleared = true
                true
            },
            markComplete = {
                migrationComplete = true
                true
            },
            logWarning = { _, _ -> },
        )

        assertNull(entries)
        assertTrue(legacyCleared)
        assertTrue(migrationComplete)
    }
}
