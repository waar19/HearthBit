# Audit de cobertura de tests — Anchor P0

> Fecha: 2026-08-24
> Rama: `feature/anchor-p0` (HEAD `00a3449`)
> Insumos:
> - `app/test/anchor_admin_models_test.dart` (Dart, 3 tests)
> - `app/test/anchor_ota_manifest_test.dart` (Dart, 3 tests)
> - `app/android/app/src/test/kotlin/com/hearthbit/app/mesh/AnchorAdminProtocolTest.kt` (Kotlin, 5 tests)
> - `app/android/app/src/test/kotlin/com/hearthbit/app/mesh/AnchorOtaProtocolTest.kt` (Kotlin, 2 tests)
> - Specs: `2026-08-20-anchor-live-charts-design.md` (4 ítems), `2026-08-22-anchor-ota-design.md` (5 ítems), `2026-08-23-anchor-ota-speed-design.md` (5 ítems).

## Resumen

| Spec | Cubiertos | Añadir | Hardware-only | N/A | Total |
|---|---|---|---|---|---|
| Live-charts (2026-08-20) | 3 | 0 | 1 | 0 | 4 |
| OTA (2026-08-22) | 1 | 0 | 3 | 1 | 5 |
| OTA-speed (2026-08-23) | 0 | 2 | 2 | 1 | 5 |
| **Total** | **4** | **2** | **6** | **2** | **14** |

> Nota: el brief menciona "5 ítems" para el spec de live-charts, pero el archivo `2026-08-20-anchor-live-charts-design.md` lista 4 en su sección "Criterios de éxito". Se respeta el contenido del spec (4).

## Spec 1 — Live-charts (2026-08-20)

| # | Criterio | Test existente (path:línea) | Acción |
|---|---|---|---|
| 1 | El panel muestra las cuatro gráficas actualizándose cada ~4 s con el Anchor real. | — | hardware-only |
| 2 | Con firmware v6 (sin actualizar) el panel sigue funcionando y omite la gráfica de memoria. | `AnchorAdminProtocolTest.kt:60-100` (v6 payload sin extensión de heap, `parseStatus` con `0` bytes sobrantes → `freeHeap == null`); `AnchorAdminProtocolTest.kt:102-130` (v7 con 8 bytes válidos y rechazo de 4 bytes); `anchor_admin_models_test.dart:4-37` (constructor con `freeHeap: null` cuando la placa no lo reporta). | cubierto |
| 3 | Un reinicio del Anchor durante el sondeo no produce picos falsos ni errores en pantalla. | `anchor_admin_models_test.dart:67-76` (satura deltas a 0 cuando los contadores se reinician). | cubierto |
| 4 | Los tests de Kotlin y Dart nuevos pasan; los existentes no se rompen. | `flutter test`: 6/6 PASS; `:app:testDebugUnitTest` (Anchor): 7/7 PASS. | cubierto |

## Spec 2 — OTA (2026-08-22)

| # | Criterio | Test existente (path:línea) | Acción |
|---|---|---|---|
| 1 | Una placa con v8 y la clave pública nueva acepta v9 desde HearthBit sin cable ni internet. | — | hardware-only |
| 2 | La app nunca transfiere una imagen igual, anterior, corrupta o incoherente con su manifiesto. | `AnchorOtaProtocolTest.kt:39-65` (stale: `version > currentVersion` falla; corrupto: SHA-256 mismatch; out-of-range: índice fuera del manifiesto). `anchor_ota_manifest_test.dart:37-57` (magic/longitud/version/chunk inválidos). `anchor_ota_manifest_test.dart:59-71` (bundle: binario con SHA que no coincide con el manifiesto → `FormatException`). | cubierto |
| 3 | El operador ve progreso y un resultado inequívoco. | — | hardware-only |
| 4 | Una interrupción o imagen fallida deja el Anchor arrancable en la versión anterior. | — | hardware-only (bootloader/rollback) |
| 5 | La clave privada no aparece en Git, assets, logs ni binarios de la aplicación. | — | N/A (chequeo operativo, no unit test) |

## Spec 3 — OTA-speed (2026-08-23)

