# Guía de ejecución de gates P0 prioritarios

Esta guía convierte en pasos ejecutables cinco gates ya definidos en
[prueba de campo](field-test.md). No crea IDs, estados ni criterios nuevos y no
registra una ejecución física.

## Estado y alcance de esta entrega

- Estado de esta entrega documental: **PENDING / BLOCKED**.
- El preflight es conceptual y estructural: prepara alias, versiones,
  topologías, manifiesto, reporte y rutas de evidencia. No enciende una radio,
  no demuestra transporte y nunca produce `PASS`.
- La ejecución física requiere el hardware indicado, aislamiento comprobable y
  evidencia saneada. Hasta que se realice, cada gate continúa `PENDING` o
  `BLOCKED`.
- El tooling actual puede elevar un paquete completo únicamente a
  `READY_FOR_REVIEW`. Una revisión independiente externa es la única que puede
  registrar `PASS`, `FAIL` o `BLOCKED` por gate. La excepción de plataforma
  `P0-IOS-FORCEQUIT-01` nunca puede terminar en `PASS`.
- Un build, test automatizado, emulador, preflight, hash o peer visible no
  sustituye la ejecución física.

## Preparación común

1. Cree una corrida nueva con
   [`New-RescuePilotRun.ps1`](../scripts/field-test/New-RescuePilotRun.ps1).
   Use `RUN-<UTC>-<CASE_ID>` para cada caso y conserve el estado generado
   `PENDING` o `BLOCKED`.
2. Complete el
   [manifiesto](templates/rescue-pilot-manifest.template.json) y el
   [reporte](templates/rescue-pilot-report.template.md) sin cambiar la
   semántica de sus estados. Los cinco IDs de esta guía ya están incluidos en
   `required_scenarios` del tooling actual.
3. Sincronice los relojes y registre inicio/fin UTC. Use únicamente los alias
   obligatorios de `field-test.md`; no invente alias por corrida ni use nombres,
   teléfonos, seriales, MAC, peer IDs, nombres Bluetooth u otros IDs estables.
   En las topologías de esta guía, `Node A = HB-S25`, `Node B = HB-R1`,
   `Node C = HB-R2`, `Node D = HB-IP` y `ESP32 Anchor = LR-A`. Los alias
   `MT-A`, `MT-B` y `LR-B` quedan reservados para los casos que realmente usan
   esos equipos.
4. Registre por nodo plataforma, versión del sistema, versión de app o firmware,
   batería y estado de pantalla/app. Registre también el ID del gate, latencia,
   ACK, pérdida y recuperación tras reinicio, incluso cuando el valor sea
   `unavailable` o `not_applicable`.
5. Desactive Internet, Wi-Fi y datos celulares cuando la plataforma lo permita.
   Mantenga Bluetooth encendido. Active GPS únicamente para
   `P0-RESCUE-KILL-DOZE`.
6. Conserve únicamente el marcador sintético exigido por `field-test.md`, con
   formato `<CASE_ID>-<RUN>-<PASO>-<ORIGEN>-<DESTINO>`, para correlacionar
   evidencia. No conserve ningún otro contenido de mensajes ni contenido real,
   coordenadas, nombres, teléfonos o datos personales.
7. Registre `hop_count: unavailable` para las métricas de la app. Solo puede
   añadir una observación de saltos cuando la separación física, la topología
   controlada y su evidencia demuestren el recorrido. No infiera saltos a
   partir de TTL.
8. Registre latencia con timestamps UTC de los eventos observables; ACK como
   estado/conteo; pérdida como eventos esperados frente a observados; y
   recuperación tras reinicio como `observed`, `not_observed`,
   `not_applicable` o `unavailable`. No convierta una métrica ausente en cero.
9. Sanee cada archivo antes de calcular su SHA-256. Cada gate debe tener
   evidencia propia; no reutilice una ruta ni un mismo contenido/hash para
   escenarios o categorías diferentes.

Los scripts
[`Collect-AdbFieldLog.ps1`](../scripts/field-test/Collect-AdbFieldLog.ps1),
[`New-FieldTestReport.ps1`](../scripts/field-test/New-FieldTestReport.ps1) y
[`collect-ios-field-log.sh`](../scripts/field-test/collect-ios-field-log.sh)
validan únicamente IDs `D1-*`; no deben usarse cambiando el ID ni reescribirse
para aparentar cobertura P0. Además, el capturador iOS inicia o reinicia la app,
por lo que no sirve como evidencia del intervalo posterior al force-quit.

