# Anchor P0 close-out — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cerrar la rama `feature/anchor-p0` de forma verificable: sincronizar los 3
specs con el código que ya está en `HEAD`, auditar tests/i18n/parity iOS, ejecutar
gates de CI, documentar el procedimiento de validación física para que el usuario
lo corra con su hardware, y mergear + taggear.

**Architecture:** Plan de cierre (no greenfield). Cada tarea es una verificación
sobre código ya existente o un fix pequeño derivado de la verificación. La
implementación original vive en commits previos
(`826a12e`, `0d35abd`, `2fc30f0`); esta fase la hace "lista para tag".

**Tech Stack:** Flutter/Dart (app), Kotlin (Android), Swift (iOS), C/ESP-IDF
(firmware), PowerShell (CI/scripts).

## Hallazgos de la auditoría previa (input del plan)

- Firmware ya en `BITLE_FW_VERSION 10` (spec original apuntaba a v6→v7).
- Kotlin `parseStatus` ya implementa la regla 0/8 bytes y modela `freeHeap`/`minFreeHeap`.
- iOS Swift `parseStatus` y máquina OTA ya implementadas.
- Dart `AnchorActivityHistory`, `AnchorSparkline` y `AnchorAdminScreen._activityCard`
  ya presentes.
- i18n EN/ES completas para `anchorAdmin*` y `anchorOta*`.
- Android `CONNECTION_PRIORITY_HIGH` ya cableado en `MeshEngine.kt`.
- Tests existentes: `app/test/anchor_admin_models_test.dart`,
  `app/test/anchor_ota_manifest_test.dart`,
  `app/android/.../AnchorAdminProtocolTest.kt`,
  `app/android/.../AnchorOtaProtocolTest.kt`.

**Lo que falta (este plan lo cubre):** sync specs↔HEAD, audit tests +
rellenar huecos, audit i18n, audit parity iOS, gates CI/lint, procedimiento
de validación hardware (gate del usuario), security review, merge + tag.

## Archivos a tocar (resumen)

- Modificar (sync/audit):
  - `docs/superpowers/specs/2026-08-20-anchor-live-charts-design.md`
  - `docs/superpowers/specs/2026-08-22-anchor-ota-design.md`
  - `docs/superpowers/specs/2026-08-23-anchor-ota-speed-design.md`
  - `app/lib/l10n/app_*.arb` (audit + posibles claves nuevas para DE/FR/ZH/JA)
  - `app/lib/screens/anchor_admin_screen.dart` (audit UX iOS background)
- Crear (procedimiento):
  - `docs/superpowers/plans/2026-08-24-anchor-p0-hardware-validation.md`
- No crear archivos de código nuevos a menos que la auditoría revele un hueco real.

---

## Task 1: Sincronizar spec live-charts con HEAD

**Files:**
- Modify: `docs/superpowers/specs/2026-08-20-anchor-live-charts-design.md`

- [ ] **Step 1: Confirmar que la sección "Cambio de firmware (v6 → v7)" del spec coincide con HEAD**

Ejecutar inspección:

```powershell
git show feature/anchor-p0:firmware/anchor-node/main/bitle_admin.c | Select-String -Pattern "free_heap|min_free_heap|esp_get_free_heap|esp_get_minimum" -Context 2
git show feature/anchor-p0:firmware/anchor-node/main/bitle_ota.h | Select-String -Pattern "BITLE_FW_VERSION"
git show feature/anchor-p0:app/android/app/src/main/kotlin/com/hearthbit/app/mesh/AnchorAdminProtocol.kt | Select-String -Pattern "parseStatus|freeHeap|when \(buffer\.remaining\(\)\)" -Context 3
git show feature/anchor-p0:app/ios/Runner/IOSMeshProtocol.swift | Select-String -Pattern "parseStatus|freeHeap|minFreeHeap" -Context 3
git show feature/anchor-p0:app/lib/screens/anchor_admin_screen.dart | Select-String -Pattern "_activityCard|_chartTile|anchor_sparkline" -Context 2
```

