# Prueba de campo

La radio BLE no se valida con emuladores. Use teléfonos físicos y desactive
Wi-Fi y datos móviles durante la prueba.

Para un operativo completo con roster, triage, casos, clusters, zonas,
anuncios de autoridad y GeoJSON, siga también el
[piloto P0 para equipo de rescate](rescue-team-pilot.md). Su preflight crea
manifiesto y reporte en estado `PENDING`/`BLOCKED`; la validación automática
solo puede elevar el paquete a `READY_FOR_REVIEW` y nunca declara `PASS` ni
evidencia RF.

## Gates P0 de publicación

Estos casos bloquean la declaración «lista para emergencias reales». Su estado
inicial es `PENDING`; solo una ejecución física con evidencia saneada puede
cambiarlo a `PASS`, `FAIL` o `BLOCKED`.

- `P0-SOS-NO-AUDIENCE`: enviar SOS sin pares, reiniciar la app y comprobar que
  el outbox conserva, reintenta y vence sin afirmar entrega.
- `P0-SOS-ACK`: confirmar estados pendiente, emitido, ACK único, ACK duplicado
  y receptor BitChat sin capacidad ACK.
- `P0-STORE-REBOOT`: receptor fuera de línea, relay intermedio reiniciado y
  entrega posterior exactamente una vez.
- `P0-RESCUE-KILL-DOZE`: cerrar proceso, bloquear pantalla y entrar en Doze;
  verificar pings nativos esperados/ejecutados y GPS fresco durante el TTL.
- `P0-PRIVATE-NOISE`: privado HearthBit↔HearthBit y HearthBit↔BitChat,
  desconexión, rekey y drenaje del outbox sin duplicados.
- `P0-FOUR-NODE-TWO-HOP`: cuatro nodos, extremos sin enlace directo, controles
  negativos con relays apagados y entrega en ambos sentidos.
- `P0-LAN-PI`: móvil↔mDNS↔relay Raspberry Pi con PSK correcta, rechazo con PSK
  incorrecta, reconexión y ausencia de bucles.
- `P0-RADAR-10M`: sesión de diez minutos con acercamiento, alejamiento,
  calibración, pérdida de señal y texto al 200 % sin colapso de layout.
- `P0-BATTERY-24H`: malla activa 24 horas en Android e iOS, registrando batería,
  memoria, duty-cycle BLE y estabilidad sin contenido ni identificadores.
- `P0-IOS-MESH-RESTART`: en un iPhone con Bluetooth ya encendido, activar,
  detener y reactivar la malla varias veces sin alternar Bluetooth; cada ciclo
  debe abandonar «Iniciando» y llegar a «Malla activa».
- `P0-INTEROP-OFF`: con BitChat cercano, ocultar su chat público, mostrar su SOS
  como «red externa», mantenerlo como presencia sin chat y confirmar que
  interoperabilidad ON restaura el comportamiento compatible.
- `P0-PANIC-WIPE`: borrar sin matar el proceso y verificar identidad nueva,
  bases, colas, grupos, claves, gateways y diagnósticos vacíos.
- `P0-OPTICAL-TRUST`: firma válida conocida, firma alterada rechazada, emisor
  desconocido con confirmación de huella y formato legado advertido.

Para cada caso registre commit, versión, alias de equipos, sistema operativo,
inicio/fin UTC, resultado, primer criterio incumplido y hashes SHA-256 de la
evidencia. No agregue coordenadas, seriales, MAC, peer IDs, claves ni mensajes
reales.

## Protocolo P0 de reloj, rescate y enlaces críticos

Todos estos casos empiezan en `PENDING`. Use una ejecución nueva por caso:
`RUN-<UTC>-<CASE_ID>`, y marcadores
`<CASE_ID>-<RUN>-<PASO>-<ORIGEN>-<DESTINO>`. La topología debe usar solo los
alias `HB-S25`, `HB-IP`, `HB-R1`, `HB-R2`, `MT-A`, `MT-B`, `LR-A` y `LR-B`.
Registre versiones, batería, estado foreground/background, tiempos UTC,
distancias aproximadas, TTL, conteo de copias y resultado; no registre
coordenadas reales, contenido personal, nombres Bluetooth, MAC, seriales, peer
IDs, claves ni payloads privados.

La evidencia mínima por caso es: `capture.json`, log saneado por nodo observado,
informe con el marcador y el primer criterio incumplido, capturas de UI
redactadas cuando el criterio sea visual y SHA-256 de cada archivo. Los logs de
radio o serie se conservan solo desde cinco segundos antes del marcador hasta
cinco segundos después del resultado. Un test automatizado, una compilación o
la mera visibilidad de un peer no sustituyen la evidencia física.

### P0-SOS-CLOCK-01 — desfase de reloj del SOS

**Topología:** enlace directo `HB-IP (víctima) ↔ HB-S25 (rescatista)`, sin
relay, Wi-Fi ni datos móviles. Antes de empezar anote la zona horaria y active
fecha/hora automáticas en ambos equipos. Use un perfil de prueba nuevo en el
iPhone y confirme que el S25 no conserva su identidad ni un `ANNOUNCE` previo.

1. Ajuste manualmente `HB-IP` a **30 minutos en el pasado**. Envíe primero un
   mensaje estándar firmado con marcador `...-OLD-STANDARD-IP-S25`; debe ser
   rechazado. Emita después `ANNOUNCE` con TTL completo 7 seguido
   inmediatamente por `...-PAST-SOS-IP-S25`.
2. Confirme que el S25 acepta una sola copia del SOS y conserva su vigencia de
   hasta 24 horas, sin aceptar por ello el mensaje estándar viejo.
3. Ajuste `HB-IP` a **30 minutos en el futuro** y repita con
   `...-FUTURE-SOS-IP-S25`; debe rechazarse porque supera +10 minutos.
4. Repita los límites -24 h y +10 min si el cliente permite timestamp
   determinista. Al terminar, restaure fecha/hora y zona automáticas y
   compruebe sincronización antes de cualquier otro caso.

**PASS:** estándar viejo rechazado; `ANNOUNCE` previo TTL 7 y SOS atrasado
aceptados una vez; SOS adelantado más de 10 min rechazado; reloj restaurado.
**FAIL:** se acepta tráfico estándar viejo, se pierde el SOS atrasado válido,
se acepta el futuro prohibido, el TTL no es 7 o queda el reloj alterado.

### P0-SOS-BATTERY-01 — rescate con batería crítica