## Secuencia mínima de topologías del piloto

Estas topologías son una secuencia de preparación y ejecución de gates
existentes, no escenarios ni IDs adicionales.

### A. Android—iPhone—Android—ESP32 Anchor—Android

Use la cadena para comprobar transporte sin Internet, Wi-Fi ni datos celulares:

`HB-S25 (Android) — HB-IP (iPhone) — HB-R1 (Android) —`
`LR-A (ESP32 Anchor) — HB-R2 (Android)`

1. Registre versiones y los alias obligatorios indicados, desactive conectividad
   IP cuando sea posible y mantenga Bluetooth encendido.
2. En enlaces adyacentes compatibles ejecute `P0-SOS-ACK`: observe ACK real en
   clientes capaces y ausencia de capacidad ACK en BitChat, sin inventar una
   confirmación.
3. En un Android seleccionado ejecute `P0-RESCUE-KILL-DOZE` con GPS habilitado
   solo durante ese gate.
4. En el iPhone ejecute `P0-IOS-FORCEQUIT-01` contra un Android adyacente.
5. Use el tramo `HB-R1 — LR-A — HB-R2` para preparar la
   topología C y ejecutar `P0-STORE-REBOOT`.

No declare que toda la cadena de cinco nodos satisface
`P0-FOUR-NODE-TWO-HOP`; ese gate usa su topología B propia. Cada paso anterior
mantiene evidencia y resultado separados bajo su ID existente.

### B. Node A—B—C—D con al menos dos saltos

Ejecute `P0-FOUR-NODE-TWO-HOP` con:

`Node A (HB-S25) — Node B (HB-R1) — Node C (HB-R2) — Node D (HB-IP)`

Los extremos `HB-S25` y `HB-IP` no deben tener enlace directo. Compruebe el
control negativo con `HB-R1` y `HB-R2` apagados, luego la entrega en ambos
sentidos con la topología
restaurada. En las métricas de app registre `hop_count: unavailable`. Solo la
observación física/topología controlada puede documentar que hubo al menos dos
saltos; TTL no es una medida de hop count.

### C. HB-S25—LR-A—reboot—HB-IP

Ejecute `P0-STORE-REBOOT` con:

`HB-S25 — LR-A — reinicio de LR-A — HB-IP`

`HB-IP` permanece fuera de línea al emitir. Después del depósito, reinicie
`LR-A`, mantenga `HB-S25` y `HB-IP` sin enlace directo y vuelva a poner `HB-IP`
en línea. Observe recuperación y una única entrega posterior.

## `P0-SOS-ACK`

#### 1. Objetivo

Confirmar los estados ya definidos de SOS pendiente, emitido, ACK único, ACK
duplicado y receptor BitChat sin capacidad ACK, sin presentar ausencia de
capacidad como confirmación.

#### 2. Hardware

- Dos teléfonos físicos HearthBit para el recorrido con ACK.
- Un teléfono físico con BitChat oficial para el recorrido sin capacidad ACK.
- Reloj UTC o fuente de hora sincronizada.

#### 3. Software

- Builds/versiones de HearthBit registradas en ambos extremos.
- Versión de BitChat y plataforma registradas.
- Manifiesto y reporte del piloto actual.

#### 4. Topología

Primero `HB-S25 (HearthBit emisor) ↔ HB-IP (HearthBit receptor)`, directa.
Después `HB-S25 (HearthBit emisor) ↔ HB-R1 (BitChat receptor)`, directa. Use
solo esos alias obligatorios y no agregue relays durante este gate.

#### 5. Condiciones iniciales

- Internet, Wi-Fi y datos celulares apagados cuando sea posible; Bluetooth
  encendido; GPS apagado.
- Relojes sincronizados, apps abiertas y peers visibles.
- Un marcador sintético distinto para cada recorrido.
- Estado de SOS/outbox previo registrado, sin reutilizar un SOS anterior.

#### 6. Pasos numerados

1. Inicie la evidencia y anote UTC, alias, plataformas, versiones y gate ID.
2. Envíe el SOS al HearthBit capaz de ACK y registre la transición de pendiente
   a emitido.
3. Confirme en el receptor una sola recepción y en el emisor un único ACK.
4. Reproduzca o provoque el ACK duplicado previsto por el caso y compruebe que
   no crea una segunda confirmación ni una segunda entrega.