Resultado esperado (todos verdaderos):
- `build_status` añade `free_heap` y `min_free_heap` tras el nickname.
- `BITLE_FW_VERSION 10` (no 6/7; el spec se redactó cuando apuntaba a v6→v7).
- Kotlin `parseStatus` con `when (buffer.remaining())` ramificando 0/8/default-null.
- Swift `parseStatus` con `freeHeap` y `minFreeHeap`.
- Flutter `_activityCard` con 4 `_chartTile` y `anchor_sparkline`.

Si cualquier item falla, **STOP** y reportar — significa que la implementación
no está donde el plan asume y el resto del cierre no es seguro.

- [ ] **Step 2: Añadir sección "Implementation delta" al spec**

Insertar al final de `2026-08-20-anchor-live-charts-design.md` (antes de
"Criterios de éxito"):

```markdown
## Implementation delta (cierre 2026-08-24)

- Firmware saltó de v6 a v10 antes de cerrar este spec. Los dos campos
  `u32` (`free_heap`, `min_free_heap`) se añadieron al payload como
  describe la sección "Cambio de firmware", sin reintroducir
  `BITLE_ADMIN_PROTOCOL_VERSION`.
- `AnchorAdminProtocol.parseStatus` (Kotlin y Swift) implementa la
  regla "0 u 8 bytes sobrantes; otro → null" y modela los dos
  campos como opcionales.
- Flutter: `AnchorActivityHistory` mantiene el buffer circular de 60
  muestras; `AnchorSparkline` se dibuja con `CustomPainter`
  (sin `fl_chart`).
- i18n: EN y ES completas; DE/FR/ZH/JA heredan el fallback inglés
  (decidido en el spec, no se amplía en esta entrega).
- Pendiente (gates fuera de código): validación física con ESP32-S3
  N16R8 + Bitle-5528 (ver `2026-08-24-anchor-p0-hardware-validation.md`).
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-08-20-anchor-live-charts-design.md
git commit -m "docs(spec): sync anchor-live-charts with HEAD (firmware v10, parseStatus 0/8, i18n EN/ES)"
```

---

## Task 2: Sincronizar spec OTA con HEAD

**Files:**
- Modify: `docs/superpowers/specs/2026-08-22-anchor-ota-design.md`

- [ ] **Step 1: Confirmar componentes OTA en HEAD**

```powershell
git show feature/anchor-p0:firmware/anchor-node/main/bitle_ota.c | Select-String -Pattern "OTA_MANIFEST|OTA_REQ|OTA_CHUNK|OTA_STATUS" -Context 2
git show feature/anchor-p0:app/android/app/src/main/kotlin/com/hearthbit/app/mesh/MeshEngine.kt | Select-String -Pattern "startAnchorOta|preparing|transferring|rebooting|completed|failed" -Context 3
git show feature/anchor-p0:app/ios/Runner/HearthBitMeshPlugin.swift | Select-String -Pattern "AnchorOtaStage|anchorOtaTransfer|OTA_MANIFEST|OTA_REQ|OTA_CHUNK|OTA_STATUS" -Context 3
git show feature/anchor-p0:app/lib/models/anchor_ota_manifest.dart | Select-String -Pattern "class|Manifest|version|signature" -Context 1
git show feature/anchor-p0:app/lib/models/anchor_admin_models.dart | Select-String -Pattern "AnchorOtaBundle|manifest|image|version" -Context 1
```

Resultado esperado:
- Firmware: handlers `OTA_MANIFEST` (0xA0), `OTA_REQ` (0xA1), `OTA_CHUNK` (0xA2), `OTA_STATUS` (0xA3).
- Android: `startAnchorOta` + máquina de eventos con `preparing/transferring/rebooting/completed/failed`.
- iOS: `AnchorOtaStage` enum + `AnchorOtaTransfer` class con los 5 estados.
- Dart: `AnchorOtaManifest` con `version/signature/chunk/sha256`; `AnchorOtaBundle` con `manifest + image`.

