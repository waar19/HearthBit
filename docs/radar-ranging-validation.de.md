# Validierung von Radar und Entfernungsmessung

[English](radar-ranging-validation.en.md) ·
[Español](radar-ranging-validation.md) · **Deutsch** ·
[Français](radar-ranging-validation.fr.md) ·
[简体中文](radar-ranging-validation.zh.md) ·
[日本語](radar-ranging-validation.ja.md)

## Umfang und Sicherheit

- GPS dient zur Führung über größere Entfernungen.
- BLE RSSI zeigt Nähe und Trend, aber keine physische Richtung.
- Der experimentelle BLE-Rundblick verfällt nach 90 Sekunden oder 15 m.
- Android Ranging nutzt je nach Hardware Channel Sounding, Wi-Fi NAN RTT oder
  BLE RSSI auf Android 16 oder neuer.
- Das akustische Sonar misst kurze Distanzen in drei BeepBeep-ähnlichen Runden.

Das Sonar funktioniert am besten bei 1–25 m und freier Sicht. Nicht direkt am
Ohr verwenden; Kinder und Tiere können hohe Frequenzen hören. Keine Messung
ersetzt die Beurteilung durch Rettungskräfte.

## Layout

1. Radar auf einem schmalen Bildschirm öffnen.
2. Das Telefon in die Nähe von Metall bringen.
3. Prüfen, dass nur ein Hinweis erscheint und der Kreis nicht wandert.
4. Eine Acht bewegen und prüfen, dass der Hinweis ohne Layoutsprung verschwindet.
5. Rundblick starten; die Anleitung muss über dem Kreis liegen.
6. Nach 90 Sekunden oder 15 m muss ein neuer Rundblick verlangt werden.

## Android Ranging

Zwei Geräte mit Android 16+ und `RANGING`-Berechtigung:

1. Mesh und Radarfreigabe am Ziel aktivieren.
2. Radar am zweiten Telefon öffnen und Funkmessung starten.
3. Gemessene Distanz und Fehlerspanne prüfen.
4. Bei 1, 3, 5 und 10 m mit freier Sicht und einer Wand wiederholen.

## Akustiktest Android–iPhone

1. App offen lassen, Radar- und Mikrofonfreigabe erteilen.
2. Bluetooth-Headsets trennen; Lautsprecher und Mikrofone freilassen.
3. Geräte 1–3 m auseinanderlegen und die Akustikmessung starten.
4. Während aller drei Runden stillhalten und mit einem Maßband vergleichen.
5. Bei 5, 10 und 20 m sowie mit Umgebungsgeräuschen wiederholen.

Fehlen zwei Chirps pro Runde, muss HearthBit das Ergebnis verwerfen.

## Dauerhafte Android-Benachrichtigung

Mesh aktivieren, die Benachrichtigung unter Android 14+ wegwischen und prüfen,
dass sie erneut erscheint. Nach dem Stoppen des Meshes muss sie dauerhaft
verschwinden.