**Topología:** `HB-S25 (víctima) ↔ HB-IP (rescatista)` directa. Lleve el S25 a
10 % o menos sin activar el rol `PHONE_BEACON`; anote porcentaje y temperatura.

1. Active Modo Rescate en el S25, bloquee la pantalla y déjelo en segundo plano.
2. Capture durante al menos 15 minutos dos ciclos de ping con marcador
   `...-SOS-S25-IP`; confirme escaneo continuo, sin pausa del perfil crítico.
3. Aleje y acerque el iPhone entre pings; el siguiente SOS debe descubrirse y
   entregarse una sola vez. Registre batería inicial/final, duración y consumo
   porcentual; detenga la prueba si el equipo se calienta o llega a 3 %.

**PASS:** rescate activo mantiene scan continuo a ≤10 %, entrega el SOS y deja
medición de consumo. **FAIL:** entra en pausas críticas, requiere abrir la app,
no entrega, duplica o no se registró batería/duración.

### P0-BT-RECOVERY-01 — recuperación Bluetooth Android

**Topología:** `HB-S25 (víctima) ↔ HB-IP (rescatista)`, rescate activo y ambas
apps inicialmente en segundo plano.

1. Confirme un ping `...-BEFORE-OFF-S25-IP`. Apague Bluetooth desde ajustes
   rápidos del S25 durante 60 segundos sin abrir HearthBit.
2. Reactive Bluetooth sin abrir HearthBit ni desbloquear más de lo necesario.
3. Espere el siguiente intervalo. Capture transición OFF→ON, reactivación de
   scan/GATT y marcador `...-AFTER-ON-S25-IP`.

**PASS:** recuperación automática y siguiente ping entregado una vez sin abrir
la app. **FAIL:** servicio detenido, scan no vuelve, requiere interacción,
pierde/duplica el ping o continúa transmitiendo mientras Bluetooth está OFF.

### P0-RESCUE-RESTART-01 — START_STICKY y alarma persistida

**Topología:** `HB-S25 (víctima) ↔ HB-IP (rescatista)`, intervalo conocido de
rescate y pantalla bloqueada.

1. Reciba `...-BEFORE-KILL-S25-IP` y anote `lastPingAt` saneado y la próxima
   hora prevista. Mate solo el proceso con ADB y repita, en otra ejecución,
   mediante el gestor/OEM; no pulse «Detener» ni «Forzar detención».
2. Mantenga la app cerrada. Verifique que `AlarmManager` o `START_STICKY`
   reconstruye el schedule desde estado persistido.
3. Confirme `...-AFTER-RESTART-S25-IP` dentro del siguiente intervalo y cuente
   copias. Repita matando justo después de un ping para comprobar que el
   `lastPingAt` persistido impide un duplicado inmediato.

**PASS:** reanuda sin abrir la app, el ping debido ocurre una vez y el recién
persistido no se duplica. **FAIL:** pierde estado, exige abrir la app, duplica o
emite después de expirar. «Forzar detención» de Android es un caso de
plataforma distinto y debe registrarse `BLOCKED_PLATFORM`, no como recuperación
exitosa de `START_STICKY`.

### P0-IOS-FORCEQUIT-01 — límite de force-quit en iOS

**Topología:** `HB-IP (víctima) ↔ HB-S25 (rescatista)`, rescate activo.

1. Confirme `...-BEFORE-FORCEQUIT-IP-S25`; después cierre HearthBit
   explícitamente desde el selector de apps.
2. Espere dos intervalos sin reabrirla y compruebe desde el S25 que no hay
   restauración fiable, anuncios ni nuevos pings.
3. Verifique que la guía/UI operativa advierte que force-quit impide el rescate
   en segundo plano hasta reabrir la app.

El resultado esperado de plataforma es `BLOCKED_PLATFORM` (o `FAIL` de
continuidad), nunca `PASS`: iOS bloquea la restauración BLE tras force-quit y
la app no debe prometer una solución imposible. El caso solo cumple su objetivo
documental si la ausencia de ping y la advertencia quedan evidenciadas.

### P0-RADAR-30M-01 — renovación de consentimiento

**Topología:** `HB-S25 (rescatista) ↔ HB-IP (víctima)` directa; Modo Rescate en
la víctima con ping periódico. Mantenga la búsqueda activa por más de 10 min.

1. Tras `...-PING-01-IP-S25`, abra radar y anote expiración remota esperada
   `timestamp + 30 min`.
2. Observe al menos dos pings posteriores `...-PING-02` y `...-PING-03`; cada
   uno debe renovar la ventana otros 30 min y el radar debe seguir midiendo sin
   pedir consentimiento nuevamente.
3. En una ejecución separada detenga los pings sin enviar `STOP`; espere 30 min
   desde el último ping y confirme que radar expira y deja de medir.

**PASS:** búsqueda supera 10 min, cada ping renueva 30 min y la ausencia de
pings causa expiración. **FAIL:** conserva el límite viejo de 10 min, no
renueva, renueva sin ping, permanece activo tras vencer o exige reabrir la app.

### P0-BEACON-HOP-01 — control de baliza con un relay

**Topología aislada:** `HB-S25 (rescatista) ↔ HB-R1 ↔ HB-IP (víctima)`;
`HB-S25` y `HB-IP` no deben tener enlace directo. Para el control negativo
inserte `HB-R2` y aísle `HB-IP` de `HB-R1`.

1. Con `HB-R1` apagado, `...-REQUEST-S25-IP` no debe llegar. Enciéndalo y emita
   un request firmado con TTL 2.
2. Confirme un único forward en `HB-R1`, TTL 2→1 y actuación solo después del
   grant local. El relay no debe aplicar el control.
3. En la topología `HB-S25 ↔ HB-R1 ↔ HB-R2 ↔ HB-IP`, repita
   `...-TWO-RELAYS-S25-IP`; no debe llegar ni reenviarse desde TTL 1.
4. Con iOS actuando, envíe HearthBit a background. iOS debe detener la baliza y
   el rescatista debe ver el estado `STOP`/detenido, sin prometer actuación en
   background.

**PASS:** solo un relay, TTL 2→1, control negativo de dos relays y STOP visible
al pasar iOS a background. **FAIL:** enlace directo no descartado, segundo
relay, TTL incorrecto, actuación sin grant, relay actuando o estado remoto
oculta el STOP.

### P0-MESHTASTIC-QUEUE-01 — prioridad crítica en radio real

**Hardware/topología:** dos nodos Meshtastic compatibles `MT-A ↔ LoRa ↔ MT-B`,
con `HB-S25 ↔ BLE ↔ MT-A` y receptor conectado a `MT-B`. Sin ambos radios,
marque `BLOCKED_HARDWARE`.