Si falla, **STOP**.

- [ ] **Step 2: Añadir "Implementation delta" al spec OTA**

Insertar al final de `2026-08-22-anchor-ota-design.md`:

```markdown
## Implementation delta (cierre 2026-08-24)

- El flujo end-to-end está implementado: Flutter (`AnchorAdminScreen`),
  Android (`MeshEngine.kt`), iOS (`HearthBitMeshPlugin.swift`),
  firmware (`bitle_ota.c`).
- `AnchorOtaManifest` y `AnchorOtaBundle` validan magic, longitud,
  tamaño y chunk; rechazan binarios ausentes o inconsistentes.
- `BITLE_FW_VERSION` actual: **10**. La primera versión firmada por
  el owner fue v8; v9 validó el flujo BLE; v10 es la versión actual
  publicada.
- Pendiente: ceremonia de claves del owner (`tools/gen_owner_key.py`).
  El usuario la ejecuta localmente; la clave privada nunca entra al
  repo ni a CI.
- Pendiente (hardware): ver `2026-08-24-anchor-p0-hardware-validation.md`.
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-08-22-anchor-ota-design.md
git commit -m "docs(spec): sync anchor-ota with HEAD (v8/v9/v10, native state machines, Dart bundle)"
```

---

## Task 3: Sincronizar spec OTA-speed con HEAD

**Files:**
- Modify: `docs/superpowers/specs/2026-08-23-anchor-ota-speed-design.md`

- [ ] **Step 1: Confirmar `CONNECTION_PRIORITY_HIGH` y restauración en HEAD**

```powershell
git show feature/anchor-p0:app/android/app/src/main/kotlin/com/hearthbit/app/mesh/MeshEngine.kt | Select-String -Pattern "CONNECTION_PRIORITY_HIGH|CONNECTION_PRIORITY_BALANCED|requestConnectionPriority" -Context 3
git show feature/anchor-p0:tools/sign_fw.py | Select-String -Pattern "472|chunk|chunk_size|--chunk-size" -Context 2
```

Resultado esperado:
- `MeshEngine.kt` solicita `CONNECTION_PRIORITY_HIGH` antes de
  `OTA_MANIFEST` y restaura `CONNECTION_PRIORITY_BALANCED` en todas
  las rutas terminales (éxito, error, timeout, kill por usuario).
- `tools/sign_fw.py` tiene `--chunk-size` y default 472.

Si falla, **STOP**.

- [ ] **Step 2: Añadir "Implementation delta" al spec OTA-speed**

Insertar al final de `2026-08-23-anchor-ota-speed-design.md`:

```markdown
## Implementation delta (cierre 2026-08-24)

- Android `CONNECTION_PRIORITY_HIGH` se solicita y restaura de forma
  idempotente en todas las rutas terminales dentro de `MeshEngine.kt`.
- `tools/sign_fw.py` usa 472 bytes como chunk default; `--chunk-size`
  sigue disponible para diagnóstico.
- iOS sin cambios (CoreBluetooth no expone equivalente).
- Pendiente (hardware): medición física de v9→v10 en ESP32-S3 N16R8
  con la app Android; ver `2026-08-24-anchor-p0-hardware-validation.md`.
- Pendiente (operación): borrado + flash + reclamo manual del
  `Bitle-5528` con clave no registrada en código.
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-08-23-anchor-ota-speed-design.md
git commit -m "docs(spec): sync anchor-ota-speed with HEAD (priority, 472-byte chunk default)"
```

---

## Task 4: Auditar suite de tests Dart y Android

**Files:**
- Read: `app/test/anchor_admin_models_test.dart`
- Read: `app/test/anchor_ota_manifest_test.dart`
- Read: `app/android/app/src/test/kotlin/com/hearthbit/app/mesh/AnchorAdminProtocolTest.kt`
- Read: `app/android/app/src/test/kotlin/com/hearthbit/app/mesh/AnchorOtaProtocolTest.kt`
- Modify (gap fill): nuevos tests si los existentes no cubren los criterios del spec.

