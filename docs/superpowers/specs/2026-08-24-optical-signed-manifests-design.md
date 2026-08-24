# Manifiestos firmados ópticos (Phase 2.2 — cierre)

Fecha: 2026-08-24
Estado: aprobado por el usuario (alcance Phase 2.2 confirmado)

## Contexto

HearthBit transfiere archivos por QR (cadena de símbolos HBQ) entre
dispositivos sin red. La cadena CHANGELOG "Sin publicar" lista:

- "Manifiestos firmados para transferencia óptica"
- "advertencia de origen no verificado"
- "lectura explícita del formato anterior"

Una auditoría rápida muestra que los tres elementos ya están
implementados en el código de producción. La rama `feature/anchor-p0`
(que viene de Phase 1) más el trabajo previo ya aterrizaron la
funcionalidad, pero **no existe spec formal** que documente el diseño
ni audit reciente que verifique la cobertura de tests contra los
criterios de aceptación.

Este spec cierra el gap documental + de cobertura. Implementación
mínima o nula en código; foco en spec, audit, tests adicionales y
CHANGELOG.

Trabajo previo relevante (no se modifica):

- `app/lib/services/optical_protocol.dart` — protocolo HBQ v1/v2
  (líneas 14-30 constantes; 71-72 `signingPayload`; 250-317 decoder
  valida estructura y firma).
- `app/lib/services/optical_protocol.dart:387` `OpticalHeader.isSigned`
  getter.
- `app/lib/services/optical_protocol.dart:319-339` `_isCoherentHeader`
  valida fileSize, chunkSize, chunkCount, sha256, fileName, senderPeerId.
- `app/lib/screens/optical_receive_screen.dart:153-188` —
  `_OpticalTrust` enum (verified / unverified / legacy) y la lógica
  que dispara `_confirmUnverified` cuando no se puede validar origen.
- `app/lib/screens/optical_receive_screen.dart:208` `_confirmUnverified`
  muestra fingerprint al usuario.
- `app/lib/screens/optical_receive_screen.dart:517` enum `_OpticalTrust`.
- `app/lib/services/sealed_transfer_package.dart` — formato HBTS
  paralelo (para paquetes sellados, no óptico).
- `app/lib/l10n/app_en.arb:674-681` — strings `opticalUnverifiedTitle`,
  `opticalUnverifiedBody`, `opticalLegacyWarning`, `opticalFingerprint`,
  `opticalAcceptUnverified`, `opticalSignatureInvalid`,
  `opticalVerifiedSource`.
- `app/test/optical_protocol_test.dart`,
  `app/test/sealed_transfer_package_test.dart`.

## Objetivo

Cerrar el item del CHANGELOG "Sin publicar" para que release:

1. Haya un spec formal del diseño de manifiestos firmados ópticos.
2. La cobertura de tests demuestre que el rechazo de firma inválida,
   el manejo de legacy, y la advertencia de origen no verificado
   funcionan end-to-end.
3. El CHANGELOG tenga una entrada "Sin publicar" actualizada con
   la lista de lo que entra en release.
4. i18n strings estén cubiertas en EN/ES (per política del proyecto:
   DE/FR/ZH/JA heredan fallback).

## Fuera de alcance

- Cambios al protocolo HBQ v1/v2 (frozen por compatibilidad).
- Cambios al formato HBTS (paquetes sellados, no óptico).
- Re-firma retroactiva de manifiestos antiguos.
- Cambios al modelo de trust store (los anchors firmados por
  Ed25519 ya están en `MeshIdentity` y `KeystoreSecureStore`).
- Localización a DE/FR/ZH/JA más allá del fallback inglés (decidido
  en Phase 1, no se revierte).

## Diseño

### Hueco 1 — Spec formal (no existe)

El diseño está implementado pero solo documentado en código
(comentarios en `optical_protocol.dart` líneas 6-12, 70-72, 296-303).
Necesita un spec al lado del código que:

- Defina el protocolo HBQ v2 con su formato binario (magic, version,
  type, transferId, seed, fileSize, chunkSize, chunkCount, sha256,
  fileName, senderPeerId, signature).
- Explique el orden de campos y el `signingPayload` canónico.
- Defina la regla de rechazo: si v2 sin firma de 64 bytes, o firma
  que no verifica contra `senderPeerId` conocido, el header se
  descarta.
- Defina el fallback: HBQ v1 (sin firma) sigue siendo decodificable
  pero con `_OpticalTrust.legacy` y warning explícito.
