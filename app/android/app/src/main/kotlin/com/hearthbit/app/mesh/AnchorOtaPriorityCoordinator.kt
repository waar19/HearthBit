package com.hearthbit.app.mesh

import android.bluetooth.BluetoothGatt

/**
 * Política aislada de prioridad BLE para la OTA del Anchor.
 *
 * La decisión de qué prioridad solicitar vive aquí para que se pueda
 * verificar sin instanciar `BluetoothGatt` (ver `AnchorOtaPriorityCoordinatorTest`).
 * `MeshEngine` construye el `applyPriority` con un lambda que mira
 * `clientGatts[sourceAddress]` y delega a `gatt.requestConnectionPriority`;
 * el coordinador se limita a mapear la intención a la constante.
 *
 * Contrato:
 * - `requestHigh()` se llama antes de enviar un `OTA_MANIFEST` (inicio o
 *   reenvío). Sugiere `CONNECTION_PRIORITY_HIGH` al controlador.
 * - `restoreBalanced()` se llama en cada ruta terminal (status=0, completion,
 *   fail) y restaura `CONNECTION_PRIORITY_BALANCED`. Es idempotente.
 * - Una respuesta `false` (o excepción) del `applyPriority` NO aborta la OTA:
 *   la sugerencia de prioridad es una optimización, no un requisito.
 */
internal class AnchorOtaPriorityCoordinator(
    private val requestConnectionPriority: (Int) -> Boolean,
) {
    fun requestHigh(): Boolean =
        requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH)

    fun restoreBalanced(): Boolean =
        requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_BALANCED)
}
