# Optical signed manifests — Implementation Plan (Phase 2.2 cierre)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cerrar el item "manifiestos firmados ópticos" del CHANGELOG
"Sin publicar" escribiendo spec, audit de tests, i18n EN/ES, y
CHANGELOG. La implementación de HBQ v1/v2 con Ed25519 ya está
aterrizada en `feature/anchor-p0`; este plan es de cierre.

**Architecture:** Plan documental + audit + TDD gap fill. Cero
cambios en lógica de protocolo. El spec
(`docs/superpowers/specs/2026-08-24-optical-signed-manifests-design.md`)
es la fuente de verdad del diseño.

**Tech Stack:** Dart/Flutter (tests), PowerShell (verificaciones), i18n
tooling (`flutter gen-l10n`).

## Global Constraints

- Rama activa: `feature/anchor-p0`. No se cambia de rama.
- `git push` SOLO lo ejecuta el usuario. Los subagentes commitean pero
  no pushean.
- Política del repo: código fuente de claves NUNCA entra al repo ni
  a assets, logs o artefactos.
- Conventional Commits: `test:`, `docs:`, `chore:`, `feat:` (solo si
  hay código nuevo).
- NO modificar `app/lib/services/optical_protocol.dart` excepto para
  añadir un comentario breve apuntando al spec. La lógica está
  congelada.
- `flutter analyze` y `flutter test` deben terminar verdes al cerrar
  la fase.

## Archivos a tocar (resumen)

- Modificar:
  - `app/lib/services/optical_protocol.dart` (1 comentario breve, Hueco 1)
  - `CHANGELOG.md` (entrada en "Sin publicar", Hueco 4)
  - `app/lib/l10n/app_es.arb` (traducciones faltantes, Hueco 3)
  - Tests existentes si hay gaps (TDD, Hueco 2)
- Crear:
  - `docs/superpowers/plans/2026-08-24-optical-signed-manifests-audit.md`
  - `docs/superpowers/plans/2026-08-24-optical-signed-manifests-security-review.md`

## SDD Setup

- Workspace: `C:\src\emergency-com\.superpowers\sdd\2026-08-24-optical-signed-manifests\`
- BASE al arrancar: `def28e5` (HEAD del spec).
- Ledger en `<workspace>/progress.md`.
- Ejecución: subagent per task + review per task + final whole-branch review.

---

## Task 1: Audit de tests de seguridad (Hueco 2)

**Files:**
- Create: `docs/superpowers/plans/2026-08-24-optical-signed-manifests-audit.md`
- Modify (TDD gap fill): `app/test/optical_protocol_test.dart` o nuevo archivo si los gaps lo ameritan

**Interfaces:**
- Tabla en el audit MD con los 7 escenarios del spec Hueco 2:
  1. Header v2 con firma inválida → `_OpticalTrust.unverified`.
  2. Header v2 firmado por peer conocido → `_OpticalTrust.verified`.
  3. Header v2 firmado por peer desconocido → `_OpticalTrust.unverified` + fingerprint.
  4. Header v1 (legacy) → `_OpticalTrust.legacy` + warning.
  5. Header con firma truncada/ausente en v2 → rechazo.
  6. Header con `signingPayload` modificado post-firma → verificación falla.
  7. Header con senderPeerId vacío en v2 → rechazo.

- [ ] **Step 1: Inventariar tests existentes**

```powershell
Get-Content app/test/optical_protocol_test.dart | Measure-Object -Line
Select-String -Path app/test -Pattern "isSigned|verifyPeerSignature|OpticalTrust|unverified|legacy" -Recurse
```

- [ ] **Step 2: Mapear cada escenario a un test existente o gap**

Para cada uno de los 7 escenarios:
- ¿Existe test? → path:línea.
- ¿No existe? → gap a rellenar.

- [ ] **Step 3: TDD gap fill (si hay)**

Para cada gap:
- Escribir test que falla.
- Si el código de producción necesita un fix pequeño, aplicarlo (debe ser mínimo; la lógica está congelada).
- Confirmar que el test pasa.

- [ ] **Step 4: Escribir audit MD**

`docs/superpowers/plans/2026-08-24-optical-signed-manifests-audit.md` con:

```markdown
# Audit de tests de manifiestos firmados ópticos (Hueco 2)

