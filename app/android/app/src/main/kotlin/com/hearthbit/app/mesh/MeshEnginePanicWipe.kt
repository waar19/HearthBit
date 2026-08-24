package com.hearthbit.app.mesh

import android.content.SharedPreferences

/**
 * Borra cada almacén persistente del mesh durante [MeshEngine.panicWipe].
 *
 * Hueco 4 de
 * `docs/superpowers/specs/2026-08-24-panic-wipe-sqlite-cipher-design.md`:
 * la auditoría exige que `MeshEngine.panicWipe()` limpie todos los
 * almacenes nativos. Esta función encapsula ese sub-wipe para poder
 * verificar la cobertura con doubles locales en `PanicWipeTest`, sin
 * necesidad de instanciar el `MeshEngine` completo (que requiere
 * `BluetoothManager`, `Keystore`, etc.).
 *
 * El orden es deliberado y debe coincidir con el código de producción:
 * 1. `storeForward` (caché store-and-forward de paquetes pendientes).
 * 2. `emergencyFingerprints` (fingerprint de emergencias ya vistas).
 * 3. `peerTrust` (pins TOFU de identidad de peers).
 * 4. `rescueMode` (estado del modo rescate).
 * 5. `relationshipPreferences` (SharedPreferences directa de relaciones).
 * 6. `relationshipSecureStore` (KeystoreSecureStore de relaciones).
 * 7. `identity` (claves Noise + Ed25519 persistidas).
 *
 * La función es idempotente: cada `clear()`/`disable()`/`commit()` debe
 * tolerar un estado ya vacío.
 */
internal object MeshEnginePanicWipe {
    fun wipePersistentState(
        relationshipPreferences: SharedPreferences,
        clearStoreAndForward: () -> Unit,
        clearEmergencyFingerprints: () -> Unit,
        clearPeerTrustStore: () -> Unit,
        clearRescueModeStore: () -> Unit,
        clearRelationshipSecureStore: () -> Unit,
        clearIdentity: () -> Unit,
    ) {
        clearStoreAndForward()
        clearEmergencyFingerprints()
        clearPeerTrustStore()
        clearRescueModeStore()
        check(relationshipPreferences.edit().clear().commit()) {
            "No se pudo borrar hearthbit_mesh_relationships"
        }
        clearRelationshipSecureStore()
        clearIdentity()
    }
}