1. Sature la cola BLE con al menos 64 frames estándar
   `...-STANDARD-<NN>`, manteniendo el enlace LoRa ocupado.
2. Envíe inmediatamente `...-SOS-CRITICAL-S25-DST`.
3. Correlacione log saneado de evicción, `requestAck`, TX/RX Meshtastic y
   recepción final; no conserve payloads de otros canales.

**PASS:** el SOS crítico reemplaza al estándar más antiguo, sale antes que el
backlog y llega una vez; la cola nunca supera 64. **FAIL:** se rechaza/retrasa
detrás del backlog, expulsa otro crítico, excede capacidad o duplica.

### P0-LORA-ATOMIC-01 — frame opaco íntegro

**Hardware/topología:** `HB-S25 ↔ BLE ↔ LR-A ↔ LoRa ↔ LR-B ↔ BLE ↔ HB-IP`,
sin enlace BLE directo entre teléfonos. Requiere radios configurados y
autorización normativa; de lo contrario use `BLOCKED_HARDWARE` o
`BLOCKED_REGULATORY`.

1. Envíe simultáneamente frames estándar deterministas y un SOS crítico
   `...-ATOMIC-SOS-S25-IP`, incluyendo un frame cercano al MTU admitido.
2. Capture en ambos extremos longitud, SHA-256 y contador de cada frame opaco,
   sin guardar su contenido. Introduzca una pérdida/reintento de radio.
3. Confirme que cada entrega corresponde a un frame completo: nunca mezcle
   bytes de dos frames, entregue prefijos ni reconstruya un frame parcial.

**PASS:** mismo tamaño y SHA-256 extremo a extremo, una entrega completa por
marcador y ningún parcial/intercalado aun con reintento. **FAIL:** hash o
longitud distintos, entrega parcial, mezcla, duplicado no deduplicado o SOS
bloqueado por tráfico estándar.

## Matriz mínima

1. Instale HearthBit en dos Android.
2. Instale BitChat oficial en un tercer Android o iPhone.
3. Con los tres a menos de cinco metros, active la malla y confirme que aparecen
   los nombres cercanos.
4. Envíe mensajes públicos desde cada app y confirme recepción cruzada.
5. Abra un chat privado, espere que el candado indique canal seguro y pruebe en
   ambos sentidos.
6. Aleje el tercer equipo fuera del alcance directo del primero, dejando el
   segundo a mitad de camino; confirme el relé de dos saltos.
7. Apague el destinatario, envíe un mensaje dirigido, vuelva a encenderlo antes
   de 12 horas y confirme el reintento store-and-forward.
8. Inserte un ESP32 Bitle entre dos equipos fuera de alcance directo y repita.

La interoperabilidad HearthBit↔BitChat con hardware real (pasos 2-5) es una
prueba manual obligatoria antes de declarar compatibilidad física; los tests
binarios automatizados no la sustituyen.

### Interoperabilidad desactivada

Estado funcional: `PASS` el 2026-08-14 en S25 con un BitChat cercano. Se
confirmó chat público oculto con interop OFF, SOS externo etiquetado y
restauración del comportamiento al activar interop. La captura HCI del paso 6
y la paridad en iPhone permanecen `PENDING`.

1. En HearthBit, confirme que «Compatibilidad con BitChat» está desactivada.
2. Mantenga un BitChat oficial a menos de cinco metros y envíe un mensaje
   público normal. No debe aparecer en el canal HearthBit.
3. Envíe desde BitChat un payload SOS compatible. Debe aparecer una sola vez
   con la insignia «RED EXTERNA».
4. Abra «Cercanos»: BitChat puede aparecer como presencia externa, pero no debe
   ofrecer chat, archivo, radar ni candado.
5. Active la compatibilidad, repita el mensaje público y confirme que vuelve a
   mostrarse. Desactívela de nuevo y confirme el filtro sin reiniciar Bluetooth.
6. Capture HCI/PacketLogger con contenido saneado: antes de la prueba anónima
   `HB-LINK1`, un enlace BitChat normal no debe recibir `ANNOUNCE`,
   `HBT_CAPABILITY` ni capacidades locales. El anuncio previo a un SOS público
   es la excepción esperada.

**PASS:** se cumplen los seis pasos en cinco ciclos consecutivos.
**FAIL:** aparece chat BitChat con interop OFF, falta la etiqueta del SOS, se
habilita una acción de chat externa o se filtra identidad antes de probar el
enlace.

### Reactivación de la malla en iPhone

Estado: `PENDING` hasta disponer de Mac con Xcode y un iPhone físico.

1. Abra HearthBit con Bluetooth encendido y active la malla; espere «Malla
   activa».
2. Pulse «DETENER», espere el estado detenido y vuelva a activar sin apagar
   Bluetooth ni cerrar la app.
3. Repita el ciclo cinco veces, incluyendo una pasada después de enviar la app
   a segundo plano y recuperarla.
4. Registre el tiempo desde «Iniciando» hasta «Malla activa» y los estados de
   `CBCentralManager` y `CBPeripheralManager`, sin guardar identificadores.

**PASS:** los cinco ciclos llegan a «Malla activa» sin alternar Bluetooth.
**FAIL:** un ciclo queda en «Iniciando», necesita alternar Bluetooth o duplica
servicios/anuncios.

## D1 — guion reproducible pendiente de ejecución física

Esta sección define el procedimiento y la evidencia esperada; **no registra
resultados**. Cada ejecución usa un identificador nuevo y conserva como
`PENDING`, `PASS`, `FAIL` o `BLOCKED` solamente lo que declare la persona que
realizó la prueba. No cambie los registros históricos de este documento.

### Preparación, identificadores y captura

1. Use alias no personales para los nodos: `HB-A`, `HB-B`, `BC-A`, `TV-R1`,
   `PI-R1`, `LINUX-R1` y `BITLE-A`. No escriba nombres Bluetooth reales, MAC,
   números de serie, nombres de personas ni lugares en mensajes o informes.
2. Sincronice la hora de los equipos. Desactive Wi-Fi y datos móviles en los
   teléfonos para los casos BLE. Documente aparte distancia y obstáculos sin
   incluir ubicación exacta.
3. Genere una ejecución y marcadores únicos en PowerShell:

   ```powershell
   $run = "RUN-" + (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
   $hbToBc = "D1-NOISE-01-HB2BC-$run"
   $bcToHb = "D1-NOISE-01-BC2HB-$run"
   ```

