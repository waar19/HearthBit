# Registro de extensiones de malla HearthBit

## 1. Alcance y regla de compatibilidad

Este registro gobierna extensiones de HearthBit sobre el perfil de
`docs/bitchat-core-profile.md`. Las palabras **MUST**, **MUST NOT**, **SHOULD**,
**SHOULD NOT** y **MAY** se interpretan según RFC 2119.

La fuente BitChat fijada es
`vendor/bitchat-android@5156f7de89ec9f6a3429630d90f709b68f6fd7fd`.
Ese commit no registra Courier `0x04`, los tipos exteriores `0x23`–`0x28`,
`0x2A`–`0x2C` ni los tipos Noise interiores `0x30`–`0x31`. `0x29` sí está asignado por
upstream a `VOICE_FRAME`; Bitle asigna `0x24` a `PREKEY_BUNDLE`. Las entradas
propias de este documento pertenecen a HearthBit/Bitle y **MUST NOT**
presentarse como compatibilidad upstream.

Los valores numéricos viven en espacios distintos:

1. **Tipo exterior:** byte `type` del paquete BitChat.
2. **Tipo Noise interior:** primer byte del plaintext de `NOISE_ENCRYPTED`.
3. **Subtype de ExtensionEnvelope:** UInt16 dentro del contenedor futuro.

La coincidencia numérica entre espacios no implica la misma semántica. Por
ejemplo, `0x20` exterior es fragmentación y `0x20` interior es archivo privado
BitChat.

## 2. Reglas comunes de admisión

Antes de enviar una extensión dirigida, un nodo:

1. **MUST** haber recibido y validado el `ANNOUNCE` del destinatario.
2. **MUST** haber vinculado sender ID, clave estática Noise y clave Ed25519.
3. **MUST** aplicar la condición adicional de negociación indicada por la
   entrada.

Las asignaciones broadcast directas `RADAR_CONTROL`, `HBT_CAPABILITY`,
`NODE_CAPABILITY` y `EMERGENCY_CAPABILITY` son la excepción de transporte: el
emisor **MUST** transmitir primero su propio `ANNOUNCE` y luego la extensión.
El receptor **MUST** descartar o diferir la extensión hasta haber autenticado
ese `ANNOUNCE`; el orden de llegada por sí solo no autentica nada.

Antes de aplicar una extensión recibida, el nodo **MUST**:

- conocer al emisor por un `ANNOUNCE` autenticado;
- verificar la firma exterior cuando la entrada sea firmada;
- validar versión, longitud, timestamp y límites antes de cambiar estado;
- rechazar únicamente la extensión si falla, sin degradar la identidad ya
  autenticada ni reinterpretar el payload como otro tipo.

Una observación BLE, un peer ID en service data o una conexión GATT no cumplen
la condición de `ANNOUNCE` autenticado.

## 3. Registro activo

Este registro distingue asignaciones activas de aliases temporales de
recepción. Un alias legacy **MUST NOT** usarse para emitir.

| Espacio | Valor | Nombre | Propietario | Crítica | Store-forward |
|---|---:|---|---|---|---|
| exterior | `0x04` | `COURIER_ENVELOPE` | HearthBit/Bitle | sí | sí, opaco y acotado |
| exterior | `0x23` | `RADAR_CONTROL` | HearthBit | sí | nunca |
| exterior | `0x24` | `PREKEY_BUNDLE` | Bitle | sí | caché prekey Bitle |
| exterior | `0x25` | `NODE_CAPABILITY` | HearthBit/Bitle | sí al aplicarla | nunca |
| exterior | `0x26` | `BEACON_CONTROL` | HearthBit | sí | nunca |
| exterior | `0x27` | `RANGING_CONTROL` | HearthBit | sí | nunca |
| exterior | `0x28` | `EMERGENCY_CAPABILITY` | HearthBit | no | nunca |
| exterior | `0x2A` | `HBT_CAPABILITY` | HearthBit | no | nunca |
| exterior | `0x2B` | `EMERGENCY_ACK` | HearthBit | sí | dirigido y acotado |
| exterior | `0x2C` | `KEY_ROTATION` | HearthBit | sí | nunca |
| Noise interior | `0x30` | `HBT_TRANSFER_FRAME` | HearthBit | no para la sesión | nunca |
| Noise interior | `0x31` | `ANCHOR_ADMIN` | HearthBit/Bitle | sí | nunca |

