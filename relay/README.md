# HearthBit Relay para Linux

Relay BLE para Linux y Raspberry Pi que usa BlueZ por D-Bus y conserva el
paquete binario HearthBit/BitChat v1/v2. Opera a la vez como periférico GATT
(teléfonos y nodos se conectan al relay) y como central (el relay descubre
otros dispositivos llamados `Bitle Relay`).

## Funciones

- Servicio y característica compatibles:
  - `F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C`
  - `A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D`
- Decodificación estricta v1/v2, rutas de origen, enteros big-endian y padding.
- Relay con decremento de TTL sin modificar los bytes firmados.
- Identidad persistente X25519/Ed25519, ANNOUNCE firmado y rol de infraestructura.
- Deduplicación persistente mediante BLAKE2s sobre el paquete sin TTL ni
  padding.
- Store-and-forward acotado en SQLite, con expiración, límite de registros,
  límite total de bytes y registro de entregas por enlace.
- Servicio systemd, contenedor y add-on local de Home Assistant.

Las reglas de relay coinciden con el firmware ancla: no se reenvían paquetes
con TTL menor o igual a uno, `REQUEST_SYNC` (`0x21`) ni handshakes Noise
(`0x10`) sin destinatario.

## Instalación en Raspberry Pi OS/Debian

Requiere Python 3.11 o posterior, BlueZ y un adaptador que permita
advertising BLE:

```bash
sudo apt update
sudo apt install -y bluez python3-venv
sudo install -d /opt/hearthbit-relay /etc/hearthbit-relay
sudo cp -a relay/. /opt/hearthbit-relay/
sudo python3 -m venv /opt/hearthbit-relay/venv
sudo /opt/hearthbit-relay/venv/bin/pip install /opt/hearthbit-relay
sudo cp /opt/hearthbit-relay/config.example.json /etc/hearthbit-relay/config.json
sudo cp /opt/hearthbit-relay/systemd/hearthbit-relay.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hearthbit-relay
sudo journalctl -u hearthbit-relay -f
```

El servicio se ejecuta como root para que la política del D-Bus de BlueZ
permita registrar GATT y advertising. Su filesystem queda restringido por
systemd y solo `/var/lib/hearthbit-relay` es escribible.

Antes de desplegar, confirme:

```bash
bluetoothctl show hci0
busctl tree org.bluez
```

`Powered: yes` debe estar disponible. Algunos adaptadores USB baratos no
soportan central y periférico simultáneamente.

## Configuración

`config.example.json` contiene todos los campos. Los valores operativos más
importantes son:

- `adapter`: adaptador BlueZ, normalmente `hci0`.
- `local_name`: nombre BLE visible; el discovery usa el UUID de servicio y no
  depende de que otros dispositivos tengan un nombre concreto.
- `nickname`: nombre publicado dentro del ANNOUNCE firmado.
- `identity_path`: archivo privado persistente de identidad; el relay fuerza
  permisos `0600` y directorio `0700`.
- `node_role`: `INFRA_RELAY` o `INFRA_DATA_ANCHOR`.
- `announce_interval_seconds`: renovación periódica del ANNOUNCE y capacidad.
- `central_enabled`: además de aceptar teléfonos, busca y conecta otros relays.
- `max_central_links`: máximo de conexiones centrales (4 por defecto);
  reduzca el valor si el adaptador o controlador BlueZ tiene menos recursos.
- `max_packet_size`: límite previo a decodificar; 2048 cubre los tamaños
  normalizados del protocolo.
- `store.max_bytes` y `store.max_packets`: límites duros de disco.
- `store.packet_ttl_seconds`: retención local máxima.
- `store.require_signature`: exige que el flag de firma esté presente antes
  de persistir.
- `store.message_types`: tipos elegibles para persistencia. Por defecto guarda
  mensajes públicos y CourierEnvelope. ANNOUNCE y capacidades `0x24/0x25`
  nunca se persisten. El transporte Noise `0x11` no se guarda porque depende
  de una sesión viva.

La expiración TLV de un `CourierEnvelope` siempre reduce, nunca amplía, la
retención configurada.

## Contenedor

El contenedor usa el daemon BlueZ del host. No ejecute un segundo `bluetoothd`
dentro del contenedor.

```bash
cd relay
docker compose up -d --build
```

`compose.yaml` monta el socket D-Bus del sistema y usa red del host. Revise
`config.example.json` antes de iniciarlo. Montar el D-Bus del host concede al
contenedor control sobre servicios del sistema; use solamente una imagen
construida desde código revisado.

## Add-on local de Home Assistant

El directorio `relay/` es también un add-on autocontenido:

1. Copie todo `relay/` a `/addons/hearthbit_relay` en Home Assistant OS.
2. En **Ajustes > Add-ons > Tienda de add-ons**, recargue los add-ons locales.
3. Instale **HearthBit Relay**, revise sus opciones e inícielo.

El add-on usa `host_dbus` y red del host. Se declara sin AppArmor porque
necesita registrar un servicio GATT y un anuncio en BlueZ; esto amplía el
impacto de una vulnerabilidad y debe reservarse para hosts dedicados o de
confianza. La base del contenedor es multi-arquitectura y cubre `aarch64`,
`amd64` y `armv7`.

## Desarrollo y pruebas

Las pruebas no necesitan hardware Bluetooth:

```bash
cd relay
python -m venv .venv
. .venv/bin/activate
python -m pip install -e ".[test]"
pytest
```

En Windows use `.venv\Scripts\activate` en lugar de `source`; la ejecución
real del transporte requiere Linux porque BlueZ expone el D-Bus del sistema.

## Modelo de store-and-forward

El relay persiste únicamente bytes opacos y metadatos mínimos: fingerprint,
tipo, sender ID, tiempos y entregas. Al aparecer un enlace nuevo reenvía un
lote cronológico y registra la entrega. La cuota se aplica eliminando primero
el paquete local más antiguo; las expiraciones se purgan antes.

Esto proporciona transporte diferido, no convierte al proceso en un endpoint
de chat. El relay no descifra payloads ni participa en Noise.

## Limitaciones de esta fase

- Tiene identidad propia y valida criptográficamente ANNOUNCE, pero todavía no
  participa como endpoint en handshakes Noise. `require_signature` comprueba
  presencia y formato para los demás paquetes almacenables, no su autenticidad.
- No calcula los tags HMAC diarios de Courier ni conoce cuándo está presente
  el destinatario. Los sobres siguen cifrados y se difunden a enlaces futuros;
  el receptor deduplica por ciphertext.
- La API GATT de BlueZ emite una notificación a todos los centrales suscritos;
  no permite seleccionar uno desde `StartNotify`. Los ecos se neutralizan con
  deduplicación.
- El tamaño efectivo de una escritura BLE depende del ATT MTU negociado. Los
  clientes deben usar la fragmentación `0x20` para paquetes que no quepan.
- Las pruebas automatizadas cubren protocolo, políticas, deduplicación,
  cuotas y replay. El advertising, conexión dual-role y convivencia Wi-Fi/BLE
  requieren validación física en cada modelo de adaptador.