5. Repita con BitChat como receptor y registre explícitamente que no dispone de
   capacidad ACK.
6. Cierre la captura, sanee archivos, calcule hashes y complete el reporte sin
   elevar el estado del paquete a `PASS`.

#### 7. Resultado esperado

El emisor distingue pendiente, emitido y confirmado por ACK; el ACK repetido es
idempotente. BitChat puede recibir el SOS, pero la falta de capacidad ACK no se
convierte en una confirmación falsa.

#### 8. Métricas a registrar

- UTC de emisión, recepción y ACK; latencia emisión→recepción y emisión→ACK.
- Alias efímero, plataforma, app version y test ID.
- Conteo de recepciones, ACK observados y ACK duplicados.
- Pérdida esperada/observada.
- `reboot_recovery: not_applicable`.
- `hop_count: unavailable`.

#### 9. Criterio PASS

En revisión independiente: se observan todos los estados definidos; hay una
sola entrega y un ACK efectivo en el recorrido capaz; el ACK duplicado no cambia
el resultado; y el recorrido BitChat no inventa ACK. Deben existir evidencia
física saneada y hashes propios del gate.

#### 10. Criterio FAIL

Falta cualquiera de los estados requeridos, el SOS no llega, se duplica la
entrega o confirmación, el ACK duplicado produce un efecto adicional, o se
presenta como confirmado un receptor sin capacidad ACK.

#### 11. Evidencia requerida

- Inventario por alias con versiones y UTC.
- Reporte del operador con transiciones, latencias, conteos y primera condición
  incumplida.
- Capturas UI redactadas del estado pendiente, emitido y ACK.
- Logs/diagnóstico saneados de emisor y receptores.
- Evidencia separada del recorrido BitChat sin capacidad ACK.
- SHA-256 de cada archivo declarado en el manifiesto.

## `P0-STORE-REBOOT`

#### 1. Objetivo

Confirmar que, con el receptor fuera de línea y el relay/ancla intermedio
reiniciado, el mensaje almacenado se recupera y se entrega posteriormente
exactamente una vez.

#### 2. Hardware

- Dos nodos físicos compatibles como emisor y receptor.
- Un ESP32 Anchor físico con almacenamiento/relay aplicable al gate.
- Medio físico de separación o apantallamiento entre los nodos extremos.

#### 3. Software

- Versiones registradas de las apps de ambos nodos.
- Versión de firmware del Anchor registrada.
- Manifiesto y reporte del piloto actual.

#### 4. Topología

Topología C: `HB-S25 — LR-A — reinicio de LR-A — HB-IP`. `HB-S25` y `HB-IP`
no deben disponer de enlace directo durante la prueba.

#### 5. Condiciones iniciales

- Internet, Wi-Fi y datos celulares apagados cuando sea posible; Bluetooth
  encendido; GPS apagado.
- `HB-IP` fuera de línea.
- `LR-A` operativo y visible desde `HB-S25` antes del depósito.
- Topología, reloj, alias, versiones y marcador sintético documentados.

#### 6. Pasos numerados

1. Inicie evidencia por nodo y Anchor; registre UTC y el gate ID.
2. Con `HB-IP` fuera de línea, emita el marcador sintético desde `HB-S25` y
   confirme el almacenamiento esperado en `LR-A`. La evidencia puede conservar
   ese marcador exigido, pero ningún contenido real.
3. Reinicie `LR-A` y registre inicio, fin y recuperación del firmware.
4. Mantenga `HB-S25` y `HB-IP` sin enlace directo y vuelva a poner `HB-IP` en
   línea.
5. Observe la entrega posterior en `HB-IP` y cuente las copias.
6. Vuelva a observar/reconectar dentro de la misma ejecución para comprobar que
   no aparece otra copia.
7. Sanee, calcule SHA-256 y complete manifiesto/reporte.

#### 7. Resultado esperado

`LR-A` conserva el elemento durante el reinicio, recupera su operación y
`HB-IP` recibe posteriormente una sola copia válida.

#### 8. Métricas a registrar

- UTC de emisión, depósito, inicio/fin de reinicio, recuperación y entrega.
- Alias efímero, plataforma, versiones de app/firmware y test ID.
- Latencia emisión→depósito y recuperación→entrega.
- ACK observado o `unavailable`, según lo exponga el transporte.
- Conteos de depósitos, entregas, duplicados y pérdida.
- `reboot_recovery: observed` o `not_observed`.
- `hop_count: unavailable`; la topología física se documenta aparte.

