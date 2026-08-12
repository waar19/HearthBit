# HearthBit

<img src="app/assets/icon/hearthbit.png" alt="HearthBit app icon" width="160">

**English** · [Español](README.es.md)

HearthBit ("the network that keeps beating") is a mobile emergency
communication app that works without internet. Phones form a Bluetooth Low
Energy (BLE) mesh and relay messages between nearby devices. The fixed ESP32
nodes in `firmware/anchor-node` extend coverage and keep messages in transit.

Beyond chat and SOS alerts, HearthBit transfers files without internet through
a chain of transports with automatic fallback:

- **Nearby Connections** (Android): fast and zero-configuration.
- **LAN / hotspot**: direct TCP when both devices share a local network.
- **Wi-Fi Aware** (Android 10+, progressive): direct data without an access
  point.
- **Inline BLE**: small files (≤ 256 KiB) over the mesh itself.
- **Optical QR**: rateless fountain codes between screen and camera, with no
  radio at all; ideal for isolated devices or bulletins.

Every offer is signed with Ed25519 and the content travels end-to-end
encrypted (X25519 + XChaCha20-Poly1305) with SHA-256 verification, whatever
the transport. On iOS, Nearby and Wi-Fi Aware are not available yet: LAN, BLE
or optical are used instead.

For rescue teams it includes an AirTag-style **proximity radar**: from any SOS
alert you can track the victim's Bluetooth signal with closeness indication,
trend ("you are getting closer" / "the signal is fading"), haptics that speed
up as you approach, and straight-line GPS distance if the alert carried
coordinates. The victim's **rescue mode** re-broadcasts their SOS with fresh
GPS every 5 minutes.

## Support the project

HearthBit is open source and community-supported. Donations help fund physical
device testing, emergency-field trials and relay-node hardware.

[![Support HearthBit on Buy Me a Coffee](https://img.shields.io/badge/Buy_Me_a_Coffee-support_HearthBit-FFDD00?logo=buymeacoffee&logoColor=000000)](https://buymeacoffee.com/wilmeralzal)

## Spread the project

Emergency meshes become more useful as more people install them before a
disaster. Share HearthBit with your family, neighbors, rescue groups and local
communities:

**[Invite someone to HearthBit](https://github.com/waar19/HearthBit)**

The app also includes a native **Share HearthBit** button in About and on the
Nearby screen.

## Languages

The app is localized in English, Spanish, German, French, Chinese (Simplified)
and Japanese, and follows the system language automatically. See
[docs/localization.md](docs/localization.md) to add a new language.

## Components

- `app/`: Flutter application for Android and iOS.
- `app/android/relay/`: relay-only Android TV and Automotive variants.
- `firmware/anchor-node/`: Bitle firmware for ESP32-C3/ESP32-S3.
- `relay/`: Linux/Raspberry Pi relay daemon and Home Assistant add-on.
- `docs/`: protocol, architecture, deployment and field tests.
- `vendor/bitchat-android/`: protocol reference and Noise core used by
  Android.

## Quick start

```powershell
git submodule update --init --recursive
cd app
flutter pub get
flutter run
```

The mesh needs physical devices; emulators do not reproduce the BLE central
and peripheral roles. A useful test requires two Android phones, or one
Android and one iPhone, with Bluetooth enabled.

## Security and scope

Public messages are visible to any channel participant and are signed to
detect tampering. Private messages use Noise XX sessions compatible with
BitChat. HearthBit does not replace official emergency channels and does not
guarantee delivery: BLE and background execution are constrained by each
operating system.

## Licenses

Our own code is distributed under MIT. BitChat is published under the
Unlicense. The Bitle firmware is distributed under MIT and keeps its
attribution in the corresponding submodule.

Direct app dependencies and their licenses: `cryptography`, `sqflite`,
`geolocator`, `path_provider`, `file_selector`, `qr`, `mobile_scanner`,
`image` and `crypto` use compatible MIT/BSD/Apache-2.0 licenses. Google Play
Services Nearby (Android only) is used under the standard Google Play Services
terms. The LT fountain codes of the optical mode are our own implementation
(MIT), with no third-party RaptorQ dependencies.

## Before publishing

Administrative checklist (outside the scope of the code):

1. Trademark availability search for "HearthBit" (classes 9 and 42) and
   registration where applicable.
2. Names on Google Play and the App Store, and project domain(s).
3. Dependency license review on every update (`flutter pub deps`).
4. Run the full physical matrix in `docs/field-test.md`, including the manual
   HearthBit↔BitChat test, before declaring interoperability.