“Crítica” significa que interpretar mal la entrada puede modificar
autorización, privacidad, identidad operativa o política de relay. Una entrada
crítica desconocida o inválida **MUST** rechazarse como unidad. No exige cerrar
la sesión ni descartar el `ANNOUNCE`.

Una entrada no crítica desconocida **MUST** ignorarse sin efectos y el
procesamiento del paquete o sesión **MAY** continuar.

### 3.1 Recepción legacy temporal y ambigua

Durante la transición, Android, iOS y relay **MUST** aceptar como candidatos de
recepción:

- `LEGACY_HBT_CAPABILITY = 0x24`;
- `LEGACY_EMERGENCY_ACK = 0x29`.

Los emisores **MUST NOT** producir esos aliases: `HBT_CAPABILITY` se emite solo
como `0x2A` y `EMERGENCY_ACK` solo como `0x2B`.

El byte no basta para decidir la semántica. `0x24` también es
`PREKEY_BUNDLE` de Bitle y `0x29` es `VOICE_FRAME` en el commit BitChat fijado.
Un receptor **MUST** considerar un candidato legacy como extensión HearthBit
solo después de validar el `ANNOUNCE` del emisor, la firma exterior y la
estructura exacta registrada. Para `LEGACY_EMERGENCY_ACK` además **MUST**
exigir `recipientId` igual al nodo local, capacidad de ACK negociada, timestamp
dentro de la ventana y payload versionado de 33 octetos. Si cualquier
condición falla, **MUST NOT** reinterpretar el paquete como la extensión
HearthBit ni modificar estado. Los relays que no interpretan el payload
**MAY** moverlo de forma opaca, pero **MUST NOT** normalizar su tipo.

## 4. `COURIER_ENVELOPE` exterior `0x04`

### 4.1 Propósito y negociación

Courier transporta un paquete `NOISE_ENCRYPTED` opaco a través de un
`INFRA_DATA_ANCHOR`. Un teléfono **MUST** depositar Courier únicamente después
de:

- un `ANNOUNCE` autenticado del ancla;
- un `NODE_CAPABILITY 0x25` firmado que declare
  `INFRA_DATA_ANCHOR`;
- una sesión Noise directa establecida con esa ancla.

El paquete exterior **MUST** estar dirigido al ID del ancla y **MUST** estar
firmado por el depositante. El ancla **MUST** comprobar que el sender del
paquete coincide con la identidad del enlace directo.

### 4.2 Payload

El payload usa TLV `type:UInt8, length:UInt16BE, value`:

| TLV | Requisito | Valor |
|---:|---|---|
| `0x01` | obligatorio | recipient tag, 16 octetos |
| `0x02` | obligatorio | expiración Unix ms, UInt64 BE |
| `0x03` | obligatorio | ciphertext opaco no vacío |
| `0x04` | opcional | copias UInt8, rango 1–8; omitido equivale a 1 |
| `0x05` | opcional | prekey ID UInt32 BE |

TLV desconocidos **SHOULD** ignorarse. Un TLV conocido con longitud inválida
**MUST** invalidar el sobre. El tag, expiración, ciphertext y cuotas normativas
se definen en la sección Courier del perfil núcleo. HearthBit emite 4 copias
por defecto; omitir `0x04` sigue significando 1 para compatibilidad de lectura.

### 4.3 Store-forward

Esta es la única asignación HearthBit de propósito general elegible para
store-forward opaco. La caché `PREKEY_BUNDLE` de Bitle es una clase separada y
nunca convierte `0x24` en capacidad HBT. El ancla:

- **MUST** conservar el ciphertext opaco, no plaintext ni claves de sesión;
- **MUST** deduplicar por `SHA-256(ciphertext)`;
- **MUST** limitar expiración a 25 horas y nunca ampliarla;
- **MUST** aplicar cuota global y por depositante;
- **MUST NOT** almacenar un depósito sin identidad y firma verificadas.

La implementación Bitle usa 128 sobres globales y 8 por depositante. Un relay
que solo comprueba la presencia del flag de firma, pero no la firma, **MUST
NOT** aceptar depósitos Courier como ancla segura.

## 5. `RADAR_CONTROL` exterior `0x23`

### 5.1 Semántica

`RADAR_CONTROL` concede o revoca consentimiento temporal para usar RSSI como
radar de proximidad. No transporta ubicación precisa ni demuestra dirección.
El paquete **MUST** estar firmado, **MUST** emitirse después del `ANNOUNCE`
propio y **MUST** usar TTL 1.