#### 9. Criterio PASS

En revisión independiente: el receptor estaba fuera de línea, el Anchor fue
reiniciado, la recuperación quedó evidenciada y la entrega posterior ocurrió
exactamente una vez sin enlace directo entre extremos.

#### 10. Criterio FAIL

El elemento se pierde tras el reinicio, no se entrega al volver el receptor, se
entrega más de una vez, se entrega a otro nodo o la evidencia no permite
descartar entrega directa.

#### 11. Evidencia requerida

- Inventario y diagrama/fotos redactadas de topología por alias.
- Control de separación de `HB-S25` y `HB-IP`.
- Logs saneados de ambos nodos y consola saneada del Anchor alrededor del
  depósito, reinicio, recuperación y entrega.
- Reporte con timestamps, latencias, conteo de copias y primera condición
  incumplida.
- Captura UI redactada de la única recepción.
- SHA-256 de cada archivo propio del gate.

## `P0-FOUR-NODE-TWO-HOP`

#### 1. Objetivo

Confirmar con cuatro nodos que los extremos sin enlace directo se comunican con
al menos dos saltos, que los controles con relays apagados no entregan y que la
entrega funciona en ambos sentidos.

#### 2. Hardware

- Cuatro nodos físicos compatibles: `Node A (HB-S25)`, `Node B (HB-R1)`,
  `Node C (HB-R2)` y `Node D (HB-IP)`.
- Elementos de separación, distancia o apantallamiento para impedir el enlace
  directo `HB-S25`↔`HB-IP`.

#### 3. Software

- Versiones de app o firmware registradas para `HB-S25`, `HB-R1`, `HB-R2` y
  `HB-IP`.
- Manifiesto y reporte del piloto actual.

#### 4. Topología

Topología B: `Node A (HB-S25) — Node B (HB-R1) — Node C (HB-R2) — Node D
(HB-IP)`. `HB-S25` y `HB-IP` son extremos; `HB-R1` y `HB-R2` son relays. La
disposición física controlada debe demostrar al menos dos saltos sin usar TTL
como sustituto de esa observación.

#### 5. Condiciones iniciales

- Internet, Wi-Fi y datos celulares apagados cuando sea posible; Bluetooth
  encendido; GPS apagado.
- Relojes sincronizados y alias obligatorios registrados.
- `HB-S25` y `HB-IP` aislados entre sí.
- Marcadores sintéticos distintos para ida, vuelta y controles negativos.

#### 6. Pasos numerados

1. Inicie evidencia en los nodos observados y registre topología, UTC y gate ID.
2. Apague `HB-R1` y `HB-R2`. Desde `HB-S25` emita el control negativo hacia
   `HB-IP` y confirme que no se entrega.
3. Encienda `HB-R1` y `HB-R2` sin mover nodos, espere su estado operativo y
   envíe de `HB-S25` a `HB-IP`.
4. Confirme una sola recepción válida en `HB-IP`.
5. Envíe un marcador distinto de `HB-IP` a `HB-S25` y confirme una sola
   recepción válida.
6. Apague de nuevo los relays sin mover nodos y repita el control negativo.
7. Sanee, calcule hashes y registre resultados sin inferir hop count desde TTL.

#### 7. Resultado esperado

No hay entrega en los controles con relays apagados. Con `HB-R1` y `HB-R2`
operativos, los marcadores se entregan una sola vez en ambos sentidos entre
`HB-S25` y `HB-IP`.

#### 8. Métricas a registrar

- UTC y latencia de ida/vuelta; mediana o peor valor solo si se realizan
  repeticiones ya requeridas por la matriz.
- Alias efímero, plataforma, versiones y test ID.
- ACK por dirección o `unavailable`.
- Entregas esperadas/observadas, duplicados y pérdida.
- `reboot_recovery: not_applicable`.
- Métrica de app `hop_count: unavailable`.
- Observación física de al menos dos saltos únicamente con evidencia de la
  topología controlada.

#### 9. Criterio PASS

En revisión independiente: ambos controles negativos no entregan, `HB-S25` y
`HB-IP` no poseen enlace directo y la entrega válida ocurre exactamente una vez
en ambos sentidos con `HB-R1` y `HB-R2` operativos.

#### 10. Criterio FAIL

Hay entrega con relays apagados, falta una dirección, aparece un duplicado, los
extremos conservan enlace directo o se afirma el número de saltos a partir de
TTL o de una métrica no observable.