## Escenarios cubiertos
| # | Escenario | Test (path:línea) | Resultado |
|---|---|---|---|
| 1 | Header v2 firma inválida | ... | PASS / GAP |
| ... | ... | ... | ... |

## Conclusión
[PASS si los 7 están cubiertos, FAIL con lista de gaps si faltan]
```

- [ ] **Step 5: Correr tests**

```bash
cd app
flutter test test/optical_protocol_test.dart
```

Resultado: verde. Si no, status `BLOCKED`.

- [ ] **Step 6: Commit**

```bash
git add app/test docs/superpowers/plans/2026-08-24-optical-signed-manifests-audit.md
git commit -m "test: optical signed manifests coverage audit (Hueco 2)"
```

Si no hubo tests nuevos, el commit es solo del audit MD.

---

## Task 2: i18n EN/ES + CHANGELOG + spec link (Huecos 3+4+1 close)

**Files:**
- Modify: `app/lib/l10n/app_es.arb` (si faltan traducciones)
- Modify: `CHANGELOG.md` (entrada en "Sin publicar")
- Modify: `app/lib/services/optical_protocol.dart` (1 comentario breve al inicio)
- Run: `flutter gen-l10n` (si hubo cambios en ARB)

**Interfaces:**
- 7 claves EN: `opticalUnverifiedTitle`, `opticalUnverifiedBody`, `opticalLegacyWarning`, `opticalFingerprint`, `opticalAcceptUnverified`, `opticalSignatureInvalid`, `opticalVerifiedSource`.
- ES: deben existir con traducciones razonables (no literales).
- DE/FR/ZH/JA: fallback a EN (política Phase 1, no se revierte).

- [ ] **Step 1: Verificar i18n ES**

```powershell
Select-String -Path app/lib/l10n/app_es.arb -Pattern "opticalUnverifiedTitle|opticalUnverifiedBody|opticalLegacyWarning|opticalFingerprint|opticalAcceptUnverified|opticalSignatureInvalid|opticalVerifiedSource"
```

Resultado esperado: 7 matches.

- [ ] **Step 2: Si falta alguna en ES, traducir**

Política del proyecto: español neutro (es-CO). Las traducciones deben ser
claras y consistentes con el resto del ARB en ES.

- [ ] **Step 3: Regenerar localizaciones (si hubo cambios)**

```bash
cd app
flutter gen-l10n
```

Verificar que `app/lib/l10n/generated/app_localizations_es.dart` (y los
otros 5) reflejan los cambios.

- [ ] **Step 4: Actualizar CHANGELOG.md**

En la sección "Sin publicar", añadir bullets:

```markdown
### Seguridad
- Manifiestos ópticos firmados Ed25519 (HBQ v2). Advertencia
  explícita al recibir un header de origen no verificado, mostrando
  fingerprint para confirmación manual del usuario. Soporte de
  formato legacy (HBQ v1) con warning visible; los headers legacy
  nunca autentican.
