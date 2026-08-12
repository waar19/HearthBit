// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'HearthBit';

  @override
  String storageOpenError(String error) {
    return 'Lokaler Speicher konnte nicht geöffnet werden:\n$error';
  }

  @override
  String statusActiveLabel(String nickname, int count) {
    return '$nickname · $count in der Nähe';
  }

  @override
  String statusDegradedLabel(String nickname) {
    return '$nickname · nur Empfang (kein BLE-Advertising)';
  }

  @override
  String get statusStarting => 'Mesh wird gestartet…';

  @override
  String get statusError => 'Mesh-Fehler';

  @override
  String get statusStopped => 'Mesh gestoppt';

  @override
  String get actionStop => 'STOPPEN';

  @override
  String get actionRestart => 'NEU STARTEN';

  @override
  String get actionActivate => 'EINSCHALTEN';

  @override
  String get actionRetry => 'ERNEUT VERSUCHEN';

  @override
  String get tooltipChangeName => 'Namen ändern';

  @override
  String get tooltipPanicWipe => 'Notfall-Löschung';

  @override
  String get tabChannel => 'Kanal';

  @override
  String get tabNearby => 'In der Nähe';

  @override
  String get tabFiles => 'Dateien';

  @override
  String get tabSos => 'SOS';

  @override
  String get emptyChatTitle => 'Noch keine Nachrichten';

  @override
  String get emptyChatBody =>
      'Schalte das Mesh ein. Nachrichten springen ohne Internet zwischen Telefonen in der Nähe.';

  @override
  String get composerPublicHint => 'Nachricht an alle in der Nähe';

  @override
  String get composerPrivateHint => 'Verschlüsselte Nachricht';

  @override
  String get privateChatIntro =>
      'Die erste Nachricht startet einen Noise-XX-Handshake.';

  @override
  String get emptyPeersTitle => 'Keine Geräte in der Nähe';

  @override
  String get emptyPeersBody =>
      'Lass Bluetooth aktiviert und bringe ein anderes Telefon mit HearthBit oder BitChat in die Nähe.';

  @override
  String get peerSecure => 'verschlüsselter Kanal bereit';

  @override
  String get peerTapToEncrypt => 'zum Verschlüsseln tippen';

  @override
  String get tooltipRadar => 'Näherungsradar';

  @override
  String get tooltipSendFile => 'Datei senden';

  @override
  String get sosCardTitle => 'Prioritätsalarm senden';

  @override
  String get sosCardBody =>
      'Wenn möglich, wird dein GPS-Standort angehängt. Der Alarm ist öffentlich und wird über das Mesh weitergeleitet.';

  @override
  String get sosMedical => 'Ich brauche medizinische Hilfe';

  @override
  String get sosTrapped => 'Ich bin eingeschlossen';

  @override
  String get sosImOk => 'Mir geht es gut';

  @override
  String get sosDefaultMessage => 'Ich brauche Hilfe';

  @override
  String get sosReceivedTitle => 'Empfangene Alarme';

  @override
  String get sosNoneReceived => 'Keine SOS-Alarme empfangen.';

  @override
  String get actionTrack => 'ORTEN';

  @override
  String get rescueModeTitle => 'Rettungsmodus';

  @override
  String rescueModeActive(int minutes) {
    return 'Dein SOS wird alle $minutes Min. mit Standort erneut gesendet.';
  }

  @override
  String rescueModeLastPing(String time) {
    return 'Zuletzt gesendet: $time.';
  }

  @override
  String rescueModeInactive(int minutes) {
    return 'Sendet dein SOS alle $minutes Minuten mit aktuellem GPS erneut, auch bei ausgeschaltetem Bildschirm.';
  }

  @override
  String get rescueModeNoBackgroundLocation =>
      'Ohne dauerhafte Standortfreigabe wird das GPS nur bei geöffneter App aktualisiert.';

  @override
  String get actionAllow => 'ERLAUBEN';

  @override
  String get powerCardTitle => 'Akku & Standort';

  @override
  String get powerCardSubtitle =>
      'Einstellungen, die das Mesh am Leben halten und Rettern helfen, dich zu finden.';

  @override
  String get powerBatteryOptimization =>
      'Akku-Optimierung für HearthBit deaktiviert';

  @override
  String get actionDisable => 'DEAKTIVIEREN';

  @override
  String get powerLocationAndroid => 'Standort „immer erlauben“ aktiviert';

  @override
  String get powerLocationIos => 'Standort „immer“ erlaubt';

  @override
  String get powerSaverAndroid =>
      'Der System-Energiesparmodus ist aktiv und kann das Mesh beenden';

  @override
  String get powerSaverIos =>
      'Der Stromsparmodus ist aktiv und reduziert Bluetooth im Hintergrund';

  @override
  String get powerTipsTitle => 'Tipps zum Akkusparen';

  @override
  String get actionAdjust => 'ANPASSEN';

  @override
  String get powerTipBrightness =>
      'Stelle die Bildschirmhelligkeit auf das Minimum und verkürze die Sperrzeit.';

  @override
  String get powerTipMobileData =>
      'Wenn es kein Internet gibt, schalte mobile Daten und 5G aus: Das Mesh nutzt sie nicht und die Netzsuche verbraucht viel Akku.';

  @override
  String get powerTipCloseApps =>
      'Schließe Apps, die du nicht brauchst; lass Bluetooth und Standort aktiviert.';

  @override
  String get powerTipAndroidRecents =>
      'Wische HearthBit nicht aus den letzten Apps: Das System würde das Mesh beenden.';

  @override
  String get powerTipAndroidVendor =>
      'Einige Hersteller (Xiaomi, Huawei, Samsung) haben eigene Energiesparfunktionen: Nimm HearthBit auch dort aus.';

  @override
  String get powerTipAndroidSync =>
      'Deaktiviere die automatische Kontosynchronisierung, solange der Notfall andauert.';

  @override
  String get powerTipIosForceClose =>
      'Beende HearthBit nicht erzwungen: iOS startet die App nicht von selbst neu.';

  @override
  String get powerTipIosBackgroundRefresh =>
      'Deaktiviere die Hintergrundaktualisierung anderer Apps in den Einstellungen.';

  @override
  String get powerTipIosLowPower =>
      'Vermeide den Stromsparmodus, außer HearthBit ist auf dem Bildschirm: Er reduziert Bluetooth im Hintergrund.';

  @override
  String get powerTipShareBattery =>
      'Teilt Powerbanks in der Nachbarschaft: Ein einziges eingeschaltetes Telefon hält den ganzen Block verbunden.';

  @override
  String get nicknameDialogTitle => 'Anzeigename';

  @override
  String get nicknameDialogHint => 'z. B. Haus 12 oder Ana';

  @override
  String get actionCancel => 'ABBRECHEN';

  @override
  String get actionSave => 'SPEICHERN';

  @override
  String get wipeDialogTitle => 'Gesamte Identität löschen?';

  @override
  String get wipeDialogBody =>
      'Schlüssel, Verlauf und ausstehende Nachrichten werden gelöscht. Das kann nicht rückgängig gemacht werden.';

  @override
  String get actionWipe => 'ALLES LÖSCHEN';

  @override
  String get photoProfileTitle => 'Notfallprofil';

  @override
  String photoProfileBody(String size) {
    return 'Das Foto ist $size MiB groß. Komprimieren beschleunigt die Übertragung und spart Akku im Mesh.';
  }

  @override
  String get actionSendOriginal => 'ORIGINAL SENDEN';

  @override
  String get actionCompress => 'KOMPRIMIEREN';

  @override
  String offerFileError(String error) {
    return 'Die Datei konnte nicht angeboten werden: $error';
  }

  @override
  String get sendByQr => 'Per QR senden';

  @override
  String get receiveByQr => 'Per QR empfangen';

  @override
  String get emptyTransfersTitle => 'Keine Übertragungen';

  @override
  String get emptyTransfersBody =>
      'Tippe auf die Büroklammer neben einem Gerät in der Nähe, um ihm eine Datei anzubieten. Das Angebot reist verschlüsselt über das Mesh und der Inhalt nutzt den schnellsten verfügbaren Transport. Der QR-Modus funktioniert sogar ganz ohne Funk.';

  @override
  String transferFrom(String nickname) {
    return 'Von $nickname';
  }

  @override
  String transferTo(String nickname) {
    return 'An $nickname';
  }

  @override
  String transferProgress(String done, String total) {
    return '$done von $total';
  }

  @override
  String transferSavedAt(String path) {
    return 'Gespeichert unter $path';
  }

  @override
  String get stateOffered => 'Angebot';

  @override
  String get stateConnecting => 'Verbinden';

  @override
  String get stateTransferring => 'Übertragung';

  @override
  String get stateCompleted => 'Fertig';

  @override
  String get stateRejected => 'Abgelehnt';

  @override
  String get stateCancelled => 'Abgebrochen';

  @override
  String get stateFailed => 'Fehlgeschlagen';

  @override
  String get transportBle => 'Bluetooth';

  @override
  String get transportLan => 'Lokales WLAN';

  @override
  String get transportNearby => 'Nearby';

  @override
  String get transportWifiAware => 'Wi-Fi Aware';

  @override
  String get transportOptical => 'Optischer QR';

  @override
  String get actionReject => 'ABLEHNEN';

  @override
  String get actionAccept => 'ANNEHMEN';

  @override
  String get actionDelete => 'ENTFERNEN';

  @override
  String get opticalFileEmpty => 'Die Datei ist leer';

  @override
  String opticalSendStats(String fileName, int chunks, int symbol) {
    return '$fileName · $chunks Chunks · Symbol $symbol';
  }

  @override
  String get opticalConfirmed =>
      'Der Empfänger hat den Empfang über BLE bestätigt';

  @override
  String get opticalSpeedLabel => 'Geschwindigkeit';

  @override
  String opticalFps(int fps) {
    return '$fps QR/s';
  }

  @override
  String get densityCompact => 'Kompakt';

  @override
  String get densityMedium => 'Mittel';

  @override
  String get densityHigh => 'Hoch';

  @override
  String get opticalSendHint =>
      'Wenn die Empfängerkamera viele Frames verpasst, verringere Geschwindigkeit oder Dichte. Der Code ist rateless: Wiederholte Symbole beschädigen die Übertragung nie.';

  @override
  String get opticalShaFailed =>
      'SHA-256-Prüfung fehlgeschlagen; starte die Übertragung neu';

  @override
  String opticalSavedTitle(String fileName) {
    return '$fileName geprüft und gespeichert';
  }

  @override
  String get genericFile => 'Datei';

  @override
  String get actionDone => 'FERTIG';

  @override
  String get opticalScanHint =>
      'Richte die Kamera auf den QR-Code des Senders. Der Header wiederholt sich alle paar Frames.';

  @override
  String opticalReceiveStats(
    String fileName,
    int decoded,
    int total,
    int symbols,
  ) {
    return '$fileName · $decoded von $total Chunks · $symbols Symbole';
  }

  @override
  String radarTitle(String nickname) {
    return 'Radar · $nickname';
  }

  @override
  String get radarSignalLost => 'SIGNAL VERLOREN';

  @override
  String get radarSignalLostHint =>
      'Gehe langsam deinen Weg zurück, bis das Signal wiederkommt.';

  @override
  String get radarSearching => 'Signal wird gesucht…';

  @override
  String get radarSearchingHint =>
      'Gehe langsam in einem weiten Kreis. Das Radar erfasst das direkte Bluetooth-Signal (einige Dutzend Meter).';

  @override
  String get proximityVeryClose => 'SEHR NAH';

  @override
  String get proximityClose => 'NAH';

  @override
  String get proximityInRange => 'IN REICHWEITE';

  @override
  String get proximityFar => 'WEIT';

  @override
  String get trendApproaching => 'Du kommst näher';

  @override
  String get trendReceding => 'Das Signal wird schwächer';

  @override
  String get trendSteady => 'Signal stabil';

  @override
  String get trendUnknown => 'Signal wird gemessen…';

  @override
  String get distanceVeryNear => 'weniger als 2 m entfernt';

  @override
  String distanceApprox(int meters) {
    return '≈ $meters m';
  }

  @override
  String get distanceFar => 'mehr als 15 m entfernt';

  @override
  String radarDbm(int dbm) {
    return 'Signal $dbm dBm';
  }

  @override
  String radarGpsDistance(String distance) {
    return 'Zuletzt gemeldetes GPS: $distance Luftlinie entfernt';
  }

  @override
  String get errorPermissions =>
      'Für das Mesh sind Bluetooth- und Benachrichtigungsberechtigungen erforderlich.';

  @override
  String get errorLocationOff =>
      'Aktiviere den Systemstandort für den Rettungsmodus';

  @override
  String get errorUnknown => 'Unbekannter Fehler';

  @override
  String get terrInterrupted => 'Beim Schließen der App unterbrochen';

  @override
  String get terrFileSize =>
      'Die Datei muss zwischen 1 Byte und 512 MiB groß sein';

  @override
  String get terrOfferExpired => 'Das Angebot ist ohne Antwort abgelaufen';

  @override
  String get terrNoTransport => 'Kein mit dem Sender kompatibler Transport';

  @override
  String get terrInvalidSignature =>
      'Ein Angebot mit ungültiger Signatur wurde verworfen';

  @override
  String get terrUnsupportedTransport =>
      'Transport in dieser Version nicht unterstützt';

  @override
  String get terrLanIncomplete => 'Die LAN-Verbindung endete unvollständig';

  @override
  String terrLanFailed(String error) {
    return 'LAN fehlgeschlagen: $error';
  }

  @override
  String terrBleChunk(String error) {
    return 'Ungültiger BLE-Chunk: $error';
  }

  @override
  String get terrTransport => 'Transportfehler';

  @override
  String terrNearbyStart(String error) {
    return 'Nearby konnte nicht gestartet werden: $error';
  }

  @override
  String terrWifiAwareStart(String error) {
    return 'Wi-Fi Aware konnte nicht gestartet werden: $error';
  }

  @override
  String terrBleInterrupted(String error) {
    return 'BLE-Übertragung unterbrochen: $error';
  }

  @override
  String get terrReceiverSilent => 'Der Empfänger bestätigt keine Chunks mehr';

  @override
  String terrNearbyUnavailable(String error) {
    return 'Nearby nicht verfügbar: $error';
  }

  @override
  String terrWifiAwareUnavailable(String error) {
    return 'Wi-Fi Aware nicht verfügbar: $error';
  }

  @override
  String get terrContainerIncomplete => 'Der Container kam unvollständig an';

  @override
  String terrContainerDecrypt(String error) {
    return 'Der Container konnte nicht entschlüsselt werden: $error';
  }

  @override
  String get terrShaMismatch =>
      'SHA-256-Prüfung fehlgeschlagen; Datei verworfen';

  @override
  String terrNoMeshSession(String error) {
    return 'Keine Mesh-Verbindung zum Peer: $error';
  }

  @override
  String get terrTransportTimeout => 'Der Transport hat nicht geantwortet';
}
