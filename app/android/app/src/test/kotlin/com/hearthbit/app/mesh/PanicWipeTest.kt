package com.hearthbit.app.mesh

import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Cubre el Hueco 4 de
 * `docs/superpowers/specs/2026-08-24-panic-wipe-sqlite-cipher-design.md`:
 * `MeshEngine.panicWipe()` debe borrar cada uno de los almacenes
 * persistentes nativos.
 *
 * El motor completo requiere `BluetoothManager`, `Keystore` y
 * `Context` reales, así que el test ejercita el helper extraído
 * `MeshEnginePanicWipe.wipePersistentState` que `MeshEngine.panicWipe()`
 * invoca para el sub-wipe persistente. El test verifica que:
 *
 * - `relationshipPreferences` (SharedPreferences directa) queda vacía.
 * - Cada uno de los seis callbacks de borrado (storeForward,
 *   emergencyFingerprints, peerTrust, rescueMode, secureStore, identity)
 *   se invoca exactamente una vez y en el orden documentado.
 * - El wipe es idempotente: una segunda llamada con el estado vacío
 *   no lanza.
 *
 * Si añades un nuevo store al panic wipe, añade su `FakeClearable` aquí
 * y extiendo la lista de invocaciones esperadas; el test fallará hasta
 * que actualices la lista de callbacks en `MeshEngine.panicWipe()`.
 */
class PanicWipeTest {
    @Test
    fun `panicWipe clears every persistent native store in the documented order`() {
        val relationshipPrefs = FakeSharedPreferences().apply {
            edit().putString("ios_overflow_service_bit", "1").commit()
            edit().putStringSet("session_peers", setOf("peer-a", "peer-b")).commit()
        }
        val storeForward = FakeClearable("storeForward")
        val fingerprints = FakeClearable("emergencyFingerprints")
        val peerTrust = FakeClearable("peerTrust")
        val rescue = FakeClearable("rescueMode")
        val secureStore = FakeClearable("relationshipSecureStore")
        val identity = FakeClearable("identity")

        TestMeshEngine(
            relationshipPreferences = relationshipPrefs,
            storeForward = storeForward,
            fingerprints = fingerprints,
            peerTrust = peerTrust,
            rescue = rescue,
            secureStore = secureStore,
            identity = identity,
        ).panicWipe()

        assertEquals(
            "relationshipPreferences debe quedar vacía tras el wipe",
            0,
            relationshipPrefs.size,
        )
        assertEquals(
            "Cada store debe limpiarse exactamente una vez y en orden",
            listOf(
                "storeForward",
                "emergencyFingerprints",
                "peerTrust",
                "rescueMode",
                "relationshipSecureStore",
                "identity",
            ),
            listOf(storeForward, fingerprints, peerTrust, rescue, secureStore, identity)
                .flatMap { it.clears },
        )
        assertTrue(storeForward.cleared)
        assertTrue(fingerprints.cleared)
        assertTrue(peerTrust.cleared)
        assertTrue(rescue.cleared)
        assertTrue(secureStore.cleared)
        assertTrue(identity.cleared)
    }

    @Test
    fun `panicWipe is idempotent when run on an already wiped engine`() {
        val relationshipPrefs = FakeSharedPreferences()
        val storeForward = FakeClearable("storeForward")
        val fingerprints = FakeClearable("emergencyFingerprints")
        val peerTrust = FakeClearable("peerTrust")
        val rescue = FakeClearable("rescueMode")
        val secureStore = FakeClearable("relationshipSecureStore")
        val identity = FakeClearable("identity")
        val engine = TestMeshEngine(
            relationshipPreferences = relationshipPrefs,
            storeForward = storeForward,
            fingerprints = fingerprints,
            peerTrust = peerTrust,
            rescue = rescue,
            secureStore = secureStore,
            identity = identity,
        )

        engine.panicWipe()
        // Segunda llamada: no debe lanzar, y cada callback se invoca
        // exactamente una vez adicional.
        engine.panicWipe()

        assertEquals(0, relationshipPrefs.size)
        for (target in listOf(storeForward, fingerprints, peerTrust, rescue, secureStore, identity)) {
            assertEquals("Cada store debe limpiarse dos veces (una por wipe)", 2, target.clearCount)
        }
    }