4. Conecte únicamente el Android que se va a observar. Si hay varios en
   `adb devices`, pase `-DeviceSerial`; ese valor se usa para seleccionar el
   equipo, pero no se escribe en la evidencia. Inicie la captura justo antes
   del caso:

   ```powershell
   .\scripts\field-test\Collect-AdbFieldLog.ps1 `
     -CaseId D1-NOISE-01 -RunId $run -NodeAlias HB-A `
     -DurationSeconds 240 -DeviceSerial "<serial-adb>"
   ```

   El script no limpia `logcat`, no cambia datos ni configuración de la app y
   solo inicia y detiene su propio proceso lector. Filtra por
   `HearthBitMesh:V *:S` y redacta en memoria MAC, nombres Bluetooth, prefijos
   binarios e identificadores de peers antes de escribir el log. Para dos
   Android, ejecute una captura por nodo en terminales separadas con el mismo
   `RunId`.
5. Genere primero un informe pendiente. Después de revisar UI, topología y
   logs, vuelva a generarlo con el resultado real; los informes anteriores no
   se sobrescriben:

   ```powershell
   $capture = Get-ChildItem .\artifacts\field-test -Directory |
     Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
   .\scripts\field-test\New-FieldTestReport.ps1 `
     -CaptureMetadataPath (Join-Path $capture.FullName "capture.json")

   .\scripts\field-test\New-FieldTestReport.ps1 `
     -CaptureMetadataPath (Join-Path $capture.FullName "capture.json") `
     -Result PASS -ReasonCode ALL_CRITERIA_MET `
     -ObservedIdentifier $hbToBc,$bcToHb
   ```

   `PASS` exige que se cumplan **todos** los criterios manuales y de logs del
   caso. `FAIL` identifica un incumplimiento reproducible. `BLOCKED` se usa
   cuando falta interacción o hardware, no como sustituto de un fallo.

En Android, los tipos útiles del log saneado son `16` (`0x10`, handshake
Noise), `17` (`0x11`, paquete Noise cifrado), `32` (`0x20`, fragmento), `4`
(Courier) y `37` (`0x25`, capacidad/rol). `RX decoded` prueba recepción y
decodificación exterior; por sí solo no prueba entrega visual, contenido,
cifrado extremo a extremo ni ausencia de un enlace directo.

### D1-NOISE-01 — DM Noise HearthBit↔BitChat

**Topología:** `HB-A ↔ BC-A`, a menos de cinco metros y sin otro relay.

1. Inicie la captura en el Android HearthBit. Espere a que ambas apps muestren
   al peer y abra el canal privado.
2. Desde HearthBit envíe como único contenido `$hbToBc`. En BitChat confirme
   recepción privada, una sola vez, y responda con `$bcToHb`.
3. En HearthBit confirme recepción privada, una sola vez. Cierre y vuelva a
   abrir el chat sin borrar identidad y envíe un tercer marcador de la misma
   ejecución para comprobar continuidad de la sesión.

**PASS:** ambos marcadores aparecen una vez en el chat privado correcto, las
dos interfaces indican canal seguro y la captura HearthBit contiene recepción
`type=16` durante establecimiento y `type=17` para la respuesta, sin
`Noise handshake state/protocol failure`, rechazo de identidad ni cierre de
conexión.

**FAIL:** falta una dirección, aparece el marcador en chat público o texto
claro, hay duplicado, se asocia al peer equivocado o aparece cualquiera de los
errores anteriores. El log Android no basta para declarar PASS sin confirmar
manualmente la recepción en BitChat.

### D1-FRAG-01 — fragmentación de payload mayor de 512 B

**Topología:** enlace directo `HB-A ↔ BC-A`; repita cada dirección. Cree texto
ASCII determinista de más de 512 bytes:

```powershell
$fragHb = "D1-FRAG-01-HB2BC-$run"
$payloadHb = $fragHb + "|" + ("F" * 700)
[Text.Encoding]::UTF8.GetByteCount($payloadHb)
$payloadHb | Set-Clipboard
```

1. Verifique que el conteo sea mayor de 512, pegue el payload sin modificarlo y
   envíelo de HearthBit a BitChat.
2. Genere `D1-FRAG-01-BC2HB-$run` con otros 700 caracteres y repita desde
   BitChat.
3. Compare identificador, longitud y contenido completo en el receptor; no
   basta con ver el comienzo del texto.

**PASS:** cada receptor muestra una sola copia exacta; la captura del Android
que recibe desde BitChat contiene varios `RX decoded` con `type=32` y un único
`FRAGMENT reassembled` cuyo `bytes` es mayor de 512, seguido del tipo interior
esperado. No hay `RX rejected`, `packet decode failed` ni `GATT queue full`.

**FAIL:** truncamiento, corrupción, duplicado, timeout, reensamblado de 512
bytes o menos, total de fragmentos incoherente o cualquiera de los errores
indicados. El envío HearthBit→BitChat requiere confirmación visual/log de
BitChat porque `adb` en HearthBit no observa la recepción remota.

### D1-RELAY-01 — relay físico de dos enlaces

Ejecute tres variantes independientes con IDs
`D1-RELAY-01-TV-$run`, `D1-RELAY-01-PI-$run` y
`D1-RELAY-01-BITLE-$run`. La topología de cada variante es
`HB-A ↔ R1 ↔ HB-B`: son dos enlaces de radio y una retransmisión.

1. Separe o apantalle `HB-A` y `HB-B`. Con `R1` apagado, compruebe durante dos
   minutos que no se descubren directamente y que un marcador de control no se
   entrega.
2. Coloque como `R1`, según la variante, un Android TV, Raspberry Pi/BlueZ o
   Bitle. No cambie distancia, orientación ni obstáculos.
3. Encienda solo `R1`, espere su anuncio y envíe el marcador desde `HB-A`.
   Repita desde `HB-B` con sufijo `-RETURN`.
4. Apague `R1` y repita el control negativo para demostrar que no apareció un
   enlace directo durante la ejecución.

**PASS:** ambos marcadores se entregan una vez únicamente con `R1` encendido;
el receptor registra TTL 6 para un origen TTL 7 y el relay registra una sola
retransmisión. TV debe indicar su modo real (dual o central degradado), Pi debe
tener `Powered: yes` y Bitle debe registrar `Relayed ... to 1 link(s)`.

**FAIL:** entrega con `R1` apagado, TTL sin decremento o decrementado más de una
vez, más de una retransmisión, duplicado o una dirección ausente. Un build
correcto o un relay visible sin los dos controles negativos no demuestra los
dos enlaces físicos.

### D1-LORA-01 — troncal entre dos islas BLE