#### 11. Evidencia requerida

- Inventario, posiciones/distancias aproximadas y topología por alias, sin
  coordenadas.
- Evidencia redactada de relays apagados/encendidos y aislamiento A↔D.
- Logs saneados por nodo observado y capturas UI redactadas de ida/vuelta.
- Reporte con timestamps, latencia, ACK, pérdida y conteo de copias.
- Registro explícito `hop_count: unavailable` en métricas de app.
- SHA-256 de cada archivo propio del gate.

## `P0-RESCUE-KILL-DOZE`

#### 1. Objetivo

Cerrar el proceso Android, bloquear la pantalla y entrar en Doze para verificar
los pings nativos esperados/ejecutados y que el GPS usado por rescate permanece
fresco durante su TTL.

#### 2. Hardware

- Un Android físico como víctima en modo rescate.
- Un nodo físico compatible como rescatista/observador.
- Equipo Windows con ADB autorizado para observar proceso y Doze sin registrar
  el serial.

#### 3. Software

- Build HearthBit y versión Android registrados en la víctima.
- Versión de app/plataforma registrada en el observador.
- Herramientas ADB y manifiesto/reporte del piloto actual.

#### 4. Topología

`HB-S25 (Android víctima) ↔ HB-IP (rescatista)`, enlace directo y estable. No
agregue relays durante este gate.

#### 5. Condiciones iniciales

- Internet, Wi-Fi y datos celulares apagados cuando sea posible; Bluetooth
  encendido.
- GPS y permiso de ubicación habilitados porque este gate los requiere.
- Modo rescate activo con intervalo y TTL existentes registrados.
- Un ping previo observado; relojes, batería, alias, versiones y estados
  foreground/background documentados.

#### 6. Pasos numerados

1. Inicie evidencia saneada en Android y en el observador; registre el ping
   previo, UTC y gate ID.
2. Cierre/mate el proceso sin usar la acción Android «Forzar detención», bloquee
   la pantalla y mantenga la app sin abrir.
3. Lleve el dispositivo a Doze mediante el procedimiento de prueba del sistema
   y evidencie el estado alcanzado.
4. Observe los pings nativos marcados como esperados y ejecutados durante los
   intervalos/TTL ya configurados.
5. En el rescatista confirme la recepción correspondiente y registre copias,
   ACK y latencia.
6. Compruebe que el timestamp de ubicación usado por el ping está dentro del TTL
   configurado, sin guardar coordenadas.
7. Salga de Doze, cierre capturas, sanee y calcule SHA-256.

#### 7. Resultado esperado

Con proceso cerrado, pantalla bloqueada y Doze activo, la programación nativa
registra los pings esperados/ejecutados; el observador recibe el ping aplicable
y la ubicación asociada es fresca dentro del TTL configurado.

#### 8. Métricas a registrar

- UTC de kill, entrada/salida de Doze, ping esperado, ejecución y recepción.
- Alias efímero, plataforma, versiones, test ID, batería y estado de pantalla.
- Latencia ejecución→recepción, ACK y pérdida.
- Conteo de pings esperados, ejecutados, recibidos y duplicados.
- Frescura como edad de ubicación frente al TTL, sin coordenadas.
- `reboot_recovery: not_applicable`.
- `hop_count: unavailable`.

#### 9. Criterio PASS

En revisión independiente: el proceso estuvo cerrado sin force-stop, la pantalla
permaneció bloqueada, Doze quedó evidenciado, los pings nativos
esperados/ejecutados corresponden al schedule existente, el receptor observa el
ping aplicable y la ubicación está fresca durante el TTL.

#### 10. Criterio FAIL

Se requiere abrir la app, falta un ping esperado/ejecutado o recibido, aparece
un duplicado, el ping usa ubicación vencida, se emite después del TTL o no se
puede demostrar kill, pantalla bloqueada o Doze.

#### 11. Evidencia requerida

- Inventario por alias, versiones, batería, intervalo y TTL.
- Salida ADB saneada que demuestre cierre de proceso y estado Doze.
- Logs saneados de programación/ejecución nativa y recepción remota.
- Evidencia de frescura mediante timestamps/edad, nunca coordenadas.
- Reporte con latencia, ACK, pérdida, conteos y primera condición incumplida.
- Captura UI redactada del rescatista y SHA-256 de cada archivo.

## `P0-IOS-FORCEQUIT-01`

