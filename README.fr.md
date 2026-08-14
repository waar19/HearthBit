# HearthBit

<img src="app/assets/icon/hearthbit.png" alt="Icône de l’application HearthBit" width="160">

[English](README.md) · [Español](README.es.md) · [Deutsch](README.de.md) ·
**Français** · [简体中文](README.zh.md) · [日本語](README.ja.md)

HearthBit (« le réseau qui continue de battre ») est une application mobile de
communication d’urgence qui fonctionne sans Internet. Les téléphones forment un
maillage Bluetooth Low Energy et relaient les messages. Des nœuds ESP32, des
relais Android TV/Automotive, Linux et Raspberry Pi peuvent étendre sa portée.

## Fonctionnalités

- Communications publiques et privées compatibles avec BitChat.
- Alertes SOS signées, mode secours et mises à jour GPS périodiques.
- Transfert de fichiers par Nearby Connections, LAN/hotspot, Wi-Fi Aware, BLE
  ou QR optique.
- Radar de recherche avec proximité BLE, tendance, boussole, fusion GPS,
  Ranging d’Android 16 et mesure acoustique facultative à courte portée.
- Premiers secours hors ligne, groupes familiaux et balises physiques.
- Interface en anglais, espagnol, allemand, français, chinois simplifié et
  japonais.

Les capacités dépendent du matériel et du système. Le RSSI BLE ne fournit pas
une direction réelle ; Android Ranging nécessite des appareils compatibles. Le
sonar acoustique vise environ 1 à 25 m et fonctionne mieux en visibilité
directe. HearthBit ne remplace pas les services d’urgence officiels.

## Transparence et confidentialité

Le code source est visible publiquement afin de permettre l’audit de
l’identité, du chiffrement, de la localisation, du fonctionnement en arrière-
plan et de l’interopérabilité. Consultez [NOTICE.md](NOTICE.md), le
[rapport de transparence](docs/transparency.fr.md) et
[l’architecture](docs/architecture.md).

Les messages publics sont visibles par les participants du canal. Les messages
privés utilisent des sessions Noise XX. Le radar, la localisation et les
mesures acoustiques exigent un consentement temporaire. La livraison, la mesure
de distance et l’exécution en arrière-plan ne sont pas garanties.

## Licence

HearthBit est un projet **source-available**, et non un projet open source
approuvé par l’OSI. Le code original HearthBit est soumis à la
[PolyForm Noncommercial License 1.0.0](LICENSE). Il peut être inspecté, utilisé,
modifié et redistribué pour les usages non commerciaux qu’elle autorise.
L’usage commercial nécessite une licence écrite distincte :
[COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md).

Les versions déjà publiées sous MIT restent sous MIT.
`vendor/bitchat-android/`, les sous-modules du firmware et les dépendances
conservent leurs propres licences. Voir [NOTICE.md](NOTICE.md).

## Démarrage rapide

```powershell
git submodule update --init --recursive
cd app
flutter pub get
flutter run
```

Des appareils physiques avec Bluetooth activé sont nécessaires pour tester
réellement le maillage.

## Soutenir le projet

Les dons financent les essais sur appareils, les tests de terrain et le
matériel de relais :
[Buy Me a Coffee](https://buymeacoffee.com/wilmeralzal).