El payload fijo mide 26 octetos:

```text
version:   UInt8 = 0x01
action:    UInt8 = 0x01 GRANT | 0x02 REVOKE
expiresAt: UInt64 big-endian, Unix ms
nonce:     16 octetos aleatorios
```

Para `REVOKE`, `expiresAt` **MUST** ser cero. Para `GRANT`, la expiración
**MUST** estar en el futuro y **MUST NOT** superar 30 minutos más 2 minutos de
tolerancia desde el reloj receptor. El timestamp exterior **MUST** estar dentro
de ±2 minutos.

El receptor **MUST** verificar la firma con la clave vinculada por `ANNOUNCE`
antes de crear, renovar o revocar consentimiento. Un grant normal emitido por
la UI dura 15 minutos. El consentimiento derivado de un SOS tiene una política
separada de 30 minutos y no cambia el encoding `RADAR_CONTROL`. Mientras el
Modo Rescate esté activo, cada ping **MUST** renovar el grant local por otros
30 minutos antes de emitir el SOS. La ventana derivada que calcula el receptor
**MUST NOT** superar 30 minutos desde su propio reloj y toda suma de expiración
**MUST** usar aritmética saturada.

### 5.2 Criticidad y persistencia

`RADAR_CONTROL` es crítico para autorización. Un valor desconocido, expirado,
mal firmado o mal formado **MUST** ignorarse con estado deny-by-default. Nunca
**MUST** almacenarse ni retransmitirse mediante store-forward: una revocación
retrasada o un grant reproducido serían inseguros.

## 6. `HBT_CAPABILITY` exterior `0x2A`

`HBT_CAPABILITY` anuncia soporte para HearthBit Transfer Protocol. El payload
actual **MUST** ser exactamente:

```text
version: UInt8 = 0x01
```

El paquete **MUST** estar firmado y el receptor **MUST** haber autenticado antes
el `ANNOUNCE` del emisor. La capacidad es no crítica: si versión o longitud son
desconocidas, el receptor **MUST** ignorarla y asumir que HBT no está
disponible.

No debe confundirse con el TLV BitChat `ANNOUNCE 0x05` ni con su bit
`PRIVATE_MEDIA`. HearthBit conserva `ANNOUNCE` sin TLV propios porque la
tolerancia de clientes históricos no está demostrada.

`HBT_CAPABILITY` **MUST NOT** entrar en GCS ni store-forward. Un emisor
**SHOULD** volver a emitirlo inmediatamente después de su `ANNOUNCE` periódico.
La lectura temporal de `LEGACY_HBT_CAPABILITY 0x24` usa estas mismas reglas de
payload y autenticación, pero un emisor **MUST NOT** volver a producir `0x24`.

## 7. `NODE_CAPABILITY` exterior `0x25`

### 7.1 Payload

El payload fijo mide 3 octetos:

```text
version: UInt8 = 0x01
role:    UInt8
flags:   UInt8
```

Roles:

| Código | Rol |
|---:|---|
| `0x01` | `PHONE_RELAY` |
| `0x02` | `PHONE_BEACON` |
| `0x03` | `INFRA_RELAY` |
| `0x04` | `INFRA_DATA_ANCHOR` |

Flags informativos:

| Bit | Máscara | Significado |
|---:|---:|---|
| 0 | `0x01` | retransmite |
| 1 | `0x02` | puede originar chat |
| 2 | `0x04` | conserva paquetes dirigidos |
| 3 | `0x08` | presencia solamente |
| 4 | `0x10` | `LONG_RANGE_TRUNK`: troncal de largo alcance operativo |

La política se deriva del `role`; los flags sirven para diagnóstico y futura
validación. Un receptor **SHOULD** comprobar que coincidan y **MUST NOT**
conceder más privilegios por flags inconsistentes.

`LONG_RANGE_TRUNK` significa únicamente que el emisor declara operativo su
enlace troncal en ese momento. **MUST NOT** inferirse del nickname, del rol ni
de un indicador de infraestructura, y **MUST NOT** conceder relay,
store-forward, chat, autorización o confianza adicional. Si falta el bit, el
receptor conserva solo el rol anunciado y no presenta una troncal visible.

### 7.2 Admisión y almacenamiento

El paquete **MUST** estar firmado. El receptor **MUST** aplicar el rol solo
después del `ANNOUNCE` autenticado del mismo sender. Un valor desconocido o
inválido **MUST** conservar la política local segura previa; nunca debe
promocionar un nodo a ancla.