Este es un guion reproducible **pendiente de ejecución física**; no registra
resultados. Antes de transmitir, valide con la ANE Colombia la frecuencia,
potencia, antena, ciclo de trabajo y demás condiciones aplicables. Sin esa
validación normativa, no active los SX1262 y marque la ejecución `BLOCKED`.

**Hardware y topología:** dos XIAO ESP32-S3 + Wio-SX1262 con antena conectada,
`LR-A` y `LR-B`, y dos teléfonos, `HB-A` y `HB-B`:

```text
isla A                         isla B
HB-A ↔ BLE ↔ LR-A ↔ LoRa ↔ LR-B ↔ BLE ↔ HB-B
```

Separe o apantalle las islas para que `HB-A` no descubra a `HB-B` ni a `LR-B`,
y viceversa. Desactive Wi-Fi y datos móviles. Use la misma configuración de
radio autorizada en ambos nodos y no cambie distancia, orientación, potencia u
obstáculos entre el control y la prueba.

1. Cree marcadores únicos:

   ```powershell
   $loraOut = "D1-LORA-01-A2B-$run"
   $loraBack = "D1-LORA-01-B2A-$run"
   $loraControl = "D1-LORA-01-CONTROL-$run"
   ```

2. Inicie capturas ADB saneadas con `CaseId D1-LORA-01` en ambos teléfonos y
   capture por separado las consolas serie de `LR-A` y `LR-B`. Redacte MAC,
   peer IDs, nombres Bluetooth, coordenadas y números de serie; conserve los
   marcadores y horas UTC.
3. **Control negativo inicial:** con uno de los nodos apagado o ambos troncales
   deshabilitados, espere dos minutos, confirme que las islas no se descubren
   directamente y envíe `$loraControl` desde `HB-A`. No debe aparecer en
   `HB-B`; tampoco debe existir un par `trunk TX`/`trunk RX packet`.
4. Encienda ambos nodos sin moverlos. En cada consola confirme
   `trunk up: ...`; `no SX1262 radio` no es un troncal operativo. Espere el
   `ANNOUNCE` y el `NODE_CAPABILITY` autenticados. La UI puede mostrar el rol
   anunciado, pero solo muestra troncal activa si recibió
   `LONG_RANGE_TRUNK=0x10`; nunca lo infiere del nickname o de infraestructura.
5. Envíe `$loraOut` desde `HB-A` y confirme una única copia exacta en `HB-B`.
   Después envíe `$loraBack` desde `HB-B` y confirme una única copia exacta en
   `HB-A`.
6. Correlacione por dirección la entrega visual y ADB con `trunk TX` en el nodo
   de entrada y `trunk RX packet len=... rssi=... snr=...` en el de salida. No
   guarde payloads privados ni salida serie completa sin sanear.
7. **Control negativo final:** apague un nodo sin mover nada, espere dos minutos
   y repita un marcador con sufijo `-FINAL`. No debe entregarse. Genere el
   informe únicamente después de revisar las cuatro capturas.

**Evidencia mínima:** `capture.json` e informe con SHA-256 por teléfono; logs
serie saneados de ambos nodos; configuración de radio autorizada; alias,
distancias aproximadas, obstáculos y tiempos UTC; presencia del bit `0x10` en
el evento/snapshot de cada nodo que lo anuncie; marcadores de ida, vuelta y
ambos controles; recepción visual exacta y conteo de copias.

**PASS:** ambos marcadores se entregan exactamente una vez y en el chat
correcto; cada dirección tiene TX en la isla de origen y RX en la de destino;
los dos controles negativos no se entregan; no existe enlace BLE cruzado; y la
UI declara troncal activa solo para peers cuyo `NODE_CAPABILITY` autenticado
incluye `0x10`.

**FAIL:** cualquier entrega durante un control negativo, falta de ida o vuelta,
duplicado, cruce BLE directo, RX sin TX correlacionable, corrupción, o UI que
infiere LoRa por nombre, rol o infraestructura. Use `BLOCKED`, no `PASS`, si
falta autorización normativa, hardware, captura de una isla, emisión del flag
`0x10` o confirmación visual. Compilar firmware y observar `trunk up` no
demuestran por sí solos el recorrido extremo a extremo.

### D1-COURIER-01 — Courier cifrado mediante Bitle

**Topología inicial:** `HB-A ↔ BITLE-A`, directa; `HB-B` apagado o fuera de
alcance. Bitle debe anunciar `INFRA_DATA_ANCHOR`.

1. Inicie capturas en los Android disponibles y use
   `D1-COURIER-01-DEPOSIT-$run` como DM privado de `HB-A` a `HB-B`.
2. Confirme que `HB-A` establece Noise directamente con Bitle y que el log
   Android contiene `Courier deposited with anchor`; en la consola saneada de
   Bitle debe aparecer `Envelope deposited`.
3. Retire o apague `HB-A`. Encienda `HB-B` en enlace directo solo con Bitle y
   espere el anuncio y la entrega.
4. Reconecte `HB-B` una segunda vez para comprobar deduplicación.

**PASS:** Bitle almacena un sobre `0x04`, nunca imprime el marcador ni el
ciphertext, registra `Handed 1 envelope(s) toward peer`, y `HB-B` muestra una
sola copia privada exacta. El depósito ocurre solo con enlace directo,
identidad verificada y sesión Noise; la copia se elimina o queda marcada como
entregada según el firmware.

**FAIL:** depósito por enlace multisalto o peer no verificado, texto claro en
logs, entrega a otro destinatario, sobre vencido aceptado, duplicado o mensaje
ausente. La consola serie de Bitle puede emitir MAC y nickname en otras líneas:
no guarde la salida completa; conserve únicamente las líneas Courier después
de redactarlas.

### D1-ROUTE-V2-01 — paquete v2 vía relay Linux

**Topología:** `HB-A ↔ LINUX-R1 ↔ HB-B`, sin enlace directo. Configure
`LINUX-R1` como `INFRA_RELAY`, `central_enabled: true` y `log_level: DEBUG`.
Use un cliente de prueba capaz de emitir v2 con flag route `0x08`, una ruta
conocida y el marcador `D1-ROUTE-V2-01-$run`.

1. Haga el control negativo con el relay detenido.
2. Inicie el relay y capture por separado el log Android saneado y las líneas
   `packet type=... ttl=... forwarded=...` del journal Linux, sustituyendo
   cualquier ID de enlace por los alias del guion.
3. Envíe el paquete v2 dirigido, detenga el relay y repita el control negativo.

