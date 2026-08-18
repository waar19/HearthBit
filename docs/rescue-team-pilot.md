# Piloto P0 para equipo de rescate

Estado inicial: **BLOCKED / PENDING**. Este documento es un runbook y no
contiene evidencia de una ejecución. Ningún build, test automatizado, emulador,
preflight o dispositivo visible por ADB autoriza cambiar un gate físico a
`PASS`.

## Requisitos antes de convocar el piloto

- Varios Android físicos representativos; como mínimo víctima, rescatista y
  relay para los casos de dos saltos.
- Un iPhone físico y un Mac con Xcode para los gates iOS.
- Anclas Bitle reales para Courier y topologías de infraestructura.
- Raspberry Pi/BlueZ para `P0-LAN-PI`.
- Dos radios Meshtastic para sus gates y dos kits LoRa/SX1262 para los gates de
  islas, con antenas conectadas y autorización normativa documentada.
- Cargadores, baterías, elementos de aislamiento/apantallamiento, reloj UTC y
  una persona operadora distinta de quien confirma recepción cuando el caso lo
  requiera.

Si falta un elemento, registre `BLOCKED_HARDWARE`,
`BLOCKED_REGULATORY` o `PENDING`; no reduzca la topología y la declare
equivalente.

## Preparación segura

1. Identifique commit, build y versiones. Use solo alias como `HB-VICTIM-1`,
   `HB-RESCUE-1`, `HB-RELAY-1`, `HB-IOS-1`, `ANCHOR-1` y `LORA-A`.
2. Cree una carpeta nueva con
   `scripts\field-test\New-RescuePilotRun.ps1`. El script intenta consultar
   `adb version`, `flutter --version`, `git --version`, `python --version`,
   `java -version` y `xcodebuild -version` con timeout. Registra la primera
   línea real o solo `UNAVAILABLE`, `TIMEOUT_OR_START_FAILURE` o
   `VERSION_QUERY_FAILED`; nunca inventa una versión. `adb devices` se usa de
   forma read-only y solo se conserva el número de equipos. El script no
   inicia/detiene `flutter run`, servicios ni aplicaciones.
3. Mantenga el manifiesto en `PENDING` o `BLOCKED`. No copie seriales, MAC,
   peer IDs, nombres Bluetooth, claves, coordenadas reales ni contenido humano.
4. Defina los criterios y topologías antes de mover equipos. Use controles
   negativos para descartar enlaces directos.
5. Use datos sintéticos. Sanee cada archivo antes de calcular SHA-256.

## Secuencia del piloto

Para las tres topologías mínimas y los procedimientos completos de
`P0-SOS-ACK`, `P0-STORE-REBOOT`, `P0-FOUR-NODE-TWO-HOP`,
`P0-RESCUE-KILL-DOZE` y `P0-IOS-FORCEQUIT-01`, siga la
[guía de ejecución P0](p0-execution-guide.md).

### 1. Roster y autoridad

- Importe un roster de rescate firmado con roles sintéticos; pruebe firma
  alterada, miembro ausente, duplicado, expirado y conflicto con un pin previo.
- Confirme que un peer del roster queda protegido frente a presión de capacidad
  y que el conflicto aumenta el contador agregado sin exportar su identidad.
- Publique, actualice, expire y revoque un anuncio de autoridad. Pruebe emisor
  no autorizado, firma alterada, secuencia repetida y dispositivo offline.
- La UI debe diferenciar autoridad válida, vencida y no verificada sin presentar
  una recepción técnica como orden atendida.

### 2. Triage y casos

- Cree SOS T1 sintéticos para `OK`, ayuda, lesión, atrapamiento, extracción y
  múltiples personas. Verifique persistencia de todos los campos y compatibilidad
  con SOS anteriores.
- Cree casos, asigne y reasigne rescatistas, cambie prioridad/estado, registre
  ACK duplicado y cierre/reapertura. Compruebe idempotencia y trabajo offline.
- Reinicie app, teléfono y relay según el gate; ningún caso confirmado puede
  volver a pendiente ni duplicarse sin una transición explícita.

### 3. Clusters y zonas

- Agrupe reportes sintéticos en un cluster y pruebe separación/unión al cambiar
  tiempo o distancia de prueba. Confirme que el cluster no inventa identidad,
  causalidad ni número de víctimas.
