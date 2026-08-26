# Security re-audit — Manifiestos ópticos firmados (Fase 2.2, Task 3)

> Fecha: 2026-08-26
> Rama: `feature/anchor-p0`
> Insumos:
> - Spec: [`docs/superpowers/specs/2026-08-24-optical-signed-manifests-design.md`](../specs/2026-08-24-optical-signed-manifests-design.md)
> - Plan: [`docs/superpowers/plans/2026-08-24-optical-signed-manifests-plan.md`](2026-08-24-optical-signed-manifests-plan.md)
> - Audit de tests: [`2026-08-24-optical-signed-manifests-audit.md`](2026-08-24-optical-signed-manifests-audit.md)

## Veredicto: PASS

La lógica de producción de `optical_protocol.dart` está congelada desde
`cd261f9`/`def28e5`. Este re-audit confirma que ni la fase ni el cierre
documental introdujeron material sensible, claves, ni logs con
identificadores completos.

## Chequeos ejecutados

### 1. Claves privadas en archivos trackeados

```powershell
git ls-files | Select-String -Pattern "private_key|BEGIN PRIVATE" -CaseSensitive:$false
```

**Salida:** 0 coincidencias.

**Veredicto:** PASS. Ningún archivo trackeado contiene material de
clave privada.

### 2. Claves privadas en historial (introducciones)

```powershell
git log --all -S "BEGIN PRIVATE KEY" --diff-filter=A --name-only --format="COMMIT:%H"
```

**Salida:** 4 archivos en 3 commits, todos documentos del plan `.md`:

| Commit | Archivo |
|---|---|
| `cd261f9` | `docs/superpowers/plans/2026-08-24-optical-signed-manifests-plan.md` |
| `ce43008` | `docs/superpowers/plans/2026-08-24-panic-wipe-security-review.md` |
| `1ad1e05` | `docs/superpowers/plans/2026-08-24-anchor-p0-closure.md` |
| `1ad1e05` | `docs/superpowers/plans/2026-08-24-panic-wipe-sqlite-cipher-plan.md` |

La cadena `"BEGIN PRIVATE KEY"` aparece como texto descriptivo dentro de
los propios comandos de chequeo documentados en los planes (este archivo
incluido). No es material criptográfico real.

**Veredicto:** PASS. Sin claves privadas reales en el historial.

### 3. Logs nativos con identificadores estables

```powershell
Select-String -Path app/lib app/android/app/src/main -Pattern "Log\.[dvwie]\(.*(peerId|peerAddress|macAddress)" -Recurse
```

**Salida:** 1 coincidencia, ya sanitizada:

| Archivo:línea | Contenido |
|---|---|
| `app/android/app/src/main/kotlin/com/hearthbit/app/mesh/MeshEngine.kt:2415` | `MeshLog.i(MeshEngineConstants.LOG_TAG, "REQUEST_SYNC sent to ${peerIdHex.take(8)}")` |

El único log que menciona un identificador emite `peerIdHex.take(8)`: un
prefijo truncado de 8 caracteres, no el `peerId` completo. Esto es
consistente con la política del CHANGELOG "identificadores desactivados
en builds de producción" y con el spec de privacidad. No hay logs de
`peerAddress` ni `macAddress` completos.

**Veredicto:** PASS. Sin exposición de identificadores estables completos
en logs nativos.

### 4. Gates locales

| Gate | Comando | Resultado |
|---|---|---|
| Flutter analyze | `flutter analyze` | PASS — "No issues found! (ran in 135.9s)" |
| Flutter test | `flutter test` | PASS — 422 tests, "All tests passed!" |
| Gradle unit test | `.\gradlew.bat :app:testDebugUnitTest` | SKIPPED — `JAVA_HOME` no configurado y no hay instalación de Java/Android SDK en esta máquina. El audit previo ([`2026-08-24-anchor-p0-closure-audit.md`](2026-08-24-anchor-p0-closure-audit.md)) registró `:app:testDebugUnitTest` (Anchor): 7/7 PASS en el entorno que sí tenía Java. |
| xcodebuild | — | SKIPPED — Windows, sin macOS. |

## Notas

- El cierre de la Fase 2.2 es documental + audit + TDD gap fill. Cero
  cambios en la lógica de protocolo desde `cd261f9`/`def28e5`.
- El único cambio de código de la fase de cierre es el comentario de 3
  líneas añadido a `app/lib/services/optical_protocol.dart` apuntando al
  spec (Task 2). No introduce superficie de ataque.
- Los tests de seguridad de la Fase 2.2 (7 escenarios del Hueco 2) están
  cubiertos y en verde según el audit de tests
  ([`2026-08-24-optical-signed-manifests-audit.md`](2026-08-24-optical-signed-manifests-audit.md)).

## Conclusión

PASS. La Fase 2.2 no introduce claves, no expone identificadores estables
en logs y mantiene los gates locales en verde (con gradle test skippeado
por entorno, ya validado en el audit previo). Lista para la review final
de la rama (Task 4).
