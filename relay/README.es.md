# HearthBit Relay para Linux

[English](README.md)

Relay BLE para Linux y Raspberry Pi que usa BlueZ por D-Bus y conserva el
paquete binario HearthBit/BitChat v1/v2. Opera a la vez como periférico GATT
(teléfonos y nodos se conectan al relay) y como central (el relay descubre
otros dispositivos con el servicio compatible).

## Funciones

- Servicio y característica compatibles:
  - `F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C`
  - `A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D`
- Decodificación estricta v1/v2, rutas de origen, enteros big-endian y padding.
- Relay con decremento de TTL sin modificar los bytes firmados.
- Identidad persistente X25519/Ed25519, ANNOUNCE firmado y rol de infraestructura.
- Deduplicación persistente mediante BLAKE2s sobre el paquete sin TTL ni padding.
- Store-and-forward acotado en SQLite, con expiración, límites y entregas por enlace.
- Gateway TCP Wi-Fi/LAN opt-in con PSK, AES-256-GCM, mDNS
  `_hearthbit._tcp.local` y anti-loop fuera del frame BitChat.
- Bridges MQTT 5 y Matrix opt-in para mensajes públicos firmados, sin
  transportar datos privados.
- Servicio systemd, contenedor y add-on local de Home Assistant.

Las reglas de relay coinciden con el firmware ancla: no se reenvían paquetes
con TTL menor o igual a uno, `REQUEST_SYNC` (`0x21`) ni handshakes Noise
(`0x10`) sin destinatario.

## Instalación en Raspberry Pi OS/Debian

Requiere Python 3.11 o posterior, BlueZ y un adaptador que permita advertising
BLE:

```bash
sudo apt update
sudo apt install -y bluez python3-venv
sudo useradd --system --home /var/lib/hearthbit-relay --shell /usr/sbin/nologin hearthbit-relay
sudo usermod -aG bluetooth hearthbit-relay
sudo install -d /opt/hearthbit-relay /etc/hearthbit-relay
sudo install -d -o hearthbit-relay -g hearthbit-relay -m 0700 /var/lib/hearthbit-relay
sudo cp -a relay/. /opt/hearthbit-relay/
sudo python3 -m venv /opt/hearthbit-relay/venv
sudo /opt/hearthbit-relay/venv/bin/pip install /opt/hearthbit-relay
sudo cp /opt/hearthbit-relay/config.example.json /etc/hearthbit-relay/config.json
sudo cp /opt/hearthbit-relay/systemd/hearthbit-relay.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hearthbit-relay
sudo journalctl -u hearthbit-relay -f
```

El perfil base se ejecuta como el usuario no privilegiado `hearthbit-relay`,
con solo `CAP_NET_ADMIN`, `CAP_NET_RAW` y pertenencia al grupo `bluetooth`.
BlueZ debe estar encendido por el sistema. Verifique en la distribución que su
política D-Bus permita a ese usuario registrar GATT y advertising; si lo
deniega, añada una regla local limitada a `org.bluez` y no convierta el
servicio en root.

La unidad base solo permite `AF_UNIX` y `AF_BLUETOOTH`. Si activa LAN, MQTT o
Matrix, instale el drop-in de red:

```bash
sudo install -D -m 0644 /opt/hearthbit-relay/systemd/hearthbit-relay-network.conf \
  /etc/systemd/system/hearthbit-relay.service.d/network.conf
sudo systemctl daemon-reload
```

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
- `local_name`: nombre BLE visible; el descubrimiento usa el UUID del servicio.
- `nickname`: nombre publicado dentro del ANNOUNCE firmado.
- `identity_path`: identidad privada persistente con permisos `0600` y
  directorio `0700`.
