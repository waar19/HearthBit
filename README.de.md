# HearthBit

<img src="app/assets/icon/hearthbit.png" alt="HearthBit-App-Symbol" width="160">

[English](README.md) · [Español](README.es.md) · **Deutsch** ·
[Français](README.fr.md) · [简体中文](README.zh.md) · [日本語](README.ja.md)

HearthBit („das Netzwerk, das weiterschlägt“) ist eine mobile
Notfallkommunikations-App, die ohne Internet funktioniert. Telefone bilden ein
Bluetooth-Low-Energy-Mesh und leiten Nachrichten weiter. ESP32-Knoten, Android
TV/Automotive sowie Linux- und Raspberry-Pi-Relays können die Reichweite
erweitern.

## Funktionen

- Öffentliche und private, mit BitChat kompatible Kommunikation.
- Signierte SOS-Meldungen, Rettungsmodus und periodische GPS-Aktualisierung.
- Dateiübertragung über Nearby Connections, LAN/Hotspot, Wi-Fi Aware, BLE oder
  optische QR-Codes.
- Professionelles Suchradar mit BLE-Nähe, Trend, Kompass, GPS-Fusion,
  Android-16-Ranging und optionaler akustischer Kurzstreckenmessung.
- Offline-Notrufnummern, Familiengruppen und physische Signalgeber.
- Benutzeroberfläche auf Englisch, Spanisch, Deutsch, Französisch,
  vereinfachtem Chinesisch und Japanisch.

Die Verfügbarkeit hängt von Hardware und Betriebssystem ab. BLE-RSSI liefert
keine echte Richtung; Android Ranging benötigt kompatible Geräte. Das
akustische Sonar ist für etwa 1–25 m gedacht und funktioniert am besten bei
Sichtverbindung. HearthBit ersetzt keine offiziellen Notrufkanäle.

## Transparenz und Datenschutz

Der Quellcode ist öffentlich einsehbar, damit Identität, Verschlüsselung,
Standortverarbeitung, Hintergrundbetrieb und Protokollkompatibilität geprüft
werden können. Siehe [NOTICE.md](NOTICE.md),
[Transparenzbericht](docs/transparency.de.md) und
[Architektur](docs/architecture.md).

Öffentliche Nachrichten sind für Kanalteilnehmer sichtbar. Private Nachrichten
verwenden Noise-XX-Sitzungen. Radar, Standort und akustische Messungen erfordern
eine zeitlich begrenzte Zustimmung. Es gibt keine Garantie für Zustellung,
Entfernungsmessung oder Hintergrundbetrieb.

## Lizenz

HearthBit ist **source-available**, aber kein von der OSI anerkanntes
Open-Source-Projekt. Eigener HearthBit-Code steht unter der
[PolyForm Noncommercial License 1.0.0](LICENSE). Er darf für die dort erlaubten
nichtkommerziellen Zwecke geprüft, verwendet, verändert und weitergegeben
werden. Kommerzielle Nutzung erfordert eine separate schriftliche Lizenz:
[COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md).

Bereits unter MIT veröffentlichte Versionen bleiben unter MIT.
`vendor/bitchat-android/`, Firmware-Submodule und Abhängigkeiten behalten ihre
jeweiligen Lizenzen. Einzelheiten stehen in [NOTICE.md](NOTICE.md).

## Schnellstart

```powershell
git submodule update --init --recursive
cd app
flutter pub get
flutter run
```

Für realistische Mesh-Tests sind physische Geräte mit aktiviertem Bluetooth
erforderlich.

## Projekt unterstützen

Spenden finanzieren Gerätetests, Feldversuche und Relay-Hardware:
[Buy Me a Coffee](https://buymeacoffee.com/wilmeralzal).
