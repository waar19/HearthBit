# Perfil compatible con BitChat

Este archivo es un resumen no normativo. La especificación fijada al commit
exacto del submódulo está en
[Perfil núcleo BitChat](bitchat-core-profile.md); las asignaciones propias y
sus reglas de negociación están en el
[Registro de extensiones HearthBit](extension-registry.md). En caso de
conflicto, prevalecen esos dos documentos.

HearthBit usa el UUID principal de BitChat:

- Servicio: `F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C`
- Característica: `A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D`

La característica acepta `write`, `write without response` y `notify`.

## Descubrimiento privado e interoperabilidad

El modo privado es el valor predeterminado. Android sustituye el peer ID del
scan response por `0xA5 || token`, donde `token` son los primeros 8 octetos de
`HMAC-SHA256(noisePrivateKey, floor(unixMillis / 15 minutos))`. El receptor
trata este valor solo como pista para conectar: no crea identidad, confianza ni
estado de radar. iOS no añade identidad al anuncio.

Los `ANNOUNCE` ordinarios usan TTL 1 en modo privado. Al emitir un SOS o
check-in público, el emisor envía inmediatamente antes un `ANNOUNCE` firmado
con TTL completo y el TLV `EMERGENCY_PREANNOUNCE` (`type=0xF1`, longitud
`0x01`, valor exacto `0x01`). Esto se hace tanto en modo público como privado.
La interoperabilidad BitChat opt-in restaura el peer ID estático y el TTL
completo de los anuncios ordinarios, pero no les añade el marcador.

### Política de reloj para `ANNOUNCE`

Android e iOS aceptan normalmente un `ANNOUNCE` solo si su timestamp está
dentro de ±10 minutos del reloj local. Como excepción de disponibilidad para
víctimas con el reloj atrasado, un `ANNOUNCE` cuya firma ya fue verificada y
cuyo payload contiene el marcador exacto `EMERGENCY_PREANNOUNCE` puede tener
hasta 24 horas de antigüedad. Esta excepción no amplía el futuro: incluso con
el marcador, un anuncio adelantado más de 10 minutos se rechaza.

El TTL se normaliza a cero para firmar y puede ser alterado por relés. Por
tanto, nunca decide ni amplía la ventana de reloj: cambiar un TTL firmado como
1 a 7 conserva la firma, pero el anuncio sigue sujeto a 10 minutos si no lleva
el marcador firmado.

El relay de infraestructura no aplica la excepción de emergencia: exige
siempre ±10 minutos, tanto para anuncios atrasados como adelantados. Las
implementaciones comparan límites de tiempo sin valor absoluto ni aritmética
que pueda desbordar los enteros de timestamp.

Antes de compartir identidad en un enlace GATT privado, HearthBit intercambia
la secuencia de transporte ASCII `HB-LINK1`. No es un paquete mesh, no se
reenvía y no contiene identidad. Un enlace se considera HearthBit si presentó
el token rotatorio `0xA5`, esa secuencia, un `ANNOUNCE` directo con TLV `0xF0`
o un `HBT_CAPABILITY` directo cuya firma se verificó con el anuncio previo.
Esta prueba evita que un cliente BitChat normal reciba nuestros `ANNOUNCE` y
paquetes de capacidades, pero no autentica al software remoto.

Con interoperabilidad desactivada, un `MESSAGE` firmado por un peer aún no
verificado como HearthBit se reenvía según el TTL, pero no se entrega a la UI.
La excepción es un SOS público: se entrega con `external=true` para mostrar la
insignia «red externa». El peer permanece visible como presencia externa sin
chat. El `ANNOUNCE` de alcance completo previo al SOS también conserva su
excepción de envío a enlaces no probados.

## Matriz de transportes e interoperabilidad

HearthBit mantiene el frame binario y su criptografía separados del medio de
radio. Un transporte externo mueve bytes opacos: no puede eliminar firmas,
terminar Noise ni reinterpretar identidades.

- **BLE/BitChat:** transporte base disponible en Android e iOS. En modo privado
  usa el token rotatorio y la prueba `HB-LINK1` descritos arriba.
