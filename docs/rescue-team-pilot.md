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
   `scripts\field-test\New-RescuePilotRun.ps1`. El script consulta versiones y
   `adb devices` de forma read-only, registra solo el número de equipos y no
   inicia/detiene `flutter run`, servicios ni aplicaciones.
3. Mantenga el manifiesto en `PENDING` o `BLOCKED`. No copie seriales, MAC,
   peer IDs, nombres Bluetooth, claves, coordenadas reales ni contenido humano.
4. Defina los criterios y topologías antes de mover equipos. Use controles
   negativos para descartar enlaces directos.
5. Use datos sintéticos. Sanee cada archivo antes de calcular SHA-256.

## Secuencia del piloto

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
- reloj, recuperación Bluetooth, reinicio de rescate, límite force-quit iOS,
  beacon por un salto, prioridad Meshtastic y atomicidad LoRa cuando apliquen.

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

`PASS` exige que todos los criterios aplicables estén confirmados por la persona
operadora y que los archivos/hashes existan. El preflight puede rechazar un
`PASS` incompleto, pero no puede confirmar cobertura, RF, recepción visual,
integridad humana, exactitud clínica o cumplimiento regulatorio.

## Cierre

1. Ejecute el guard de manifiesto con `-ManifestPath ... -RequestPass` solo
   después de completar evidencia. Si falla, el estado permanece pendiente.
2. Registre `FAIL` ante un criterio incumplido reproducible; no lo convierta en
   `BLOCKED`.
3. Registre gates físicos no ejecutados por hardware de forma explícita.
4. Archive evidencia saneada según la política del equipo y destruya copias con
   información accidentalmente sensible.
5. La declaración «lista para emergencias reales» permanece bloqueada mientras
   cualquier P0 aplicable esté pendiente, bloqueado, fallido o sin evidencia.