```

- [ ] **Step 5: Añadir comentario en optical_protocol.dart**

En la cabecera del archivo (después del bloque de imports, antes de
la declaración de la clase):

```dart
// Spec: docs/superpowers/specs/2026-08-24-optical-signed-manifests-design.md
// v1 (legacy) y v2 (firmado Ed25519). Decoder rechaza v2 sin firma
// de 64 bytes; warning explícito para legacy.
```

- [ ] **Step 6: Correr `flutter analyze`**

```bash
cd app
flutter analyze
```

Resultado: 0 issues. Si no, status `BLOCKED`.

- [ ] **Step 7: Commit**

```bash
git add app/lib/l10n/app_es.arb
git add app/lib/l10n/generated
git add CHANGELOG.md
git add app/lib/services/optical_protocol.dart
git commit -m "docs(i18n): optical manifest strings in ES; CHANGELOG; spec link"
```

(Conventional Commit usa `docs:` porque el grueso es documental; el comentario en `optical_protocol.dart` califica.)

---

## Task 3: Security re-audit + CI verification

**Files:**
- Create: `docs/superpowers/plans\2026-08-24-optical-signed-manifests-security-review.md`

- [ ] **Step 1: Re-correr security checks**

```powershell
git ls-files | Select-String -Pattern "private_key|BEGIN PRIVATE" -CaseSensitive:$false
git log --all -p -S "BEGIN PRIVATE KEY" --diff-filter=A --name-only
```

- [ ] **Step 2: Verificar logs nativos**

```powershell
Select-String -Path app/lib app/android/app/src/main -Pattern "Log\.[dvwie]\(.*(peerId|peerAddress|macAddress)" -Recurse
```

- [ ] **Step 3: Correr CI gates localmente**

```bash
cd app
flutter analyze
flutter test
```

```bash
cd app/android
./gradlew :app:testDebugUnitTest
```

xcodebuild skip (Windows). Documentar.

- [ ] **Step 4: Escribir security review MD**

`docs/superpowers/plans/2026-08-24-optical-signed-manifests-security-review.md` con:
- Comandos ejecutados + output.
- Verdict: PASS / FAIL.

- [ ] **Step 5: Commit (si hubo fixes de seguridad)**

Solo si se parchó algo. Si no, status `DONE` sin commit.

---

## Task 4: Final whole-branch review + handoff

**Files:** ninguno (es review + handoff).

- [ ] **Step 1: Generar review package**

```bash
bash scripts/sdd-workspace docs/superpowers/plans/2026-08-24-optical-signed-manifests-plan.md
bash scripts/review-package docs/superpowers/plans/2026-08-24-optical-signed-manifests-plan.md <BASE> <HEAD>
```

Donde BASE = `def28e5` (HEAD del spec) y HEAD = último commit de la fase.

- [ ] **Step 2: Dispatch final code-reviewer**

Subagent `worker` con el path del diff, el brief, y los 4 huecos como
checklist.

- [ ] **Step 3: Si hay findings, dispatch ONE fix subagent + scoped re-review**

Per SDD: "ONE fix dispatch, one scoped re-review, adjudicate residuals".

- [ ] **Step 4: Hand off al usuario**

Mensaje al usuario con:
- Resumen de los commits de la fase.
- Comando `git push` listo (no ejecutado).
- Recordatorio: validación macOS pendiente (no se pudo correr en Windows).

- [ ] **Step 5: Cleanup workspace**

Documentar al usuario (safety policy Windows bloquea `Remove-Item`).

---

## Criterios de salida de la fase 2.2

- [ ] Spec en `docs/superpowers/specs/2026-08-24-optical-signed-manifests-design.md` commiteado.
- [ ] Audit MD creado con 7 escenarios cubiertos o gaps rellenados.
- [ ] i18n EN/ES verificadas.
- [ ] CHANGELOG "Sin publicar" actualizado.
- [ ] Comentario en `optical_protocol.dart` apuntando al spec.
- [ ] Security re-audit verde.
- [ ] `flutter analyze` 0 issues, `flutter test` verde, gradle test verde.
- [ ] Final whole-branch review sin findings bloqueantes.
- [ ] Push, merge y tag ejecutados por el usuario (gated).

Cuando estos 9 ítems estén en verde, fase 2.2 cerrada. Sigue 2.3
(gateway LAN Pi) y 2.4 (Matrix/MQTT TLS).
