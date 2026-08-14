# Transparenz und Datenschutz

HearthBit veröffentlicht den Quellcode, damit Identität, Verschlüsselung,
Standortverarbeitung, Hintergrundbetrieb und Interoperabilität überprüft werden
können. Das Projekt ist source-available, nicht OSI-anerkannte Open Source.

## Daten und Netzwerk

Die lokale Mesh-Kommunikation benötigt kein zentrales Konto. Schlüssel und
Identität entstehen auf dem Gerät; Nachrichten, Transfers und ausstehende
Sendungen können lokal gespeichert werden. Die Kern-App benötigt keine
Analytik. Online-Karten, optionale MQTT/Matrix/LAN-Gateways, externe Links und
Google Play Services können jedoch Daten an andere Betreiber übertragen.

BLE-Signale sind für Geräte in der Nähe beobachtbar. Öffentliche Nachrichten
sind nicht vertraulich. Private Nachrichten verwenden Noise XX, aber
Funkpräsenz, Zeitpunkte und Routing-Metadaten können sichtbar bleiben.

## Standort und Entfernung

GPS, BLE-RSSI, Android Ranging und akustisches Sonar haben unterschiedliche
Fehlerquellen. Ein BLE-Rundblick verfällt nach 90 Sekunden oder 15 m Bewegung.
Das Sonar verarbeitet kurze PCM-Aufnahmen im Speicher und erzeugt
hochfrequente Töne, die Menschen, Tiere oder fremde Mikrofone wahrnehmen
können. Messungen sind nicht zertifiziert.

Radar, Standort und akustische Messung benötigen eine zeitlich begrenzte
Zustimmung. Android zeigt während des aktiven Meshes eine dauerhafte
Benachrichtigung; iOS entscheidet selbst über Hintergrund-BLE.

## Grenzen

HearthBit garantiert weder Zustellung noch Anonymität, Schutz gegen
Funkstörungen, reale Identität hinter einem Spitznamen oder Schutz eines
kompromittierten Geräts. Die App ersetzt keine offiziellen Notrufsysteme.
Sicherheitsmeldungen dürfen keine echten Kennungen, Standorte, Aufnahmen oder
Notfallnachrichten veröffentlichen.

## Lizenz

Eigener HearthBit-Code steht unter PolyForm Noncommercial 1.0.0; kommerzielle
Nutzung erfordert eine separate Vereinbarung. Bereits unter MIT veröffentlichte
Versionen bleiben MIT. Drittanbieter und Submodule behalten ihre Lizenzen.
Siehe [`LICENSE`](../LICENSE), [`NOTICE.md`](../NOTICE.md) und
[`COMMERCIAL-LICENSE.md`](../COMMERCIAL-LICENSE.md).
