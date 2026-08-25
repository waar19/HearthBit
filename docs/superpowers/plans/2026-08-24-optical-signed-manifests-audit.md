# Audit de tests de manifiestos firmados ópticos (Hueco 2)

Cierra la primera tarea del plan
[`2026-08-24-optical-signed-manifests-plan.md`](2026-08-24-optical-signed-manifests-plan.md)
contra el spec
[`2026-08-24-optical-signed-manifests-design.md`](../specs/2026-08-24-optical-signed-manifests-design.md).

Estado: PASS — los 7 escenarios del spec Hueco 2 quedan cubiertos. Los huecos
detectados al inventariar los tests existentes se rellenaron con TDD sin tocar
la lógica de producción.

## Escenarios cubiertos

| # | Escenario del spec | Test (path:línea) | Resultado |
|---|---|---|---|
| 1 | Header v2 con firma inválida (peer conocido) → `classifyOpticalTrust` devuelve `null` (caller descarta y muestra `opticalSignatureInvalid`). | `app/test/optical_trust_test.dart:43-51` | PASS |
| 1b | Variante: verificador lanza excepción → también se trata como firma inválida. | `app/test/optical_trust_test.dart:54-64` | PASS |
| 2 | Header v2 firmado por peer conocido con firma válida → `OpticalTrust.verified`, sin confirmación del usuario. | `app/test/optical_trust_test.dart:30-40` | PASS |
| 3 | Header v2 firmado por peer desconocido → `OpticalTrust.unverified` con `requiresUserConfirmation: true` (la UI muestra fingerprint). | `app/test/optical_trust_test.dart:67-79` | PASS |
| 4 | Header v1 (legacy) → `OpticalTrust.legacy` con `requiresUserConfirmation: true` aunque el peer sea "conocido" (legacy nunca autentica). | `app/test/optical_trust_test.dart:82-103` | PASS |
| 5 | Header v2 con firma truncada o ausente → el decoder rechaza el símbolo. | `app/test/optical_protocol_test.dart:95-113` | PASS |
| 6 | Modificar un byte del `signingPayload` (v2) cambia la preimagen, por lo que la verificación Ed25519 falla aunque la firma siga presente; el caller recibe `null` por `classifyOpticalTrust`. Se usa un par de claves Ed25519 real (de `package:cryptography`) para que la prueba sea criptográficamente significativa. | `app/test/optical_trust_test.dart:106-167` | PASS |
| 7 | Header v2 con `senderPeerId` vacío → `encodeHeader` lanza `ArgumentError` (incoherente) y el decoder no produce header. | `app/test/optical_protocol_test.dart:115-122` | PASS |

## Gaps rellenados durante el audit

Antes de este audit, los tests existentes (`optical_protocol_test.dart`)
solo cubrían los escenarios 5 y 7. Se creó
`app/test/optical_trust_test.dart` con 6 tests nuevos:

- 2 (verified) y 1/1b (inválida/exception) cubren el camino positivo y
  negativo del verificador Ed25519.
- 3 (peer desconocido) garantiza que el callback `verifySignature` no se
  invoca fuera del camino de peer conocido.
- 4 (legacy) blinda el invariante "v1 nunca autentica".
- 6 (tampering) usa `Ed25519().sign`/`verify` reales para confirmar que la
  mutación de cualquier byte dentro del `signingPayload` rompe la firma.

Durante el rellenado se corrigió un lint preexistente en
`optical_protocol_test.dart:77` (`_validSignedHeader` →
`validSignedHeader`) para que `flutter analyze` quede en cero issues.

## Conclusión

PASS — los 7 escenarios del Hueco 2 del spec están cubiertos. `flutter
analyze` y `flutter test` (sobre los archivos `optical_protocol_test.dart` y
`optical_trust_test.dart`) están en verde. La lógica de producción se
mantuvo congelada: los tests cierran contrato sobre `classifyOpticalTrust`
y `OpticalProtocol.signingPayload` ya implementados en
`def28e5`/`cd261f9`.

Próxima tarea del plan: Task 2 (i18n EN/ES + CHANGELOG + spec link).
