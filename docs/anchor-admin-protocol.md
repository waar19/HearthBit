# Protocolo de administración del Anchor

El panel de administración está disponible desde firmware Anchor `v6`. Usa la
sesión Noise XX existente y no agrega UUIDs BLE ni tipos de paquete BitChat. El
contenido interno cifrado usa el tipo Noise `0x31`.

## Seguridad

- La clave nunca se transmite. El teléfono deriva un verificador de 32 bytes
  con PBKDF2-HMAC-SHA256, salt de 16 bytes generado por el Anchor y 120.000
  iteraciones.
- El Anchor conserva en NVS (`admin`) solo salt, verificador y estado de
  bloqueo. Cada comando protegido incluye HMAC-SHA256 con el verificador.
- `AUTH_CHALLENGE_GET` entrega un nonce aleatorio de 16 bytes, asociado a
  conexión y `request_id`, válido por 30 segundos y consumido una sola vez.
- Después de cinco pruebas incorrectas se aplica un bloqueo persistente de
  30 segundos. Los siguientes fallos duplican el tiempo hasta un máximo de una
  hora. Una autenticación correcta limpia el contador.
- Noise cifra y autentica el transporte. El HMAC adicional demuestra posesión
  de la clave y evita repetición dentro de una sesión.

El primer `SET_PASSWORD` reclama un Anchor sin clave. Durante ese paso no existe
todavía un secreto previo que autentique al propietario. El despliegue debe
reclamar cada placa bajo control físico, antes de exponerla en un lugar público,
y verificar el identificador de peer mostrado en la aplicación.

## Formato

Todos los enteros son big-endian.

Solicitud:

```
version:u8 = 1 | command:u8 | request_id:u32 | body
```

Respuesta:

```
version:u8 = 1 | (command | 0x80):u8 | request_id:u32 | status:u8 | body
```

Comandos:

- `0x01 STATUS_GET`
- `0x02 AUTH_CHALLENGE_GET`
- `0x03 SET_PASSWORD`
- `0x04 CHANGE_PASSWORD`
- `0x05 RENAME`
- `0x06 REBOOT`
- `0x07 FACTORY_RESET`

Estados:

- `0`: correcto
- `1`: trama inválida
- `2`: versión o comando no compatible
- `3`: Anchor sin reclamar
- `4`: Anchor ya reclamado
- `5`: autenticación incorrecta
- `6`: bloqueo temporal
- `7`: desafío expirado
- `8`: valor inválido
- `9`: fallo interno

## Challenge y prueba

La respuesta de challenge contiene:

```
claimed:u8 | salt:16 | nonce:16 | iterations:u32 | retry_after_seconds:u32
```

Una solicitud autenticada contiene:

```
header:6 | nonce:16 | command_data:N | proof:32
```

`proof = HMAC-SHA256(verifier, header || nonce || command_data)`.

Para `SET_PASSWORD`, `command_data` es el nuevo verificador y ese mismo valor
autentica la prueba. Para `CHANGE_PASSWORD`, la prueba usa el verificador actual
y los datos contienen el nuevo. `RENAME` usa `length:u8 | ASCII imprimible`;
reinicio y restablecimiento no llevan datos.

## Estado operativo

`STATUS_GET` no requiere la clave, pero solo se acepta dentro de Noise. Su cuerpo
contiene:

```
claimed:u8
firmware_version:u32
protocol_version:u32
uptime_ms:u64
boot_count:u64
received:u64 | forwarded:u64 | stored:u64 | delivered:u64
deduplicated:u64 | expired:u64 | rejected:u64
last_activity_uptime_ms:u64
mailbox_used:u16 | mailbox_capacity:u16
mailbox_available:u8 | clock_valid:u8 | clock_authoritative:u8
nickname_length:u8 | nickname
```

No incluye IDs de personas, contenido, coordenadas, tags de destinatario ni
claves.

## Restablecimiento

`FACTORY_RESET` borra identidad Noise/Ed25519, nombre, reloj, métricas, estado
administrativo, configuración LoRa, estado OTA y el buzón `msgstore`. La
respuesta cifrada se encola antes de programar el reinicio. Después del arranque
el dispositivo tiene un peer ID nuevo y debe reclamarse nuevamente.

## Validación física de firmware v6

La interoperabilidad Android↔ESP32-S3 N16R8 se comprobó en hardware real:

- reclamo inicial y persistencia de la clave;
- cambio de nombre y persistencia tras reinicio;
- incremento del contador de arranques;
- rechazo de clave incorrecta y bloqueo temporal con cuenta regresiva visible;
- restablecimiento de fábrica con identidad nueva, `boot_count` reiniciado y
  estado administrativo nuevamente sin reclamar.

La prueba no registró ni publicó claves, identificadores completos, contenido
de mensajes ni coordenadas.
