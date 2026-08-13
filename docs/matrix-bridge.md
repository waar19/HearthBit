# Bridge Matrix

El relay Python puede publicar e importar, de forma **opt-in**, eventos
HearthBit en rooms Matrix explícitas. Está desactivado por defecto. Funciona
con un access token de bot o de application service, pero no registra usuarios,
no invita, no hace join y no descubre rooms.

## Frontera de confianza

Matrix es una frontera pública: el homeserver, administradores, bridges,
integraciones y miembros de cada room pueden leer y conservar el texto. E2EE
de Matrix no está implementado. Use únicamente rooms destinadas a mensajes
públicos y aplique allí la política de retención y moderación de la
organización.

Solo cruza la frontera un `MESSAGE (0x02)` que:

1. no tiene `recipientID`;
2. incluye una firma Ed25519 válida;
3. tiene un `ANNOUNCE` reciente, autofirmado y consistente con `senderID`;
4. tiene un timestamp dentro de la ventana configurada.

Un SOS es el mismo tipo público firmado con payload que empieza por `SOS|`.
Tiene una expiración menor. En ambos sentidos se vuelven a verificar tipo,
destinatario ausente, ANNOUNCE, relación de identidad, firma, timestamp,
fingerprint y expiración.

El evento `m.room.message` muestra el payload público como `body` y conserva el
frame firmado original y el ANNOUNCE en `org.hearthbit.bridge.v1`. También
incluye fingerprint, clase `message`/`sos`, publicación, expiración, ID del
bridge y path. El frame no se reconstruye ni se firma de nuevo.

Los mensajes escritos por personas o bots sin metadata HearthBit válida son
solo conversación Matrix: **nunca se inyectan en la malla**. Matrix no puede
convertir texto arbitrario en un mensaje firmado por un peer HearthBit.

## Rooms, allowlist y moderación

`rooms` es una lista cerrada de IDs como `!rescate:example.org`.
`sender_allowlist` es una lista cerrada de IDs Matrix autorizados a aportar
eventos HearthBit, normalmente bots de otros gateways revisados. El bridge
ignora:

- rooms no configuradas;
- emisores fuera de la allowlist y su propio `bot_user_id`;
- eventos sin metadata estricta o con campos adicionales dentro del envelope;
- frames privados, Courier, Noise, fragmentos, sync, capacidades y tipos
  desconocidos.

La allowlist autoriza al emisor Matrix a presentar una prueba; no sustituye la
firma HearthBit. Para operar:

- restrinja invitaciones, envío y lectura con ACL/power levels de Matrix;
- dé al bot solo permiso para enviar `m.room.message`;
- modere spam y contenido público en Matrix;
- rote/revoque el token al retirar un gateway;
- use rooms separadas cuando existan dominios de moderación distintos.

## Anti-loop, deduplicación y replay

Cada bridge deriva un ID estable de la identidad persistente del relay. El
evento conserva el path externo sin modificar el frame. Se rechazan el propio
ID, IDs repetidos, hops mal formados y paths mayores a `max_bridge_hops`.

El fingerprint BLAKE2s canónico no depende del TTL. Un fingerprint importado se
retiene hasta la expiración y se acepta una sola vez; el core conserva además
su deduplicación persistente. La expiración del evento nunca amplía la edad
máxima del timestamp HearthBit. Un reinicio puede volver a ver eventos del
timeline, pero las verificaciones de timestamp/expiración y la deduplicación
del core limitan el replay.

Las transacciones de salida usan IDs deterministas para que un reintento del
homeserver no cree eventos duplicados.

## Privados y sobres opacos

El bridge no descifra privados y no transporta `NOISE_ENCRYPTED`.
`matrix.private_opaque` es una sección separada y permanece deshabilitada.
Aunque puede declarar `peer_ids`, esta versión rechaza `enabled: true`: una
room Matrix no garantiza que un sobre llegue únicamente a peers HearthBit
explícitos ni ofrece routing unicast verificable. Activarlo sin esa garantía
ampliaría destinatarios y metadata, por lo que falla de forma cerrada.

## Token, TLS y logs

El token no es un campo de configuración. Se obtiene primero de la variable
nombrada por `access_token_env` y, si falta, de `access_token_file`. El archivo
no puede ser symlink y en Linux debe tener modo `0600`. No incluya el token en
URLs, repositorios ni opciones del add-on.

HTTPS es obligatorio. HTTP solo se admite en `localhost`, `127.0.0.1` o `::1`
cuando `allow_insecure_localhost_for_tests` es `true`; esa opción existe
exclusivamente para pruebas. `tls_ca_file` permite una CA privada sin
desactivar la validación TLS.

Los logs reportan estado y errores genéricos: no registran token, cuerpos,
frames, contenido de respuestas ni URLs con parámetros.

## Configuración

Ejemplo para un bot:

```json
{
  "matrix": {
    "enabled": true,
    "homeserver_url": "https://matrix.example.org",
    "rooms": ["!rescate:example.org"],
    "sender_allowlist": ["@otro-hearthbit:example.org"],
    "bot_user_id": "@hearthbit:example.org",
    "application_service_mode": false,
    "access_token_env": "HEARTHBIT_MATRIX_ACCESS_TOKEN",
    "access_token_file": "/run/secrets/matrix-token",
    "tls_ca_file": "",
    "private_opaque": {
      "enabled": false,
      "peer_ids": []
    }
  }
}
```

Para un application service use su token y cambie
`application_service_mode` a `true`; el cliente añade `user_id=bot_user_id` a
`/sync` y `/send`. El registro, namespace y permisos del application service se
administran en el homeserver.

## Home Assistant

El add-on expone la sección `matrix`, monta `/ssl` como solo lectura y usa por
defecto `/data/matrix-access-token`. Cree ese archivo mediante un mecanismo
administrativo seguro, con modo `0600`, y no pegue el token en el editor de
opciones.

Antes de activar:

1. cree una cuenta bot o application service con permisos mínimos;
2. una explícitamente esa identidad a las rooms configuradas;
3. instale la CA privada en `/ssl` si aplica;
4. cree `/data/matrix-access-token`;
5. configure IDs exactos de rooms, bot y allowlist;
6. cambie `enabled` a `true` y reinicie.

El relay nunca intentará resolver una room por alias ni hacer autojoin. Si
falla TLS, autenticación o Matrix, no degrada a HTTP ni omite las validaciones.
