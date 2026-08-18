# Guía de densidad y ubicación de anclas

Esta guía ayuda a preparar un despliegue; no promete cobertura, alcance ni
entrega. Los rangos y cantidades iniciales deben validarse en el sitio con el
hardware, firmware, antenas, potencia y obstáculos reales. No existe una cifra
universal de metros, metros cuadrados o nodos por persona aplicable a BLE o
LoRa.

## Límite confirmado del ancla Bitle

El perfil fijado en `firmware/anchor-node` configura seis conexiones NimBLE
totales (`CONFIG_BT_NIMBLE_MAX_CONNECTIONS=6`). El firmware abre como máximo
dos enlaces centrales salientes entre nodos y reserva al menos dos plazas para
teléfonos entrantes. Es un presupuesto simultáneo del firmware actual, no seis
usuarios garantizados: reconexiones, enlaces entre anclas, teléfonos y calidad
del controlador compiten por esas plazas.

## Metodología de site survey

1. Dibuje zonas operativas y rutas de personas, no círculos teóricos. Marque
   muros, losas, ascensores, racks, vehículos, agua, vegetación, desniveles y
   fuentes de interferencia de 2,4 GHz.
2. Defina los flujos críticos: víctima→rescatista, rescatista→puesto de mando,
   dos islas BLE por troncal y retorno. Asigne alias no personales a equipos.
3. Haga un control negativo con el relay apagado para demostrar qué extremos no
   tienen enlace directo.
4. Instale una primera pareja de anclas a altura segura, con antena despejada y
   lejos de metal. Mida en ambos sentidos con teléfonos representativos,
   pantalla encendida/bloqueada y carga normal/congestionada.
5. Registre descubrimiento, reconexión, entrega única, TTL, duplicados,
   conflictos de confianza, límites open-SOS, damping, batería y temperatura.
   No registre MAC, peer IDs, claves, contenido real ni coordenadas publicables.
6. Mueva o agregue anclas hasta que cada ruta crítica conserve una alternativa
   independiente. Repita controles negativos después de cada cambio.
7. Congele ubicación, orientación, antena, versión y energía solo después de
   una corrida aceptada con evidencia saneada y hashes.

## Perfiles de partida

### Hogar

Empiece con una ancla en una zona central y elevada. Pruebe detrás de cocina,
baño, muros estructurales y entre pisos. Agregue otra ancla si una salida, un
dormitorio o una ruta de evacuación depende de un único enlace inestable. No
extrapole el resultado de una vivienda a otra.

### Edificio

Trate cada planta, escalera, núcleo de ascensores y sótano como dominios
distintos. Coloque candidatos cerca de rutas de evacuación, evitando encerrar
la antena en gabinetes metálicos. Use redundancia vertical por escaleras
separadas cuando sea posible y valide con ocupación y Wi‑Fi reales.

### Campamento o puesto temporal

Organice anclas por zonas funcionales —triaje, refugio, logística y mando— y
pruebe después de mover carpas, vehículos o depósitos de agua. Eleve antenas
sin crear riesgos mecánicos o eléctricos. Mantenga una unidad y una fuente de
energía de reemplazo listas.

### Islas BLE con LoRa

Use LoRa solo para unir islas BLE que ya funcionan localmente:

`teléfonos ↔ BLE ↔ LR-A ↔ LoRa ↔ LR-B ↔ BLE ↔ teléfonos`

Cada isla necesita controles negativos que descarten un cruce BLE directo. El
troncal requiere dos radios, antenas conectadas, configuración idéntica y
autorizada, y evidencia TX/RX con longitud y SHA-256 del frame opaco. Un mensaje
`trunk up`, una compilación o el nombre del nodo no prueban entrega extremo a
extremo.

## Factores de instalación

- **Altura y orientación:** pruebe varias alturas seguras; más alto no siempre
  es mejor dentro de estructuras con losas o ductos.
- **Metal, agua y terreno:** racks, vehículos, concreto armado, multitudes,
  depósitos y vegetación húmeda pueden bloquear o reflejar señal.
- **Interferencia:** mida en horas representativas con Wi‑Fi, microondas,
  generadores, radios y equipos del operativo encendidos.
- **Redundancia:** una ruta crítica no debe depender de una sola ancla, fuente,
  antena, escalera o troncal.
- **Energía:** mida consumo del conjunto real. Dimensione batería o LiFePO4,
  regulador y panel solar con margen por clima, temperatura, envejecimiento y
  días sin sol; una estimación de placa no sustituye una prueba de autonomía.
- **Seguridad:** use caja, ventilación, alivio de tensión, fusible y montaje
  apropiados. No coloque baterías o paneles donde obstruyan evacuación.
- **Regulación:** antes de transmitir LoRa confirme frecuencia, potencia,
  antena, ciclo de trabajo y homologación aplicables al país y al lugar. Si no
  hay confirmación, el gate es `BLOCKED_REGULATORY`.

## Criterios de aceptación por zona

| Criterio | Evidencia mínima | Aceptación |
| --- | --- | --- |
| Topología | Control negativo antes y después | Sin entrega directa cuando el relay/troncal está apagado |
| Descubrimiento | Cinco intentos por combinación y estado de pantalla | Cumple el umbral definido por el equipo antes del survey |
| Entrega crítica | Marcador sintético, firma válida, ACK y conteo | Una entrega válida; sin duplicados ni afirmación de rescate humano |
| Redundancia | Fallo deliberado de una ancla o fuente | La ruta alternativa definida sigue operativa |
| Capacidad | Ocupación esperada y presión de conexiones | No supera seis enlaces totales ni dos salientes por ancla Bitle |
| Recuperación | Reinicio y pérdida temporal de radio | Recupera sin intervención no prevista ni tormenta de conexiones |
| Energía | Duración, batería inicial/final y temperatura | Cumple la autonomía local con margen documentado |
| Privacidad | Revisión de logs, exports y manifiesto | Sin PII, IDs de radio, claves, coordenadas ni contenido real |
| LoRa | Permiso, control BLE negativo, TX/RX y hash | Frame íntegro en ambos sentidos con configuración autorizada |

Los umbrales de tiempo, autonomía y tasa de éxito se fijan antes de ejecutar el
survey según la misión. Si se cambian después de ver el resultado, debe quedar
registrada la justificación y repetirse la corrida.

## Recalibración

Revise la densidad al cambiar firmware, antena, caja, altura, potencia, perfil
de energía, distribución física, estación o carga de usuarios. Recalibre
también cuando aumenten reconexiones, límites open-SOS, supresiones por damping,
expulsiones/conflictos de confianza, pérdida de ACK, consumo o temperatura.

Una métrica estable no demuestra cobertura total. Combine contadores agregados
con recorridos físicos, controles negativos y evidencia de cada ruta crítica.
Mantenga el resultado `PENDING` o `BLOCKED` cuando falte hardware, regulación o
evidencia.
