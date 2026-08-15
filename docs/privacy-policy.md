# HearthBit Privacy Policy

**Effective date:** August 15, 2026  
**Last updated:** August 15, 2026

[Versión en español](privacy-policy.es.md)

HearthBit is an offline-first emergency communication application maintained
by the HearthBit project. This policy explains how HearthBit processes
information when you use the mobile application.

HearthBit does not require an account and the project maintainer does not
operate a central messaging, identity, or analytics server. Most information is
processed and stored on your device or sent directly to devices and services
that you choose to use.

## Information HearthBit processes

### Identity and device information

HearthBit generates cryptographic identity keys and a peer identity on your
device. Your chosen nickname, public keys, device capabilities, rotating
discovery tokens, and radio/network metadata may be exchanged with nearby
compatible devices so they can discover, authenticate, and communicate with
your device.

Nearby observers may infer that a compatible device is present and may observe
signal strength and timing. HearthBit's private mode reduces persistent
identifiers in normal Bluetooth discovery, but radio anonymity cannot be
guaranteed. Enabling optional BitChat interoperability increases the amount of
identity information visible to compatible devices.

### Messages, files, voice notes, and trusted contacts

Messages, pending outbox entries, file transfers, voice notes, and trusted
family configuration may be stored locally so HearthBit can work without
internet. Public-channel messages and public SOS alerts are intentionally
shared with participants in the reachable mesh. Private messages and private
transfers use authenticated encrypted sessions.

HearthBit does not request access to your address book. If you enter a trusted
contact's phone number, it is stored locally and is passed to your chosen
messaging application only when you ask HearthBit to prepare an SMS. HearthBit
does not send the SMS automatically.

### Location

HearthBit may process precise or approximate location to:

- attach a location to an SOS when you explicitly choose exact, approximate, or
  no location;
- refresh rescue-mode SOS broadcasts and calculate rescue-radar distance;
- provide temporary location updates to verified trusted-family members; and
- display maps and cache map tiles for offline use.

On Android, HearthBit requests background location because rescue mode must be
able to refresh SOS coordinates while the screen is off. Background location
is used for this emergency feature while the mesh/rescue foreground service is
active, with a persistent system notification. HearthBit does not send your
location to the project maintainer.

A public SOS deliberately shares its selected location precision and
cryptographic identity with reachable mesh participants. Private family
check-ins are sent through encrypted private channels. Your operating system
may independently retain permission and location-access records.

### Microphone

Microphone access is used only when you initiate a voice note or optional
acoustic distance measurement. Voice notes are stored locally and sent to the
recipient you select. Acoustic ranging records short audio windows in memory
to detect ranging signals; HearthBit does not intentionally save those windows
as voice recordings. Audio is not sent to the project maintainer.

### Camera

Camera access is used when you choose to scan QR codes for trusted-family
verification or optical file transfer. Camera frames are processed on the
device and are not sent to the project maintainer.

### Bluetooth, nearby devices, and local networks

HearthBit uses Bluetooth Low Energy, Android Nearby Connections, Wi-Fi Aware,
LAN/hotspot connections, and related device signals to discover compatible
devices, relay messages, estimate proximity, and transfer files. Depending on
the selected transport, nearby devices and platform providers may process
device identifiers, network addresses, radio metadata, and transfer metadata.

### Diagnostics

HearthBit may create diagnostic logs on the device to help explain failures.
These logs are not uploaded automatically. Review and remove personal or
emergency information before choosing to share a diagnostic report.

## Internet access and third-party services

The core local mesh does not need a HearthBit-operated server. Network access
can occur when you:

- load online map tiles;
- use an operating-system or third-party transport such as Google Play
  Services Nearby;
- enable an optional MQTT, Matrix, Reticulum/LXMF, or LAN gateway;
- open an external link; or
- use a donation or project-hosting service.

These providers may receive information such as your IP address, requested map
area, device/network metadata, identifiers, message content, or timestamps,
depending on the feature you activate. Their processing is governed by their
own terms and privacy policies.

Optional gateways intentionally move messages beyond the local mesh and change
the trust boundary. Gateway operators are responsible for disclosing their
deployment, protecting credentials and logs, and complying with applicable
law. External bridges block emergency frames containing coordinates by
default, unless an operator explicitly enables that forwarding.

## How information is shared

HearthBit shares information only as needed for features you activate:

- with reachable mesh participants when you publish a message or SOS;
- with a selected recipient when you send a private message, file, voice note,
  or trusted-family update;
- with nearby compatible devices for discovery, authentication, routing, and
  proximity estimation;
- with a gateway or third-party service that you enable; and
- with your chosen phone, SMS, file, or browser application when you initiate
  the corresponding action.

The HearthBit project maintainer does not sell personal information and does
not use it for advertising or behavioral profiling.

## Storage, security, and retention

HearthBit stores operational data on your device for offline reliability.
Identity keys and other secrets use platform-protected storage where available.
App-controlled received files and voice notes are encrypted at rest and may be
temporarily decrypted for playback or export. No security mechanism can
protect information after a device, recipient, gateway, or signing key is
compromised.

Data remains on your device until you delete it, use HearthBit's emergency wipe,
clear the app's data, or uninstall the app, subject to operating-system behavior.
Emergency wipe removes HearthBit-controlled identities, trust state, messages,
transfers, preferences, caches, and known temporary files. It cannot delete
copies already delivered to another device or service, or guarantee deletion
from operating-system backups, notification history, or exported files.

## Your choices

You can:

- deny optional permissions, although the related feature will not work;
- choose exact, approximate, or no location before a public SOS;
- disable rescue mode, optional gateways, interoperability, and acoustic
  ranging;
- delete individual content where the app provides that control;
- use emergency wipe to remove HearthBit-controlled local data; and
- clear app storage or uninstall HearthBit using your operating system.

## Children's privacy

HearthBit is not designed to collect personal information from children for
the project maintainer. Because emergency messages can disclose sensitive
information to other devices, a parent or guardian should supervise use by a
minor and review location and communication choices.

## Emergency and safety limitations

HearthBit is not a certified medical, navigation, emergency-service, or
public-safety system. It does not guarantee delivery, precise ranging, radio
anonymity, or availability. Contact official emergency services whenever they
are available.

## Changes to this policy

Material changes will be published on this page with a new “Last updated” date.
The version available at this URL applies to the current public release unless
the release notes state otherwise.

## Contact

For privacy questions, contact the HearthBit maintainer through the verified
contact channel on the
[repository owner's GitHub profile](https://github.com/waar19). Do not post
locations, private keys, recordings, emergency messages, or other sensitive
information in a public issue. Security vulnerabilities must be reported using
the [private security advisory form](https://github.com/waar19/HearthBit/security/advisories/new).

Additional technical detail is available in the
[HearthBit transparency document](transparency.md).