#### 1. Objetivo

Documentar el límite real de iOS: después de cerrar HearthBit explícitamente
desde el selector de apps no existe restauración BLE fiable hasta reabrirla, y
la guía/UI debe advertirlo.

#### 2. Hardware

- Un iPhone físico como víctima.
- Un Android físico como rescatista/observador.
- Un Mac con Xcode para evidencia iOS que no relance la app durante el intervalo.

#### 3. Software

- Versión iOS y build HearthBit registrados.
- Versión Android/app del observador registrada.
- Manifiesto y reporte del piloto actual.

#### 4. Topología

`HB-IP (iPhone víctima) ↔ HB-S25 (Android rescatista)`, directa, con rescate
activo.

#### 5. Condiciones iniciales

- Internet, Wi-Fi y datos celulares apagados cuando sea posible; Bluetooth
  encendido; GPS apagado.
- Ping anterior al force-quit confirmado.
- Intervalo de rescate existente, UTC, alias, versiones y estados registrados.
- Captura preparada sin usar herramientas que inicien o reinicien HearthBit.

#### 6. Pasos numerados

1. Confirme y registre el ping sintético previo al force-quit.
2. Cierre HearthBit explícitamente desde el selector de apps del iPhone.
3. Espere dos intervalos de rescate sin reabrirla.
4. Desde Android compruebe que no hay restauración fiable, anuncios ni pings
   nuevos.
5. Verifique que la guía/UI operativa advierte que el force-quit impide rescate
   en segundo plano hasta reabrir la app.
6. Registre el resultado como `BLOCKED_PLATFORM` o como `FAIL` de continuidad,
   nunca como `PASS`.
7. Sanee archivos, calcule hashes y complete el paquete sin relanzar la app
   dentro de la ventana observada.

#### 7. Resultado esperado

No aparecen nuevos anuncios ni pings durante dos intervalos y la limitación se
comunica claramente. El estado esperado es `BLOCKED_PLATFORM` o `FAIL` de
continuidad; nunca `PASS`.

#### 8. Métricas a registrar

- UTC del ping previo, force-quit, cada intervalo esperado y fin de observación.
- Alias efímero, plataforma, versiones y test ID.
- Latencia previa al force-quit; latencia posterior `not_applicable`.
- ACK previo y ACK posterior `not_observed`.
- Pings esperados frente a observados y pérdida posterior.
- `reboot_recovery: not_applicable`.
- `hop_count: unavailable`.

#### 9. Criterio PASS

**No aplicable. Este gate nunca puede declararse `PASS`.** Que la ausencia de
ping y la advertencia queden evidenciadas cumple el objetivo documental, pero
el resultado sigue siendo `BLOCKED_PLATFORM` o `FAIL` de continuidad.

#### 10. Criterio FAIL

Registre `FAIL` de continuidad porque no hay pings posteriores al force-quit.
También existe incumplimiento documental si la UI/guía promete restauración,
omite la advertencia o la evidencia no cubre los dos intervalos sin reapertura.
Si aparece actividad inesperada, no la convierta en `PASS`: documéntela para
investigación.

#### 11. Evidencia requerida

- Inventario por alias con versiones, intervalos y UTC.
- Evidencia redactada del ping previo y del force-quit manual.
- Observación Android saneada de dos intervalos sin anuncios/pings nuevos.
- Captura redactada de la advertencia operativa.
- Reporte que indique `BLOCKED_PLATFORM` o `FAIL`, nunca `PASS`.
- SHA-256 de cada archivo propio del gate.

## Cierre del paquete

1. Mantenga cada gate no ejecutado en `PENDING` o `BLOCKED`; no complete campos
   con observaciones supuestas.
2. Después de una ejecución física, asocie cada evidencia saneada a su gate y
   categoría en el manifiesto y añada su SHA-256.
3. Ejecute
   [`Test-RescuePilotRun.ps1`](../scripts/field-test/Test-RescuePilotRun.ps1)
   para comprobar el comportamiento estructural del tooling.
4. Solo cuando el paquete completo tenga hardware confirmado, criterios
   documentados y evidencia propia válida, use `New-RescuePilotRun.ps1
   -ManifestPath <ruta> -RequestReview`. El máximo automático es
   `READY_FOR_REVIEW`.
5. La persona revisora independiente registra fuera del script la decisión de
   cada gate. No cambie estados históricos ni use hashes como sustituto de
   recepción, topología o ejecución RF.