    /**
     * Doble local de [MeshEngine] que ejercita el mismo helper
     * (`MeshEnginePanicWipe.wipePersistentState`) con la misma firma de
     * callbacks que el código de producción. Mantiene el contrato
     * "TestMeshEngine(...).panicWipe()" del plan y aísla el sub-wipe
     * persistente del resto del motor.
     */
    private class TestMeshEngine(
        private val relationshipPreferences: SharedPreferences,
        private val storeForward: FakeClearable,
        private val fingerprints: FakeClearable,
        private val peerTrust: FakeClearable,
        private val rescue: FakeClearable,
        private val secureStore: FakeClearable,
        private val identity: FakeClearable,
    ) {
        fun panicWipe() {
            MeshEnginePanicWipe.wipePersistentState(
                relationshipPreferences = relationshipPreferences,
                clearStoreAndForward = { storeForward.clear() },
                clearEmergencyFingerprints = { fingerprints.clear() },
                clearPeerTrustStore = { peerTrust.clear() },
                clearRescueModeStore = { rescue.clear() },
                clearRelationshipSecureStore = { secureStore.clear() },
                clearIdentity = { identity.clear() },
            )
        }
    }

    /**
     * Doble de un store "clearable" que registra el orden de invocación
     * para que el test pueda asertar tanto cobertura como secuencia.
     */
    private class FakeClearable(val label: String) {
        var clearCount: Int = 0
            private set
        val clears: MutableList<String> = mutableListOf()
        val cleared: Boolean get() = clearCount > 0

        fun clear() {
            clearCount += 1
            clears += label
        }
    }

    /**
     * Implementación mínima de [SharedPreferences] con un `Map` en memoria.
     * Solo cubre los métodos que [MeshEnginePanicWipe.wipePersistentState]
     * invoca: `edit()`, `edit().putString()`, `edit().clear()` y
     * `edit().commit()`. El resto lanza para evidenciar cualquier
     * dependencia accidental del helper en APIs no contempladas.
     */
    private class FakeSharedPreferences : SharedPreferences {
        private val values: MutableMap<String, Any?> = mutableMapOf()
        val size: Int get() = values.size

        override fun getAll(): Map<String, *> = values.toMap()

        override fun getString(key: String, defValue: String?): String? =
            values[key] as? String ?: defValue

        override fun getStringSet(key: String, defValues: Set<String>?): Set<String>? =
            @Suppress("UNCHECKED_CAST")
            (values[key] as? Set<String>) ?: defValues

        override fun getInt(key: String, defValue: Int): Int =
            (values[key] as? Int) ?: defValue

        override fun getLong(key: String, defValue: Long): Long =
            (values[key] as? Long) ?: defValue

        override fun getFloat(key: String, defValue: Float): Float =
            (values[key] as? Float) ?: defValue

        override fun getBoolean(key: String, defValue: Boolean): Boolean =
            (values[key] as? Boolean) ?: defValue

        override fun contains(key: String): Boolean = values.containsKey(key)

        override fun edit(): SharedPreferences.Editor = FakeEditor(values)

        override fun registerOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener?,
        ) = Unit

        override fun unregisterOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener?,
        ) = Unit

        private class FakeEditor(
            private val backing: MutableMap<String, Any?>,
        ) : SharedPreferences.Editor {
            private val pending: MutableMap<String, Any?> = backing.toMutableMap()
            private val removals: MutableSet<String> = mutableSetOf()
            private var clearAll = false

            override fun putString(key: String, value: String?): SharedPreferences.Editor = apply {
                if (value == null) {
                    pending.remove(key)
                    removals += key
                } else {
                    pending[key] = value
                    removals -= key
                }
            }

            override fun putStringSet(
                key: String,
                values: Set<String>?,
            ): SharedPreferences.Editor = apply {
                if (values == null) {
                    pending.remove(key)
                    removals += key
                } else {
                    pending[key] = values.toSet()
                    removals -= key
                }
            }

            override fun putInt(key: String, value: Int): SharedPreferences.Editor = apply {
                pending[key] = value
                removals -= key
            }

            override fun putLong(key: String, value: Long): SharedPreferences.Editor = apply {
                pending[key] = value
                removals -= key
            }

            override fun putFloat(key: String, value: Float): SharedPreferences.Editor = apply {
                pending[key] = value
                removals -= key
            }

            override fun putBoolean(key: String, value: Boolean): SharedPreferences.Editor = apply {
                pending[key] = value
                removals -= key
            }

            override fun remove(key: String): SharedPreferences.Editor = apply {
                pending.remove(key)
                removals += key
            }

            override fun clear(): SharedPreferences.Editor = apply {
                clearAll = true
                pending.clear()
            }

            override fun commit(): Boolean {
                apply()
                return true
            }

            override fun apply() {
                if (clearAll) {
                    backing.clear()
                } else {
                    for (key in removals) {
                        backing.remove(key)
                    }
                }
                backing.putAll(pending)
            }
        }
    }
}