`NODE_CAPABILITY` es crítico al aplicarse porque controla relay y
store-forward, pero opcional para mantener una sesión de chat. **MUST NOT**
guardarse en store-forward ni GCS. Un emisor **SHOULD** enviarlo inmediatamente
después de cada `ANNOUNCE`.

## 8. `BEACON_CONTROL` exterior `0x26`

`0x25` continúa reservado para `NODE_CAPABILITY`; la baliza física usa
exclusivamente `0x26`. El payload **MUST** usar versión 1. El paquete **MUST**
estar firmado Ed25519 con la clave vinculada por el `ANNOUNCE` previo y
dirigido mediante `recipientId` al peer
anunciado y emitido con TTL inicial 2. Un relay **MAY** retransmitirlo
exactamente una vez si `ttl > 1` y `recipientId` no corresponde al nodo local;
**MUST** decrementarlo a 1 y conservar destinatario, payload, firma y nonce.
Un `BEACON_CONTROL` con TTL 0 o mayor que 2 **MUST** rechazarse. El relay
**MUST NOT** aplicar el control, volver a retransmitirlo con TTL 1, guardarlo en
store-forward ni incorporarlo a sincronización GCS. La fragmentación de enlace
BitChat **MUST** conservar y validar el TTL 2 directo o el TTL 1 después del
único relay; el paquete reensamblado no vuelve a retransmitirse.

El payload fijo mide 27 octetos:

```text
version:   UInt8 = 0x01
action:    UInt8 = 0x01 REQUEST | 0x02 GRANT | 0x03 REVOKE | 0x04 STOP
expiresAt: UInt64 big-endian, Unix ms
nonce:     16 octetos aleatorios
flags:     UInt8, bit 0 flash | bit 1 sound | bit 2 vibrate
```

Los bits de flags desconocidos invalidan el payload. `REQUEST` y `GRANT`
**MUST** llevar al menos un actuador y una expiración futura no superior a
5 minutos desde el reloj receptor. `REVOKE` y `STOP` **MUST** llevar
`expiresAt = 0` y `flags = 0`. El timestamp exterior **MUST** estar dentro de
±2 minutos. Longitud, versión, acción, destinatario, TTL 1 o 2, timestamp,
expiración y firma se validan antes de cualquier cambio de estado.

`REQUEST` nunca activa hardware por sí solo. La actuación requiere un `GRANT`
local, producido por aceptación manual o por la política de autoaceptación ya
autorizada. El receptor **MAY** autoaceptar únicamente si ya tenía activo el
modo rescate o un consentimiento de radar local, la identidad HearthBit del
emisor está verificada y existe una relación segura previa; en cualquier otro
estado requiere aceptación explícita. Rechazar produce `REVOKE`. `STOP` detiene una
concesión con el mismo nonce. La actuación termina al expirar, al pasar iOS a
segundo plano, al desconectar el plugin o al detenerse localmente.

## 9. `RANGING_CONTROL` exterior `0x27`

`RANGING_CONTROL` coordina una sesión dirigida de medición. El paquete **MUST**
llevar `recipientId`, firma Ed25519 del peer anunciado, TTL 1 y timestamp dentro
de ±2 minutos. **MUST NOT** entrar en relay, GCS ni store-forward.

El payload v1 contiene, en orden big-endian: versión UInt8, acción UInt8,
tecnología UInt8, ronda UInt8, nonce de sesión de 16 octetos, valor Float64,
error Float32, confianza Float32, longitud opaca UInt16 y esos bytes opacos.
La longitud fija antes de los bytes opacos es 38; la parte opaca **MUST NOT**
superar 1024 octetos. Acción, tecnología, longitudes y valores finitos **MUST**
validarse antes de aplicar el control.

## 10. Emergencia exterior `0x28` y `0x2B`

`EMERGENCY_CAPABILITY 0x28` anuncia soporte de acuses. Su payload fijo es
`version:UInt8 = 0x01, flags:UInt8`; el bit 0 declara `EMERGENCY_ACK`. El
paquete **MUST** estar firmado y solo se aplica después del `ANNOUNCE`
autenticado. **MUST NOT** entrar en GCS ni store-forward.

