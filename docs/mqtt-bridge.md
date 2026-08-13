# Bridge MQTT

El relay Python puede enlazar, de forma **opt-in**, mensajes públicos de una
comunidad mediante MQTT 5. El bridge está desactivado por defecto y no
implementa Matrix ni convierte MQTT en un endpoint de chat.

## Frontera de confianza

MQTT es una frontera entre dos dominios: la malla de radio local y el broker.
El broker, sus operadores y otros clientes del topic pueden observar los
mensajes públicos. TLS protege el enlace al broker, pero no oculta el contenido
al broker ni sustituye la firma Ed25519 de HearthBit.

Antes de exportar, el relay exige:

1. `MESSAGE (0x02)` sin `recipientID`; cualquier paquete dirigido se descarta.
2. Firma Ed25519 válida.
3. `ANNOUNCE` reciente, autofirmado, con relación válida entre clave Noise,
   `senderID` y clave de firma.
4. Timestamp de mensaje dentro de la ventana configurada.

El envelope lleva el frame firmado original en base64 y una copia del
`ANNOUNCE` validado como prueba de clave. El `ANNOUNCE` no se publica como
evento independiente ni se inyecta en la malla remota. Al importar se vuelven
a validar tipo, ausencia de destinatario, timestamp, `ANNOUNCE`, relación de
identidad, firma y fingerprint antes de entregar el frame al core.

Esta validación demuestra continuidad criptográfica con la identidad
autodeclarada; **no demuestra** que esa identidad pertenezca a una persona,
organización o rescatista concreto. La autorización de comunidad depende de
las credenciales y ACL del broker. Una comunidad que necesite identidad
organizacional debe añadir un proceso externo de alta y revocación.

Nunca cruzan esta frontera:

- mensajes dirigidos o privados;
- `NOISE_HANDSHAKE` y `NOISE_ENCRYPTED`;
- Courier;
- fragmentos, sync, HBT o transferencias;
- controles de radar;
- ANNOUNCE o capacidades como eventos independientes;
- cualquier tipo desconocido.

Un SOS es un `MESSAGE` público firmado cuyo payload empieza por `SOS|`. Sigue
la misma validación y usa una expiración más corta.

## Transporte y anti-loop

El documento JSON contiene únicamente:

- versión, comunidad y clase `message`/`sos`;
- frame y ANNOUNCE en base64;
- fingerprint BLAKE2s canónico;
- instante de publicación y expiración;
- ID de bridge y path de IDs de bridge.

El frame no se traduce ni se vuelve a firmar. MQTT usa QoS 1 y MQTT 5
`MessageExpiryInterval`. `retain` siempre es `false`; además, el importador
rechaza cualquier entrega marcada como retained. La expiración del envelope
nunca puede ampliar la ventana local del mensaje.

Cada bridge tiene un ID estable derivado de la identidad persistente del relay.
Un ID repetido en el path, el propio ID, un path demasiado largo o un
fingerprint ya importado causa rechazo. El core mantiene además su
deduplicación normal independiente del TTL.

## TLS, mTLS y credenciales

TLS con verificación de hostname es obligatorio; no existe opción para
desactivarlo. `tls_ca_file` permite una CA privada. Para mTLS deben configurarse
juntos `tls_client_cert_file` y `tls_client_key_file`.

Los valores de usuario y contraseña no son campos de configuración y no se
registran en logs. Se obtienen, en este orden:

1. variables indicadas por `username_env` y `password_env`;
2. campos `username` y `password` de `secrets_file` para valores ausentes.

En Linux, el archivo de secretos debe tener modo `0600` y no puede ser un
enlace simbólico. Ejemplo fuera del repositorio:

```json
{"username":"hearthbit-refugio-norte","password":"valor-secreto"}
```

```bash
chmod 600 /var/lib/hearthbit-relay/mqtt-secrets.json
```

Los paths de certificado y clave pueden aparecer en config, pero su contenido
privado debe permanecer en un secret store o volumen de solo lectura.

## Configuración

Instale el extra mantenido de Eclipse Paho:

```bash
python -m pip install -e "relay[mqtt]"
```

Ejemplo mínimo:

```json
{
  "mqtt": {
    "enabled": true,
    "host": "mqtt.example.org",
    "port": 8883,
    "community": "refugio-norte",
    "topic_prefix": "hearthbit",
    "tls_ca_file": "/etc/ssl/certs/community-ca.pem",
    "secrets_file": "/var/lib/hearthbit-relay/mqtt-secrets.json"
  }
}
```

El topic exacto resultante es
`hearthbit/refugio-norte/public`. No se aceptan comodines en el prefijo ni
separadores en el ID de comunidad.

Configure el broker con una identidad distinta por comunidad y ACL de lectura
y escritura solo para ese topic exacto. No conceda `#`, `hearthbit/#` ni acceso
entre comunidades. La ACL se aplica en el broker; el relay también comprueba
que el campo `community` del envelope coincide con su configuración.

## Home Assistant

Las opciones del add-on exponen la sección `mqtt`, los paths bajo `/ssl` y
`secrets_file`, pero nunca usuario o contraseña. `/ssl` se monta de solo
lectura. Para el add-on, cree `/data/mqtt-secrets.json` con modo `0600` mediante
un mecanismo administrativo seguro y deje el path predeterminado. No copie el
secreto al editor de opciones ni a `config.example.json`.

Antes de activar:

1. instale la CA y, si aplica, certificado/clave de cliente en `/ssl`;
2. cree el archivo de secretos;
3. limite la ACL al topic exacto de la comunidad;
4. complete `host` y `community`;
5. cambie `enabled` a `true` y reinicie el add-on.

Si falla TLS, autenticación, suscripción o el ACK QoS 1, el bridge no degrada a
una conexión sin cifrar.