- **Wi-Fi Aware (archivos):** transporte de archivos grandes negociado dentro de una
  sesión Noise ya autenticada. Android requiere API 29 para el data path con
  puerto. El `transferId` no se anuncia: se derivan con SHA-256 y dominios
  distintos un token de descubrimiento de 16 bytes y una passphrase WPA3. Si
  Aware no está disponible, el selector cae a Nearby, LAN, BLE u óptico. iOS
  26 requiere emparejamiento del sistema y permanece deshabilitado hasta pasar
  los gates en Xcode y hardware real.
- **Wi-Fi Aware (SOS):** en Android 8+ con hardware NAN, el servicio
  `hearthbit-mesh` publica y suscribe a la vez. `ANNOUNCE` de emergencia y
  `MESSAGE` SOS de hasta 255 bytes viajan como mensajes follow-up, sin data
  path. El motor vuelve a validar identidad, firma, reloj y dedupe.
- **Wi-Fi Direct:** Android descubre `_hearthbit._tcp` por DNS-SD. En rescate
  crea un Group Owner autónomo si no encuentra peers; también se activa cuando
  el advertising BLE falla. El canal público TCP usa el HELLO `HBEM` y solo
  acepta frames públicos firmados de emergencia, con límite de 30/minuto.
- **MultipeerConnectivity:** iOS anuncia y busca `hearthbit-sos` únicamente en
  primer plano durante rescate o radar. La sesión exige cifrado de Apple y
  mueve frames opacos; las firmas HearthBit siguen siendo la autoridad.
- **Audio SOS:** 4-FSK a 15,5/16,5/17,5/18,5 kHz, 48 kHz y símbolos de 8 ms.
  Un preámbulo de 20 símbolos precede `length u16 | frame | CRC32`. El frame
  máximo es 320 bytes. La baliza alterna el `ANNOUNCE` de emergencia y el
  `MESSAGE` firmados; el receptor solo los inyecta por el ingreso público.
- **Meshtastic:** integración Android opt-in con la Device API BLE oficial
  (`6ba1b218-15a8-461f-9fa8-5dcae273eafd`). Los frames HearthBit fragmentados
  caben en payloads de hasta 180 bytes y viajan en `PortNum.PRIVATE_APP` (256).
  Meshtastic aporta radio LoRa y cifrado de canal; las firmas y sesiones
  HearthBit siguen siendo la autoridad extremo a extremo. No se escanea ni se
  conecta a un radio Meshtastic hasta que la persona activa el control.
- **Reticulum/LXMF:** enlace opcional entre relays. LXMF cifra el transporte y
  solo acepta hashes de destino y origen configurados explícitamente. Los
  mensajes públicos HearthBit deben conservar una firma válida y una prueba de
  identidad; los privados no salen de la malla local. Una ruta de bridges fuera
  del frame corta bucles y las coordenadas de emergencia se bloquean por defecto.
- **Ancla Bitle LoRa:** `LONG_RANGE_TRUNK` (`0x10`) solo se anuncia cuando el
  troncal está operativo. La validación física `D1-LORA-01` sigue siendo
  obligatoria antes de afirmar alcance entre barrios.

## Paquete v1

Los enteros usan orden big-endian.

1. Versión: 1 byte (`0x01`)
2. Tipo: 1 byte
3. TTL: 1 byte
4. Timestamp Unix en milisegundos: 8 bytes
5. Flags: 1 byte
6. Longitud de payload: 2 bytes
7. Sender ID: 8 bytes
8. Recipient ID: 8 bytes, si `flags & 0x01`
9. Payload
10. Firma Ed25519: 64 bytes, si `flags & 0x02`

### Simulacro autenticado

El bit reservado `flags & 0x20` es `DRILL`. Forma parte de los bytes
canónicos firmados (a diferencia de TTL y RSR) y solo es válido en paquetes
v1 públicos `ANNOUNCE` (`0x01`) y `MESSAGE` (`0x02`). Un frame `DRILL` debe:

