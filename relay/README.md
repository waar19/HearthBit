# HearthBit Relay for Linux

[Español](README.es.md)

BLE relay for Linux and Raspberry Pi using BlueZ over D-Bus while preserving
the HearthBit/BitChat v1/v2 binary packet. It operates both as a GATT
peripheral, accepting phones and nodes, and as a central that discovers other
devices exposing the compatible service.

## Features

- Compatible service and characteristic:
  - `F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C`
  - `A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D`
- Strict v1/v2 decoding, source routes, big-endian integers, and padding.
- TTL-decrementing relay that does not modify signed bytes.
- Persistent X25519/Ed25519 identity, signed ANNOUNCE, and infrastructure role.
- Persistent BLAKE2s deduplication over packets without TTL or padding.
- Bounded SQLite store-and-forward with expiry, quotas, and per-link delivery.
- Opt-in Wi-Fi/LAN TCP gateway with PSK, AES-256-GCM, mDNS
  `_hearthbit._tcp.local`, and loop prevention outside the BitChat frame.
- Opt-in MQTT 5 and Matrix bridges for signed public messages; neither carries
  private data.
- systemd service, container, and local Home Assistant add-on.

Relay rules match the anchor firmware: packets are not forwarded when TTL is
one or less, nor are `REQUEST_SYNC` (`0x21`) or undirected Noise handshakes
(`0x10`).

## Raspberry Pi OS/Debian installation

Python 3.11 or later, BlueZ, and a BLE adapter that supports advertising are
required:

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

The service runs as root so that the BlueZ D-Bus policy permits GATT and
advertising registration. systemd restricts its filesystem; only
`/var/lib/hearthbit-relay` is writable.

Check the adapter before deployment:

```bash
bluetoothctl show hci0
busctl tree org.bluez
```

`Powered: yes` must be available. Some inexpensive USB adapters cannot operate
as central and peripheral simultaneously.

## Configuration

`config.example.json` contains every field. The main operational values are:

- `adapter`: BlueZ adapter, usually `hci0`.
- `local_name`: visible BLE name; discovery uses the service UUID.
- `nickname`: name published in the signed ANNOUNCE.
- `identity_path`: persistent private identity with forced `0600` file and
  `0700` directory permissions.
- `node_role`: `INFRA_RELAY` or `INFRA_DATA_ANCHOR`.
- `announce_interval_seconds`: ANNOUNCE and capability refresh interval.
- `central_enabled`: discovers and connects to relays in addition to accepting
  phones.
- `max_central_links`: maximum central connections.
- `max_packet_size`: pre-decode input limit.
- `lan`: local gateway, disabled by default; requires a `psk_base64` of at
  least 32 bytes. See
  [`../docs/lan-mesh-gateway.md`](../docs/lan-mesh-gateway.md).
- `mqtt`: disabled bridge, secrets outside the configuration, mandatory TLS.
  See [`../docs/mqtt-bridge.md`](../docs/mqtt-bridge.md).
- `matrix`: disabled bridge requiring HTTPS and a sender allowlist. See
  [`../docs/matrix-bridge.md`](../docs/matrix-bridge.md).
- `store.max_bytes`, `store.max_packets`, and `store.packet_ttl_seconds`: hard
  persistence limits.
- `store.require_signature`: requires the signature flag before persistence.
- `store.message_types`: eligible types. ANNOUNCE, capabilities, and Noise are
  never persisted.

A `CourierEnvelope` expiry TLV can only reduce, never extend, configured
retention.

## Container

The container uses the host BlueZ daemon. Do not run a second `bluetoothd`
inside it.

```bash
cd relay
docker compose up -d --build
```

`compose.yaml` mounts the system D-Bus socket and uses host networking.
Mounting D-Bus grants control over host services; use only an image built from
reviewed source.

## Local Home Assistant add-on

1. Copy `relay/` to `/addons/hearthbit_relay` on Home Assistant OS.
2. In **Settings > Add-ons > Add-on store**, reload local add-ons.
3. Install **HearthBit Relay**, review its options, and start it.

The add-on uses `host_dbus` and host networking. It runs without AppArmor
because BlueZ GATT and advertising registration require broad host access; use
it only on dedicated or trusted hosts. The image supports `aarch64`, `amd64`,
and `armv7`.

## Development and tests

Automated tests do not require Bluetooth hardware:

```bash
cd relay
python -m venv .venv
. .venv/bin/activate
python -m pip install -e ".[test]"
pytest
```

On Windows use `.venv\Scripts\activate`. The real transport requires Linux and
BlueZ.

## Store-and-forward model

The relay persists opaque bytes and minimal metadata: fingerprint, type,
sender ID, timestamps, and deliveries. When a new link appears, it forwards a
chronological batch and records delivery. Quota enforcement purges expired
packets first, then the oldest local packet.

This provides delayed transport. The relay does not decrypt payloads or
participate in Noise.

## Current limitations

- It validates ANNOUNCE but is not a Noise handshake endpoint.
  `require_signature` checks presence and format, not authenticity, for other
  storable packets.
- It does not calculate daily Courier HMAC tags or know recipient presence.
  Envelopes remain encrypted and recipients deduplicate them.
- BlueZ notifies every subscribed central; deduplication neutralizes echoes.
- Effective write size depends on ATT MTU. Clients must use `0x20`
  fragmentation when needed.
- Automated tests cover protocol and policies. Advertising, dual-role
  operation, and Wi-Fi/BLE coexistence require physical validation for each
  adapter model.