**PASS:** el destino recibe una copia exacta; Android registra `version=2` y
TTL 6; Linux registra una sola aceptación y `forwarded=1`; los bytes capturados
antes y después del relay conservan versión, flag y lista de ruta, y solo
cambia TTL. La firma sigue válida porque su forma canónica usa TTL cero.

**FAIL:** entrega sin relay, conversión a v1, ruta truncada/reordenada, firma
inválida, TTL incorrecto, duplicado o más de un forward. Los logs actuales de
Android y Linux no muestran la lista de ruta: sin captura/decodificación de los
bytes en ambos lados este caso queda `BLOCKED`, no `PASS`.

El contador agregado `forwarded` del relay cuenta cada envío real de un frame a
un enlace, incluidos los frames emitidos por store-and-forward `_replay()`. No
cuenta como un único evento lógico cuando el mismo frame se envía a varios
enlaces.

### D1-ROLE-01 — políticas PHONE e INFRA

Use marcadores `D1-ROLE-01-<ROL>-$run` y anuncie cada rol por `0x25`. Reinicie
la observación entre variantes para evitar confundir capacidades en caché.

- `PHONE_RELAY`: puede originar chat, mantiene GATT y retransmite un marcador
  entre dos nodos aislados.
- `PHONE_BEACON`: aparece solo como presencia; no muestra compositor, no
  acepta chat, no abre GATT y no retransmite el marcador.
- `INFRA_RELAY`: no puede originar chat, retransmite con TTL decrementado una
  vez y no conserva un paquete dirigido para entrega posterior.
- `INFRA_DATA_ANCHOR`: no puede originar chat, retransmite y ejecuta el caso
  Courier directo con cuotas y expiración.

**PASS:** la UI/configuración identifica el rol anunciado y cumple todas sus
restricciones; el receptor observa `type=37`; los controles con el nodo apagado
prueban relay o ausencia de relay según corresponda.

**FAIL:** un rol origina, conecta, retransmite o almacena algo prohibido; omite
una capacidad obligatoria; o continúa con la política del rol anterior. El
`type=37` solo prueba que llegó una capacidad: la conducta y el valor del rol
requieren inspección manual/configurada.

### Evidencia mínima y estado automatizable

Para cada variante conserve: `capture.json`, log saneado, informe con SHA-256,
identificadores observados, alias de topología, tiempos UTC, distancias
aproximadas y controles negativos. No incluya capturas de pantalla que revelen
nombres personales o notificaciones.

Los scripts automatizan la ventana de `adb logcat`, el filtrado, la redacción,
el timestamp, la integridad y el esqueleto de informe. Requieren interacción y
hardware: confirmar UI en ambas apps; aislar físicamente enlaces; operar
iPhone/BitChat; verificar TV/Pi/Bitle; apagar/reconectar nodos; capturar bytes
de ruta v2; y observar que los roles impiden acciones. Ningún script de esta
sección declara por sí mismo compatibilidad física.

## Matriz ampliada de mega-red

Ejecute estos casos además de la matriz móvil:

1. **Modo presencia:** con dos HearthBit ya identificados, cambie uno a
   `PHONE_BEACON`. Confirme que se deshabilitan los compositores y el relay. En
   Android, compruebe por log que se cierran GATT y los escáneres y que el
   anuncio se reinicia como no conectable; al volver a `PHONE_RELAY`, chat y
   GATT deben recuperarse sin borrar identidad ni historial.
2. **Balizas genéricas:** acerque un TV, asistente o radio BLE no compatible.
   Debe aparecer como «Presencia detectada, sin chat», desaparecer en unos
   45 s al apagarlo y cambiar de identificador después de 15 min. Confirme que
   eventos, SQLite y logs no contienen nombre Bluetooth ni MAC.
3. **Raspberry Pi/Home Assistant:** coloque el daemon BlueZ entre dos teléfonos
   sin alcance directo. Verifique un solo reenvío por paquete, decremento TTL,
   deduplicación tras reiniciar el servicio y entrega store-and-forward dentro
   de la cuota configurada.
4. **Android TV:** pruebe primero un equipo con advertising múltiple y luego
   uno sin soporte. La UI debe distinguir relay dual de modo central degradado;
   en ambos casos confirme el comportamiento real con tres nodos.
5. **Android Automotive:** inicie el relay estacionado, salga de la actividad
   y apague la pantalla. Servicio y advertising deben detenerse. Una unidad OEM
   solo puede mantenerlo con una señal de ignición autorizada y debe fallar
   cerrado cuando esa señal sea desconocida.
6. **Courier:** use un `INFRA_DATA_ANCHOR` directo y repita depósito, expiración,
   destinatario incorrecto y entrega después de reconexión.

Linux/BlueZ, TV y Automotive requieren hardware real; compilar sus paquetes o
usar un emulador no demuestra radio dual, alcance ni ejecución prolongada.

## Reconexión y sincronización GCS

Use dos teléfonos HearthBit y un BitChat oficial:

1. Conecte los tres, espere los `ANNOUNCE` firmados y envíe tres mensajes
   públicos desde cada cliente.
2. Apague Bluetooth en un HearthBit y envíe otros tres mensajes desde BitChat.
3. Reactive Bluetooth antes de seis horas. Al recibir el nuevo `ANNOUNCE`,
   HearthBit debe enviar `REQUEST_SYNC` (`0x21`) con TTL 0 y un filtro GCS
   MSB-first; BitChat debe devolver únicamente los paquetes ausentes.
4. Repita desconectando BitChat. HearthBit debe responder su `REQUEST_SYNC`
   firmado con un máximo de 40 reenvíos, TTL 0 y flag RSR (`0x10`), sin duplicar
   mensajes ya presentes.
5. Capture los bytes de una petición y compruebe los TLV de 16 bits: P `0x01`,
   M big-endian `0x02`, filtro `0x03` y tipos little-endian `0x04`.
6. Mantenga los equipos conectados dos minutos y confirme que el control de
   tasa evita tormentas: no más de ocho respuestas por enlace cada 30 s.

Registre el número de mensajes antes y después. El resultado correcto es
convergencia exacta, sin duplicados y sin propagar `REQUEST_SYNC` más allá del
vecino directo.

## Reconexión de chats privados Noise

Esta prueba es independiente de `REQUEST_SYNC`: los mensajes privados no forman
parte del filtro GCS y deben recuperar su propia sesión Noise.

1. Abra un chat privado HearthBit ↔ HearthBit, envíe un mensaje en cada sentido
   y confirme que ambos peers muestran el canal seguro.
