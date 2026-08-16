# HearthBit Transfer Protocol (HBT) v1

Protocolo de control y datos para transferir archivos entre nodos HearthBit.
El plano de control viaja por la malla BLE dentro de la sesión Noise ya
autenticada (tipo interno `0x30`), y el plano de datos usa el transporte
negociado (BLE, LAN/hotspot, Nearby Connections, Wi‑Fi Aware, Wi‑Fi Direct,
MultipeerConnectivity, intercambio externo u óptico).

Los UUID BLE, los tipos de paquete de malla y el handshake Noise XX no
cambian: siguen siendo los de BitChat.

## Marco de trama

Todas las cifras van en big-endian.

```
byte 0        versión (0x01)
byte 1        tipo de trama
bytes 2..n    secuencia de campos TLV
TLV = [tag u8][longitud u16][valor]
```

Un decodificador debe ignorar tags desconocidos (permite extensión) y
rechazar tramas con versión distinta de `0x01`.

### Tipos de trama

| Tipo | Nombre           | Dirección            | Contenido obligatorio |
|------|------------------|----------------------|------------------------|
| 0x01 | OFFER            | emisor → receptor    | TRANSFER_ID, FILE_NAME, MIME_TYPE, FILE_SIZE, SHA256, CHUNK_SIZE, TRANSPORTS, EPHEMERAL_KEY, EXPIRES_AT, SENDER_PEER_ID, SIGNATURE |
| 0x02 | ACCEPT           | receptor → emisor    | TRANSFER_ID, EPHEMERAL_KEY, TRANSPORT; opcional CHUNK_BITMAP para reanudar |
| 0x03 | REJECT           | receptor → emisor    | TRANSFER_ID; opcional REASON |
| 0x04 | TRANSPORT_HINT   | emisor → receptor    | TRANSFER_ID, TRANSPORT; opcional ENDPOINT, TOKEN |
| 0x05 | PROGRESS         | receptor → emisor    | TRANSFER_ID, RECEIVED_COUNT |
| 0x06 | COMPLETE         | receptor → emisor    | TRANSFER_ID |
| 0x07 | CANCEL           | cualquiera           | TRANSFER_ID; opcional REASON |
| 0x08 | RESUME_REQUEST   | receptor → emisor    | TRANSFER_ID, CHUNK_BITMAP |
| 0x10 | DATA_CHUNK       | emisor → receptor    | TRANSFER_ID, CHUNK_INDEX, CHUNK_DATA (solo transporte BLE) |
| 0x11 | DATA_ACK         | receptor → emisor    | TRANSFER_ID, CHUNK_INDEX (ventana BLE) |

### Tags TLV

| Tag  | Nombre          | Formato |
|------|-----------------|---------|
| 0x01 | TRANSFER_ID     | 16 bytes aleatorios |
| 0x02 | FILE_NAME       | UTF-8 saneado (sin separadores de ruta ni control, máx. 255 bytes) |
| 0x03 | MIME_TYPE       | UTF-8 |
| 0x04 | FILE_SIZE       | u64, bytes del archivo en claro |
| 0x05 | SHA256          | 32 bytes, hash del archivo en claro |
| 0x06 | CHUNK_SIZE      | u32, bytes de cada chunk en claro |
| 0x07 | TRANSPORTS      | u32, máscara: 1 BLE, 2 LAN, 4 NEARBY, 8 WIFI_AWARE, 16 OPTICAL, 32 WIFI_DIRECT, 64 MULTIPEER, 128 EXTERNAL |
| 0x08 | EPHEMERAL_KEY   | 32 bytes, clave pública X25519 efímera |
| 0x09 | EXPIRES_AT      | u64, epoch ms; la oferta caduca y se descarta |
| 0x0A | SENDER_PEER_ID  | 8 bytes, peer ID BitChat del emisor |
| 0x0B | SIGNATURE       | 64 bytes, Ed25519 |
| 0x0C | TRANSPORT       | u8: 0 BLE, 1 LAN, 2 NEARBY, 3 WIFI_AWARE, 4 OPTICAL, 5 WIFI_DIRECT, 6 MULTIPEER, 7 EXTERNAL |
| 0x0D | ENDPOINT        | UTF-8 `ip:puerto` (LAN/Wi‑Fi Aware) |
| 0x0E | TOKEN           | 16 bytes, token de conexión de un solo uso |
| 0x0F | CHUNK_INDEX     | u32 |
| 0x10 | CHUNK_DATA      | bytes cifrados (AEAD, ver abajo) |
| 0x11 | CHUNK_BITMAP    | bit por chunk, LSB primero dentro de cada byte |
| 0x12 | REASON          | UTF-8 |
| 0x14 | RECEIVED_COUNT  | u32 |

