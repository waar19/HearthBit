# Registro de extensiones de malla HearthBit

## 1. Alcance y regla de compatibilidad

Este registro gobierna extensiones de HearthBit sobre el perfil de
`docs/bitchat-core-profile.md`. Las palabras **MUST**, **MUST NOT**, **SHOULD**,
**SHOULD NOT** y **MAY** se interpretan según RFC 2119.

La fuente BitChat fijada es
`vendor/bitchat-android@5156f7de89ec9f6a3429630d90f709b68f6fd7fd`.
Ese commit no registra Courier `0x04`, los tipos exteriores `0x23`–`0x25` ni el
tipo Noise interior `0x30`. Todas las entradas de este documento pertenecen a
HearthBit/Bitle. Su existencia **MUST NOT** presentarse como compatibilidad
upstream.

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

Las asignaciones broadcast heredadas `0x23`–`0x25` son la excepción de
transporte: el emisor **MUST** transmitir primero su propio `ANNOUNCE` y luego
la extensión. El receptor **MUST** descartar o diferir la extensión hasta haber
autenticado ese `ANNOUNCE`; el orden de llegada por sí solo no autentica nada.

Antes de aplicar una extensión recibida, el nodo **MUST**:

- conocer al emisor por un `ANNOUNCE` autenticado;
- verificar la firma exterior cuando la entrada sea firmada;
- validar versión, longitud, timestamp y límites antes de cambiar estado;
- rechazar únicamente la extensión si falla, sin degradar la identidad ya
  autenticada ni reinterpretar el payload como otro tipo.

Una observación BLE, un peer ID en service data o una conexión GATT no cumplen
la condición de `ANNOUNCE` autenticado.

## 3. Registro heredado

“Heredado” significa que el valor ya está desplegado por HearthBit y debe
conservar su encoding directo. No significa heredado de BitChat upstream.

| Espacio | Valor | Nombre | Propietario | Crítica | Store-forward |
|---|---:|---|---|---|---|
| exterior | `0x04` | `COURIER_ENVELOPE` | HearthBit/Bitle | sí | sí, opaco y acotado |
| exterior | `0x23` | `RADAR_CONTROL` | HearthBit | sí | nunca |
| exterior | `0x24` | `HBT_CAPABILITY` | HearthBit | no | nunca |
| exterior | `0x25` | `NODE_CAPABILITY` | HearthBit/Bitle | sí al aplicarla | nunca |
| Noise interior | `0x30` | `HBT_TRANSFER_FRAME` | HearthBit | no para la sesión | nunca |

“Crítica” significa que interpretar mal la entrada puede modificar
autorización, privacidad, identidad operativa o política de relay. Una entrada
crítica desconocida o inválida **MUST** rechazarse como unidad. No exige cerrar
la sesión ni descartar el `ANNOUNCE`.

Una entrada no crítica desconocida **MUST** ignorarse sin efectos y el
procesamiento del paquete o sesión **MAY** continuar.

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

Esta es la única asignación heredada de este registro elegible para
store-forward. El ancla:

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
**MUST** estar en el futuro y **MUST NOT** superar 20 minutos más 2 minutos de
tolerancia desde el reloj receptor. El timestamp exterior **MUST** estar dentro
de ±2 minutos.

El receptor **MUST** verificar la firma con la clave vinculada por `ANNOUNCE`
antes de crear, renovar o revocar consentimiento. Un grant normal emitido por
la UI dura 15 minutos. El consentimiento derivado de un SOS tiene una política
separada de 10 minutos y no cambia el encoding `RADAR_CONTROL`.

### 5.2 Criticidad y persistencia

`RADAR_CONTROL` es crítico para autorización. Un valor desconocido, expirado,
mal firmado o mal formado **MUST** ignorarse con estado deny-by-default. Nunca
**MUST** almacenarse ni retransmitirse mediante store-forward: una revocación
retrasada o un grant reproducido serían inseguros.

## 6. `HBT_CAPABILITY` exterior `0x24`

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

La política se deriva del `role`; los flags sirven para diagnóstico y futura
validación. Un receptor **SHOULD** comprobar que coincidan y **MUST NOT**
conceder más privilegios por flags inconsistentes.

### 7.2 Admisión y almacenamiento

El paquete **MUST** estar firmado. El receptor **MUST** aplicar el rol solo
después del `ANNOUNCE` autenticado del mismo sender. Un valor desconocido o
inválido **MUST** conservar la política local segura previa; nunca debe
promocionar un nodo a ancla.

`NODE_CAPABILITY` es crítico al aplicarse porque controla relay y
store-forward, pero opcional para mantener una sesión de chat. **MUST NOT**
guardarse en store-forward ni GCS. Un emisor **SHOULD** enviarlo inmediatamente
después de cada `ANNOUNCE`.

## 8. `HBT_TRANSFER_FRAME` Noise interior `0x30`

El plaintext de transporte es:

```text
type: UInt8 = 0x30
hbtFrame: bytes HBT v1
```

El tipo exterior **MUST** ser `NOISE_ENCRYPTED (0x11)` y el destinatario
**MUST** ser el peer de la sesión. El emisor **MUST** haber recibido:

1. `ANNOUNCE` autenticado;
2. `HBT_CAPABILITY 0x24` válido con versión `0x01`;
3. establecimiento exitoso de Noise XX con identidad vinculada.

Un receptor que no conozca `0x30` **MUST** ignorar el plaintext desconocido sin
cerrar la sesión Noise. Una implementación **MUST NOT** tratar `0x30` como el
archivo privado BitChat `0x20`.

El frame `0x30` no es elegible para store-forward por sí mismo. El paquete
Noise exterior depende de una sesión viva. Cuando HearthBit necesita entrega
diferida de un mensaje privado usa Courier, que conserva como ciphertext el
paquete Noise completo y aplica sus propias restricciones. Los blobs de
archivo HBT **MUST NOT** entrar en Courier ni en el store-forward de mensajes.

## 9. ExtensionEnvelope futuro

### 9.1 Objetivo y estado

Las asignaciones `0x23`–`0x25` son heredadas y **MUST** conservarse. Las nuevas
extensiones **SHOULD** usar un `ExtensionEnvelope` común para evitar consumir
más tipos exteriores y para expresar propiedad, versión, criticidad y política
de almacenamiento.

Este documento fija el encoding del envelope, pero no reserva un tipo exterior
BitChat para transportarlo. Hasta que una revisión de este registro asigne un
carrier y su negociación, una implementación **MUST NOT** emitir
`ExtensionEnvelope` en la red ni reutilizar un tipo upstream. Esta restricción
evita inventar compatibilidad.

### 9.2 Encoding

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

### 9.3 Negociación y tipos desconocidos

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

## 10. Proceso de asignación

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