2. Repita con HearthBit ↔ BitChat y conserve abiertas ambas conversaciones.
3. En cada pareja, apague Bluetooth en un extremo durante 30 segundos. Mientras
   está desconectado, escriba un mensaje desde HearthBit; debe quedar marcado
   como pendiente y conservarse aunque se reinicie la app.
4. Reactive Bluetooth sin cerrar el chat. El peer debe pasar de desconectado a
   reconectando y luego a seguro sin obligar a cerrar y volver a abrir la vista.
   El mensaje pendiente debe enviarse una sola vez.
5. Envíe un mensaje desde el extremo que conservó una sesión Noise anterior.
   HearthBit debe detectar el transporte obsoleto, renegociar Noise y aceptar un
   envío posterior sin mostrar un error de identidad.
6. Repita cerrando y abriendo HearthBit, y después con el perfil de energía
   crítico. La reconexión de un chat conocido debe tener prioridad sobre enlaces
   nuevos y no esperar el ciclo completo de escaneo de ahorro.
7. Mantenga la malla en segundo plano durante cada desconexión. La notificación
   persistente debe cambiar entre «Iniciando malla», «Malla activa · N cercanos»
   y «Error en la malla» según el estado real.
8. Repita con el iPhone fuera de alcance o con Bluetooth apagado durante dos
   horas. Transcurridos más de cuatro minutos, el S25 debe mostrarlo
   desconectado aunque conserve la conversación. Envíe un marcador privado:
   debe persistirse con estado pendiente y no figurar como enviado.
9. Reactive el iPhone sin reabrir el chat. El primer `ANNOUNCE` válido debe
   publicar al peer como alcanzable pero no seguro, iniciar una nueva época
   Noise y, solo después de recuperar `secure`, drenar el mismo ID pendiente
   exactamente una vez. Anuncios posteriores dentro de la ventana no deben
   reiniciar el canal.

Registre por dirección el tiempo desde que Bluetooth vuelve a estar disponible
hasta que el canal aparece seguro, los intentos de handshake, el ID del mensaje
pendiente y el número de entregas. El resultado correcto es una sola entrega,
ningún envío nativo durante el estado desconectado, ningún cierre del chat y
recuperación automática del canal Noise.

## Descubrimiento de BitChat iOS en segundo plano

Este caso valida el anuncio especial de iOS («overflow area»), el keepalive y
la reconexión dirigida. Use un Android HearthBit con una conversación previa y
BitChat en un iPhone; la relación conocida debe existir antes de comenzar.

1. Con ambas apps en primer plano, abra el chat privado y confirme canal seguro
   y un mensaje en cada sentido.
2. Envíe BitChat al segundo plano y bloquee el iPhone. No cierre la app ni
   desactive Bluetooth. Deje ambos teléfonos inmóviles y sin mensajes durante
   diez minutos.
3. Confirme que HearthBit conserva el enlace o que vuelve a detectar al iPhone
   sin abrir BitChat. El primer enlace válido puede registrar
   `iOS overflow candidate ... mask=...` y `Learned iOS overflow service bit`;
   la máscara completa sirve para diagnóstico, pero debe redactarse junto con
   la dirección antes de guardar evidencia.
4. Desactive Bluetooth en el iPhone durante 30 segundos y reactívelo sin abrir
   BitChat. HearthBit debe iniciar un burst de escaneo y mantener una
   reconexión dirigida al peer conocido durante un máximo de 12 minutos.
5. Espere a que el canal vuelva a seguro y envíe un mensaje pendiente. Debe
   entregarse una vez. Repita la espera con HearthBit en segundo plano.
6. Mantenga la malla activa al menos 25 minutos. El log debe incluir como
   máximo un ciclado preventivo cercano a los 20 minutos
   (`Re-arming continuous BLE scans`) y el peer debe seguir recuperable.

**PASS:** el iPhone reaparece sin llevar BitChat a primer plano; el chat vuelve
a seguro, el mensaje pendiente se entrega una vez y no hay tormenta de
conexiones. Un candidato Apple que no expone el servicio debe cerrarse y no
reintentarse por cinco minutos.

**FAIL:** el peer solo aparece al abrir BitChat, el escaneo queda detenido, se
abren conexiones repetidas a dispositivos Apple ajenos, el chat exige borrar
la identidad o el mensaje se pierde/duplica. Si iOS termina BitChat o el usuario
lo cierra desde el selector de apps, registre `BLOCKED`: iOS ya no garantiza
que continúe anunciando el servicio.

## Paquetes v2 con ruta

Con un cliente BitChat que emita versión 2:

1. Envíe un paquete con flag route `0x08`, dos IDs de salto y payload conocido.
2. Confirme que HearthBit conserva los dos IDs al decodificar y volver a
   codificar; el largo del payload no debe incluir el byte de conteo ni la ruta.
3. Repita con recipient, compresión y firma activados.
4. Inyecte una ruta truncada. El paquete debe rechazarse sin cerrar la conexión.
5. Verifique también un paquete v1 normal: sus bytes deben seguir coincidiendo
   con el vector BitChat existente.

## Courier cifrado con ancla Bitle

1. Establezca una sesión Noise entre dos teléfonos y conecte el emisor
   directamente a un ancla con `0xB1 bit0`.
2. Envíe un mensaje privado. El emisor debe completar Noise con el ancla y
   depositar un `CourierEnvelope` `0x04` firmado, dirigido al ID del ancla.
3. En el log del ancla confirme `Envelope deposited`; el TLV `0x03` debe ser el
   paquete Noise cifrado opaco, nunca texto en claro.
4. Desconecte el emisor, conecte el destinatario y anuncie su clave. El ancla
   debe entregar el sobre por la etiqueta HMAC del día y eliminar su copia.
5. Confirme que el destinatario valida la firma del portador, la etiqueta y la
   expiración antes de abrir el paquete Noise, y que copias repetidas no generan
   mensajes duplicados.
6. Repita con etiqueta de otra clave, sobre vencido y ciphertext alterado:
   todos deben descartarse. Pruebe además el cruce de medianoche; se aceptan
   día anterior, actual y siguiente para tolerar desfase de reloj.

El depósito requiere enlace directo, identidad anunciada y sesión Noise con el
ancla. Un relay no verificado o alcanzado solo por varios saltos no debe aceptar
correo.

## Registro de interoperabilidad

### 2026-08-12 — Galaxy S25 ↔ BitChat en iPhone

- Android: Samsung SM-S931B, Android 16 (API 36), HearthBit debug.
- Distancia: teléfonos cercanos, BitChat en primer plano.
- Resultado confirmado por log: conexión GATT, decodificación y validación
  Ed25519 de anuncios BitChat actuales; peers directos y retransmitidos
  aceptados (`ANNOUNCE accepted`, TTL 7 y TTL 6).
