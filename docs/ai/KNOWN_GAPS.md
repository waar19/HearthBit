# Límites y trabajo pendiente conocidos

Este documento evita que una persona o un agente diagnostique como regresión algo que ya es una limitación declarada. No convierte estos límites en aceptables para una nueva funcionalidad: una tarea puede proponer cambiarlos, pero debe decirlo de forma explícita.

| Área | Estado actual | Implicación para una tarea | Fuente |
| --- | --- | --- | --- |
| Validación de radio y rescate | Varias pruebas permanecen `PENDING` o `BLOCKED` hasta tener hardware, aislamiento o condiciones físicas. | No afirmar alcance, continuidad de segundo plano ni entrega de SOS desde una suite automatizada. | [`../field-test.md`](../field-test.md), [`../p0-execution-guide.md`](../p0-execution-guide.md) |
| iOS en segundo plano | Un force-quit explícito impide una restauración BLE fiable hasta que la persona reabre la app. | No diseñar una UI que prometa rescate continuo tras force-quit. | [`../field-test.md`](../field-test.md), [`../architecture.md`](../architecture.md) |
| Capacidades de transferencia en iOS | Nearby Connections y Wi-Fi Aware no están disponibles en iOS para HearthBit; la app usa LAN, BLE u óptico según el caso. | No exponer esas portadoras como disponibles en iPhone sin una implementación y validación nuevas. | [`../../README.md`](../../README.md) |
| Núcleo Rust | El crate cubre paquetes v1/v2, firma y rotación de clave; no tiene FFI ni está conectado al runtime móvil. Varias familias de codecs siguen fuera de su alcance. | No sustituir el codec móvil por Rust ni declarar interoperabilidad nueva basándose sólo en ese crate. | [`../../core/hearthbit-core/README.md`](../../core/hearthbit-core/README.md) |
| OTA de anclas | La OTA verifica manifiesto y anti-rollback, pero la rotación/revocación autenticada de la owner key sigue abierta. | No presentar la gestión de claves OTA como resuelta para producción a gran escala. | [`../threat-model.md`](../threat-model.md), [`../anchor-deployment-guide.md`](../anchor-deployment-guide.md) |
| Relay y hardware Linux | Las pruebas automatizadas cubren protocolo y políticas, no advertising, rol dual o coexistencia Wi-Fi/BLE por modelo de adaptador. | Planificar una prueba con el adaptador objetivo antes de desplegar. | [`../../relay/README.md`](../../relay/README.md) |
| Puentes externos | LAN, MQTT, Matrix y Reticulum son opt-in y tienen controles de autenticación, allowlists y privacidad. | No activarlos por defecto ni hacer que lleven tráfico privado. | [`../lan-mesh-gateway.md`](../lan-mesh-gateway.md), [`../../relay/README.md`](../../relay/README.md) |

## Cómo actualizar esta lista

Actualice una fila cuando la limitación cambie de estado y enlace la evidencia concreta: especificación, prueba automatizada o gate físico saneado. No borre una limitación sólo porque exista código; la evidencia debe cubrir la capacidad que se afirma.