- Defina zonas operativas y límites GeoJSON sintéticos. Pruebe polígono válido,
  multipolígono, hueco, borde, coordenadas fuera de rango, geometría enorme,
  propiedades desconocidas y JSON truncado.
- Exporte e importe GeoJSON y compare estructura/hash saneado. La visualización
  no equivale a precisión topográfica ni autorización para entrar a una zona.

### 4. Gates P0 de comunicación

Ejecute los gates de [prueba de campo](field-test.md), como mínimo:

- `P0-SOS-NO-AUDIENCE`, `P0-SOS-ACK`, `P0-STORE-REBOOT`;
- `P0-RESCUE-KILL-DOZE`, `P0-PRIVATE-NOISE`,
  `P0-FOUR-NODE-TWO-HOP`;
- `P0-LAN-PI`, `P0-RADAR-10M`, `P0-BATTERY-24H`;
- `P0-IOS-MESH-RESTART`, `P0-INTEROP-OFF`, `P0-PANIC-WIPE`,
  `P0-OPTICAL-TRUST`;
- `P0-SOS-CLOCK-01`, `P0-SOS-BATTERY-01`, `P0-BT-RECOVERY-01`,
  `P0-RESCUE-RESTART-01`, `P0-IOS-FORCEQUIT-01`, `P0-RADAR-30M-01`;
- `P0-BEACON-HOP-01`, `P0-MESHTASTIC-QUEUE-01`,
  `P0-LORA-ATOMIC-01` y `P0-SONAR-NOISE-01`.

No agrupe ejecuciones incompatibles: batería 24 h, aislamiento RF, force-quit y
reinicio necesitan corridas y evidencia independientes.

## Evidencia mínima

Cada corrida debe contener:

- manifiesto basado en
  [`rescue-pilot-manifest.template.json`](templates/rescue-pilot-manifest.template.json);
- reporte basado en
  [`rescue-pilot-report.template.md`](templates/rescue-pilot-report.template.md);
- inventario por alias, commit/build, sistema, batería y estado de pantalla;
- logs saneados por nodo, export diagnóstico local y captura UI redactada;
- controles negativos de topología y primera condición incumplida;
- hashes SHA-256 de cada archivo y tiempos UTC;
- para LoRa/Meshtastic: autorización/configuración, logs de ambos extremos y
  hashes/longitudes de frames opacos, nunca payload real.

Cada escenario debe apuntar a evidencia propia. Una misma ruta o el mismo hash
no pueden reutilizarse para dos escenarios o categorías: un hash solo prueba
integridad del archivo suministrado, no cobertura, RF, recepción visual,
exactitud clínica ni cumplimiento regulatorio.

El script solo comprueba completitud estructural, rutas, categorías y hashes.
Su máximo es `READY_FOR_REVIEW`; nunca emite `PASS`.

## Cierre

1. Ejecute el guard con `-ManifestPath ... -RequestReview` después de completar
   evidencia. Si todo está íntegro, el manifiesto queda `READY_FOR_REVIEW`;
   si falla, conserva su estado anterior. El alias histórico `-RequestPass`
   produce exactamente el mismo resultado y tampoco puede emitir `PASS`.
2. Una persona revisora distinta de la operadora debe abrir cada archivo,
   comprobar el gate físico y sus controles negativos, y registrar fuera del
   script un acta independiente con alias de ambas personas, UTC, commit/build,
   decisión por gate y hash del manifiesto revisado. Solo esa acta puede usar
   `PASS`; el manifiesto generado por el script permanece
   `READY_FOR_REVIEW`.
3. Registre `FAIL` ante un criterio incumplido reproducible; no lo convierta en
   `BLOCKED`.
4. Registre gates físicos no ejecutados por hardware de forma explícita.
5. Archive evidencia saneada según la política del equipo y destruya copias con
   información accidentalmente sensible.
6. La declaración «lista para emergencias reales» permanece bloqueada mientras
   cualquier P0 aplicable esté pendiente, bloqueado, fallido o sin evidencia.

Ejecute `scripts\field-test\Test-RescuePilotRun.ps1` para verificar
automáticamente los casos incompleto, evidencia duplicada y paquete completo.
