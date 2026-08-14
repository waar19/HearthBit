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
  String get statusBannerYou => 'Du';

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
  String get privacyTitle => 'Datenschutz';

  @override
  String get privacyPrivateDefaultBody =>
      'Der private Modus ist standardmäßig aktiv. HearthBit minimiert stabile Funkkennungen und begrenzt Identitätsankündigungen.';

  @override
  String get privacyBitchatInteropTitle => 'BitChat-Kompatibilität';

  @override
  String get privacyBitchatInteropOffBody =>
      'Aus. Der private Modus bleibt aktiv.';

  @override
  String get privacyBitchatInteropWarning =>
      'An. Beobachter in der Nähe können dieses Gerät über eine stabile Funkkennung verfolgen; öffentliche Nachrichten bleiben für das Mesh lesbar.';

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
  String get secureChatUnavailableHint =>
      'Warten auf den verschlüsselten Kanal.';

  @override
  String get privateMessagePending => 'Ausstehend';

  @override
  String privateMessageSendError(String error) {
    return 'Die Nachricht konnte nicht gesendet werden: $error';
  }

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
  String get peerDoesNotSupportTransfers =>
      'Diese Person verwendet BitChat; Dateien erfordern HearthBit. Nutze stattdessen die QR-Übertragung.';

  @override
  String get sosCardTitle => 'Prioritätsalarm senden';

  @override
  String get sosCardBody =>
      'Wenn möglich, wird dein GPS-Standort angehängt. Der Alarm ist öffentlich und wird über das Mesh weitergeleitet.';

  @override
  String get sosPrivacyTitle => 'Datenschutz beim öffentlichen SOS';

  @override
  String get sosPrivacyPublicWarning =>
      'Ein öffentliches SOS legt Nachricht und kryptografische Identität gegenüber Mesh-Teilnehmern offen. Wähle die Standortgenauigkeit.';

  @override
  String get sosLocationExact => 'Genauer Standort';

  @override
  String get sosLocationExactBody =>
      'Am besten für sofortige Rettung; legt genaue Koordinaten offen.';

  @override
  String get sosLocationApproximate => 'Ungefährer Standort (empfohlen)';

  @override
  String get sosLocationApproximateBody =>
      'Rundet Koordinaten ungefähr auf ein Wohngebiet.';

  @override
  String get sosLocationNone => 'Ohne Standort';

  @override
  String get sosLocationNoneBody => 'Sendet nur deine SOS-Nachricht.';

  @override
  String get sosSendPublic => 'ÖFFENTLICHES SOS SENDEN';

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
  String get checkInPrivateBody =>
      'Sendet ein Ende-zu-Ende-verschlüsseltes Update nur an verifizierte Familienmitglieder.';

  @override
  String get checkInNoCircle =>
      'Füge ein verifiziertes Familienmitglied hinzu, bevor du privat eincheckst.';

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
  String get wipeDialogInstruction => 'Zur Bestätigung BORRAR eingeben.';

  @override
  String get wipeDialogKeyword => 'BORRAR eingeben';

  @override
  String get wipeDialogComplete =>
      'Identität und sensible Daten wurden gelöscht.';

  @override
  String get wipeDialogError =>
      'Das Löschen wurde nicht abgeschlossen. Vor der Weitergabe des Geräts erneut versuchen.';

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
  String get terrPeerDoesNotSupportTransfers =>
      'Der Empfänger unterstützt keine HearthBit-Dateiübertragung. Nutze stattdessen QR.';

  @override
  String get terrOfferExpiredNoHbt =>
      'Das Angebot ist abgelaufen, weil der Empfänger keine HearthBit-Dateiübertragung unterstützt.';

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
  String beaconRequestTitle(String nickname) {
    return '$nickname bittet dich, sichtbar zu werden';
  }

  @override
  String get beaconRequestBody =>
      'Bei Zustimmung werden Taschenlampe, Alarm und Vibration höchstens 5 Minuten verwendet. Ohne deine Zustimmung wird nichts aktiviert.';

  @override
  String get beaconMakeVisible => 'MICH SICHTBAR MACHEN';

  @override
  String get beaconStopVisible => 'PHYSISCHE BAKE STOPPEN';

  @override
  String get beaconRequestRemote => 'BAKE ANFORDERN';

  @override
  String get beaconStopRemote => 'BAKE STOPPEN';

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
  String get tooltipSupport => 'HearthBit unterstützen';

  @override
  String get aboutTitle => 'Über HearthBit';

  @override
  String get aboutBody =>
      'HearthBit ist ein source-available Notfallprojekt, dessen Code zur Datenschutz- und Sicherheitsprüfung einsehbar ist. Nichtkommerzielle Nutzung ist lizenziert; kommerzielle Nutzung erfordert eine Genehmigung.';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutSourceCode => 'Quellcode';

  @override
  String get supportButton => 'Spendiere mir einen Kaffee';

  @override
  String get shareInviteButton => 'HearthBit teilen';

  @override
  String shareInviteMessage(String url) {
    return 'Mach bei HearthBit mit, einem öffentlich prüfbaren Notfallnetz ohne Internet. Lade es herunter oder hilf mit unter $url';
  }

  @override
  String get tooltipShare => 'Menschen zu HearthBit einladen';

  @override
  String get shareInviteError =>
      'Die Teilen-Optionen konnten nicht geöffnet werden';

  @override
  String get diagnosticsExportButton => 'Diagnose exportieren';

  @override
  String get diagnosticsExportSubject => 'HearthBit-Diagnose';

  @override
  String get diagnosticsExportError =>
      'Der Diagnosebericht konnte nicht exportiert werden';

  @override
  String get openLinkError => 'Der Link konnte nicht geöffnet werden';

  @override
  String get actionClose => 'Schließen';

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

  @override
  String get recentChatsTitle => 'Letzte Unterhaltungen';

  @override
  String get nearbyPeopleTitle => 'Personen in der Nähe';

  @override
  String get peerRoleInfraRelay => 'Infrastruktur-Relay';

  @override
  String get peerRoleStorageAnchor => 'Nachrichten-Speicheranker';

  @override
  String get peerLongRangeTrunkActive => 'Langstrecken-Trunk aktiv';

  @override
  String get peerOnline => 'Online';

  @override
  String get peerOffline => 'Offline';

  @override
  String get offlineChatHint =>
      'Diese Person ist offline. Du kannst den Verlauf lesen und senden, sobald sie wieder verbunden ist.';

  @override
  String get radarConsentTitle => 'Radar-Datenschutz';

  @override
  String get radarConsentOff => 'Die Radarortung ist standardmäßig gesperrt';

  @override
  String radarConsentActive(int minutes) {
    return 'Andere können das Radar noch $minutes Min. verwenden';
  }

  @override
  String get radarConsentAllow => 'Radar für 15 Minuten erlauben';

  @override
  String get radarConsentRevoke => 'Jetzt widerrufen';

  @override
  String get radarPrivacyWarning =>
      'Dies beschränkt nur HearthBit. Andere Software kann weiterhin die Bluetooth-Signale deines Telefons messen.';

  @override
  String get rescueRadarWarning =>
      'Der Rettungsmodus teilt aktuelle SOS-Positionen und erlaubt nahen HearthBit-Rettungskräften, dein Signal zu messen, solange SOS aktiv ist.';

  @override
  String get radarConsentRequired => 'Erfordert die Zustimmung dieser Person';

  @override
  String get radarConsentSos => 'Wegen eines aktuellen SOS verfügbar';

  @override
  String get radarConsentTemporary => 'Von dieser Person vorübergehend erlaubt';

  @override
  String radarConsentExpires(String time) {
    return 'Die Erlaubnis endet um $time';
  }

  @override
  String get radarNotDirection =>
      'Der Punkt zeigt Nähe, nicht Richtung. Bewege dich langsam und prüfe, ob das Signal stärker wird.';

  @override
  String get radarPermissionExpired =>
      'Die Radar-Erlaubnis ist abgelaufen oder wurde widerrufen.';

  @override
  String get radarTentativeSignal =>
      'Vorläufiges Signal: Es wird geprüft, ob dieses iPhone die ausgewählte Person ist.';

  @override
  String get radarSweepStart => 'RICHTUNG SUCHEN';

  @override
  String get radarSweepRestart => 'SUCHE WIEDERHOLEN';

  @override
  String get radarSweepHoldTitle => 'So hältst du das Telefon';

  @override
  String get radarSweepInstruction =>
      'Halte es flach vor die Brust, Display nach oben und Oberkante nach vorn. Drehe langsam den ganzen Körper.';

  @override
  String radarSweepProgress(int percent) {
    return 'Fortschritt der Suche: $percent%';
  }

  @override
  String radarSweepResult(int heading) {
    return 'Wahrscheinlicher Signalbereich: $heading° (±30°)';
  }

  @override
  String radarSweepConfidence(int percent) {
    return 'Konfidenz: $percent%';
  }

  @override
  String get radarSweepInconclusive =>
      'Kein zuverlässiger Bereich gefunden. Drehe dich langsamer und entferne dich von Metall oder Elektronik.';

  @override
  String get radarSweepExpired =>
      'Die Richtung hat sich geändert oder ist abgelaufen. Wiederhole den Rundblick an deiner aktuellen Position.';

  @override
  String radarMeasuredDistance(String distance) {
    return 'Gemessen: $distance';
  }

  @override
  String radarGpsDistanceMargin(String distance, String accuracy) {
    return '≈$distance ±$accuracy GPS';
  }

  @override
  String get radarActionRadio => 'Funk';

  @override
  String get radarActionSonar => 'Sonar';

  @override
  String get radarActionBeacon => 'Signal';

  @override
  String get radarActionDirection => 'Richtung';

  @override
  String get radarActionSweeping => 'Suche';

  @override
  String get radarActionWaiting => 'Warten';

  @override
  String get radarRadioStart => 'Entfernung per Funk messen';

  @override
  String get radarRadioStop => 'Funkmessung beenden';

  @override
  String get radarSonarStart => 'Mit akustischem Sonar messen';

  @override
  String get radarSonarStop => 'Akustisches Sonar beenden';

  @override
  String get radarSonarMicrophoneRequired =>
      'Das akustische Sonar benötigt Mikrofonzugriff.';

  @override
  String get radarSonarTooNoisy =>
      'Die Signaltöne konnten nicht gemessen werden. Reduziere Geräusche, decke die Telefone nicht ab und versuche es erneut.';

  @override
  String get radarSweepEstimateWarning =>
      'BLE kann nur einen breiten Bereich schätzen, keine genaue Richtung. Bestätige ihn durch Bewegung und eine erneute Suche.';

  @override
  String get radarCompassUnavailable =>
      'Dieses Telefon hat keinen nutzbaren Kompasssensor. Das Näherungsradar bleibt verfügbar.';

  @override
  String get radarCompassCalibration =>
      'Entferne das Telefon von Metall oder Elektronik und bewege es zur Kompasskalibrierung in Form einer Acht.';

  @override
  String get radarDirectionGps => 'GPS-Richtung · folge der blauen Raute';

  @override
  String get radarDirectionBle => 'Durch BLE-Suche geschätzter Bereich';

  @override
  String get radarDirectionVeryClose =>
      'Du bist sehr nah: Der BLE-Bereich wird ausgeblendet, weil er nicht mehr zuverlässig ist. Drehe dich und folge der Vibration.';

  @override
  String get radarSourcesDisagree =>
      'GPS und BLE stimmen nicht überein; die Richtung bleibt bis zur nächsten Messung verborgen.';

  @override
  String get dateToday => 'Heute';

  @override
  String get dateYesterday => 'Gestern';

  @override
  String get genericPresenceSectionTitle => 'Andere Bluetooth-Signale';

  @override
  String get genericPresenceNoChat => 'Anwesenheit erkannt, kein Chat';

  @override
  String genericPresenceSignal(int rssi) {
    return 'Allgemeines Bluetooth-Signal · $rssi dBm';
  }

  @override
  String genericPresenceSummary(int count, int rssi) {
    return '$count Bluetooth-Signale in der Nähe · stärkstes $rssi dBm';
  }

  @override
  String get genericPresenceExpand => 'Signaldetails anzeigen';

  @override
  String get nodeModeTooltip => 'Knotenmodus';

  @override
  String get nodeModeTitle => 'Wie soll dieses Telefon teilnehmen?';

  @override
  String get nodeModeRelayTitle => 'Mesh-Relay';

  @override
  String get nodeModeRelayBody =>
      'Normal chatten und Nachrichten für Personen in der Nähe weiterleiten.';

  @override
  String get nodeModeBeaconTitle => 'Nur Anwesenheit';

  @override
  String get nodeModeBeaconBody =>
      'Spart Strom und kündigt deine Anwesenheit ohne Chat oder Weiterleitung an. Unter Android werden auch Datenverbindungen deaktiviert.';

  @override
  String get tabEmergency => 'Notfall';

  @override
  String get emergencyHeadline => 'Notfallmodus';

  @override
  String get emergencyInstructions =>
      'SOS 2 Sekunden gedrückt halten. HearthBit aktiviert das Mesh, teilt deinen Standort und wiederholt den Alarm.';

  @override
  String get emergencyHoldSos => 'FÜR SOS HALTEN';

  @override
  String get emergencySosActive => 'SOS AKTIV';

  @override
  String get emergencyStopRescue => 'Rettungsmodus beenden';

  @override
  String get emergencyDeliveryTitle => 'Status gesendeter Warnungen';

  @override
  String get deliveryPending => 'Übertragung ausstehend';

  @override
  String get deliveryRelayed => 'An das Mesh übertragen';

  @override
  String get deliveryAcknowledged => 'Von HearthBit bestätigt';

  @override
  String get deliveryExpired => 'Ohne Bestätigung abgelaufen';

  @override
  String get deliveryAttemptsLabel => 'Versuche';

  @override
  String get deliveryConfirmationsLabel => 'Bestätigungen';

  @override
  String get deliveryLastAttemptLabel => 'Letzter Versuch';

  @override
  String get deliveryExpiresLabel => 'Läuft ab';

  @override
  String get deliveryNoHearthBitConfirmation =>
      'Keine Bestätigung eines anderen HearthBit; ein BitChat-Knoten kann die Warnung dennoch empfangen haben.';

  @override
  String get deliveryRetry => 'Warnung erneut senden';

  @override
  String get errorEmergencyMeshUnavailable =>
      'Das Bluetooth-Mesh konnte nicht aktiviert werden. Berechtigungen prüfen und erneut versuchen.';

  @override
  String get checkInTitle => 'Status mitteilen';

  @override
  String get checkInBody =>
      'Ein kurzer Status wird mit Uhrzeit und verfügbarem Standort über das Mesh weitergeleitet.';

  @override
  String get checkInOk => 'Mir geht es gut';

  @override
  String get checkInNeedsHelp => 'Ich brauche Hilfe';

  @override
  String get checkInInjured => 'Ich bin verletzt';

  @override
  String get checkInRecentTitle => 'Neueste Statusmeldungen';

  @override
  String get checkInNone => 'Noch niemand hat einen Status geteilt.';

  @override
  String get onboardingWelcomeTitle => 'Kommunikation bei Netzausfall';

  @override
  String get onboardingWelcomeBody =>
      'HearthBit leitet Notfallnachrichten per Bluetooth zwischen nahen Telefonen weiter – ohne Mobilfunk oder Internet.';

  @override
  String get onboardingMeshTitle => 'Das Notfall-Mesh aktiv halten';

  @override
  String get onboardingMeshBody =>
      'Bluetooth-, Geräte- und Benachrichtigungsrechte ermöglichen Suche und Weiterleitung.';

  @override
  String get onboardingReadyTitle => 'Vor dem Notfall vorbereiten';

  @override
  String get onboardingReadyBody =>
      'Hintergrundstandort erlauben und HearthBit von Akku-Einschränkungen ausnehmen.';

  @override
  String get onboardingNicknameLabel => 'Dein sichtbarer Name (optional)';

  @override
  String get onboardingNext => 'WEITER';

  @override
  String get onboardingBack => 'ZURÜCK';

  @override
  String get onboardingAllowMesh => 'ERLAUBEN UND MESH STARTEN';

  @override
  String get onboardingAllowLocation => 'NOTFALLSTANDORT ERLAUBEN';

  @override
  String get onboardingFinish => 'EINRICHTUNG ABSCHLIESSEN';

  @override
  String get appearanceTitle => 'Anzeige & Barrierefreiheit';

  @override
  String get appearanceAmoled => 'AMOLED-Schwarz';

  @override
  String get appearanceAmoledBody =>
      'Echtes Schwarz spart Strom auf OLED-Displays.';

  @override
  String get appearanceHighContrast =>
      'Hoher Kontrast und größere Bedienelemente';

  @override
  String get appearanceHighContrastBody =>
      'Verbessert Lesbarkeit und vergrößert kritische Aktionen.';

  @override
  String get tooltipAppearance => 'Anzeige und Barrierefreiheit';

  @override
  String get meshHealthTitle => 'Mesh-Zustand';

  @override
  String meshHealthDirect(int count) {
    return '$count direkte Geräte';
  }

  @override
  String meshHealthRelays(int count) {
    return '$count Telefone leiten Nachrichten weiter';
  }

  @override
  String meshHealthAnchors(int count) {
    return '$count Nachrichtenspeicherpunkte';
  }

  @override
  String meshHealthTrunks(int count) {
    return '$count aktive Langstrecken-Trunks';
  }

  @override
  String meshHealthSignals(int count) {
    return '$count weitere Bluetooth-Signale';
  }

  @override
  String get meshHealthAnchorReady =>
      'Ein Nachrichtenspeicherpunkt ist in der Nähe.';

  @override
  String get meshHealthNoAnchor =>
      'Kein Nachrichtenspeicherpunkt in der Nähe sichtbar.';

  @override
  String get adaptivePowerTitle => 'Adaptiver Akkumodus';

  @override
  String get adaptivePowerNormal => 'Volle Mesh-Leistung';

  @override
  String get adaptivePowerSaving => 'Stromsparen: Suche in kurzen Intervallen';

  @override
  String get powerProfilePerformance => 'Leistung: schnelle Erkennung';

  @override
  String get powerProfileBalanced => 'Ausgewogen: volle Mesh-Abdeckung';

  @override
  String get powerProfilePowerSaver => 'Stromsparen: Suche in Intervallen';

  @override
  String get powerProfileCritical =>
      'Kritisch: minimale Verbindungen und Suche';

  @override
  String get powerProfileSurvival => 'Überleben: nur SOS-Signal';

  @override
  String get survivalModeTitle => 'Überlebensmodus';

  @override
  String get survivalModeBody =>
      'Nur ein SOS-Signal bleibt aktiv. Chat und Weiterleitung werden beendet.';

  @override
  String get survivalModeEnable => 'ÜBERLEBENSMODUS AKTIVIEREN';

  @override
  String get survivalModeDisable => 'ZUM MESH ZURÜCK';

  @override
  String get survivalModeSuggestion =>
      'Akku kritisch. Überlebensmodus verlängert die Erkennbarkeit.';

  @override
  String get gatewayTitle => 'Notfall-Internet-Gateway';

  @override
  String get gatewayBody =>
      'Wenn Internet zurückkehrt, kann dieses Telefon wartende SOS- und Statusmeldungen veröffentlichen.';

  @override
  String get gatewayOptIn => 'Internet-Ausgang über dieses Telefon erlauben';

  @override
  String get gatewayAvailable => 'Internetverbindung erkannt';

  @override
  String get gatewayUnavailable => 'Keine Internetverbindung erkannt';

  @override
  String get gatewayPrivacy =>
      'Nur SOS und Status sind zulässig. Ohne vertrauenswürdige Konfiguration wird nichts hochgeladen.';

  @override
  String gatewayPending(int count) {
    return '$count Notfalleinträge ausstehend';
  }

  @override
  String get gatewayConfigure => 'Vertrauenswürdiges Gateway einrichten';

  @override
  String get gatewayKindMatrix => 'Matrix';

  @override
  String get gatewayKindMqtt => 'MQTT';

  @override
  String get gatewayHomeserver => 'Matrix-Homeserver-URL';

  @override
  String get gatewayBroker => 'MQTT-Broker';

  @override
  String get gatewayRoom => 'Matrix-Raum-ID';

  @override
  String get gatewayTopic => 'MQTT-Thema';

  @override
  String get gatewayUsername => 'Benutzername';

  @override
  String get gatewayAccessToken => 'Zugriffstoken';

  @override
  String get gatewayPassword => 'Passwort';

  @override
  String get gatewayPort => 'Port';

  @override
  String get gatewayTls => 'Verschlüsselte TLS-Verbindung verwenden';

  @override
  String get gatewayTrustTitle => 'Vertrauen in TLS-Zertifikate';

  @override
  String get gatewayTrustSystem => 'System';

  @override
  String get gatewayTrustSystemBody =>
      'Verwendet die Zertifizierungsstellen des Geräts. Dies ist mit öffentlichen Diensten kompatibel, bindet das Gateway aber nicht an ein bestimmtes Zertifikat.';

  @override
  String get gatewayTrustTofu => 'TOFU';

  @override
  String get gatewayTrustTofuBody =>
      'Vertraut dem ersten Zertifikat dieses Endpunkts und lehnt spätere Änderungen ab. Prüfe, dass die erste Verbindung nicht abgefangen wird.';

  @override
  String get gatewayTrustPinned => 'Festgelegt';

  @override
  String get gatewayTrustPinnedBody =>
      'Nur der exakte SHA-256-Fingerabdruck wird akzeptiert. Ein Zertifikatswechsel blockiert die Zustellung, bis dieser Wert aktualisiert wird.';

  @override
  String get gatewayFingerprint => 'SHA-256-Fingerabdruck des Zertifikats';

  @override
  String get gatewayFingerprintHint =>
      '64 Hexadezimalzeichen; Trennzeichen sind erlaubt';

  @override
  String get gatewayFingerprintInvalid =>
      'Gib einen gültigen SHA-256-Fingerabdruck mit 64 Zeichen ein.';

  @override
  String get gatewayResetTofu => 'Erstes Zertifikat vergessen';

  @override
  String get gatewayResetTofuDone =>
      'Das gespeicherte TOFU-Zertifikat wurde entfernt.';

  @override
  String get gatewayPrivacyScopeTitle => 'Mit dem Gateway geteilte Daten';

  @override
  String get gatewaySensitiveContentConsent =>
      'Nachrichteninhalt und Absenderidentität teilen';

  @override
  String get gatewaySensitiveContentConsentBody =>
      'Enthält Notfallbeschreibung, Anzeigename und Peer-ID. Standardmäßig deaktiviert.';

  @override
  String get gatewayCoordinatesConsent => 'Genaue Koordinaten teilen';

  @override
  String get gatewayCoordinatesConsentBody =>
      'Enthält vorhandene Breiten- und Längengrade. Diese Einwilligung ist unabhängig vom Nachrichteninhalt.';

  @override
  String get gatewayPrivacyScopeWarning =>
      'Das Gateway sendet ausgewählte Daten an einen Internetdienst außerhalb des lokalen Mesh. Aktiviere jede Kategorie nur mit informierter Einwilligung.';

  @override
  String get mapOpen => 'Offline-Karte öffnen';

  @override
  String get mapOpenRescue => 'RETTUNGSKARTE ÖFFNEN';

  @override
  String get mapTitle => 'Offline-Rettungskarte';

  @override
  String get mapMyLocation => 'Auf meinen Standort zentrieren';

  @override
  String get mapPassiveCacheInfo =>
      'Diese Karte speichert angesehene Kacheln automatisch zur Offline-Wiederverwendung. Regionale Downloads erfordern einen autorisierten Anbieter oder einen eigenen Server.';

  @override
  String get mapTilePolicyAction => 'OSM-Richtlinie';

  @override
  String get mapDownloadVisible => 'Sichtbaren Bereich herunterladen';

  @override
  String mapDownloadComplete(int count) {
    return '$count Kartenkacheln wurden offline gespeichert.';
  }

  @override
  String mapDownloadTooLarge(int maximum) {
    return 'Der Bereich ist zu groß. Zoome hinein; das sichere Limit beträgt $maximum Kacheln.';
  }

  @override
  String mapDownloadError(String error) {
    return 'Der Kartenbereich konnte nicht geladen werden: $error';
  }

  @override
  String mapDownloading(int completed, int total) {
    return 'Karte wird gespeichert: $completed/$total';
  }

  @override
  String mapCacheError(String error) {
    return 'Der Offline-Kartenspeicher konnte nicht geöffnet werden: $error';
  }

  @override
  String get mapYouAreHere => 'Du bist hier';

  @override
  String get mapOfflineHint =>
      'Kein Netzwerk. Bereits gespeicherte Kartenkacheln bleiben sichtbar.';

  @override
  String get mapTileBlockedHint =>
      'Der Anbieter hat Kartenkacheln vorübergehend gesperrt. Rettungsmarkierungen bleiben verfügbar; für Offline-Karten ist eine autorisierte Quelle oder ein eigener Server erforderlich.';

  @override
  String get mapShowOnMap => 'Auf Karte zeigen';

  @override
  String get rescueListTitle => 'Rettungsliste · nächste zuerst';

  @override
  String get rescueListEmpty =>
      'Keine SOS-Alarme oder Statusmeldungen mit Rettungsdaten.';

  @override
  String get rescueExportCsv => 'Rettungs-CSV teilen';

  @override
  String get rescueExportSubject => 'HearthBit-Rettungsliste';

  @override
  String rescueExportError(String error) {
    return 'Die Rettungsliste konnte nicht geteilt werden: $error';
  }

  @override
  String get rescueDistanceUnknown => 'Entfernung unbekannt';

  @override
  String rescueDistanceMeters(int meters) {
    return '$meters m entfernt';
  }

  @override
  String rescueDistanceKilometers(String kilometers) {
    return '$kilometers km entfernt';
  }

  @override
  String get voiceRecord => 'Sprachnachricht aufnehmen';

  @override
  String get voiceStop => 'Aufnahme stoppen';

  @override
  String get voiceTooLong => 'Sprachnachrichten sind auf 20 Sekunden begrenzt.';

  @override
  String get voiceUnsupported =>
      'Sprachnachrichten erfordern HearthBit beim Empfänger.';

  @override
  String get voicePlay => 'Sprachnachricht abspielen';

  @override
  String get voicePause => 'Sprachnachricht pausieren';

  @override
  String get shareApkButton => 'Installierte APK teilen';

  @override
  String get sendApkToPeer => 'HearthBit-APK senden';

  @override
  String get apkSafetyTitle => 'Android-Installationsdatei teilen?';

  @override
  String apkSendToPeerWarning(String peer) {
    return '$peer erhält die Android-Installationsdatei von HearthBit.';
  }

  @override
  String get apkInstallWarning =>
      'Der Empfänger muss in den Android-Einstellungen die Installation aus der empfangenden Quelle erlauben. HearthBit installiert nichts automatisch.';

  @override
  String get apkSignatureWarning =>
      'Eine mit einem anderen Schlüssel signierte APK kann die installierte App nicht aktualisieren. Quelle und Signatur vor der Installation prüfen.';

  @override
  String get apkTransportWarning =>
      'Die APK wird nicht über BLE übertragen. Sie benötigt lokales WLAN, Nearby oder Wi-Fi Aware; falls nichts davon verfügbar ist, meldet die Übertragung einen Fehler.';

  @override
  String get apkConfirmShare => 'WEITER';

  @override
  String get apkPreparing => 'Sichere APK-Kopie wird vorbereitet…';

  @override
  String get apkSplitUnavailable =>
      'Diese Installation verwendet geteilte APKs. Nur die Basis-APK wäre unvollständig und wird daher nicht geteilt. Biete stattdessen den GitHub-Link an.';

  @override
  String get apkUnsupported =>
      'Das Teilen der installierten APK ist nur unter Android verfügbar.';

  @override
  String apkShareError(String error) {
    return 'APK konnte nicht vorbereitet oder geteilt werden: $error';
  }

  @override
  String get apkShareMessage =>
      'HearthBit-Installationsdatei für Android. Android verlangt die Freigabe dieser Installationsquelle. Eine anders signierte APK kann eine vorhandene Installation nicht aktualisieren; Quelle und Signatur zuerst prüfen.';

  @override
  String apkOfferSent(String peer) {
    return 'APK wurde $peer angeboten. Die Übertragung meldet einen Fehler, wenn kein geeigneter schneller Transport verfügbar ist.';
  }

  @override
  String get firstAidOpen => 'OFFLINE-ERSTE-HILFE ÖFFNEN';

  @override
  String get firstAidTitle => 'Offline-Erste-Hilfe';

  @override
  String get firstAidDisclaimer =>
      'Rufe den örtlichen Notruf. Dieser Leitfaden ersetzt keine professionelle Hilfe oder Ausbildung. Örtliche Vorgehensweisen unterscheiden sich: Befolge Leitstelle und Behörden.';

  @override
  String get firstAidChooseTopic => 'Wähle, was passiert ist';

  @override
  String get firstAidEnglishFallback =>
      'Diese Übersetzung konnte nicht geprüft werden. Der validierte englische Leitfaden wird angezeigt.';

  @override
  String get firstAidSteps => 'Jetzt handeln';

  @override
  String get firstAidWarnings => 'Vermeiden';

  @override
  String get firstAidSources => 'Quellen und Prüfhinweise';

  @override
  String firstAidReviewed(String date) {
    return 'Inhalt geprüft am $date';
  }

  @override
  String get firstAidLoadError =>
      'Der validierte Offline-Leitfaden konnte nicht geladen werden. Verlasse dich nicht auf unvollständige Angaben; rufe den örtlichen Notruf.';

  @override
  String get familyTitle => 'Familiengruppe';

  @override
  String get familySecurityBody =>
      'Mitglieder werden persönlich über einen signierten QR-Code geprüft. Namen und alte Geräte-IDs allein gelten nie als vertrauenswürdig.';

  @override
  String get familyCreateGroup => 'GRUPPE ERSTELLEN';

  @override
  String get familyRenameGroup => 'GRUPPE UMBENENNEN';

  @override
  String get familyGroupHint => 'Z. B. Meine Familie';

  @override
  String get familyGroupLabel => 'Gruppe';

  @override
  String get familyConfirmTitle => 'Familienmitglied bestätigen';

  @override
  String familyFingerprint(String fingerprint) {
    return 'Sicherheitscode: $fingerprint';
  }

  @override
  String get familyConfirmBody =>
      'Vergleiche diesen Sicherheitscode vor dem Speichern auf beiden Telefonen.';

  @override
  String get familyAddMember => 'MITGLIED HINZUFÜGEN';

  @override
  String get familyRemoveTitle => 'Familienmitglied entfernen?';

  @override
  String familyRemoveBody(String nickname) {
    return '$nickname erhält keine Familienmarkierung und -warnungen mehr.';
  }

  @override
  String get familyRemoveAction => 'ENTFERNEN';

  @override
  String familySaveError(String error) {
    return 'Familiengruppe konnte nicht gespeichert werden: $error';
  }

  @override
  String get familyMembersTitle => 'Verifizierte Mitglieder';

  @override
  String get familyScanAction => 'QR-Code des Mitglieds scannen';

  @override
  String get familyCreateFirst =>
      'Erstelle eine Gruppe, bevor du Mitglieder hinzufügst.';

  @override
  String get familyNoMembers => 'Noch keine verifizierten Mitglieder.';

  @override
  String get familyMyQr => 'Mein Verifizierungs-QR';

  @override
  String get familyMyQrBody =>
      'Zeige diesen QR-Code persönlich. Er enthält deinen öffentlichen Signaturschlüssel, nie deinen privaten Schlüssel.';

  @override
  String get familyQrUnavailable =>
      'Aktiviere das Mesh, damit dein signierter Verifizierungs-QR verfügbar ist.';

  @override
  String get familyScanTitle => 'Familien-QR scannen';

  @override
  String get familyQrInvalid =>
      'Dieser QR-Code ist ungültig oder seine Signatur konnte nicht geprüft werden.';

  @override
  String get familyScanHint =>
      'Scanne den QR-Code auf dem Telefon deines Familienmitglieds.';

  @override
  String get familyAlertBadge => 'VERIFIZIERTE FAMILIE';

  @override
  String get drillSafetyBanner => 'ÜBUNG - fordert keine Rettung an';

  @override
  String get drillModeTitle => 'Übungsmodus';

  @override
  String get drillModeBody =>
      'Sendet nur klar gekennzeichnete Übungsnachrichten. Sendet niemals SOS, teilt keinen Rettungsstandort, aktiviert keine Signalquelle und nutzt kein Internet-Gateway.';

  @override
  String get drillConfirmTitle => 'Übungsmodus aktivieren?';

  @override
  String get drillConfirmBody =>
      'Rettungs- und Überlebensmodus werden beendet. Übungsnachrichten sind öffentlich, können aber keine echten Notfallalarme werden.';

  @override
  String get drillEnableAction => 'ÜBUNG AKTIVIEREN';

  @override
  String get drillHoldToSend => 'HALTEN FÜR ÜBUNG';

  @override
  String get drillPracticeMessage => 'Übungsanfrage um Hilfe';

  @override
  String get drillReceivedTitle => 'Übungsnachrichten';

  @override
  String get drillNoneReceived => 'Keine Übungsnachrichten empfangen.';

  @override
  String get drillBadge => 'ÜBUNG — KEIN NOTFALL';

  @override
  String get drillInvalidMessage =>
      'Unbekannte Übungsnachricht; sie wurde von den Notfallsystemen isoliert.';

  @override
  String get drillCheckInTitle => 'Statusmeldung üben';

  @override
  String get drillCheckInBody =>
      'Diese Meldungen bleiben im Übungskanal und erscheinen nicht in Rettungsalarmen, Karten oder Exporten.';

  @override
  String get drillExitForRealTitle => 'Echtes SOS senden?';

  @override
  String get drillExitForRealBody =>
      'Dies beendet die Übung und aktiviert eine echte Rettungsanfrage mit Standortfreigabe und wiederholten SOS-Alarmen.';

  @override
  String get drillSendRealSos => 'ÜBUNG BEENDEN UND SOS SENDEN';

  @override
  String get drillDisableTitle => 'Übungsmodus beenden?';

  @override
  String get drillDisableBody =>
      'Übungsnachrichten werden beendet und HearthBit kehrt zum echten Notfallbetrieb zurück.';

  @override
  String get drillDisableAction => 'ÜBUNG BEENDEN';

  @override
  String get mapNoLocationTitle => 'Kein Standort verfügbar';

  @override
  String get mapNoLocationBody =>
      'Aktiviere den Standort oder warte auf eine gültige Rettungsposition eines Knotens. Die Karte verwendet niemals (0,0) als Ersatz.';

  @override
  String get voiceMicrophoneRequired =>
      'Für eine Sprachnachricht ist Mikrofonzugriff erforderlich.';

  @override
  String get actionOpenSettings => 'EINSTELLUNGEN ÖFFNEN';

  @override
  String get opticalUnverifiedTitle => 'Nicht verifizierte Quelle';

  @override
  String get opticalUnverifiedBody =>
      'HearthBit kann diese Übertragung keiner zuvor authentifizierten Identität zuordnen. Vergleiche den Fingerabdruck vor Annahme mit dem Absender.';

  @override
  String get opticalLegacyWarning =>
      'Dieser Absender verwendet das ältere unsignierte optische Format.';

  @override
  String opticalFingerprint(String fingerprint) {
    return 'Fingerabdruck: $fingerprint';
  }

  @override
  String get opticalAcceptUnverified => 'UNVERIFIZIERT ANNEHMEN';

  @override
  String get opticalSignatureInvalid =>
      'Die Signatur des optischen Manifests stimmt nicht mit dem bekannten Absender überein. Die Datei wurde abgelehnt.';

  @override
  String get opticalVerifiedSource => 'Verifizierter Absender';

  @override
  String get gatewayPrivacyConfirm =>
      'Dadurch werden Notfallnachrichten, Absenderdaten und enthaltene Rettungsstandorte an den konfigurierten Internetdienst gesendet. Nur mit Zustimmung der betroffenen Personen aktivieren.';

  @override
  String get gatewayEnableAction => 'GATEWAY AKTIVIEREN';

  @override
  String get gatewayTlsRequired =>
      'Für Notfalldaten erforderlich; unsichere Verbindungen werden blockiert.';

  @override
  String get locationExportConfirmTitle => 'Rettungsstandorte exportieren?';

  @override
  String get locationExportConfirmBody =>
      'Die CSV-Datei kann genaue Standorte und Notfalldetails enthalten. Nur mit vertrauenswürdigen Einsatzkräften teilen und schützen.';

  @override
  String get locationExportConfirmAction => 'STANDORTE EXPORTIEREN';

  @override
  String get lanGatewayConnected => 'LAN-Relay verbunden';

  @override
  String get lanGatewaySearching => 'LAN-Relay aktiv · lokale Suche';

  @override
  String get lanGatewayDisabled => 'LAN-Relay deaktiviert';

  @override
  String get lanGatewayConfigure => 'LAN-RELAY KONFIGURIEREN';

  @override
  String get lanGatewayDisable => 'LAN-RELAY DEAKTIVIEREN';

  @override
  String get lanGatewayPrivacy =>
      'Nur nach Zustimmung. Der gemeinsame Schlüssel muss mit deinem vertrauenswürdigen HearthBit-Raspberry-Pi-Relay übereinstimmen. Mesh-Frames werden lokal authentifiziert und verschlüsselt.';

  @override
  String get lanGatewayPsk => '32-Byte-Kopplungsschlüssel (Base64)';

  @override
  String get lanGatewayGeneratePsk => 'SCHLÜSSEL ERZEUGEN';

  @override
  String get lanGatewayInvalidPsk =>
      'Gib einen gültigen 32-Byte-Base64-Schlüssel ein.';

  @override
  String get emergencyContactsOpen => 'Notrufnummern und offizielle Links';

  @override
  String get emergencyContactsTitle => 'Notfallverzeichnis';

  @override
  String get emergencyContactsSafetyNotice =>
      'Notrufnummern können ohne mobile Daten funktionieren, benötigen aber Mobilfunk-Sprachabdeckung. Offizielle Websites benötigen Internet.';

  @override
  String get emergencyContactsCountry => 'Land oder Gebiet';

  @override
  String emergencyContactsAutomatic(String country) {
    return 'Automatisch ($country)';
  }

  @override
  String get emergencyContactsNumbers => 'Notrufnummern';

  @override
  String get emergencyContactsOrganizations => 'Offizielle Organisationen';

  @override
  String get emergencyContactsCall => 'ANRUFEN';

  @override
  String get emergencyContactsWebsite => 'WEBSITE';

  @override
  String get emergencyContactsSources => 'Quellen und Prüfung';

  @override
  String emergencyContactsReviewed(String date) {
    return 'Geprüft am $date';
  }

  @override
  String get emergencyContactsFallback =>
      'Diese Übersetzung war nicht verfügbar; das geprüfte englische Verzeichnis wird angezeigt.';

  @override
  String get emergencyContactsLoadError =>
      'Das Offline-Notfallverzeichnis konnte nicht geladen werden.';

  @override
  String get emergencyContactsOpenError =>
      'Diese Nummer oder dieser Link konnte nicht geöffnet werden.';

  @override
  String get emergencyContactsRetry => 'ERNEUT VERSUCHEN';
}