`EMERGENCY_ACK 0x2B` es dirigido y firmado. El payload mide exactamente 33
octetos: `version:UInt8 = 0x01` seguido del hash canónico SHA-256 de 32 octetos
del mensaje de emergencia. El receptor **MUST** exigir `recipientId` local,
peer previamente anunciado, firma válida, capacidad de ACK negociada y
timestamp dentro de ±48 horas antes de informar el acuse. La recepción
temporal de `LEGACY_EMERGENCY_ACK 0x29` aplica exactamente estas validaciones;
ningún emisor **MUST** producir `0x29`.

## 11. `KEY_ROTATION` exterior `0x2C`

`KEY_ROTATION` migra una identidad TOFU ya fijada a un nuevo par de claves.
No crea confianza inicial: `senderId` y `oldPeerId` **MUST** ser el peer ID
antiguo y el receptor **MUST** tener fijada previamente su clave Ed25519.

El payload v1 mide exactamente 153 octetos, en orden big-endian:

```text
version:                UInt8 = 0x01
oldPeerId:              8 octetos
newNoiseX25519:         32 octetos
newSigningEd25519:      32 octetos
timestamp:              UInt64 Unix ms
sequence:               UInt64, mayor que cero
authorizationSignature:64 octetos Ed25519
```

La autorización interna firma con la clave Ed25519 antigua:
`ASCII("HearthBitKeyRotationV1") || payload[0..88]`. Además, el paquete
exterior completo **MUST** estar firmado con esa misma clave antigua. El
timestamp interior **MUST** ser igual al timestamp exterior y estar dentro de
±10 minutos. La secuencia **MUST** ser estrictamente mayor que la última
secuencia aceptada para esa línea de identidad.

Antes de cambiar estado, el receptor valida ambas firmas, tamaños y parsers de
clave, el enlace `oldPeerId == senderId`, que el nuevo peer ID sea
`SHA-256(newNoiseX25519)[0..7]`, que sea distinto del anterior y que no esté
fijado a otro peer. Solo entonces reemplaza atómicamente el pin antiguo por el
nuevo y persiste la secuencia. Firma inválida, identidad desconocida, reloj
fuera de ventana, replay/rollback, clave cero o malformada y colisión
**MUST** rechazarse sin modificar ningún pin.

Un `ANNOUNCE` ordinario nunca autoriza una rotación ni resuelve un conflicto.
La rotación invalida las sesiones Noise anteriores; el nuevo peer debe emitir
un `ANNOUNCE` firmado con su nueva clave y negociar una sesión nueva.
`KEY_ROTATION` puede retransmitirse en vivo respetando TTL, pero **MUST NOT**
entrar en GCS ni store-forward. Un relay neutral puede parsearlo para límites y
diagnóstico, pero **MUST NOT** actualizar confianza local.

Para recuperación, el emisor conserva temporalmente la clave antigua y puede
reemitir una autorización con la misma secuencia y timestamp renovado a nodos
que aún conservan el pin antiguo. Un nodo que ya migró rechaza ese sender
antiguo; uno que perdió el anuncio puede aceptarlo. Si se pierde la clave
antigua o el estado seguro queda corrupto, la recuperación requiere olvido o
panic wipe explícito y nuevo TOFU; nunca se rota automáticamente al observar
un conflicto.

## 12. `HBT_TRANSFER_FRAME` Noise interior `0x30`

El plaintext de transporte es:

```text
type: UInt8 = 0x30
hbtFrame: bytes HBT v1
```

El tipo exterior **MUST** ser `NOISE_ENCRYPTED (0x11)` y el destinatario
**MUST** ser el peer de la sesión. El emisor **MUST** haber recibido:

1. `ANNOUNCE` autenticado;
2. `HBT_CAPABILITY 0x2A` válido con versión `0x01`;
3. establecimiento exitoso de Noise XX con identidad vinculada.

Un receptor que no conozca `0x30` **MUST** ignorar el plaintext desconocido sin
cerrar la sesión Noise. Una implementación **MUST NOT** tratar `0x30` como el
archivo privado BitChat `0x20`.

El frame `0x30` no es elegible para store-forward por sí mismo. El paquete
Noise exterior depende de una sesión viva. Cuando HearthBit necesita entrega
diferida de un mensaje privado usa Courier, que conserva como ciphertext el
paquete Noise completo y aplica sus propias restricciones. Los blobs de
archivo HBT **MUST NOT** entrar en Courier ni en el store-forward de mensajes.

## 13. `ANCHOR_ADMIN` Noise interior `0x31`