## Firma de la oferta

`SIGNATURE = Ed25519(identidad_del_emisor, versión ‖ tipo ‖ TLVs)` donde los
TLVs se serializan en el orden de codificación **excluyendo** el propio TLV
SIGNATURE. El receptor verifica con la clave de firma anunciada por el peer
en la malla (`announce`). Aunque el canal Noise ya autentica al peer, la
firma permite validar ofertas reenviadas o mostradas fuera de línea (p. ej.
boletines ópticos públicos).

## Cifrado del contenido

Independiente del transporte (Nearby y LAN ya cifran, pero el contenido va
además cifrado de extremo a extremo con las claves efímeras de la oferta):

```
secreto  = X25519(efímera_emisor, efímera_receptor)
material = HKDF-SHA256(ikm=secreto, salt=TRANSFER_ID, info="hearthbit/transfer/v1", 52 bytes)
clave    = material[0..31]
prefijo  = material[32..51]        (20 bytes)
nonce_i  = prefijo ‖ CHUNK_INDEX u32   (24 bytes, XChaCha20-Poly1305)
cifrado_i = XChaCha20-Poly1305(clave, nonce_i, aad=TRANSFER_ID, chunk_i)
```

El receptor verifica el SHA-256 del archivo completo tras descifrar todos
los chunks; si no coincide, la transferencia se marca fallida y se borra.

### Contenedor cifrado (LAN, Nearby, óptico)

Para transportes de flujo o archivo, los chunks cifrados se serializan como:

```
repetido: [CHUNK_INDEX u32][longitud u32][cifrado_i]
```

Esto permite reanudar por chunk y transferir el contenedor como archivo
opaco (Nearby FILE payload) o como flujo TCP (LAN).

### Wi-Fi Direct y MultipeerConnectivity

- Android anuncia `_hearthbit-hbt._tcp` por DNS-SD de Wi-Fi Direct. El nombre
  contiene un token SHA-256 derivado del `TRANSFER_ID`; tras formar el grupo,
  un socket TCP en el puerto 45896 autentica ese token y mueve el contenedor.
- iOS anuncia `hearthbit-hbt` con `MCNearbyServiceAdvertiser`. El token
  derivado se incluye en `discoveryInfo` y `MCSession` exige cifrado. El
  contenedor se entrega con `sendResource`.
- Ambos son planos de datos: OFFER, ACCEPT, fallback y COMPLETE siguen
  viajando por la sesión Noise.

## Paquetes `.hbt` externos

Android registra `application/x-hearthbit` para `ACTION_VIEW`/`ACTION_SEND`;
iOS registra el UTI `com.hearthbit.hbt`. Hay dos formatos:

### HBTX v1: contenedor de una sesión

```
[magic "HBTX"][versión u8][TRANSFER_ID 16B][payloadLen u64][contenedor .enc]
```

HBTX no incluye claves. El receptor debe haber aceptado previamente la oferta
con `TRANSPORT=7`; solo entonces conserva la efímera local necesaria para
derivar la clave. Quick Share, AirDrop o cualquier otra app transportan bytes
opacos. Al importar, HearthBit casa `TRANSFER_ID`, descifra y verifica SHA-256.

### HBTS v1: paquete sellado autocontenido

```
[magic "HBTS"][versión u8][packageId 16B]
[senderPeerId 8B][recipientPeerId 8B][ephemeralX25519 32B]
[fileSize u64][chunkSize u32][sha256 32B]
[nameLen u16][name][mimeLen u16][mime]
[signature Ed25519 64B]
repetido: [chunkIndex u32][cipherLen u32][ciphertext+MAC]
```

El emisor deriva `X25519(efímera, estática_del_destinatario)` y aplica
HKDF-SHA256 con `salt=packageId`, `info="hearthbit/sealed/v1"`. La cabecera
anterior a `signature` queda firmada con la identidad Ed25519 del emisor. El
receptor exige que `recipientPeerId` sea su identidad, valida la firma contra
el pin persistente del contacto, muestra el remitente antes de guardar,
descifra con su estática X25519 y verifica el SHA-256 final. El paquete puede
viajar sin una sesión de malla activa y solo el destinatario puede abrirlo.