- [ ] **Step 1: Listar criterios de aceptación cubiertos por tests existentes**

Para cada spec, abrir su sección "Criterios de éxito" y mapear a un test
existente o a un test faltante. Crear una tabla en
`docs/superpowers/plans/2026-08-24-anchor-p0-closure-audit.md` con columnas:
`Criterio`, `Spec`, `Test existente`, `Acción`.

- [ ] **Step 2: Rellenar huecos con TDD**

Por cada criterio sin test:
- Escribir el test que falla.
- Implementar el mínimo para que pase (o documentar por qué no se puede
  automatizar — p. ej. "requiere placa ESP32").
- Confirmar que el test pasa.

Si un test requiere un fixture nuevo, crearlo en `app/test/fixtures/`
o `app/android/app/src/test/resources/` según el caso.

- [ ] **Step 3: Correr la suite completa**

```powershell
cd app
flutter test test/anchor_admin_models_test.dart test/anchor_ota_manifest_test.dart
```

```powershell
cd app/android
./gradlew :app:testDebugUnitTest --tests "com.hearthbit.app.mesh.AnchorAdminProtocolTest" --tests "com.hearthbit.app.mesh.AnchorOtaProtocolTest"
```

Resultado esperado: verde. Si rojo, **STOP** y arreglar antes de continuar.

- [ ] **Step 4: Commit (solo si hubo tests nuevos)**

```bash
git add app/test app/android/app/src/test
git commit -m "test: fill gaps to cover live-charts and OTA acceptance criteria"
```

---

## Task 5: Auditar i18n

**Files:**
- Read: `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_es.arb`,
  `app/lib/l10n/app_de.arb`, `app/lib/l10n/app_fr.arb`,
  `app/lib/l10n/app_zh.arb`, `app/lib/l10n/app_ja.arb`
- Modify (gap fill): `app/lib/l10n/app_de.arb`, `app/lib/l10n/app_fr.arb`,
  `app/lib/l10n/app_zh.arb`, `app/lib/l10n/app_ja.arb` (si el spec los
  requiere, ver decisión del spec live-charts).

- [ ] **Step 1: Listar claves nuevas introducidas por live-charts y OTA**

Extraer todas las claves que empiezan con `anchorAdmin*` y `anchorOta*`
de `app_en.arb` y `app_es.arb`.

- [ ] **Step 2: Comparar con DE/FR/ZH/JA**

Para cada uno de los 4 idiomas restantes, verificar si la clave existe
o se hereda por fallback. El spec live-charts dice explícitamente
"el resto de idiomas hereda el fallback inglés como en el resto del
panel". Confirmar que el comportamiento real coincide.

- [ ] **Step 3: Decidir acción**

Tres opciones:
- **Confirmar:** fallback inglés está activo y es lo aceptado. Sin cambios.
- **Extender:** traducir a DE/FR/ZH/JA las claves críticas (las que el
  usuario ve siempre: `anchorAdminActivity`, `anchorOtaTitle`,
  `anchorOtaKeepOpen`). No traducir las opcionales o de error verbose.
- **Documentar:** crear issue `i18n-gap-anchor` para trabajo futuro.

Registrar la decisión en el audit MD y aplicar el cambio mínimo.

- [ ] **Step 4: Si hubo cambios, regenerar localizaciones**

```powershell
cd app
flutter gen-l10n
```

Verificar que el archivo generado `app/lib/l10n/app_localizations.dart`
incluye las claves nuevas.

- [ ] **Step 5: Commit (solo si hubo cambios)**

```bash
git add app/lib/l10n
git commit -m "i18n: <extend|document> anchor live-charts and OTA strings (DE/FR/ZH/JA)"
```

---

## Task 6: Auditar parity iOS

**Files:**
- Read: `app/ios/Runner/HearthBitMeshPlugin.swift`
- Read: `app/ios/Runner/IOSMeshProtocol.swift`
- Modify (gap fill): `app/lib/screens/anchor_admin_screen.dart` si el
  warning de background iOS no se muestra condicionalmente.

