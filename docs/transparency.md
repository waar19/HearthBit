# HearthBit transparency and privacy

HearthBit publishes its implementation so people can verify what the app does
during an emergency. Source visibility is a privacy and accountability
mechanism; it does not make the project OSI-approved open source. Licensing is
explained in [`NOTICE.md`](../NOTICE.md).

## Data model

HearthBit does not require a central account for local mesh communication.
Identity and cryptographic keys are generated on the device. Messages, pending
outbox entries, transfers and trusted-family configuration can be stored
locally so the app continues to work without internet.

The core app does not require an analytics service. Network access can still
occur when a user:

- loads online map tiles;
- enables an MQTT, Matrix or LAN gateway;
- follows an external link or donation link;
- uses an operating-system or third-party transport such as Google Play
  Services Nearby.

Those services have their own operators, logs, privacy policies and licenses.

## What nearby devices can observe

Private mode is enabled by default. On Android, the scan response contains a
keyed discovery token that rotates every 15 minutes instead of the stable peer
ID. iOS advertises only the service UUID. Nearby observers may still infer that
a HearthBit-compatible device is present, measure radio strength and correlate
timing. An active peer that connects can learn the identity needed to
authenticate the link. HearthBit reduces passive tracking; it does not provide
radio anonymity.

BitChat interoperability is an advanced opt-in. It restores the stable peer ID
and full identity-announcement propagation required by compatible BitChat
clients, increasing correlation risk. In private mode ordinary identity
announcements remain one hop. A public SOS deliberately sends a full-reach
signed announcement first so distant relays can verify it.

Public-channel messages are intended for channel participants and must not be
treated as confidential. They are signed to detect tampering. Private messages
use authenticated Noise XX sessions, but routing metadata, packet timing and
radio presence can remain observable.

## Location and rescue radar

Before a public SOS the user chooses exact, approximate (coordinates rounded to
three decimals), or no location. The choice also applies to periodic rescue
pings. The SOS message and cryptographic identity remain public to the mesh.
Check-ins from the emergency screen are instead sent through Noise-encrypted
private channels to verified family members. Operating systems may retain
permission and location-access records independently of HearthBit.

Radar sources have different limits:

- GPS reports a position and accuracy estimate, not indoor direction.
- BLE RSSI estimates proximity and trend; reflections, bodies and walls can
  change it sharply.
- A BLE sweep infers a broad sector and expires after 90 seconds or 15 m of
  movement.
- Android Ranging uses the technology selected by Android 16 and compatible
  hardware.
- Acoustic ranging records short PCM windows in memory and emits high-frequency
  chirps. It does not intentionally save those recordings as voice notes, but
  people, animals and other microphones nearby may hear or capture them.

Ranging-control packets are directed and identity-signed. They prevent
undetected modification by unknown senders but do not conceal all radio
metadata. Measurements are aids, not certified location evidence.

## Files, voice and local storage

File offers are signed and accepted content is verified. Private transfer
content uses the authenticated transfer channel. App-controlled received files
and voice notes are encrypted by chunks at rest and materialized as temporary
cleartext only when needed for playback. iOS marks transfer and map-cache
directories as excluded from backup.

Local databases and caches improve offline reliability. Sensitive Flutter
screens request screenshot protection (`FLAG_SECURE` on Android; capture
obscuring while iOS reports active capture). iOS cannot prevent every still
screenshot. Panic wipe removes identities, trust state, gateway TOFU pins,
preferences, transfer files, map tiles and known HearthBit temporary files, but
cannot guarantee deletion from prior backups, notification history or another
participant's device.

## Optional gateways

MQTT, Matrix and LAN gateways intentionally move messages beyond the local BLE
mesh. Enabling one changes the trust boundary: gateway operators and remote
servers may process identifiers, message content and timestamps. Administrators
must disclose that deployment and protect credentials, logs and broker/server
access. External bridges block emergency frames carrying coordinates by
default; forwarding them requires explicit operator consent. LAN binds to
loopback by default, and MQTT egress requires a non-empty bridge allowlist.

## Background behavior and battery

Android uses a foreground service and a visible persistent notification while
the mesh is active. iOS background BLE behavior is controlled by the operating
system and cannot be guaranteed. Power profiles reduce scanning and location
frequency, which can delay discovery. Survival mode is an explicit trade-off
between reachability and battery life.

## Security boundaries

HearthBit aims to provide authenticated identities, private sessions, replay
protection and signed emergency controls. It does not claim:

- guaranteed delivery or resistance to radio jamming;
- anonymity against nearby observers;
- protection after a device or signing key is compromised;
- verified real-world identity from a nickname alone;
- certified medical, navigation or public-safety operation.

Report vulnerabilities responsibly without publishing real peer identifiers,
locations, recordings or emergency messages.

## Reproducibility and verification

Protocol specifications, test vectors and validation guides are kept in
`docs/` and `tests/`. Android and Flutter automated tests cover codecs,
reconnection, privacy controls and layout. iOS-native changes must also be
compiled and tested on macOS. Claims that depend on hardware remain marked as
pending until the physical matrix passes.

## Licensing transparency

Original HearthBit code is source-available under PolyForm Noncommercial 1.0.0
and can be commercially licensed separately. Previously published MIT versions
remain MIT. Third-party and submodule code retains its own terms. See
[`LICENSE`](../LICENSE), [`NOTICE.md`](../NOTICE.md) and
[`COMMERCIAL-LICENSE.md`](../COMMERCIAL-LICENSE.md).