| # | Criterio | Test existente (path:línea) | Acción |
|---|---|---|---|
| 1 | La OTA v9→v10 termina inalámbricamente y el panel confirma v10. | — | hardware-only |
| 2 | El manifiesto empaquetado declara bloques de 472 bytes. | — | añadir (ver § Gap fill 1) |
| 3 | Android solicita prioridad alta durante la transferencia y la restaura en todas las rutas terminales. | — | añadir (ver § Gap fill 2: extraer `AnchorOtaPriorityCoordinator`) |
| 4 | La optimización no convierte la prioridad alta en requisito de actualización. | — | añadir (cubierto por la rama "no-gatt" del test del coordinador) |
| 5 | Ninguna clave administrativa o privada de firma entra al repositorio o a los logs. | — | N/A (chequeo operativo, no unit test) |

## Gap fills aplicados

### 1. Chunk de 472 bytes en el manifiesto empaquetado

- **Archivo añadido**: `app/test/anchor_ota_manifest_test.dart` — caso `packaged firmware manifest declares 472-byte chunks`.
- **Cómo**: carga `app/assets/firmware/bitle.bin.bota` desde `rootBundle`, lo parsea con `AnchorOtaManifest.parse` y verifica que `chunkSize == 472` y que el tamaño declarado coincide con `bitle.bin` (sanidad).
- **Por qué**: el spec OTA-speed exige el default de 472; el test blinda ese contrato contra cambios accidentales del script `package_anchor_firmware.py` o de `sign_fw.py`.

### 2. `AnchorOtaPriorityCoordinator` (Kotlin)

- **Archivos añadidos**:
  - `app/android/app/src/main/kotlin/com/hearthbit/app/mesh/AnchorOtaPriorityCoordinator.kt` (clase pura, sin `BluetoothGatt`).
  - `app/android/app/src/test/kotlin/com/hearthbit/app/mesh/AnchorOtaPriorityCoordinatorTest.kt` (3 tests).
- **Archivos modificados**:
  - `app/android/app/src/main/kotlin/com/hearthbit/app/mesh/MeshEngine.kt` — 5 call sites de `requestAnchorOtaConnectionPriority(addr, priority)` reemplazados por `priorityCoordinatorFor(addr).requestHigh()` / `.restoreBalanced()`. El método privado `requestAnchorOtaConnectionPriority` se conserva como `private fun` thin wrapper para minimizar el diff, pero su lógica se delega al coordinador.
- **Cómo se prueba**:
  - `requestHigh antes de OTA_MANIFEST, restoreBalanced en cada ruta terminal` (secuencia de llamadas esperada).
  - `restoreBalanced es idempotente` (múltiples llamadas no fallan, no duplican logs ruidosos).
  - `la prioridad nunca aborta la OTA cuando el apply falla` (no-gatt, gatt.requestConnectionPriority lanza, etc.).
- **Por qué**: el spec OTA-speed pide "una unidad aislada de política/coordinación, sin depender de hardware Bluetooth". La lógica vivía acoplada a `BluetoothGatt` en `MeshEngine.requestAnchorOtaConnectionPriority` (privada, 17 líneas, no testeable). El coordinador separa la decisión de prioridad del I/O de Bluetooth.

## Tests que no se automatizan

- **Live-charts #1**, **OTA #1/#3/#4**, **OTA-speed #1**: solo se validan en la placa ESP32-S3 N16R8 con Bitle-5528. Ver `docs/superpowers/plans/2026-08-24-anchor-p0-hardware-validation.md` (a crear en Task 9).
- **OTA #5**, **OTA-speed #5**: son política operativa (no incluir claves en Git/assets/logs). Se cubren con `git grep` y revisión de CI, no con un test unitario.

## Concerns

1. **Refactor de MeshEngine**: la extracción del coordinador tocó 5 sitios en una clase de 4500+ líneas. Se hizo de forma quirúrgica (el `requestAnchorOtaConnectionPriority` original sigue existiendo como wrapper, pero ahora delega). El comportamiento externo (logs, retorno, idempotencia) es idéntico. La batería previa `AnchorOtaProtocolTest` no cubre la OTA end-to-end, así que la confianza descansa en `:app:testDebugUnitTest` (los 7 tests previos siguen pasando) y en el hecho de que la lógica del coordinador es trivialmente verificable.
2. **Test asset-locked**: el test de 472 bytes parsea `app/assets/firmware/bitle.bin.bota` directamente. Si en un release futuro el script cambia el chunk a otro valor legítimo, el test rompe. Aceptable: el spec fija 472 y un cambio debe ser una decisión explícita.
3. **Asimetría iOS**: el spec OTA-speed documenta que iOS no tiene equivalente de `requestConnectionPriority` (CoreBluetooth no expone la API). El gap fill solo cubre el lado Android. iOS no necesita cambios de test.