- [ ] **Step 1: Verificar que los 5 eventos OTA de Android existen en iOS**

Comparar `MeshAnchorOtaEvent` (Dart) con la API que expone
`HearthBitMeshPlugin.swift` al MethodChannel. Eventos esperados:
`preparing`, `transferring` (con progress), `rebooting`, `completed`
(con targetVersion), `failed` (con error code estable).

Si falta alguno, **STOP** y abrir sub-tarea para implementar.

- [ ] **Step 2: Verificar warning iOS background**

El spec OTA dice: "iOS informa que debe permanecer abierta por las
restricciones de ejecución BLE." Confirmar que la pantalla
`AnchorAdminScreen` muestra un aviso contextual cuando
`defaultTargetPlatform == TargetPlatform.iOS` y el estado OTA está
activo.

Si no, añadir un `Banner` o `ListTile` dentro de `_otaCard` que
renderice `context.l10n.anchorOtaKeepOpen` solo en iOS.

- [ ] **Step 3: Correr `flutter analyze`**

```powershell
cd app
flutter analyze
```

Resultado esperado: 0 issues, 0 warnings nuevos. Si hay warnings
existentes, anotar pero no bloquear.

- [ ] **Step 4: Si hubo cambios, commit**

```bash
git add app/lib/screens/anchor_admin_screen.dart app/ios/Runner
git commit -m "fix(ios): parity for OTA events and background warning on anchor admin"
```

---

## Task 7: Gates CI/lint

**Files:**
- Modify (gap fill): workflows si faltan steps para los nuevos componentes.

- [ ] **Step 1: Verificar que `flutter analyze` corre en CI**

Abrir `.github/workflows/*.yml` y confirmar que el job de Flutter
ejecuta `flutter analyze` + `flutter test` (incluyendo los tests
nuevos del Task 4). Si no, añadirlo.

- [ ] **Step 2: Verificar que `gradle test` corre en CI**

Confirmar que el job Android ejecuta `./gradlew test` o
`./gradlew :app:testDebugUnitTest`. Si no, añadirlo.

- [ ] **Step 3: Verificar que el firmware tiene test/host-runner**

Buscar `firmware/anchor-node/test/` o equivalente. Confirmar que
`bitle_admin_self_test` se ejecuta (al menos en host o como
component-test). Si no existe runner, crear uno mínimo o documentar
por qué no.

- [ ] **Step 4: Si hubo cambios, commit**

```bash
git add .github/workflows firmware/anchor-node/test
git commit -m "ci: cover anchor live-charts, OTA, and admin protocol tests"
```

---

## Task 8: Security review (pre-merge)

**Files:**
- Read (audit): `firmware/anchor-node/main/bitle_ota.c`,
  `app/lib/models/anchor_ota_manifest.dart`,
  `app/android/.../MeshEngine.kt`, `app/ios/Runner/HearthBitMeshPlugin.swift`,
  `tools/sign_fw.py`, `tools/gen_owner_key.py`, `app/assets/firmware/`
- Modify (gap fill): `.gitignore`, scripts de firma, o logs nativos.

- [ ] **Step 1: Verificar que la clave privada NO está en el repo**

```powershell
git ls-files | Select-String -Pattern "bitle_owner_key|ota_owner_priv|private_key" -CaseSensitive:$false
git log --all -p -S "BEGIN PRIVATE KEY" --diff-filter=A --name-only
Get-ChildItem -Path app\assets\firmware -ErrorAction SilentlyContinue | Select-Object Name
```

Resultado esperado: ningún archivo commiteado con clave privada. Si
aparece algo, **STOP** y reportar — es un incidente de seguridad,
no un cleanup.

- [ ] **Step 2: Verificar que logs nativos no filtran IDs en producción**

```powershell
Select-String -Path app/android/app/src/main/kotlin -Pattern "Log\.[dvwie]\(" -Recurse | Select-String -Pattern "peerId|peerAddress|macAddress|identifierForVendor" -CaseSensitive:$false
```