## Negociación de transporte

1. El emisor manda OFFER por BLE con la máscara TRANSPORTS que soporta.
2. El receptor responde ACCEPT con el TRANSPORT elegido (el mejor de la
   intersección, orden de preferencia: LAN > NEARBY > WIFI_AWARE >
   WIFI_DIRECT > MULTIPEER > BLE) y su clave efímera. Si tiene chunks
   previos, adjunta CHUNK_BITMAP. EXTERNAL y OPTICAL se eligen manualmente.
3. Para LAN, el emisor abre un socket TCP y envía TRANSPORT_HINT con
   ENDPOINT y TOKEN; el receptor se conecta, envía el TOKEN y su bitmap, y
   el emisor transmite los chunks que falten.
4. Si el transporte falla, cualquiera de los dos envía TRANSPORT_HINT con el
   siguiente transporte de la lista y se reintenta. BLE es el último recurso
   automático para archivos ≤ 256 KiB; los modos EXTERNAL y OPTICAL se
   eligen manualmente.

## Límites y política

- Tamaño máximo por archivo: 512 MiB (LAN/Nearby), 256 KiB (BLE inline),
  8 MiB recomendado en modo óptico.
- CHUNK_SIZE por defecto: 65 536 bytes (LAN/Nearby/óptico), 350 bytes (BLE).
- Caducidad de oferta por defecto: 10 minutos.
- Cuota de recepción: máximo 1 GiB por hora y espacio libre mínimo del 10 %.
- Los blobs nunca entran al store-and-forward de mensajes de la malla; solo
  las tramas de control (≤ 512 bytes) pueden almacenarse y reenviarse.
- Prioridad SOS: mientras haya un SOS saliente reciente (< 20 s) los
  transportes de datos pausan o reducen su ritmo.

## Transporte por la malla BLE

Las tramas HBT viajan como payload interno de la sesión Noise con tipo
`0x30` (`NOISE_TRANSFER_FRAME`), nunca en claro. Los relés de malla no
reenvían tramas de datos (`0x10`/`0x11`), solo el par conectado las procesa.

## Modo óptico (HBQ v1)

El modo óptico transfiere archivos mediante una secuencia de códigos QR sin
usar ninguna radio. Cada QR contiene un símbolo en base64 con este marco:

```
[magic "HBQ" 3B][versión u8 = 0x01][tipo u8][transferId 16B][cuerpo...]
```

| Tipo | Nombre | Cuerpo |
| ---- | ------ | ------ |
| 0x00 | HEADER | `seed u32`, `fileSize u64`, `chunkSize u16`, `chunkCount u32`, `sha256 32B`, `nameLen u8 + nombre UTF-8`, `peerLen u8 + peer ID ASCII` |
| 0x01 | DATA   | `symbolIndex u32`, payload de `chunkSize` bytes |

- Los símbolos de datos son **códigos fountain LT** (distribución robust
  soliton, `c=0.03`, `δ=0.5`) generados con un PRNG xorshift32 sembrado con
  `seed ^ (symbolIndex · 0x9e3779b1)`. Emisor y receptor derivan el mismo
  conjunto de chunks XOR para cada índice, por lo que el flujo es rateless:
  la pérdida de frames solo alarga la transferencia, nunca la corrompe.
- La cabecera se remite cada 8 frames para que el receptor pueda engancharse
  en cualquier momento. Cambiar densidad o velocidad regenera `transferId`.
- El receptor verifica el SHA-256 completo antes de guardar el archivo.
- **Backchannel BLE opcional:** si la cabecera incluye el peer ID de malla
  del emisor y existe sesión Noise entre ambos, el receptor envía una trama
  HBT `COMPLETE` con el mismo `transferId` y el emisor se detiene al
  instante. Sin radio, el emisor sigue generando símbolos indefinidamente.
- RaptorQ (RFC 6330) sobre un núcleo Rust FFI queda planificado como mejora
  de eficiencia; el códec LT actual en Dart es el formato v1 de referencia.

## Vectores golden

Los tests de Dart (`app/test/transfer_protocol_test.dart`) y Kotlin
(`TransferProtocolTest.kt`) codifican la misma oferta y el mismo chunk de
ejemplo y comprueban el hex byte a byte; el codec Swift usa la misma
serialización. Cualquier cambio de formato debe actualizar los tres.
El códec óptico HBQ se prueba en `app/test/fountain_code_test.dart`.