- llevar firma Ed25519 (`flags & 0x02`), sin destinatario, ruta ni compresión;
- usar en `ANNOUNCE` el TLV exacto `EMERGENCY_PREANNOUNCE`
  (`F1 01 01`), únicamente para transportar la prueba de identidad;
- usar en `MESSAGE` el marcador versionado
  `[HB-DRILL|1|CHECKIN|<OK|HELP|INJURED>|<unixMillis>]`;
- no contener `SOS|` ni `[HB-CHECKIN|`.

El `ANNOUNCE` y `MESSAGE` de un bundle QR/audio deben tener el mismo sender ID
y el mismo valor de `DRILL`. Una firma ausente, un marcador de simulacro sin
flag, un flag sin marcador, versiones futuras o cualquier mezcla entre
simulacro y emergencia real se rechazan (`fail closed`). Los frames v1 reales
sin `0x20` conservan exactamente su semántica anterior.

Un simulacro puede retransmitirse por la malla, QR y audio, pero nunca recibe
prioridad SOS, consentimiento radar, acuse de emergencia, store-forward de
emergencia, Wi-Fi Direct/Aware de emergencia, gateway LAN/Internet,
Matrix/MQTT/Reticulum ni escalado por portadoras. La UI lo publica siempre en
el canal `drill` con la etiqueta «SIMULACRO — NO ES UNA EMERGENCIA».

Tipos implementados:

- `0x01`: anuncio de identidad TLV
- `0x02`: mensaje público
- `0x10`: handshake Noise XX
- `0x11`: transporte Noise cifrado
- `0x20`: fragmento
- `0x21`: solicitud de sincronización
- `0x23`: consentimiento temporal del radar
- `0x24`: prekey Bitle; recepción temporal de capacidad HBT heredada
- `0x25`: capacidad y rol de nodo HearthBit
- `0x26`: control dirigido de baliza física
- `0x27`: control dirigido de ranging
- `0x28`: capacidad de acuse de emergencia
- `0x29`: voz BitChat; recepción temporal de acuse de emergencia heredado
- `0x2A`: capacidad HBT
- `0x2B`: acuse de emergencia dirigido

HearthBit solo emite `HBT_CAPABILITY` como `0x2A` y `EMERGENCY_ACK` como
`0x2B`. La recepción heredada en `0x24`/`0x29` exige validar estructura,
firma, identidad anunciada y, para el acuse, destinatario local; el byte por sí
solo es ambiguo con `PREKEY_BUNDLE`/`VOICE_FRAME`.

Los tamaños se normalizan a 256, 512, 1024 o 2048 bytes mediante padding
PKCS#7 cuando la diferencia cabe en un byte.

## Seguridad

Las firmas se calculan sobre el paquete sin firma y con TTL igual a cero. Así
los relés pueden reducir TTL sin invalidar la firma. Un anuncio se acepta solo
si su clave Noise produce el sender ID y su propia clave Ed25519 valida la
firma.

Los chats privados usan `Noise_XX_25519_ChaChaPoly_SHA256`. El payload de
transporte antepone un nonce UInt32 big-endian al ciphertext. El contenido
privado empieza con tipo `0x01` y contiene TLV `0x00` para ID y `0x01` para
texto.

La fuente normativa fijada para interoperabilidad está en
`vendor/bitchat-android`.

## Protocolo de dos niveles

HearthBit distingue deliberadamente:

1. **Nivel de presencia**: un escáner puede detectar un anuncio BLE genérico.
   Solo significa «hay una señal cerca»; no demuestra identidad, no crea un
   peer y no habilita chat.
2. **Nivel de malla autenticada**: requiere un `ANNOUNCE` válido, la
   vinculación del sender ID con la clave Noise y una firma Ed25519 válida.
   Solo este nivel permite mensajes, Noise, radar consentido o transferencias.

Una detección de nivel 1 nunca se promociona automáticamente al nivel 2,
aunque ambos anuncios parezcan proceder del mismo dispositivo.

## Roles y política de relay

El rol local y el de los peers HearthBit usan uno de estos valores:

- `PHONE_RELAY`: teléfono interactivo; origina chat, retransmite y conserva
  temporalmente paquetes dirigidos para compatibilidad store-and-forward.
- `PHONE_BEACON`: presencia solamente; no origina chat, no retransmite y no
  conserva tráfico dirigido. Android además detiene el plano GATT y anuncia
  de forma no conectable; iOS aplica la política de datos, pero deja a
  CoreBluetooth controlar la conectabilidad física.
- `INFRA_RELAY`: infraestructura de tránsito; no origina chat, retransmite y
  no conserva paquetes.
- `INFRA_DATA_ANCHOR`: infraestructura con datos; no origina chat,
  retransmite y conserva tráfico dirigido.

Todo relay exige TTL mayor que 1 y lo decrementa antes del envío. Un paquete
Noise dirigido al nodo local se consume y no se retransmite; si va dirigido a
otro nodo sí puede retransmitirse. Los demás paquetes públicos siguen la
política del rol. La deduplicación continúa usando el hash canónico sin TTL.
El caché persistente no conserva handshakes ni transportes Noise crudos porque
quedan ligados a una generación de claves y serían indescifrables después de
renegociar. La entrega privada diferida usa la cola persistente del emisor o un
`CourierEnvelope`, que mantiene el ciphertext dentro de su sobre firmado.

El SOS abierto conserva el formato `SOS|texto|latitud|longitud`. Campos vacíos
significan «sin GPS»; el modo aproximado redondea ambas coordenadas a tres
decimales antes de firmar. Un check-in del círculo usa el marcador
`[HB-CHECKIN|...]` dentro de un mensaje Noise privado dirigido por separado a
cada familiar verificado; no usa el canal público.

Un SOS válido concede una ventana derivada de consentimiento radar de 30
minutos desde el timestamp del paquete, sin superar 30 minutos desde el reloj
receptor. La suma de ambas cotas **MUST** saturar en el máximo representable y
nunca desbordar. Mientras Modo Rescate siga activo, cada ping renueva también
el grant local por 30 minutos antes de emitir el SOS. El consentimiento manual
de la UI permanece separado y dura 15 minutos.

## Control y reporte RSSI del radar (`0x23`)

Los controles de consentimiento tienen 26 bytes: versión `0x01`, acción
`GRANT=0x01` o `REVOKE=0x02`, expiración Unix de 8 bytes y nonce aleatorio de
16 bytes. Se firman con la identidad Ed25519 del emisor.

`RSSI_REPORT=0x03` permite que el dispositivo que otorgó consentimiento mida
el enlace desde su lado. Su payload de 27 bytes contiene:

1. Versión `0x01`.
2. Acción `0x03`.
3. RSSI con signo de 8 bits, dentro de `-127...20`.
4. Momento de medición Unix en milisegundos, 8 bytes big-endian.
5. Nonce aleatorio de 16 bytes.

El reporte **MUST** ir firmado, dirigido al peer receptor, con TTL 0, por un
enlace directo y sin store-and-forward. El receptor solo lo publica como
`rssi(remote=true)` cuando el emisor es el objetivo activo del radar, su
consentimiento sigue vigente y tanto el timestamp del paquete como el de la
medición están dentro de la tolerancia de reloj de dos minutos. iOS intenta
muestrear una vez por segundo los periféricos conectados mientras su
consentimiento local está vigente.

## Paquete dedicado de capacidad de nodo (`0x25`)

Payload firmado:

1. Versión: `0x01`.
2. Rol: `0x01` `PHONE_RELAY`, `0x02` `PHONE_BEACON`, `0x03`
   `INFRA_RELAY`, `0x04` `INFRA_DATA_ANCHOR`.
3. Flags informativos: bit 0 relay, bit 1 origina chat, bit 2
   store-and-forward, bit 3 presencia solamente.

El receptor solo aplica el rol después de haber aceptado el `ANNOUNCE` del
sender y verificar este paquete con la clave Ed25519 ya vinculada. Un BitChat
que desconoce `0x25` lo descarta como tipo no manejado; no altera su estado de
identidad ni el flujo de chat.