Para cada hit en código de producción (no test), confirmar que está
detrás de un flag de build (p. ej. `BuildConfig.DEBUG`) o reemplazado
por un identificador opaco. El CHANGELOG "Sin publicar" menciona
"Logs nativos con identificadores desactivados en builds de
producción" — esto es la auditoría.

- [ ] **Step 3: Verificar que `tools/sign_fw.py` valida tamaño y SHA-256**

```powershell
Get-Content tools/sign_fw.py | Select-String -Pattern "sha256|size|hash|verify" -Context 3
```

Confirmar que el script rechaza binarios con tamaño o hash
inconsistente con el manifiesto (esto ya lo hace, per spec).

- [ ] **Step 4: Documentar findings**

Añadir al audit MD:

```markdown
## Security review (2026-08-24)

- Private key: no presente en repo ni en git history (verificado con
  `git ls-files` y `git log -S`).
- Native logs: <resumen de findings>.
- `tools/sign_fw.py`: valida tamaño y SHA-256 contra manifiesto.
- Conclusión: <PASS | FAIL con items>.
```

- [ ] **Step 5: Si hubo cambios, commit**

```bash
git add app/ firmware/ tools/ scripts/ .gitignore
git commit -m "chore(security): <resumen de fixes, si los hubo>"
```

---

## Task 9: Documentar procedimiento de validación hardware

**Files:**
- Create: `docs/superpowers/plans/2026-08-24-anchor-p0-hardware-validation.md`

- [ ] **Step 1: Crear el archivo con el procedimiento**

Plantilla:

```markdown
# Procedimiento de validación física — Anchor P0 close-out

**Propósito:** gate manual que el usuario (Wilmer) ejecuta con su
hardware antes de mergear `feature/anchor-p0` a `master`.

**Hardware requerido:**
- 1× ESP32-S3 N16R8 (Anchor de pruebas, p. ej. `Bitle-5528`).
- 1× teléfono Android físico con HearthBit compilado desde
  `feature/anchor-p0`.
- 1× PC con `idf.py` (ESP-IDF) y ADB.
- 1× cable USB-C para flasheo directo cuando aplique.

## Pre-flight

1. Confirmar que la rama local es `feature/anchor-p0` y el working
   tree está limpio.
2. Build del firmware:
   ```powershell
   cd firmware/anchor-node
   idf.py build
   ```
3. Build de la app Android:
   ```powershell
   cd app
   flutter build apk --debug
   ```
4. Instalar el APK en el teléfono.

## Gate 1 — Live charts

1. Abrir el panel del Anchor (`AnchorAdminScreen`).
2. Verificar las 4 gráficas (Actividad, Buzón, Memoria, Seguridad)
   actualizándose cada ~4 s.
3. Apagar el Anchor. Verificar insignia "sin conexión" en menos de
   8 s.
4. Encender el Anchor. Verificar reanudación sin picos falsos.
5. Generar tráfico (otro nodo enviando mensajes) y observar que la
   serie "Actividad" y "Seguridad" reflejan los deltas.

**PASS si:** los 5 pasos se cumplen sin error.

## Gate 2 — OTA inalámbrica

1. Con el Anchor en v9 (o la versión base que se decida), abrir el
   panel admin.
2. Verificar que la tarjeta OTA muestra "v9 → v10 disponible".
3. Confirmar la instalación. Esperar el ciclo completo:
   `preparing → transferring → rebooting → completed`.
4. Verificar versión v10 tras la reconexión.

**PASS si:** la actualización termina con v10 visible en el panel
y `anchor_admin_models` no muestra picos espurios.

## Gate 3 — OTA rápida (472-byte chunk + priority)

1. Medir tiempo total del Gate 2.
2. Repetir la actualización v9→v10 y medir.
3. Comparar con el target del spec (~1 min para 740 KB).
4. Verificar con `adb logcat` que `CONNECTION_PRIORITY_HIGH` se
   solicitó y se restauró a `BALANCED` al terminar.

**PASS si:** tiempo total ≤ 1 min ± 10% y la prioridad se restauró.

## Gate 4 — Reclamo del Bitle-5528

1. Borrar flash por USB: `idf.py -p COMx erase-flash`.
2. Flash v9 por USB.
3. En la app, abrir el panel del Anchor, "Reclamar dispositivo",
   introducir la clave de admin (que el usuario elige, no se registra
   en código ni en docs).
4. Confirmar que el Anchor queda operativo y visible en la app.

**PASS si:** el Anchor arranca en v9, aparece en la app, y la OTA
inalámbrica funciona sobre él.

## Reporte

Al terminar, completar `templates/rescue-pilot-report.template.md`
(mismo template que usa `p0-execution-guide.md`) con los IDs de gate
de este archivo, y commitear en la rama. No elevar a `PASS` global:
el revisor independiente externo es el único que puede hacerlo.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/2026-08-24-anchor-p0-hardware-validation.md
git commit -m "docs(plan): hardware validation procedure for anchor P0 close-out"
```