- Documente el fingerprint (SHA-256 de `senderPeerId` o
  `signingPayload`) que el usuario ve antes de aceptar un header
  no verificado.

**Decisión:** este spec mismo cumple Hueco 1. Una vez aprobado, se
mantiene en `docs/superpowers/specs/` y se referencia desde
`optical_protocol.dart` con un comentario corto
`// Spec: docs/superpowers/specs/2026-08-24-optical-signed-manifests-design.md`.

### Hueco 2 — Audit de tests de seguridad

Verificar que los siguientes escenarios tienen test explícito:

1. Header v2 con firma inválida → `_OpticalTrust.unverified`,
   warning, sin aceptación silenciosa.
2. Header v2 firmado por peer conocido → `_OpticalTrust.verified`.
3. Header v2 firmado por peer desconocido → `_OpticalTrust.unverified`
   + fingerprint mostrado.
4. Header v1 (legacy) → `_OpticalTrust.legacy` + warning legacy.
5. Header con firma truncada o ausente en v2 → decodificación falla
   (rechazo, no warning).
6. Header con `signingPayload` modificado post-firma → verificación
   falla.
7. Header con senderPeerId vacío en v2 → rechazo (no se puede
   verificar origen sin identidad).

**Acción:** grep + lectura de `optical_protocol_test.dart` y
`optical_receive_screen_test.dart` (si existe). Cubrir cualquier
hueco con TDD.

### Hueco 3 — i18n coverage EN/ES

Política Phase 1 confirmada: EN/ES completas, DE/FR/ZH/JA heredan.
Verificar que las 7 claves `optical*` están en `app_es.arb`. Si
alguna falta en ES, traducir.

### Hueco 4 — CHANGELOG

Actualizar `CHANGELOG.md` sección "Sin publicar" para que mencione
explícitamente:

- Manifiestos firmados HBQ v2 con Ed25519.
- Advertencia de origen no verificado con fingerprint.
- Soporte explícito del formato legacy HBQ v1 con warning.

Mover esta entrada a la versión que se publique (o documentar que
pertenece a la próxima release).

## Criterios de éxito

1. Spec existe en `docs/superpowers/specs/2026-08-24-optical-signed-manifests-design.md`
   y está commiteado.
2. `optical_protocol.dart` incluye un comentario breve que apunta al spec.
3. Audit de tests documentado en
   `docs/superpowers/plans/2026-08-24-optical-signed-manifests-audit.md`
   con tabla de escenario → test (o gap fill).
4. Si hay gaps de tests, están cubiertos con TDD y la suite sigue
   verde (`flutter test test/optical_protocol_test.dart`).
5. i18n EN/ES verificadas para las 7 claves `optical*`; cualquier
   gap en ES traducido.
6. CHANGELOG "Sin publicar" actualizado.
7. `flutter analyze` 0 issues; `flutter test` verde.

## Tests nuevos (resumen)

Probablemente pocos o ninguno. Si los tests existentes ya cubren los
7 escenarios de Hueco 2, status `DONE` sin tests nuevos. Si hay
gaps, se añaden TDD-driven.

## Riesgos y puntos abiertos

- **i18n DE/FR/ZH/JA:** los 7 strings están solo en EN/ES. Los
  4 idiomas secundarios muestran el fallback inglés. Es la política
  confirmada en Phase 1, no se revierte aquí. Si en una release futura
  se distribuye en mercados no hispanohablantes, documentar gap.
- **Tests del flujo completo de receive:** el código de
  `_OpticalTrust` está en `optical_receive_screen.dart`. Si
  `_confirmUnverified` se testea solo, se cubre el prompt; el flujo
  completo (scan → trust determination → confirm → accept) puede no
  tener test de integración. Auditar.
- **Spec retrocompatible con v1:** confirmar en el spec que v1
  sigue siendo decodificable (no se rompe compatibilidad) y que el
  warning se muestra incluso si el peer es conocido (v1 nunca
  autentica).
- **HBTS no se ve afectado:** el spec es solo para HBQ. HBTS
  (paquetes sellados) sigue su propio path de verificación.

## Próximo paso

Tras aprobación:

1. Crear `docs/superpowers/plans/2026-08-24-optical-signed-manifests-plan.md`
   con tasks bite-sized, subagent per task.
2. Ejecutar con subagent per task.
3. Cierre con final whole-branch review y merge (gated al usuario).