### Decisión de compatibilidad sobre `ANNOUNCE`

Los anuncios ordinarios mantienen el perfil conocido (`0x01`, `0x02`, `0x03`
y `0x05`) y las capacidades generales siguen en paquetes dedicados
`0x2A`/`0x25`. Solo el anuncio inmediatamente anterior a una emergencia añade
`0xF1`.

El tradeoff es deliberado: clientes antiguos con un decoder intolerante a TLV
desconocidos pueden ignorar ese anuncio y perder la autenticación del SOS a
varios saltos. Los clientes compatibles ignoran TLV desconocidos; HearthBit
solo concede la ventana de 24 horas después de decodificar el valor exacto y
verificar la firma. Así se evita que el TTL mutable abra la excepción para
tráfico ordinario, a costa de compatibilidad con builds antiguos defectuosos.

## Baliza física dirigida (`0x26`)

`0x25` sigue siendo `NODE_CAPABILITY`. `BEACON_CONTROL` usa `0x26`, siempre con
`recipientId`, firma Ed25519 y TTL inicial 2. Un relay puede reenviarlo
exactamente una vez, solo cuando no es el destinatario local, decrementando el
TTL a 1 y conservando `recipientId`, payload, firma y nonce. TTL 0 o mayor que
2 es inválido. El payload v1 fijo contiene acción
`REQUEST`, `GRANT`, `REVOKE` o `STOP`, expiración Unix ms, nonce aleatorio de
16 bytes y flags de flash, sonido y vibración. Una solicitud o concesión no
puede durar más de 5 minutos.

El receptor valida longitud exacta, versión, acción, flags, timestamp,
expiración, TTL 1 o 2 y firma contra el peer previamente anunciado. La trama
nunca entra en store-forward ni sincronización GCS. `REQUEST` no enciende
hardware por sí solo: la actuación requiere un `GRANT` local producido por la
aceptación manual o por la política de autoaceptación ya autorizada. Un relay
que no sea destinatario solo reenvía y nunca aplica el control. En iOS la
actuación se detiene al pasar la app a segundo plano; no se declara audio de
fondo.

La autoaceptación exige simultáneamente modo rescate o consentimiento de radar
activo, identidad HearthBit verificada y una relación segura previa con el
solicitante. Una firma válida por sí sola no autoriza flash, sonido ni
vibración.

## SOS óptico por QR

`HEARTHBIT-SOS:1` encapsula dos frames v2 sin padding: un `ANNOUNCE` firmado con
el marcador de preanuncio de emergencia y el `MESSAGE` SOS firmado. El texto
visible después de la primera línea forma parte del contenedor binario y debe
coincidir byte a byte; así una cámara genérica puede mostrar descripción,
coordenadas e ID aunque no tenga HearthBit.

El receptor solicita confirmación antes de inyectar. Android e iOS decodifican
ambos frames, exigen el mismo remitente y un payload de emergencia, y después
los entregan en orden al ingreso normal de la malla. Ese ingreso vuelve a
validar identidad autofirmada, firma del mensaje, reloj, deduplicación y límites
de flood. El SOS queda disponible para store-forward y puede viajar físicamente
en el teléfono del rescatista hasta encontrar otro enlace.

## Privacidad de balizas BLE genéricas en Android

- El escáner de presencia no lee ni transmite a Flutter el nombre Bluetooth
  ni la dirección MAC.
- Solo normaliza datos de servicio, solicitud de servicio y fabricante. Un
  anuncio sin ese material se ignora porque no puede agruparse de forma
  privada.
- El identificador mostrado al modelo es un HMAC local con una clave aleatoria
  creada en memoria. Rota cada 15 minutos y cambia al reiniciar el proceso.
- Las observaciones expiran tras 45 segundos y no se escriben en SQLite ni en
  logs. Flutter recibe `chatAvailable: false`, rol `PHONE_BEACON`, RSSI y la
  hora de última detección.

Estos IDs solo sirven para deduplicar la UI a corto plazo; no son identidad,
no son estables entre sesiones y no deben incorporarse a telemetría.