`ANCHOR_ADMIN` solo puede circular como plaintext autenticado dentro de una
sesión Noise directa entre la aplicación y un nodo con rol
`INFRA_DATA_ANCHOR` o `INFRA_RELAY`. Nunca se retransmite, deduplica, sincroniza
ni almacena por courier. Un receptor que no implemente `0x31` lo ignora sin
cerrar la sesión.

La versión, comandos, challenge de un solo uso, PBKDF2, HMAC, estados y límites
se especifican en [`anchor-admin-protocol.md`](anchor-admin-protocol.md). Todo
comando que modifica estado es crítico: una trama inválida se rechaza como
unidad y no puede reinterpretarse como mensaje privado o transferencia.

## 14. ExtensionEnvelope futuro

### 14.1 Objetivo y estado

Las asignaciones activas de la tabla de la sección 3 **MUST** conservarse.
`0x24` significa `PREKEY_BUNDLE`, `0x29` permanece `VOICE_FRAME`, y sus aliases
legacy existen solo para recepción validada durante la transición. Las
extensiones posteriores **SHOULD** usar un `ExtensionEnvelope` común para
evitar consumir más tipos exteriores y para expresar propiedad, versión,
criticidad y política de almacenamiento.

Este documento fija el encoding del envelope, pero no reserva un tipo exterior
BitChat para transportarlo. Hasta que una revisión de este registro asigne un
carrier y su negociación, una implementación **MUST NOT** emitir
`ExtensionEnvelope` en la red ni reutilizar un tipo upstream. Esta restricción
evita inventar compatibilidad.

### 14.2 Encoding

El encabezado mide 12 octetos:

```text
namespace: 4 octetos ASCII
subtype:   UInt16 big-endian
version:   UInt8
flags:     UInt8
length:    UInt32 big-endian
payload:   length octetos
```

`namespace` identifica al propietario del subtipo. El namespace reservado para
este proyecto es ASCII `HBIT` (`48 42 49 54`). Otros namespaces **MUST**
registrar propietario y contacto antes de su uso.

Flags:

| Bit | Máscara | Nombre | Regla |
|---:|---:|---|---|
| 0 | `0x01` | `CRITICAL` | semántica crítica para la extensión |
| 1 | `0x02` | `STORE_FORWARD` | elegible según política registrada |
| 2–7 | `0xFC` | reservados | emisor pone cero |

`length` cuenta solo `payload`. El receptor **MUST** rechazar truncamiento,
bytes sobrantes o longitud mayor que el límite de payload del perfil núcleo.
Una versión desconocida se trata como subtipo desconocido.

El flag `STORE_FORWARD` expresa elegibilidad, no autorización. Un relay **MUST**
consultar además la entrada del registro, autenticación, destinatario, cuota y
expiración. El flag nunca puede volver almacenable un subtipo registrado como
“nunca”.

### 14.3 Negociación y tipos desconocidos

Un emisor **MUST NOT** enviar un `ExtensionEnvelope` hasta haber recibido un
`ANNOUNCE` autenticado y una capacidad autenticada que declare soporte para el
carrier, namespace, subtype y versión. El simple hecho de ser HearthBit no
equivale a negociación.

Para un envelope desconocido:

- si `CRITICAL=0`, el receptor **MUST** ignorarlo sin efectos y **MAY**
  continuar procesando otros envelopes;
- si `CRITICAL=1`, el receptor **MUST** rechazar ese envelope y **SHOULD**
  registrar un diagnóstico acotado;
- en ambos casos **MUST NOT** cerrar Noise, invalidar `ANNOUNCE`, degradar
  identidad ni reinterpretar bytes;
- **MUST NOT** almacenarlo salvo que el registro y la negociación autoricen
  explícitamente store-forward.

## 15. Proceso de asignación

Toda nueva entrada **MUST** documentar:

- espacio numérico y valor;
- namespace, subtype y versión si usa `ExtensionEnvelope`;
- propietario y contacto del componente;
- encoding exacto y límites;
- autenticación y negociación requeridas;
- criticidad y comportamiento ante desconocidos;
- política `nunca`, `opaco` o `session-bound` de store-forward;
- interacción con relay, TTL, deduplicación y GCS;
- vectores de prueba Android/iOS/firmware cuando correspondan.

Una asignación **MUST NOT** colisionar con el registro del commit BitChat fijado
ni asumir que un cliente upstream ignorará el valor. Cambiar el significado de
una asignación heredada requiere una versión nueva; nunca se redefine en sitio.