---

## Task 10: Merge a master + tag (gate final del usuario)

**Files:**
- Modify: history de git.

- [ ] **Step 1: Confirmar working tree limpio**

```powershell
git status
```

Resultado esperado: `nothing to commit, working tree clean`. Si no,
**STOP** y resolver.

- [ ] **Step 2: Push de la rama (NO merge — el usuario decide)**

```bash
git push origin feature/anchor-p0
```

**STOP AQUÍ.** El usuario revisa la rama, ejecuta los 4 gates de
validación hardware, y solo entonces ejecuta el merge a `master` y
el tag. Esto es por política de repo: el usuario controla merges y
push a `master`.

Mensaje al usuario:
> "Rama `feature/anchor-p0` lista para validación. Push hecho. Los
> 4 gates de `2026-08-24-anchor-p0-hardware-validation.md` son tuyos.
> Cuando los pases, mergea a `master` y taggea (siguiente task)."

---

## Task 11: Tag de versión (post-merge, ejecutado por el usuario)

**Files:**
- Modify: tags de git.

- [ ] **Step 1: Decidir versión**

Consultar `CHANGELOG.md` sección "Sin publicar" y proponer versión
semver. Sugerencia: si la rama ya pasó gates físicos y no hay más
cambios antes de publicar, el tag es el primer release post-p0
(p. ej. `v1.1.0` si la última publicada fue `v1.0.0`; verificar
en git tags).

- [ ] **Step 2: Taggear y pushear**

```bash
git checkout master
git pull
git tag -a vX.Y.Z -m "Anchor P0 close-out: live charts, OTA, OTA-speed"
git push origin vX.Y.Z
```

Esto lo ejecuta el usuario, no el agente, por política.

---

## Criterios de salida de fase 1 (gate global)

- [ ] Los 3 specs tienen "Implementation delta" y commiteados (Tasks 1-3).
- [ ] Tests Dart y Android auditados, huecos rellenados, suite verde (Task 4).
- [ ] i18n auditado y decisión registrada (Task 5).
- [ ] Parity iOS verificada o arreglo commiteado (Task 6).
- [ ] CI cubre `flutter analyze`, `flutter test`, `gradle test`,
      firmware self-test (Task 7).
- [ ] Security review verde: sin claves privadas en repo, logs nativos
      sin IDs en producción, sign script validando (Task 8).
- [ ] Procedimiento de validación hardware commiteado (Task 9).
- [ ] Rama `feature/anchor-p0` pusheada (Task 10).
- [ ] Usuario ejecutó los 4 gates de hardware y la suite de tests
      automáticamente validados en CI pasa.
- [ ] Merge a `master` y tag de versión ejecutados por el usuario
      (Task 11).

Cuando los 9 ítems de arriba estén en verde, fase 1 cerrada. Sigue
fase 2 (spec nuevo del CHANGELOG "Sin publicar") con su propio
spec + plan.
