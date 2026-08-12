// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'HearthBit';

  @override
  String storageOpenError(String error) {
    return 'Impossible d\'ouvrir le stockage local :\n$error';
  }

  @override
  String statusActiveLabel(String nickname, int count) {
    return '$nickname · $count à proximité';
  }

  @override
  String statusDegradedLabel(String nickname) {
    return '$nickname · réception seule (pas d\'annonce BLE)';
  }

  @override
  String get statusStarting => 'Démarrage du maillage…';

  @override
  String get statusError => 'Erreur du maillage';

  @override
  String get statusStopped => 'Maillage arrêté';

  @override
  String get actionStop => 'ARRÊTER';

  @override
  String get actionRestart => 'REDÉMARRER';

  @override
  String get actionActivate => 'ACTIVER';

  @override
  String get actionRetry => 'RÉESSAYER';

  @override
  String get tooltipChangeName => 'Changer de nom';

  @override
  String get tooltipPanicWipe => 'Effacement d\'urgence';

  @override
  String get tabChannel => 'Canal';

  @override
  String get tabNearby => 'À proximité';

  @override
  String get tabFiles => 'Fichiers';

  @override
  String get tabSos => 'SOS';

  @override
  String get emptyChatTitle => 'Pas encore de messages';

  @override
  String get emptyChatBody =>
      'Activez le maillage. Les messages sauteront de téléphone en téléphone sans internet.';

  @override
  String get composerPublicHint => 'Message pour tous à proximité';

  @override
  String get composerPrivateHint => 'Message chiffré';

  @override
  String get privateChatIntro =>
      'Le premier message lancera une poignée de main Noise XX.';

  @override
  String get emptyPeersTitle => 'Aucun appareil à proximité';

  @override
  String get emptyPeersBody =>
      'Gardez le Bluetooth activé et approchez un autre téléphone avec HearthBit ou BitChat.';

  @override
  String get peerSecure => 'canal chiffré prêt';

  @override
  String get peerTapToEncrypt => 'touchez pour chiffrer';

  @override
  String get tooltipRadar => 'Radar de proximité';

  @override
  String get tooltipSendFile => 'Envoyer un fichier';

  @override
  String get sosCardTitle => 'Envoyer une alerte prioritaire';

  @override
  String get sosCardBody =>
      'Votre position GPS sera jointe si possible. L\'alerte est publique et relayée par le maillage.';

  @override
  String get sosMedical => 'J\'ai besoin d\'aide médicale';

  @override
  String get sosTrapped => 'Je suis coincé';

  @override
  String get sosImOk => 'Je vais bien';

  @override
  String get sosDefaultMessage => 'J\'ai besoin d\'aide';

  @override
  String get sosReceivedTitle => 'Alertes reçues';

  @override
  String get sosNoneReceived => 'Aucune alerte SOS reçue.';

  @override
  String get actionTrack => 'LOCALISER';

  @override
  String get rescueModeTitle => 'Mode sauvetage';

  @override
  String rescueModeActive(int minutes) {
    return 'Renvoi de votre SOS avec position toutes les $minutes min.';
  }

  @override
  String rescueModeLastPing(String time) {
    return 'Dernier envoi : $time.';
  }

  @override
  String rescueModeInactive(int minutes) {
    return 'Renvoie votre SOS avec un GPS à jour toutes les $minutes minutes, même écran éteint.';
  }

  @override
  String get rescueModeNoBackgroundLocation =>
      'Sans localisation permanente, le GPS ne se met à jour que si l\'app est ouverte.';

  @override
  String get actionAllow => 'AUTORISER';

  @override
  String get powerCardTitle => 'Batterie et localisation';

  @override
  String get powerCardSubtitle =>
      'Réglages pour que le maillage continue de battre et que les secouristes vous trouvent.';

  @override
  String get powerBatteryOptimization =>
      'Optimisation de la batterie désactivée pour HearthBit';

  @override
  String get actionDisable => 'DÉSACTIVER';

  @override
  String get powerLocationAndroid => 'Localisation autorisée « tout le temps »';

  @override
  String get powerLocationIos => 'Localisation autorisée « toujours »';

  @override
  String get powerSaverAndroid =>
      'L\'économiseur de batterie du système est actif et peut couper le maillage';

  @override
  String get powerSaverIos =>
      'Le mode économie d\'énergie est actif et réduit le Bluetooth en arrière-plan';

  @override
  String get powerTipsTitle => 'Conseils pour économiser la batterie';

  @override
  String get actionAdjust => 'AJUSTER';

  @override
  String get powerTipBrightness =>
      'Baissez la luminosité de l\'écran au minimum et réduisez le délai de verrouillage.';

  @override
  String get powerTipMobileData =>
      'S\'il n\'y a pas d\'internet, désactivez les données mobiles et la 5G : le maillage ne les utilise pas et la recherche de réseau vide la batterie.';

  @override
  String get powerTipCloseApps =>
      'Fermez les apps inutiles ; laissez le Bluetooth et la localisation actifs.';

  @override
  String get powerTipAndroidRecents =>
      'Ne fermez pas HearthBit depuis les apps récentes : le système tuerait le maillage.';

  @override
  String get powerTipAndroidVendor =>
      'Certains fabricants (Xiaomi, Huawei, Samsung) ont leur propre économiseur d\'énergie : excluez-y aussi HearthBit.';

  @override
  String get powerTipAndroidSync =>
      'Désactivez la synchronisation automatique des comptes pendant l\'urgence.';

  @override
  String get powerTipIosForceClose =>
      'Ne forcez pas la fermeture de HearthBit : iOS ne la relance pas tout seul.';

  @override
  String get powerTipIosBackgroundRefresh =>
      'Désactivez l\'actualisation en arrière-plan des autres apps dans Réglages.';

  @override
  String get powerTipIosLowPower =>
      'Évitez le mode économie d\'énergie sauf si HearthBit est à l\'écran : il réduit le Bluetooth en arrière-plan.';

  @override
  String get powerTipShareBattery =>
      'Partagez les batteries externes entre voisins : un seul téléphone allumé maintient le lien de tout le pâté de maisons.';

  @override
  String get nicknameDialogTitle => 'Nom affiché';

  @override
  String get nicknameDialogHint => 'Ex. Maison 12 ou Ana';

  @override
  String get actionCancel => 'ANNULER';

  @override
  String get actionSave => 'ENREGISTRER';

  @override
  String get wipeDialogTitle => 'Effacer toute l\'identité ?';

  @override
  String get wipeDialogBody =>
      'Les clés, l\'historique et les messages en attente seront supprimés. Cette action est irréversible.';

  @override
  String get actionWipe => 'TOUT EFFACER';

  @override
  String get photoProfileTitle => 'Profil d\'urgence';

  @override
  String photoProfileBody(String size) {
    return 'La photo pèse $size MiB. La compresser accélère l\'envoi et économise la batterie du maillage.';
  }

  @override
  String get actionSendOriginal => 'ENVOYER L\'ORIGINAL';

  @override
  String get actionCompress => 'COMPRESSER';

  @override
  String offerFileError(String error) {
    return 'Impossible de proposer le fichier : $error';
  }

  @override
  String get sendByQr => 'Envoyer par QR';

  @override
  String get receiveByQr => 'Recevoir par QR';

  @override
  String get emptyTransfersTitle => 'Aucun transfert';

  @override
  String get emptyTransfersBody =>
      'Touchez le trombone à côté d\'un appareil proche pour lui proposer un fichier. L\'offre voyage chiffrée par le maillage et le contenu utilise le transport le plus rapide disponible. Le mode QR fonctionne même sans aucune radio.';

  @override
  String transferFrom(String nickname) {
    return 'De $nickname';
  }

  @override
  String transferTo(String nickname) {
    return 'Pour $nickname';
  }

  @override
  String transferProgress(String done, String total) {
    return '$done sur $total';
  }

  @override
  String transferSavedAt(String path) {
    return 'Enregistré dans $path';
  }

  @override
  String get stateOffered => 'Offre';

  @override
  String get stateConnecting => 'Connexion';

  @override
  String get stateTransferring => 'Envoi';

  @override
  String get stateCompleted => 'Terminé';

  @override
  String get stateRejected => 'Refusé';

  @override
  String get stateCancelled => 'Annulé';

  @override
  String get stateFailed => 'Échec';

  @override
  String get transportBle => 'Bluetooth';

  @override
  String get transportLan => 'Wi-Fi local';

  @override
  String get transportNearby => 'Nearby';

  @override
  String get transportWifiAware => 'Wi-Fi Aware';

  @override
  String get transportOptical => 'QR optique';

  @override
  String get actionReject => 'REFUSER';

  @override
  String get actionAccept => 'ACCEPTER';

  @override
  String get actionDelete => 'SUPPRIMER';

  @override
  String get opticalFileEmpty => 'Le fichier est vide';

  @override
  String opticalSendStats(String fileName, int chunks, int symbol) {
    return '$fileName · $chunks fragments · symbole $symbol';
  }

  @override
  String get opticalConfirmed => 'Le récepteur a confirmé la réception via BLE';

  @override
  String get opticalSpeedLabel => 'Vitesse';

  @override
  String opticalFps(int fps) {
    return '$fps QR/s';
  }

  @override
  String get densityCompact => 'Compacte';

  @override
  String get densityMedium => 'Moyenne';

  @override
  String get densityHigh => 'Haute';

  @override
  String get opticalSendHint =>
      'Si la caméra réceptrice perd beaucoup d\'images, réduisez la vitesse ou la densité. Le code est « rateless » : répéter des symboles ne corrompt jamais le transfert.';

  @override
  String get opticalShaFailed =>
      'La vérification SHA-256 a échoué ; relancez l\'envoi';

  @override
  String opticalSavedTitle(String fileName) {
    return '$fileName vérifié et enregistré';
  }

  @override
  String get genericFile => 'Fichier';

  @override
  String get actionDone => 'TERMINÉ';

  @override
  String get opticalScanHint =>
      'Pointez la caméra vers le QR de l\'émetteur. L\'en-tête se répète toutes les quelques images.';

  @override
  String opticalReceiveStats(
    String fileName,
    int decoded,
    int total,
    int symbols,
  ) {
    return '$fileName · $decoded sur $total fragments · $symbols symboles';
  }

  @override
  String radarTitle(String nickname) {
    return 'Radar · $nickname';
  }

  @override
  String get radarSignalLost => 'SIGNAL PERDU';

  @override
  String get radarSignalLostHint =>
      'Revenez lentement sur vos pas jusqu\'à retrouver le signal.';

  @override
  String get radarSearching => 'Recherche du signal…';

  @override
  String get radarSearchingHint =>
      'Marchez lentement en décrivant un large cercle. Le radar capte le signal Bluetooth direct (quelques dizaines de mètres).';

  @override
  String get proximityVeryClose => 'TRÈS PROCHE';

  @override
  String get proximityClose => 'PROCHE';

  @override
  String get proximityInRange => 'À PORTÉE';

  @override
  String get proximityFar => 'LOIN';

  @override
  String get trendApproaching => 'Vous vous rapprochez';

  @override
  String get trendReceding => 'Le signal faiblit';

  @override
  String get trendSteady => 'Signal stable';

  @override
  String get trendUnknown => 'Mesure du signal…';

  @override
  String get distanceVeryNear => 'à moins de 2 m';

  @override
  String distanceApprox(int meters) {
    return '≈ $meters m';
  }

  @override
  String get distanceFar => 'à plus de 15 m';

  @override
  String radarDbm(int dbm) {
    return 'Signal $dbm dBm';
  }

  @override
  String radarGpsDistance(String distance) {
    return 'Dernier GPS signalé : à $distance à vol d\'oiseau';
  }

  @override
  String get errorPermissions =>
      'Les autorisations Bluetooth et notifications sont nécessaires pour créer le maillage.';

  @override
  String get errorLocationOff =>
      'Activez la localisation du système pour le mode sauvetage';

  @override
  String get errorUnknown => 'Erreur inconnue';

  @override
  String get terrInterrupted => 'Interrompu à la fermeture de l\'application';

  @override
  String get terrFileSize => 'Le fichier doit peser entre 1 octet et 512 MiB';

  @override
  String get terrOfferExpired => 'L\'offre a expiré sans réponse';

  @override
  String get terrNoTransport => 'Aucun transport compatible avec l\'émetteur';

  @override
  String get terrInvalidSignature =>
      'Une offre avec une signature invalide a été rejetée';

  @override
  String get terrUnsupportedTransport =>
      'Transport non pris en charge dans cette version';

  @override
  String get terrLanIncomplete => 'La connexion LAN s\'est terminée incomplète';

  @override
  String terrLanFailed(String error) {
    return 'Échec LAN : $error';
  }

  @override
  String terrBleChunk(String error) {
    return 'Fragment BLE invalide : $error';
  }

  @override
  String get terrTransport => 'Erreur de transport';

  @override
  String terrNearbyStart(String error) {
    return 'Impossible de démarrer Nearby : $error';
  }

  @override
  String terrWifiAwareStart(String error) {
    return 'Impossible de démarrer Wi-Fi Aware : $error';
  }

  @override
  String terrBleInterrupted(String error) {
    return 'Envoi BLE interrompu : $error';
  }

  @override
  String get terrReceiverSilent =>
      'Le récepteur ne confirme plus les fragments';

  @override
  String terrNearbyUnavailable(String error) {
    return 'Nearby indisponible : $error';
  }

  @override
  String terrWifiAwareUnavailable(String error) {
    return 'Wi-Fi Aware indisponible : $error';
  }

  @override
  String get terrContainerIncomplete => 'Le conteneur est arrivé incomplet';

  @override
  String terrContainerDecrypt(String error) {
    return 'Impossible de déchiffrer le conteneur : $error';
  }

  @override
  String get terrShaMismatch =>
      'La vérification SHA-256 a échoué ; fichier rejeté';

  @override
  String terrNoMeshSession(String error) {
    return 'Pas de connexion de maillage avec le pair : $error';
  }

  @override
  String get terrTransportTimeout => 'Le transport n\'a pas répondu';
}
