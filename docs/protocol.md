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

Los `ANNOUNCE` ordinarios usan TTL 1 en modo privado. Al emitir un SOS público,
el emisor envía primero un `ANNOUNCE` con TTL completo; es necesario para que
los saltos posteriores autentiquen el mensaje. La interoperabilidad BitChat
opt-in restaura el peer ID estático y el TTL completo de los anuncios.

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

Tipos implementados:

- `0x01`: anuncio de identidad TLV
- `0x02`: mensaje público
- `0x10`: handshake Noise XX
- `0x11`: transporte Noise cifrado
- `0x20`: fragmento
- `0x21`: solicitud de sincronización
- `0x23`: consentimiento temporal del radar
- `0x24`: capacidad HBT
- `0x25`: capacidad y rol de nodo HearthBit
- `0x26`: control dirigido de baliza física

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

No se añadió un TLV HearthBit al `ANNOUNCE`. El decoder del submódulo BitChat
actual sí conserva TLV desconocidos, pero existieron builds con la regresión
que rechazaba o reconstruía incorrectamente extensiones desconocidas. Por
tanto, que el código fijado hoy sea tolerante no prueba seguridad para toda la
flota interoperable.

HearthBit mantiene el `ANNOUNCE` en el perfil conocido (`0x01`, `0x02`,
`0x03` y el `0x05` estándar sin capacidades HearthBit) y usa paquetes
dedicados `0x24`/`0x25`. Esto reduce el fallo de un cliente antiguo a ignorar
una capacidad opcional, en vez de perder el anuncio de identidad completo.

## Baliza física dirigida (`0x26`)

`0x25` sigue siendo `NODE_CAPABILITY`. `BEACON_CONTROL` usa `0x26`, siempre con
`recipientId`, firma Ed25519 y TTL 1. El payload v1 fijo contiene acción
`REQUEST`, `GRANT`, `REVOKE` o `STOP`, expiración Unix ms, nonce aleatorio de
16 bytes y flags de flash, sonido y vibración. Una solicitud o concesión no
puede durar más de 5 minutos.

El receptor valida longitud exacta, versión, acción, flags, timestamp,
expiración y firma contra el peer previamente anunciado. La trama nunca entra
en store-forward, sincronización ni relay. `REQUEST` no enciende hardware y
siempre requiere aceptación explícita. El modo rescate y el consentimiento
temporal de radar autorizan medición, no el control remoto de flash, sonido o
vibración. En iOS la actuación se detiene al pasar la app a segundo plano; no
se declara audio de fondo.

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
