# Perfil núcleo BitChat para HearthBit

## 1. Estado, alcance y fuente fijada

Este documento es la especificación normativa autosuficiente del perfil binario
que HearthBit usa para interoperar con BitChat. Las palabras **MUST**, **MUST
NOT**, **SHOULD**, **SHOULD NOT** y **MAY** se interpretan según RFC 2119.

La referencia confirmada es el submódulo:

- Repositorio: `https://github.com/permissionlesstech/bitchat-android.git`
- Commit exacto:
  [`5156f7de89ec9f6a3429630d90f709b68f6fd7fd`](https://github.com/permissionlesstech/bitchat-android/commit/5156f7de89ec9f6a3429630d90f709b68f6fd7fd)
- Ruta local: `vendor/bitchat-android`

El commit se obtuvo con `git submodule status`, `git ls-tree HEAD
vendor/bitchat-android` y `git -C vendor/bitchat-android rev-parse HEAD`. Toda
afirmación marcada **[BC]** está confirmada por ese árbol exacto. Una afirmación
marcada **[HB]** describe una extensión o una política de HearthBit y **MUST
NOT** presentarse como capacidad de BitChat upstream.

Este perfil fija bytes en la malla BLE, autenticación, relay y sincronización.
No declara interoperabilidad con otro commit, con una versión futura ni con
clientes históricos no ensayados. Una implementación **MUST** superar la matriz
física de `docs/field-test.md` antes de anunciar compatibilidad.

## 2. Convenciones

- Todos los enteros multibyte **MUST** codificarse en big-endian, salvo el
  bitfield de capacidades de `ANNOUNCE`, que es little-endian.
- Un `peer ID` de malla **MUST** ocupar 8 octetos. Su representación textual
  canónica son 16 dígitos hexadecimales minúsculos.
- `timestamp` es tiempo Unix en milisegundos, sin signo, de 64 bits.
- `TTL` cuenta saltos. El valor normal de origen confirmado es `7`; las
  solicitudes GCS de vecino usan `0`.
- Un receptor **MUST** validar longitudes antes de reservar memoria o leer
  campos variables.

## 3. BLE, UUID y GATT **[BC]**

Un nodo conforme **MUST** usar:

- Servicio primario: `F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C`.
- Característica: `A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D`.
- Descriptor CCCD: `00002902-0000-1000-8000-00805f9b34fb`.

La característica **MUST** exponer `read`, `write`, `write without response` y
`notify`, con permisos de lectura y escritura. El anuncio BLE **MUST** incluir
el UUID de servicio. El scan response **MAY** incluir los primeros 8 octetos
del peer ID como service data y **SHOULD NOT** incluir el nombre del dispositivo
ni la potencia de transmisión.

El peer ID del scan response es únicamente una pista de descubrimiento. Un
receptor **MUST NOT** crear una identidad autenticada, habilitar mensajes
privados ni aplicar capacidades a partir del anuncio BLE. Esas acciones
requieren un `ANNOUNCE` autenticado según la sección 8.

## 4. Framing binario v1 y v2 **[BC]**

### 4.1 Encabezado fijo

El frame sin padding **MUST** tener este orden:

| Campo | v1 | v2 | Regla |
|---|---:|---:|---|
| `version` | 1 | 1 | `0x01` o `0x02` |
| `type` | 1 | 1 | tipo de mensaje |
| `ttl` | 1 | 1 | saltos restantes |
| `timestamp` | 8 | 8 | UInt64 big-endian |
| `flags` | 1 | 1 | sección 4.2 |
| `payloadLength` | 2 | 4 | UInt16/UInt32 big-endian |
| `senderID` | 8 | 8 | obligatorio |

Por tanto, el encabezado anterior a `senderID` mide 14 octetos en v1 y 16 en
v2. Después de `senderID` aparecen, en este orden:

1. `recipientID` de 8 octetos, si `HAS_RECIPIENT`.
2. Ruta, si v2 y `HAS_ROUTE`.
3. Payload transmitido.
4. Firma Ed25519 de 64 octetos, si `HAS_SIGNATURE`.

El receptor **MUST** rechazar versiones distintas de 1 y 2. Un emisor v1
**MUST NOT** incluir ruta.

### 4.2 Flags confirmados

| Bit | Máscara | Nombre | Semántica |
|---:|---:|---|---|
| 0 | `0x01` | `HAS_RECIPIENT` | incluye `recipientID` |
| 1 | `0x02` | `HAS_SIGNATURE` | incluye 64 octetos de firma |
| 2 | `0x04` | `IS_COMPRESSED` | payload comprimido |
| 3 | `0x08` | `HAS_ROUTE` | ruta presente; solo v2 |

Un emisor del núcleo **MUST** poner a cero los bits no definidos. El commit
fijado no registra `0x10` ni bits superiores como parte del framing upstream.
La marca RSR que usa código HearthBit es **[HB]** y **MUST NOT** describirse
como compatible con BitChat.

En v1, un receptor del commit fijado ignora `HAS_ROUTE`; un emisor conforme
**MUST NOT** depender de ese comportamiento.

### 4.3 Longitud y compresión

`payloadLength` cuenta los bytes transmitidos del payload. Si
`IS_COMPRESSED=1`, incluye además el prefijo de tamaño original:

- v1: `originalSize` UInt16 seguido del stream comprimido.
- v2: `originalSize` UInt32 seguido del stream comprimido.

La firma no forma parte de `payloadLength`. La ruta tampoco forma parte de
`payloadLength`.

### 4.4 Ruta v2

La ruta se codifica como:

```text
routeCount: UInt8
route[routeCount]: peerID de 8 octetos
```

La ruta contiene los saltos intermedios ordenados; no incluye al emisor ni al
destinatario final. `routeCount` **MUST** ser como máximo 255. Cada elemento
**MUST** medir 8 octetos. Un relay **MUST** descartar una ruta con saltos
duplicados para evitar bucles. Si el siguiente salto no está conectado, el
commit fijado puede volver a difusión; por ello la ruta es una preferencia, no
una garantía de entrega.

## 5. Tipos de mensaje confirmados **[BC]**

El commit fijado registra:

| Tipo | Nombre | Uso |
|---:|---|---|
| `0x01` | `ANNOUNCE` | identidad y capacidades TLV |
| `0x02` | `MESSAGE` | mensaje de usuario público o dirigido |
| `0x03` | `LEAVE` | salida de presencia |
| `0x10` | `NOISE_HANDSHAKE` | mensajes Noise XX |
| `0x11` | `NOISE_ENCRYPTED` | transporte Noise |
| `0x20` | `FRAGMENT` | fragmentación de un frame completo |
| `0x21` | `REQUEST_SYNC` | solicitud GCS entre vecinos |
| `0x22` | `FILE_TRANSFER` | archivo BLE del perfil BitChat |
| `0x29` | `VOICE_FRAME` | voz efímera, excluida de gossip |

El tipo exterior `0x04` (Courier), los tipos `0x23`–`0x25` y el tipo Noise
interior `0x30` no aparecen en ese registro. Son extensiones HearthBit
documentadas en `docs/extension-registry.md`.

Un tipo desconocido dirigido al nodo local **MUST** ignorarse sin alterar
identidad, capacidades o sesión. No se presupone que un cliente upstream
ignore, reenvíe o conserve ninguna extensión HearthBit.

## 6. Compresión **[BC]**

Un emisor:

1. **MUST NOT** intentar comprimir payloads menores de 100 octetos.
2. **SHOULD** comprimir solo si la proporción de bytes distintos es menor que
   `0.9`, calculada contra `min(length, 256)`.
3. **MUST** emitir DEFLATE crudo, sin cabecera ni trailer zlib.
4. **MUST** conservar la versión comprimida solo si es no vacía y menor que el
   payload original.

Para lectura tolerante, el receptor **MUST** aceptar:

- DEFLATE crudo, que es la forma canónica de escritura.
- Un stream envuelto en zlib RFC 1950 como compatibilidad de lectura.

Si los dos primeros octetos parecen una cabecera zlib válida, el receptor
**SHOULD** intentar zlib primero y DEFLATE crudo después. En otro caso **SHOULD**
intentar solo DEFLATE crudo. La salida **MUST** medir exactamente
`originalSize`, el inflater **MUST** haber llegado al fin del stream y **MUST
NOT** quedar entrada ni salida adicional. Un prefijo válido, un stream truncado,
bytes finales o expansión mayor que la declarada **MUST** rechazarse.

## 7. Padding selectivo y forma canónica **[BC]**

El padding usa bloques objetivo `256`, `512`, `1024` y `2048`. Para elegir
bloque se suma una reserva de 16 octetos al tamaño actual y se toma el menor
bloque que quepa. El padding se aplica solo si faltan entre 1 y 255 octetos.
Todos los octetos añadidos **MUST** contener el número de octetos añadidos,
estilo PKCS#7. Un receptor **MUST** retirar padding únicamente si todos los
octetos finales son válidos.

En BLE, solo `NOISE_HANDSHAKE (0x10)` y `NOISE_ENCRYPTED (0x11)` **MUST**
enviarse con padding. Los demás tipos **MUST** enviarse sin padding de
transporte.

El decoder **MUST** intentar primero el frame tal como llegó y, solo si falla,
volver a intentar después de retirar padding válido. Esto evita eliminar por
error un último octeto que coincida con un tamaño de padding.

La forma canónica usada por la firma es distinta de la política de transporte:
se obtiene con el encoder canónico y su padding habilitado, aunque el paquete
público se transmita sin padding BLE.

## 8. Firma Ed25519 e identidad **[BC]**

### 8.1 Bytes canónicos

Para firmar o verificar un paquete:

1. Se **MUST** copiar el paquete completo, incluida versión, tipo, timestamp,
   destinatario, payload y ruta.
2. `ttl` **MUST** reemplazarse por `0`.
3. `signature` **MUST** eliminarse y `HAS_SIGNATURE` quedar a cero.
4. La copia **MUST** codificarse con las reglas normales de compresión y con
   padding canónico habilitado.
5. Se **MUST** firmar el resultado con Ed25519.

La firma transmitida **MUST** medir 64 octetos. Reducir TTL durante relay no
invalida la firma porque TTL canónico siempre es cero. Cambiar destinatario,
ruta, timestamp, tipo o payload sí **MUST** invalidarla.

### 8.2 Derivación de peer ID

La clave estática Noise/X25519 **MUST** medir 32 octetos. El peer ID se deriva:

```text
peerID = SHA-256(noiseStaticPublicKey)[0..8)
```

El `senderID` del paquete, el peer ID reclamado por el enlace y ese valor
derivado **MUST** coincidir.

### 8.3 Validación de ANNOUNCE

Un `ANNOUNCE` **MUST**:

- tener tipo `0x01`;
- contener una clave Ed25519 de 32 octetos;
- vincular correctamente sender ID y clave Noise;
- portar firma;
- verificar su propia firma con la clave Ed25519 anunciada;
- estar dentro de ±10 minutos del reloj receptor.

El receptor **MUST NOT** sustituir silenciosamente una clave Noise o Ed25519 ya
vinculada. Un cambio de identidad requiere un flujo autenticado explícito fuera
de este perfil.

## 9. ANNOUNCE y TLV **[BC]**

El payload es una secuencia:

```text
type: UInt8
length: UInt8
value: length octetos
```

Tipos conocidos:

| TLV | Nombre | Longitud/semántica |
|---:|---|---|
| `0x01` | nickname | UTF-8, máximo 255 octetos |
| `0x02` | Noise public key | clave estática X25519; 32 octetos para identidad válida |
| `0x03` | signing public key | clave Ed25519; 32 octetos |
| `0x04` | direct neighbors | cero o más peer IDs de 8 octetos; emisor limita a 10 |
| `0x05` | capabilities | bitfield little-endian, mínimo un octeto |

`0x01`, `0x02` y `0x03` son obligatorios. El bit confirmado de capacidades
`PRIVATE_MEDIA` es el bit 8 (`1 << 8`) y señala el payload Noise interior
`0x20` de BitChat, no HBT.

Un receptor **MUST** comprobar que cada valor cabe en el payload. TLV
desconocidos **MUST** saltarse para procesar el anuncio y **SHOULD** conservarse
sin cambios si el anuncio se decodifica y vuelve a codificar. Esa tolerancia
está confirmada solo para el commit fijado; no prueba que builds anteriores
acepten TLV HearthBit. Por ello HearthBit **MUST NOT** anunciar capacidades
propias mediante TLV nuevos de `ANNOUNCE`.

## 10. Noise XX e identidad **[BC]**

Las sesiones privadas **MUST** usar:

```text
Noise_XX_25519_ChaChaPoly_SHA256
```

El handshake exterior usa `NOISE_HANDSHAKE (0x10)` y destinatario explícito.
Los tres mensajes XX sin payload adicional miden 32, 96 y 48 octetos,
respectivamente. Antes de establecer la sesión, cada extremo **MUST** extraer
la clave estática remota autenticada por XX y comprobar que deriva el peer ID
reclamado. Una sesión con identidad no coincidente **MUST** fallar antes de
crear los cifradores de transporte.

El transporte exterior usa `NOISE_ENCRYPTED (0x11)`. Su payload es:

```text
nonce: UInt32 big-endian
ciphertextAndTag: ChaChaPoly (tag de 16 octetos)
```

El receptor **MUST** aplicar protección de replay. El commit fijado usa una
ventana deslizante de 1024 nonces. La sesión **SHOULD** renovarse al cumplir una
hora o alcanzar el límite local de mensajes; ningún emisor **MUST** sobrepasar
el espacio UInt32 de nonce.

El plaintext comienza con un octeto de tipo Noise. Los valores confirmados son
`0x01` mensaje privado, `0x02` leído, `0x03` entregado, `0x08` voz, `0x10`
challenge, `0x11` response, `0x20` archivo BitChat y `0x21` estado autenticado
del peer. `0x30` es HBT **[HB]**, no un valor upstream confirmado.

## 11. Fragmentación `0x20` **[BC]**

Se fragmenta el frame original completo, sin padding exterior. Un frame mayor
de 512 octetos **SHOULD** fragmentarse. Cada fragmento es un paquete nuevo de
tipo `0x20`, sin firma propia, con este payload:

```text
fragmentID: 8 octetos aleatorios
index:      UInt16 big-endian, base 0
total:      UInt16 big-endian
originalType: UInt8
data:       uno o más octetos
```

El encabezado del fragmento mide 13 octetos. `total` **MUST** estar entre 1 y
65535, `index` **MUST** ser menor que `total` y `data` **MUST NOT** estar vacío.
El tamaño máximo nominal de datos por fragmento es 469 octetos y **MUST**
reducirse cuando destinatario o ruta consuman espacio.

Para recepción segura en este perfil:

- se **MUST** limitar `total` a 256;
- cada conjunto **MUST** limitarse a 1 MiB;
- como máximo **MUST** haber 64 conjuntos activos;
- el total global **MUST** limitarse a 4 MiB;
- metadatos inconsistentes **MUST** invalidar el conjunto;
- conjuntos incompletos **MUST** expirar a los 30 segundos.

Tras reensamblar, el receptor **MUST** decodificar de nuevo el frame original y
**MUST** pasarlo por las mismas validaciones de identidad, firma y tipo. El
relay conserva el TTL original para aplicar política y persistencia local, pero
suprime explícitamente un segundo reenvío del contenido reensamblado; los
fragmentos ya se relayaron individualmente.

## 12. Sincronización GCS `0x21` **[BC]**

`REQUEST_SYNC` es una solicitud firmada de vecino con TTL `0`. El payload usa
TLV con longitud UInt16 big-endian:

| TLV | Valor |
|---:|---|
| `0x01` | `P`, UInt8; parámetro Golomb-Rice, mínimo 1 |
| `0x02` | `M`, UInt32 big-endian; rango, mayor que 0 |
| `0x03` | bitstream GCS opaco |

El ID sincronizable de un paquete es:

```text
packetID = SHA-256(type || senderID || timestampBE64 || payload)[0..16)
```

TTL, destinatario, ruta y firma no participan. El GCS toma los primeros 8
octetos de `SHA-256(packetID)` como entero big-endian positivo, lo reduce módulo
`M`, cambia cero por uno, ordena valores y codifica deltas con Golomb-Rice.
Los bits se empaquetan MSB-first.

Solo el `ANNOUNCE` más reciente por emisor y mensajes `MESSAGE` broadcast
recientes participan. `VOICE_FRAME` y extensiones HearthBit **MUST NOT**
incorporarse por defecto. La utilidad GCS tiene fallback de 256 octetos y 1% de
falsos positivos; el servicio BLE del commit fijado configura 400 octetos y 1%.
Un receptor **MUST** rechazar un TLV de filtro mayor de 1024 octetos. Una
respuesta **MUST** enviar únicamente paquetes que el filtro probablemente no
contenga y **MUST** fijar su TTL a cero.

El camino de emisión del commit fijado firma `REQUEST_SYNC`, pero su
`SecurityManager` genérico no incluye `0x21` entre los tipos cuya firma exige
al recibir. HearthBit **[HB]** **MUST** exigir emisor anunciado y firma válida
antes de responder; esta es una regla de endurecimiento local, no una garantía
del receptor upstream.

Un falso positivo puede omitir temporalmente un paquete; GCS no es prueba de
posesión ni autenticación. Cada paquete recuperado **MUST** validarse como si
hubiera llegado normalmente.

## 13. Relay, deduplicación y TTL

### 13.1 Comportamiento confirmado **[BC]**

El TTL de origen normal es 7. El relay upstream fijado no reenvía TTL 0; para
cualquier TTL positivo lo decrementa antes de enviar. Puede usar siguiente
salto de ruta o difusión. También aplica probabilidad adaptativa según tamaño
de red, de modo que relay no implica entrega garantizada.

La caché de duplicados del commit fijado conserva hasta 10 000 entradas durante
5 minutos. Registra un paquete solo después de su autenticación. Su clave
operativa incluye timestamp, peer de entrada y hash de payload; para fragmentos
incluye el payload completo. Esta caché operativa no es el `packetID` GCS y
**MUST NOT** confundirse con una identidad criptográfica.

### 13.2 Política HearthBit **[HB]**

HearthBit aplica una regla más conservadora: un rol relay **MUST** exigir
`TTL > 1`, decrementar exactamente una vez y no retransmitir un paquete Noise
dirigido al nodo local. Los paquetes dirigidos a otro nodo **MAY** relayarse.
Los roles `PHONE_BEACON` **MUST NOT** relayar.

El fingerprint de relay HearthBit v2 se calcula de forma idéntica en Python y
firmware:

1. se toma el frame transmitido hasta el final de la firma, excluyendo padding;
2. se reemplaza el octeto TTL por `0x00`;
3. se limpia únicamente el bit local RSR (`flags & ~0x10`);
4. se calcula SHA-256 sobre esos bytes, sin re-encode ni descompresión.

El relay persistente usa `digest[0..16)` y el firmware, por su caché RAM
acotada, usa `digest[0..8)`. Durante la migración, el relay Python consulta
también la huella BLAKE2s anterior en la tabla `seen`, pero toda inserción y
todo envelope externo nuevo usa SHA-256. Esta es una política local y no
amplía el contrato upstream.

## 14. Courier **[HB]**

Courier es store-and-forward cifrado de HearthBit/Bitle. Usa el tipo exterior
legacy `0x04`, que no está registrado en el commit BitChat fijado. No existe
una afirmación de compatibilidad upstream.

El payload es TLV con longitud UInt16 big-endian:

| TLV | Requisito | Valor |
|---:|---|---|
| `0x01` | obligatorio | recipient tag de 16 octetos |
| `0x02` | obligatorio | expiración Unix ms, UInt64 BE |
| `0x03` | obligatorio | ciphertext opaco no vacío |
| `0x04` | opcional | copias, UInt8 entre 1 y 8; por defecto 1 |
| `0x05` | opcional | prekey ID, UInt32 BE |

El recipient tag se calcula:

```text
HMAC-SHA256(
  key = recipientNoiseStaticPublicKey,
  data = UTF8("bitchat-courier-tag-v1") || epochDayBE32
)[0..16)
```

El receptor **MAY** probar día anterior, actual y siguiente para tolerar el
cambio de día. La expiración **MUST** estar en el futuro y **MUST NOT** superar
25 horas desde la recepción. El valor normal emitido por HearthBit es 12 horas.

Un ancla **MUST** aceptar depósitos solo desde un enlace directo cuya identidad
y firma hayan sido verificadas. **MUST** almacenar únicamente el sobre opaco,
aplicar cuotas, deduplicar por `SHA-256(ciphertext)` y nunca ampliar su
expiración. El cliente destinatario **MUST** comprobar tag, expiración, frame
interior `NOISE_ENCRYPTED`, recipient ID y replay antes de procesarlo.

La implementación Bitle limita el buzón a 128 sobres y 8 por depositante. Un
relay genérico que no pueda autenticar la firma completa **MUST NOT** afirmar
que ofrece Courier seguro.

## 15. Límites y defensa contra DoS

Una implementación conforme **MUST** imponer, como mínimo:

- payload declarado y expandido: máximo 10 MiB;
- v1: payload transmitido y tamaño original máximo 65535;
- compresión: stream no vacío, expansión exacta y ratio máximo `50 000:1`;
- reserva de memoria previa para entrada comprimida y salida expandida;
- firma: exactamente 64 octetos;
- sender ID, recipient ID y saltos: exactamente 8 octetos;
- claves Noise y Ed25519: 32 octetos;
- límites de fragmentación de la sección 11;
- filtro GCS recibido: máximo 1024 octetos;
- deduplicación acotada y con expiración;
- control de frecuencia para respuestas sync y reintentos de radio.

Campos truncados, longitudes que desborden, rutas imposibles, padding inválido,
streams parciales y paquetes reensamblados que no decodifiquen **MUST**
rechazarse sin efectos parciales. La autenticación **MUST** ocurrir antes de
crear estado duradero, actualizar presencia, aceptar capacidades o almacenar
store-and-forward.

## 16. Background y discovery

### 16.1 Confirmado en el Android fijado **[BC]**

Android mantiene la malla en segundo plano mediante un foreground service
persistente cuando el usuario lo habilita y existen permisos Bluetooth. En
Android 12 o posterior requiere `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` y
`BLUETOOTH_ADVERTISE`; en versiones anteriores el escaneo depende de permiso
de ubicación. El servicio no elimina las restricciones de Doze, fabricante,
radio o sistema operativo.

El escáner **MUST** filtrar por el UUID de servicio. El anuncio GATT permanece
conectable, pero la cadencia de scan **MAY** usar duty cycle según batería,
background y conexiones directas. El perfil fijado usa, entre otros:

- background con peers directos: 1 s activo / 29 s inactivo;
- background sin peers directos: 1 s / 59 s;
- foreground balanceado: 8 s / 2 s;
- ahorro: 2 s / 28 s;
- ultra bajo: 1 s / 29 s.

El nodo **SHOULD** reintentar fallos transitorios de scan/advertising con
backoff y **SHOULD** vigilar escaneos silenciosamente detenidos.

### 16.2 Regla de seguridad HearthBit **[HB]**

HearthBit distingue presencia BLE de malla autenticada. Una observación de
radio **MAY** mostrarse como señal cercana, pero **MUST NOT** habilitar chat,
radar, extensiones, Courier ni transferencias. Solo un `ANNOUNCE` válido
promueve al peer al nivel autenticado.

La ejecución background es best effort. Ningún emisor **MUST** interpretar la
ausencia de un peer como revocación de identidad, confirmación de entrega o
prueba de que el dispositivo está apagado.

## 17. Requisitos de conformidad

Una implementación que afirme conformidad con este perfil:

1. **MUST** identificar el commit fijado en sus resultados de prueba.
2. **MUST** implementar v1, firma canónica TTL 0, ANNOUNCE autenticado,
   Noise XX, fragmentación y límites de recepción.
3. **SHOULD** implementar v2/rutas y GCS si participa como relay completo.
4. **MUST** separar capacidades confirmadas **[BC]** de extensiones **[HB]**.
5. Para extensiones dirigidas, **MUST NOT** enviar antes de autenticar el
   `ANNOUNCE` del destino y completar la negociación de
   `docs/extension-registry.md`; para extensiones broadcast heredadas, **MUST**
   emitir primero el `ANNOUNCE` propio y el receptor **MUST** autenticarlo antes
   de aplicar la extensión.
6. **MUST NOT** usar una prueba HearthBit↔HearthBit como evidencia de
   compatibilidad upstream.