- Correcciones necesarias para lograrlo: firma canónica con TTL=0 y padding,
  compresión raw-deflate compatible, TLV de capacidades y serialización de
  escrituras GATT.
- Confirmación visual manual del build actual: `HB_MEGA_1723` llegó de
  HearthBit a BitChat y `BITCHAT_MEGA_1725` llegó de BitChat a HearthBit.
- Tras apagar y reactivar Bluetooth en el iPhone, `HB_RECONNECT_1731` y
  `BITCHAT_RECONNECT_1732` llegaron en ambos sentidos. El log confirmó
  `REQUEST_SYNC` con TTL 0, solicitudes salientes y respuestas que reprodujeron
  uno y dos paquetes ausentes.
- Pendiente con hardware adicional: Noise DM deliberado en ambos sentidos y
  relay físico de dos saltos.

### 2026-08-13 — Build de reconexión en Galaxy S25

- `flutter analyze`, 76 pruebas Flutter y la suite unitaria Android terminaron
  correctamente.
- El APK debug compiló y se instaló por ADB en el Samsung SM-S931B.
- `dumpsys notification` confirmó la notificación persistente real con ID
  `7401`, flag de servicio en primer plano y texto
  `Malla activa · 1 dispositivo cercano`.
- La reconexión Noise privada con BitChat y HearthBit iOS sigue pendiente de la
  ejecución física descrita en «Reconexión de chats privados Noise»; estos
  resultados no se infieren de las pruebas automatizadas.

## Matriz de transferencia de archivos

Pruebe cada celda con un archivo pequeño (~100 KB) y una foto (~3 MB):

| Transporte | Android↔Android | Android↔iPhone | iPhone↔iPhone |
| ---------- | --------------- | -------------- | ------------- |
| Nearby Connections | ✔ requerido | n/a (iOS pendiente) | n/a |
| LAN / hotspot | ✔ requerido | ✔ requerido | ✔ requerido |
| Wi-Fi Aware | ✔ si ambos API 29+ | n/a | n/a |
| BLE inline (≤ 256 KiB) | ✔ requerido | ✔ requerido | ✔ requerido |
| QR óptico | ✔ requerido | ✔ requerido | ✔ requerido |

Escenarios adversos a cubrir en al menos un transporte:

- Pérdida de frames en el modo QR (tape parcialmente la pantalla): la
  transferencia debe alargarse, nunca corromperse.
- Cancelación a mitad desde ambos extremos; verificar que el estado queda
  `cancelada` en ambos y que los archivos parciales se eliminan.
- Fallo de transporte forzado (apagar Wi-Fi durante LAN): debe caer al
  siguiente transporte sin intervención.
- Aplicación en segundo plano durante la transferencia.
- Batería < 15 % y almacenamiento casi lleno en el receptor.
- SOS enviado durante una transferencia grande: los mensajes deben llegar
  sin demora perceptible.

## Radar de proximidad

Con dos teléfonos y la malla activa:

1. Desde una alerta SOS toque «RASTREAR» (o el icono de radar en Cercanos) y
   confirme que aparecen lecturas en menos de 5 s.
2. Camine acercándose y alejándose en línea recta (10-30 m): la tendencia
   debe cambiar a «te estás acercando» / «la señal se está debilitando» en
   pocos segundos, sin parpadear con usted quieto.
3. Verifique la vibración: más rápida e intensa al acercarse.
4. Apague el Bluetooth del objetivo: en ~5 s debe aparecer «señal perdida».
5. Repita con el teléfono objetivo en un bolsillo o bajo una caja (atenúa la
   señal): las bandas de distancia deben degradarse, nunca congelar la UI.
6. Combinaciones requeridas: Android→Android, Android→iPhone (objetivo iOS en
   primer plano y en segundo plano), iPhone→Android.

En Android, el radar o el modo rescate mantienen el escaneo BLE continuo incluso
con batería al 10 % o menos. Esto prioriza el descubrimiento de emergencia, pero
puede acelerar considerablemente la descarga; registre el consumo y conecte el
cargador cuando sea posible. El rol explícito `PHONE_BEACON` conserva su modo de
supervivencia sin escaneo.

### P0-SONAR-NOISE-01 — Escucha acústica con ruido y ecos

Requiere Android e iPhone, cinta métrica y una fuente de música o voz:

1. Conceda micrófono en ambos teléfonos, desconecte auriculares Bluetooth y
   coloque los dispositivos descubiertos a 1, 3, 5 y 10 m.
2. Mida tres veces en silencio y registre distancia, error y confianza.
3. Repita con conversación y música grave a volumen normal junto a uno de los
   teléfonos. Deben completarse al menos dos rondas válidas de cinco intentos,
   sin mostrar distancias fuera del margen declarado.
4. Coloque uno de los teléfonos a 30–50 cm de una pared para provocar eco. El
   eco posterior a la señal local no debe reemplazar la señal remota.
5. Cubra el altavoz local o conecte auriculares Bluetooth. La app debe indicar
   que falta la señal propia, no confundirlo con ruido ambiental.
6. Quite el permiso de micrófono primero al iniciador y luego al receptor. El
   iniciador debe ofrecer abrir ajustes; cuando falla el receptor, el otro
   teléfono debe informar que el permiso remoto no fue concedido.
7. Repita con una versión anterior en un extremo. La sesión debe iniciar por el
   fallback de 1,5 s aunque no reciba `acousticReady`.

Criterio P0: ninguna ejecución puede producir una distancia válida a partir de
un eco, ni quedar activa más de 25 s. Compare tasa de éxito, error absoluto y
confianza con la compilación anterior.

## Evidencia a registrar

- Modelos y versiones de Android/iOS.
- Distancia aproximada y obstáculos.
- Hora de envío y recepción.
- Estado foreground/background de cada app.
- Porcentaje de batería antes y después de una hora.

## Prueba automatizada

`MeshProtocolTest` congela las cabeceras binarias v1/v2, rutas, compresión, la
forma canónica de firma, GCS y Courier, además del parseo tolerante de anuncios
usados por BitChat. La prueba de ANNOUNCE también garantiza que HearthBit no
vuelva a emitir el TLV privado `0xF0`.
Ejecútela con:

```powershell
cd app\android
$env:JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"
.\gradlew.bat :app:testDebugUnitTest
```

Esta prueba detecta cambios incompatibles en bytes, pero no reemplaza la matriz
de tres dispositivos.
