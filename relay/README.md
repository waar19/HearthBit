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
- Persistent SHA-256/128 deduplication over packets without TTL or padding,
  with read compatibility for legacy BLAKE2s entries.
- Bounded SQLite store-and-forward with expiry, quotas, and per-link delivery.
- Opt-in Wi-Fi/LAN TCP gateway with PSK, AES-256-GCM, mDNS
  `_hearthbit._tcp.local`, and loop prevention outside the BitChat frame.
- Opt-in MQTT 5 and Matrix bridges for signed public messages; neither carries
  private data.
- Opt-in Reticulum/LXMF bridge for verified signed public messages between
  explicitly allowlisted relay destinations; private traffic is never exported.
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

The base service runs as the unprivileged `hearthbit-relay` user with only
`CAP_NET_ADMIN`, `CAP_NET_RAW`, and membership in `bluetooth`. Verify that the
distribution's D-Bus policy lets that user register BlueZ GATT and advertising;
if needed, add a narrowly scoped local `org.bluez` policy instead of running
the relay as root.

The base unit permits only `AF_UNIX` and `AF_BLUETOOTH`. When LAN, MQTT, or
Matrix is enabled, install `systemd/hearthbit-relay-network.conf` as
`/etc/systemd/system/hearthbit-relay.service.d/network.conf`.

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
- `trust_store_path`: atomically persisted TOFU peer identities with `0600`
  permissions. When omitted, `trusted-peers.json` is placed beside
  `identity_path`.
- `node_role`: `INFRA_RELAY` or `INFRA_DATA_ANCHOR`.
- `announce_interval_seconds`: ANNOUNCE and capability refresh interval.
- `central_enabled`: discovers and connects to relays in addition to accepting
  phones.
- `max_central_links`: maximum central connections.
- `max_packet_size`: pre-decode input limit.
- `identity_verification.unknown_signed_policy`: `reject` requires a valid
  ANNOUNCE before any signed packet can be forwarded or stored. The legacy
  `relay-live` value remains accepted for configuration compatibility but is
  treated as `reject`; it never permits unverified forwarding. Learned signing
  keys remain pinned across restarts. A corrupt trust store prevents startup
  rather than resetting trust.
- `flood`: per-sender and per-bridge token buckets with emergency reserve.
- `lan`: local gateway, disabled by default; requires a `psk_base64` of at
  least 32 bytes. See
  [`../docs/lan-mesh-gateway.md`](../docs/lan-mesh-gateway.md).
- `mqtt`: disabled bridge, secrets outside the configuration, mandatory TLS,
  and an explicit inbound `bridge_allowlist`.
  See [`../docs/mqtt-bridge.md`](../docs/mqtt-bridge.md).
- `matrix`: disabled bridge requiring HTTPS and a sender allowlist. See
  [`../docs/matrix-bridge.md`](../docs/matrix-bridge.md).
- `reticulum`: disabled LXMF bridge requiring explicit 16-byte destination
  hashes and source allowlists. Install it with
  `pip install -e ".[reticulum]"`. Only verified signed public messages cross
  the bridge, and emergency coordinates remain blocked unless the operator
  opts in.
- `store.max_bytes`, `store.max_packets`, and `store.packet_ttl_seconds`: hard
  persistence limits.
- `store.require_signature`: requires the signature flag before persistence.
- `store.message_types`: eligible types. ANNOUNCE, capabilities, and Noise are
  never persisted.

A `CourierEnvelope` expiry TLV can only reduce, never extend, configured
retention. `EMERGENCY_ACK 0x2B` is persisted only with a recipient, signature,
and the registered payload shape; retention never exceeds 48 hours even when
`store.packet_ttl_seconds` is higher. Ambiguous legacy ACK `0x29` is always
purged.

Stop the service before trust administration. `hearthbit-relay-trust --store
PATH list` lists sender IDs; `remove --sender ID --confirm` explicitly clears
one pin, while `replace --sender ID --signing-key KEY --noise-key KEY --confirm`
atomically rotates public identity material. Obtain replacement keys over an
authenticated administrative channel.

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

The add-on uses `host_dbus` and host networking with `apparmor.txt` enabled.
Startup rejects symlinked secrets and forces mode `0600` for identity, MQTT
credentials, and Matrix tokens under `/data`. The image supports `aarch64`,
`amd64`, and `armv7`.

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

- It validates ANNOUNCE and persistently pins each sender's Ed25519 key but is
  not a Noise handshake endpoint. Without a known ANNOUNCE, the default policy
  permits live relay and forbids persistence.
- It does not calculate daily Courier HMAC tags or know recipient presence.
  Envelopes remain encrypted and recipients deduplicate them.
- BlueZ notifies every subscribed central; deduplication neutralizes echoes.
- Effective write size depends on ATT MTU. Clients must use `0x20`
  fragmentation when needed.
- Automated tests cover protocol and policies. Advertising, dual-role
  operation, and Wi-Fi/BLE coexistence require physical validation for each
  adapter model.