- `node_role`: `INFRA_RELAY` o `INFRA_DATA_ANCHOR`.
- `announce_interval_seconds`: renovación de ANNOUNCE y capacidad.
- `central_enabled`: busca y conecta otros relays además de aceptar teléfonos.
- `max_central_links`: máximo de conexiones centrales.
- `max_packet_size`: límite antes de decodificar.
- `identity_verification.unknown_signed_policy`: `relay-live` reenvía, pero no
  almacena, firmas sin ANNOUNCE conocido; `reject` exige identidad previa. Una
  clave aprendida queda fijada hasta reiniciar el proceso y toda firma
  posterior se verifica antes de reenviar o guardar.
- `flood`: buckets por sender y bridge, con reserva separada para emergencias.
- `lan`: gateway local desactivado por defecto; requiere `psk_base64` de al
  menos 32 bytes. Consulte
  [`../docs/lan-mesh-gateway.md`](../docs/lan-mesh-gateway.md).
- `mqtt`: bridge desactivado, secretos fuera de la configuración, TLS y
  `bridge_allowlist` explícita para entrada. Consulte
  [`../docs/mqtt-bridge.md`](../docs/mqtt-bridge.md).
- `matrix`: bridge desactivado, HTTPS y allowlist de emisores. Consulte
  [`../docs/matrix-bridge.md`](../docs/matrix-bridge.md).
- `store.max_bytes`, `store.max_packets` y `store.packet_ttl_seconds`: límites
  duros de persistencia.
- `store.require_signature`: exige el flag de firma antes de persistir.
- `store.message_types`: tipos elegibles. ANNOUNCE, capacidades y Noise no se
  persisten.

La expiración TLV de un `CourierEnvelope` siempre reduce, nunca amplía, la
retención configurada.

## Contenedor

El contenedor usa el daemon BlueZ del host. No ejecute un segundo `bluetoothd`
dentro del contenedor.

```bash
cd relay
docker compose up -d --build
```

`compose.yaml` monta el socket D-Bus del sistema y usa red del host. Montar el
D-Bus concede control sobre servicios del sistema; use solo una imagen
construida desde código revisado.

## Add-on local de Home Assistant

1. Copie `relay/` a `/addons/hearthbit_relay` en Home Assistant OS.
2. En **Ajustes > Add-ons > Tienda de add-ons**, recargue los add-ons locales.
3. Instale **HearthBit Relay**, revise sus opciones e inícielo.

El add-on usa `host_dbus` y red del host con el perfil `apparmor.txt`
habilitado. El arranque rechaza secretos simbólicos y fuerza `0600` sobre
identidad, credenciales MQTT y token Matrix en `/data`. La imagen cubre
`aarch64`, `amd64` y `armv7`.

## Desarrollo y pruebas

Las pruebas no necesitan hardware Bluetooth:

```bash
cd relay
python -m venv .venv
. .venv/bin/activate
python -m pip install -e ".[test]"
pytest
```

En Windows use `.venv\Scripts\activate`; el transporte real requiere Linux y
BlueZ.

## Modelo de store-and-forward

El relay persiste bytes opacos y metadatos mínimos: fingerprint, tipo, sender
ID, tiempos y entregas. Cuando aparece un enlace nuevo reenvía un lote
cronológico y registra la entrega. Las cuotas eliminan primero el paquete local
más antiguo y purgan antes las expiraciones.

Esto proporciona transporte diferido; el relay no descifra payloads ni
participa en Noise.

## Limitaciones de esta fase

- Valida ANNOUNCE y fija la clave Ed25519 por sender durante el proceso, pero
  no participa como endpoint en handshakes Noise. Sin ANNOUNCE conocido, la
  política predeterminada permite relay en vivo y prohíbe persistencia.
- No calcula tags HMAC diarios de Courier ni conoce la presencia del
  destinatario. Los sobres siguen cifrados y el receptor deduplica.
- BlueZ notifica a todos los centrales suscritos; la deduplicación neutraliza
  ecos.
- El tamaño efectivo depende del ATT MTU. Los clientes deben usar fragmentación
  `0x20` cuando corresponda.
- Las pruebas automatizadas cubren protocolo y políticas. Advertising,
  dual-role y convivencia Wi-Fi/BLE requieren validación física por adaptador.
