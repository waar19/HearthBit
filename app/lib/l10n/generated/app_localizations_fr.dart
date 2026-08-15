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
  String get statusBannerYou => 'Vous';

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
  String get privacyTitle => 'Confidentialité';

  @override
  String get privacyPrivateDefaultBody =>
      'Le mode privé est activé par défaut. HearthBit réduit les identifiants radio stables et limite les annonces d’identité.';

  @override
  String get privacyBitchatInteropTitle => 'Compatibilité BitChat';

  @override
  String get privacyBitchatInteropOffBody =>
      'Désactivée. Les discussions publiques BitChat sont masquées. Les appareils externes restent visibles sans discussion ; seules leurs alertes SOS publiques sont affichées.';

  @override
  String get privacyBitchatInteropWarning =>
      'Activée. Des observateurs proches peuvent corréler cet appareil grâce à un identifiant radio stable et les messages publics restent lisibles par le réseau.';

  @override
  String get meshtasticInteropTitle => 'Radio Meshtastic longue portée';

  @override
  String get meshtasticInteropBody =>
      'Désactivée par défaut. Une fois activée, HearthBit se connecte à une radio Meshtastic proche. Le contenu privé reste chiffré de bout en bout sur le maillage LoRa.';

  @override
  String get externalPresenceNoChat =>
      'Présence réseau externe · sans discussion';

  @override
  String get externalNetworkBadge => 'RÉSEAU EXTERNE';

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
  String get secureChatUnavailableHint => 'En attente du canal chiffré.';

  @override
  String get privateMessagePending => 'En attente';

  @override
  String privateMessageSendError(String error) {
    return 'Impossible d’envoyer le message : $error';
  }

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
  String get peerDoesNotSupportTransfers =>
      'Cette personne utilise BitChat ; les fichiers nécessitent HearthBit. Utilisez plutôt le transfert par QR.';

  @override
  String get sosCardTitle => 'Envoyer une alerte prioritaire';

  @override
  String get sosCardBody =>
      'Votre position GPS sera jointe si possible. L\'alerte est publique et relayée par le maillage.';

  @override
  String get sosPrivacyTitle => 'Confidentialité du SOS public';

  @override
  String get sosPrivacyPublicWarning =>
      'Un SOS public révèle votre message et votre identité cryptographique aux participants du maillage. Choisissez la précision de la position.';

  @override
  String get sosLocationExact => 'Position exacte';

  @override
  String get sosLocationExactBody =>
      'Idéale pour un secours immédiat ; expose des coordonnées précises.';

  @override
  String get sosLocationApproximate => 'Position approximative (recommandé)';

  @override
  String get sosLocationApproximateBody =>
      'Arrondit les coordonnées à une zone de quartier environ.';

  @override
  String get sosLocationNone => 'Sans position';

  @override
  String get sosLocationNoneBody => 'Envoie uniquement votre message SOS.';

  @override
  String get sosSendPublic => 'ENVOYER LE SOS PUBLIC';

  @override
  String get sosMedical => 'J\'ai besoin d\'aide médicale';

  @override
  String get sosTrapped => 'Je suis coincé';

  @override
  String get sosImOk => 'Je vais bien';

  @override
  String get sosDefaultMessage => 'J\'ai besoin d\'aide';

  @override
  String get emergencySmsOpen => 'Prévenir un contact de confiance par SMS';

  @override
  String get emergencySmsTitle => 'SMS d\'urgence';

  @override
  String get emergencySmsBody =>
      'Préparez un message pour un contact de confiance. Votre application de messagerie s\'ouvrira pour le vérifier et l\'envoyer.';

  @override
  String get emergencySmsRecipient => 'Téléphone du contact de confiance';

  @override
  String get emergencySmsMessage => 'Message d\'urgence';

  @override
  String get emergencySmsDisclaimer =>
      'Le message n\'est pas envoyé automatiquement et ne remplace pas un appel aux services d\'urgence officiels.';

  @override
  String get emergencySmsCompose => 'OUVRIR LA MESSAGERIE';

  @override
  String get emergencySmsUnavailable =>
      'Aucune application de messagerie compatible';

  @override
  String get emergencySmsInvalidRecipient =>
      'Saisissez un numéro de téléphone valide';

  @override
  String emergencySmsBodyWithoutLocation(String message) {
    return 'Alerte d\'urgence HearthBit : $message. Ce SMS ne remplace pas les services d\'urgence officiels.';
  }

  @override
  String emergencySmsBodyWithLocation(
    String message,
    String latitude,
    String longitude,
  ) {
    return 'Alerte d\'urgence HearthBit : $message. Coordonnées : $latitude, $longitude. Ce SMS ne remplace pas les services d\'urgence officiels.';
  }

  @override
  String get sosReceivedTitle => 'Alertes reçues';

  @override
  String get sosNoneReceived => 'Aucune alerte SOS reçue.';

  @override
  String get checkInPrivateBody =>
      'Envoie une mise à jour chiffrée de bout en bout uniquement aux proches vérifiés.';

  @override
  String get checkInNoCircle =>
      'Ajoutez un proche vérifié avant d’envoyer un check-in privé.';

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
  String get wipeDialogInstruction => 'Pour confirmer, saisissez BORRAR.';

  @override
  String get wipeDialogKeyword => 'Saisissez BORRAR';

  @override
  String get wipeDialogComplete =>
      'L\'identité et les données sensibles ont été effacées.';

  @override
  String get wipeDialogError =>
      'L\'effacement n\'a pas abouti. Réessayez avant de confier l\'appareil.';

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
  String get terrPeerDoesNotSupportTransfers =>
      'Le destinataire ne prend pas en charge les fichiers HearthBit. Utilisez plutôt le transfert par QR.';

  @override
  String get terrOfferExpiredNoHbt =>
      'L’offre a expiré car le destinataire ne prend pas en charge les transferts HearthBit.';

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
  String beaconRequestTitle(String nickname) {
    return '$nickname vous demande de vous rendre visible';
  }

  @override
  String get beaconRequestBody =>
      'Acceptez pour utiliser la lampe, l’alarme et les vibrations pendant 5 minutes maximum. Rien ne s’active sans votre accord.';

  @override
  String get beaconMakeVisible => 'ME RENDRE VISIBLE';

  @override
  String get beaconStopVisible => 'ARRÊTER LA BALISE PHYSIQUE';

  @override
  String get beaconRequestRemote => 'DEMANDER LA BALISE';

  @override
  String get beaconStopRemote => 'ARRÊTER LA BALISE';

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
  String get radarNoSignalHint =>
      'Pas encore de lecture directe du signal. Gardez HearthBit ouvert sur les deux téléphones et marchez lentement.';

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
  String get tooltipSupport => 'Soutenir HearthBit';

  @override
  String get aboutTitle => 'À propos de HearthBit';

  @override
  String get aboutBody =>
      'HearthBit est un projet d’urgence source-available, dont le code est visible pour auditer la confidentialité et la sécurité. L’usage non commercial est autorisé par licence ; l’usage commercial exige une permission.';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutSourceCode => 'Code source';

  @override
  String get supportButton => 'Offrez-moi un café';

  @override
  String get shareInviteButton => 'Partager HearthBit';

  @override
  String shareInviteMessage(String url) {
    return 'Rejoignez HearthBit, un réseau maillé d’urgence publiquement vérifiable qui fonctionne sans Internet. Téléchargez-le ou contribuez sur $url';
  }

  @override
  String get tooltipShare => 'Inviter des personnes sur HearthBit';

  @override
  String get shareInviteError => 'Impossible d\'ouvrir les options de partage';

  @override
  String get diagnosticsExportButton => 'Exporter le diagnostic';

  @override
  String get diagnosticsExportSubject => 'Diagnostic HearthBit';

  @override
  String get diagnosticsExportError =>
      'Impossible d\'exporter le rapport de diagnostic';

  @override
  String get diagnosticsTitle => 'Diagnostic';

  @override
  String get diagnosticsRefreshTooltip => 'Actualiser le diagnostic';

  @override
  String get diagnosticsMeshSection => 'Maillage';

  @override
  String get diagnosticsPlatform => 'Plateforme';

  @override
  String get diagnosticsStatus => 'État';

  @override
  String get diagnosticsNearbyDevices => 'Appareils à proximité';

  @override
  String get diagnosticsAdvertising => 'Annonce BLE';

  @override
  String get diagnosticsMeshScan => 'Balayage du maillage';

  @override
  String get diagnosticsGenericScan => 'Balayage des signaux génériques';

  @override
  String get diagnosticsEnergySection => 'Énergie';

  @override
  String get diagnosticsBattery => 'Batterie';

  @override
  String get diagnosticsPowerProfile => 'Profil énergétique';

  @override
  String get diagnosticsBleDutyCycle => 'Cycle d\'activité BLE';

  @override
  String get diagnosticsScanStarts => 'Démarrages du balayage';

  @override
  String get diagnosticsStoreForward => 'File de stockage et retransmission';

  @override
  String get diagnosticsTransportsSection => 'Transports actifs';

  @override
  String get diagnosticsNoActiveTransports => 'Aucun transport actif signalé';

  @override
  String get diagnosticsEventsSection => 'Événements récents';

  @override
  String get diagnosticsNoEvents => 'Aucun événement de diagnostic';

  @override
  String get diagnosticsEnabled => 'Actif';

  @override
  String get diagnosticsDisabled => 'Inactif';

  @override
  String get openLinkError => 'Impossible d\'ouvrir le lien';

  @override
  String get actionClose => 'Fermer';

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

  @override
  String get recentChatsTitle => 'Conversations récentes';

  @override
  String get nearbyPeopleTitle => 'Personnes à proximité';

  @override
  String get peerRoleInfraRelay => 'Relais d’infrastructure';

  @override
  String get peerRoleStorageAnchor => 'Ancre de stockage des messages';

  @override
  String get peerLongRangeTrunkActive => 'Liaison longue portée active';

  @override
  String get peerOnline => 'En ligne';

  @override
  String get peerOffline => 'Hors ligne';

  @override
  String get offlineChatHint =>
      'Cette personne est hors ligne. Vous pouvez lire l\'historique et envoyer lorsqu\'elle se reconnectera.';

  @override
  String get radarConsentTitle => 'Confidentialité du radar';

  @override
  String get radarConsentOff => 'La localisation radar est bloquée par défaut';

  @override
  String radarConsentActive(int minutes) {
    return 'Les autres peuvent utiliser le radar encore $minutes min';
  }

  @override
  String get radarConsentAllow => 'Autoriser le radar pendant 15 minutes';

  @override
  String get radarConsentRevoke => 'Révoquer maintenant';

  @override
  String get radarPrivacyWarning =>
      'Cela limite uniquement HearthBit. Un autre logiciel peut toujours mesurer les signaux Bluetooth émis par votre téléphone.';

  @override
  String get rescueRadarWarning =>
      'Le mode secours partage des positions SOS actualisées et permet aux secouristes HearthBit proches de mesurer votre signal tant que le SOS reste actif.';

  @override
  String get radarConsentRequired =>
      'Nécessite le consentement de cette personne';

  @override
  String get radarConsentSos => 'Disponible grâce à un SOS récent';

  @override
  String get radarConsentTemporary =>
      'Autorisé temporairement par cette personne';

  @override
  String radarConsentExpires(String time) {
    return 'L\'autorisation expire à $time';
  }

  @override
  String get radarNotDirection =>
      'Le point indique la proximité, pas la direction. Déplacez-vous lentement et vérifiez si le signal se renforce.';

  @override
  String get radarPermissionExpired =>
      'L\'autorisation radar a expiré ou a été révoquée.';

  @override
  String get radarTentativeSignal =>
      'Signal provisoire : vérification que cet iPhone correspond à la personne sélectionnée.';

  @override
  String get radarSweepStart => 'CHERCHER LA DIRECTION';

  @override
  String get radarSweepRestart => 'REFAIRE LE BALAYAGE';

  @override
  String get radarSweepHoldTitle => 'Comment tenir le téléphone';

  @override
  String get radarSweepInstruction =>
      'Gardez-le à plat devant la poitrine, écran vers le haut et bord supérieur vers l’avant. Tournez lentement tout le corps.';

  @override
  String radarSweepProgress(int percent) {
    return 'Progression du balayage : $percent %';
  }

  @override
  String radarSweepResult(int heading) {
    return 'Secteur probable du signal : $heading° (±30°)';
  }

  @override
  String radarSweepConfidence(int percent) {
    return 'Confiance : $percent %';
  }

  @override
  String get radarSweepInconclusive =>
      'Aucun secteur fiable détecté. Tournez plus lentement et éloignez-vous du métal ou des appareils électroniques.';

  @override
  String get radarSweepExpired =>
      'La direction a changé ou a expiré. Recommencez le balayage depuis votre position actuelle.';

  @override
  String radarMeasuredDistance(String distance) {
    return 'Mesurée : $distance';
  }

  @override
  String radarGpsDistanceMargin(String distance, String accuracy) {
    return '≈$distance ±$accuracy GPS';
  }

  @override
  String get radarActionRadio => 'Radio';

  @override
  String get radarActionSonar => 'Sonar';

  @override
  String get radarActionBeacon => 'Balise';

  @override
  String get radarActionDirection => 'Direction';

  @override
  String get radarActionSweeping => 'Balayage';

  @override
  String get radarActionWaiting => 'En attente';

  @override
  String get radarRadioStart => 'Mesurer la distance par radio';

  @override
  String get radarRadioStop => 'Arrêter la mesure radio';

  @override
  String get radarSonarStart => 'Mesurer avec le sonar acoustique';

  @override
  String get radarSonarStop => 'Arrêter le sonar acoustique';

  @override
  String get radarSonarMicrophoneRequired =>
      'Le sonar acoustique nécessite l’accès au microphone.';

  @override
  String get radarSonarTooNoisy =>
      'Les signaux n’ont pas pu être mesurés. Réduisez le bruit, laissez les téléphones découverts et réessayez.';

  @override
  String get radarSonarRemoteMicrophoneRequired =>
      'L’autre téléphone n’a pas autorisé l’accès au microphone pour le sonar.';

  @override
  String get radarSonarSelfChirpMissing =>
      'Ce téléphone n’a pas détecté son propre signal. Déconnectez les écouteurs Bluetooth, dégagez le haut-parleur et réessayez.';

  @override
  String get radarSweepEstimateWarning =>
      'Le BLE estime seulement un secteur large, pas une direction exacte. Confirmez-le en vous déplaçant et en recommençant.';

  @override
  String get radarCompassUnavailable =>
      'Ce téléphone ne dispose pas d’une boussole utilisable. Le radar de proximité reste disponible.';

  @override
  String get radarCompassCalibration =>
      'Éloignez le téléphone du métal ou des appareils électroniques et décrivez un huit pour calibrer la boussole.';

  @override
  String get radarDirectionGps => 'Cap guidé par GPS · suivez le losange bleu';

  @override
  String get radarDirectionBle => 'Secteur estimé par balayage BLE';

  @override
  String get radarDirectionVeryClose =>
      'Vous êtes très proche : le secteur BLE est masqué car il n’est plus fiable. Tournez-vous et suivez les vibrations.';

  @override
  String get radarSourcesDisagree =>
      'Le GPS et le BLE divergent ; la direction reste masquée jusqu\'à une nouvelle mesure.';

  @override
  String get dateToday => 'Aujourd’hui';

  @override
  String get dateYesterday => 'Hier';

  @override
  String get genericPresenceSectionTitle => 'Autres signaux Bluetooth';

  @override
  String get genericPresenceNoChat => 'Présence détectée, sans chat';

  @override
  String genericPresenceSignal(int rssi) {
    return 'Signal Bluetooth générique · $rssi dBm';
  }

  @override
  String genericPresenceSummary(int count, int rssi) {
    return '$count signaux Bluetooth proches · plus fort $rssi dBm';
  }

  @override
  String get genericPresenceExpand => 'Afficher le détail des signaux';

  @override
  String get nodeModeTooltip => 'Mode du nœud';

  @override
  String get nodeModeTitle => 'Comment ce téléphone doit-il participer ?';

  @override
  String get nodeModeRelayTitle => 'Relais maillé';

  @override
  String get nodeModeRelayBody =>
      'Discutez normalement et relayez les messages des personnes proches.';

  @override
  String get nodeModeBeaconTitle => 'Présence uniquement';

  @override
  String get nodeModeBeaconBody =>
      'Économise l’énergie et annonce votre présence sans discussion ni relais. Sur Android, les liaisons de données sont aussi désactivées.';

  @override
  String get tabEmergency => 'Urgence';

  @override
  String get emergencyHeadline => 'Mode urgence';

  @override
  String get emergencyInstructions =>
      'Maintenez SOS pendant 2 secondes. HearthBit active le maillage, partage votre position et répète l’alerte.';

  @override
  String get emergencyHoldSos => 'MAINTENIR POUR SOS';

  @override
  String get emergencySosActive => 'SOS ACTIF';

  @override
  String get emergencyStopRescue => 'Arrêter le mode secours';

  @override
  String get emergencyDeliveryTitle => 'État des alertes diffusées';

  @override
  String get deliveryPending => 'Diffusion en attente';

  @override
  String get deliveryRelayed => 'Diffusée sur le maillage';

  @override
  String get deliveryAcknowledged => 'Confirmée par HearthBit';

  @override
  String get deliveryExpired => 'Expirée sans confirmation';

  @override
  String get deliveryAttemptsLabel => 'Tentatives';

  @override
  String get deliveryConfirmationsLabel => 'Confirmations';

  @override
  String get deliveryLastAttemptLabel => 'Dernière tentative';

  @override
  String get deliveryExpiresLabel => 'Expire';

  @override
  String get deliveryNoHearthBitConfirmation =>
      'Aucune confirmation d’un autre HearthBit ; un nœud BitChat a néanmoins pu la recevoir.';

  @override
  String get deliveryRetry => 'Réessayer l’alerte';

  @override
  String get errorEmergencyMeshUnavailable =>
      'Impossible d’activer le maillage Bluetooth. Vérifiez les autorisations.';

  @override
  String get checkInTitle => 'Indiquez votre état';

  @override
  String get checkInBody =>
      'Un bref état est relayé avec l’heure et la position disponible.';

  @override
  String get checkInOk => 'Je vais bien';

  @override
  String get checkInNeedsHelp => 'J’ai besoin d’aide';

  @override
  String get checkInInjured => 'Je suis blessé';

  @override
  String get checkInRecentTitle => 'Derniers états';

  @override
  String get checkInNone => 'Personne n’a encore partagé son état.';

  @override
  String get onboardingWelcomeTitle => 'Communiquer quand les réseaux tombent';

  @override
  String get onboardingWelcomeBody =>
      'HearthBit relaie les messages d’urgence par Bluetooth, sans réseau mobile ni internet.';

  @override
  String get onboardingMeshTitle => 'Maintenez le maillage d’urgence actif';

  @override
  String get onboardingMeshBody =>
      'Les autorisations Bluetooth, appareils proches et notifications permettent la découverte et le relais.';

  @override
  String get onboardingReadyTitle => 'Préparez-vous avant l’urgence';

  @override
  String get onboardingReadyBody =>
      'Autorisez la position en arrière-plan et retirez les restrictions de batterie.';

  @override
  String get onboardingNicknameLabel => 'Votre nom visible (facultatif)';

  @override
  String get onboardingNext => 'SUIVANT';

  @override
  String get onboardingBack => 'RETOUR';

  @override
  String get onboardingAllowMesh => 'AUTORISER ET ACTIVER';

  @override
  String get onboardingAllowLocation => 'AUTORISER LA POSITION D’URGENCE';

  @override
  String get onboardingFinish => 'TERMINER';

  @override
  String get appearanceTitle => 'Affichage et accessibilité';

  @override
  String get appearanceAmoled => 'Thème noir AMOLED';

  @override
  String get appearanceAmoledBody =>
      'Le noir réel économise la batterie des écrans OLED.';

  @override
  String get appearanceHighContrast => 'Contraste élevé et grands contrôles';

  @override
  String get appearanceHighContrastBody =>
      'Améliore la lisibilité et agrandit les actions critiques.';

  @override
  String get tooltipAppearance => 'Affichage et accessibilité';

  @override
  String get meshHealthTitle => 'État du maillage';

  @override
  String meshHealthDirect(int count) {
    return '$count appareils directs';
  }

  @override
  String meshHealthRelays(int count) {
    return '$count téléphones retransmettent les messages';
  }

  @override
  String meshHealthAnchors(int count) {
    return '$count points de stockage des messages';
  }

  @override
  String meshHealthTrunks(int count) {
    return '$count liaisons longue portée actives';
  }

  @override
  String meshHealthSignals(int count) {
    return '$count autres signaux Bluetooth';
  }

  @override
  String get meshHealthAnchorReady =>
      'Un point de stockage des messages est proche.';

  @override
  String get meshHealthNoAnchor =>
      'Aucun point de stockage des messages à proximité.';

  @override
  String get adaptivePowerTitle => 'Batterie adaptative';

  @override
  String get adaptivePowerNormal => 'Performances complètes';

  @override
  String get adaptivePowerSaving => 'Économie : balayage par courtes périodes';

  @override
  String get powerProfilePerformance => 'Performance : détection rapide';

  @override
  String get powerProfileBalanced =>
      'Équilibré : couverture complète du maillage';

  @override
  String get powerProfilePowerSaver => 'Économie : balayage par intervalles';

  @override
  String get powerProfileCritical =>
      'Critique : connexions et balayage minimaux';

  @override
  String get powerProfileSurvival => 'Survie : balise SOS uniquement';

  @override
  String get survivalModeTitle => 'Mode survie';

  @override
  String get survivalModeBody =>
      'Seule une balise SOS reste active. Discussion et relais sont arrêtés.';

  @override
  String get survivalModeEnable => 'ACTIVER LE MODE SURVIE';

  @override
  String get survivalModeDisable => 'REVENIR AU MAILLAGE';

  @override
  String get survivalModeSuggestion =>
      'Batterie critique. Le mode survie prolonge votre détection.';

  @override
  String get gatewayTitle => 'Passerelle internet d’urgence';

  @override
  String get gatewayBody =>
      'Au retour d’internet, ce téléphone peut publier les SOS et états en attente.';

  @override
  String get gatewayOptIn =>
      'Autoriser ce téléphone à offrir une sortie internet';

  @override
  String get gatewayAvailable => 'Connexion internet détectée';

  @override
  String get gatewayUnavailable => 'Aucune connexion internet détectée';

  @override
  String get gatewayPrivacy =>
      'Seuls SOS et états sont éligibles. Rien n’est envoyé sans passerelle de confiance configurée.';

  @override
  String gatewayPending(int count) {
    return '$count éléments d’urgence en attente';
  }

  @override
  String get gatewayConfigure => 'Configurer une passerelle de confiance';

  @override
  String get gatewayKindMatrix => 'Matrix';

  @override
  String get gatewayKindMqtt => 'MQTT';

  @override
  String get gatewayHomeserver => 'URL du serveur Matrix';

  @override
  String get gatewayBroker => 'Serveur MQTT';

  @override
  String get gatewayRoom => 'ID du salon Matrix';

  @override
  String get gatewayTopic => 'Sujet MQTT';

  @override
  String get gatewayUsername => 'Utilisateur';

  @override
  String get gatewayAccessToken => 'Jeton d’accès';

  @override
  String get gatewayPassword => 'Mot de passe';

  @override
  String get gatewayPort => 'Port';

  @override
  String get gatewayTls => 'Utiliser une connexion TLS chiffrée';

  @override
  String get gatewayTrustTitle => 'Confiance du certificat TLS';

  @override
  String get gatewayTrustSystem => 'Système';

  @override
  String get gatewayTrustSystemBody =>
      'Utilise les autorités de certification approuvées par l’appareil. Compatible avec les services publics, sans verrouiller la passerelle sur un certificat.';

  @override
  String get gatewayTrustTofu => 'TOFU';

  @override
  String get gatewayTrustTofuBody =>
      'Approuve le premier certificat vu pour ce service et refuse les changements ultérieurs. Vérifiez que la première connexion n’est pas interceptée.';

  @override
  String get gatewayTrustPinned => 'Épinglé';

  @override
  String get gatewayTrustPinnedBody =>
      'Seule l’empreinte SHA-256 exacte est acceptée. Un renouvellement de certificat bloquera l’envoi jusqu’à la mise à jour de cette valeur.';

  @override
  String get gatewayFingerprint => 'Empreinte SHA-256 du certificat';

  @override
  String get gatewayFingerprintHint =>
      '64 caractères hexadécimaux ; séparateurs autorisés';

  @override
  String get gatewayFingerprintInvalid =>
      'Saisissez une empreinte SHA-256 valide de 64 caractères.';

  @override
  String get gatewayResetTofu => 'Oublier le premier certificat';

  @override
  String get gatewayResetTofuDone =>
      'Le certificat TOFU enregistré a été supprimé.';

  @override
  String get gatewayPrivacyScopeTitle => 'Données partagées avec la passerelle';

  @override
  String get gatewaySensitiveContentConsent =>
      'Partager le contenu et l’identité de l’expéditeur';

  @override
  String get gatewaySensitiveContentConsentBody =>
      'Inclut la description d’urgence, le nom affiché et l’identifiant du pair. Désactivé par défaut.';

  @override
  String get gatewayCoordinatesConsent => 'Partager les coordonnées précises';

  @override
  String get gatewayCoordinatesConsentBody =>
      'Inclut latitude et longitude lorsqu’elles existent. Ce consentement est distinct du contenu.';

  @override
  String get gatewayPrivacyScopeWarning =>
      'La passerelle envoie les données sélectionnées à un service Internet hors du maillage local. Activez chaque catégorie uniquement avec un consentement éclairé.';

  @override
  String get mapOpen => 'Ouvrir la carte hors ligne';

  @override
  String get mapOpenRescue => 'OUVRIR LA CARTE DE SECOURS';

  @override
  String get mapTitle => 'Carte de secours hors ligne';

  @override
  String get mapMyLocation => 'Centrer sur ma position';

  @override
  String get mapPassiveCacheInfo =>
      'Cette carte conserve automatiquement les tuiles consultées pour les réutiliser hors ligne. Le téléchargement d’une région exige un fournisseur autorisé ou votre propre serveur.';

  @override
  String get mapTilePolicyAction => 'Politique OSM';

  @override
  String get mapDownloadVisible => 'Télécharger la zone visible';

  @override
  String mapDownloadComplete(int count) {
    return '$count tuiles enregistrées pour une utilisation hors ligne.';
  }

  @override
  String mapDownloadTooLarge(int maximum) {
    return 'Cette zone est trop grande. Zoomez ; la limite sûre est de $maximum tuiles.';
  }

  @override
  String mapDownloadError(String error) {
    return 'Impossible de télécharger la zone : $error';
  }

  @override
  String mapDownloading(int completed, int total) {
    return 'Enregistrement de la carte : $completed/$total';
  }

  @override
  String mapCacheError(String error) {
    return 'Impossible d\'ouvrir le cache hors ligne : $error';
  }

  @override
  String get mapYouAreHere => 'Vous êtes ici';

  @override
  String get mapOfflineHint =>
      'Réseau indisponible. Les tuiles déjà enregistrées restent visibles.';

  @override
  String get mapTileBlockedHint =>
      'Le fournisseur a temporairement bloqué les tuiles. Les marqueurs de secours restent disponibles ; utilisez une source autorisée ou votre propre serveur pour les cartes hors ligne.';

  @override
  String get mapShowOnMap => 'Afficher sur la carte';

  @override
  String get rescueListTitle => 'File de secours · plus proches d\'abord';

  @override
  String get rescueListEmpty =>
      'Aucune alerte SOS ni aucun pointage avec données de secours.';

  @override
  String get rescueExportCsv => 'Partager le CSV de secours';

  @override
  String get rescueExportSubject => 'File de secours HearthBit';

  @override
  String rescueExportError(String error) {
    return 'Impossible de partager la liste : $error';
  }

  @override
  String get rescueDistanceUnknown => 'distance inconnue';

  @override
  String rescueDistanceMeters(int meters) {
    return 'à $meters m';
  }

  @override
  String rescueDistanceKilometers(String kilometers) {
    return 'à $kilometers km';
  }

  @override
  String get voiceRecord => 'Enregistrer un message vocal';

  @override
  String get voiceStop => 'Arrêter l’enregistrement';

  @override
  String get voiceTooLong => 'Les messages vocaux sont limités à 20 secondes.';

  @override
  String get voiceUnsupported =>
      'Les messages vocaux nécessitent HearthBit chez le destinataire.';

  @override
  String get voicePlay => 'Lire le message vocal';

  @override
  String get voicePause => 'Mettre en pause';

  @override
  String get shareApkButton => 'Partager l’APK installée';

  @override
  String get sendApkToPeer => 'Envoyer l’APK HearthBit';

  @override
  String get apkSafetyTitle => 'Partager l’installateur Android ?';

  @override
  String apkSendToPeerWarning(String peer) {
    return '$peer recevra l’installateur Android de HearthBit.';
  }

  @override
  String get apkInstallWarning =>
      'Le destinataire devra autoriser l’installation d’applications depuis la source de réception dans les réglages Android. HearthBit n’installera rien automatiquement.';

  @override
  String get apkSignatureWarning =>
      'Une APK signée avec une autre clé ne peut pas mettre à jour l’application installée. Vérifiez la source et la signature avant l’installation.';

  @override
  String get apkTransportWarning =>
      'L’APK n’est pas transférée par BLE. Elle nécessite le Wi-Fi local, Nearby ou Wi-Fi Aware ; le transfert signalera une erreur si aucun n’est disponible.';

  @override
  String get apkConfirmShare => 'CONTINUER';

  @override
  String get apkPreparing => 'Préparation d’une copie sûre de l’APK…';

  @override
  String get apkSplitUnavailable =>
      'Cette installation utilise des APK fractionnées. Partager uniquement l’APK de base produirait un installateur incomplet ; HearthBit ne la partagera donc pas. Proposez plutôt le lien GitHub.';

  @override
  String get apkUnsupported =>
      'Le partage de l’APK installée est disponible uniquement sur Android.';

  @override
  String apkShareError(String error) {
    return 'Impossible de préparer ou partager l’APK : $error';
  }

  @override
  String get apkShareMessage =>
      'Installateur HearthBit pour Android. Android exige d’autoriser les installations depuis cette source. Une APK signée différemment ne peut pas mettre à jour une installation existante ; vérifiez d’abord la source et la signature.';

  @override
  String apkOfferSent(String peer) {
    return 'APK proposée à $peer. Le transfert signalera une erreur si aucun transport rapide adapté n’est disponible.';
  }

  @override
  String get firstAidOpen => 'OUVRIR LES PREMIERS SECOURS HORS LIGNE';

  @override
  String get firstAidTitle => 'Premiers secours hors ligne';

  @override
  String get firstAidDisclaimer =>
      'Appelez les secours locaux. Ce guide ne remplace ni l’aide professionnelle ni la formation. Les pratiques varient : suivez l’opérateur et les autorités.';

  @override
  String get firstAidChooseTopic => 'Choisissez ce qui se passe';

  @override
  String get firstAidEnglishFallback =>
      'Cette traduction n’a pas pu être vérifiée. Le guide anglais validé est affiché.';

  @override
  String get firstAidSteps => 'Agir maintenant';

  @override
  String get firstAidWarnings => 'À éviter';

  @override
  String get firstAidSources => 'Sources et informations de révision';

  @override
  String firstAidReviewed(String date) {
    return 'Contenu révisé le $date';
  }

  @override
  String get firstAidLoadError =>
      'Impossible de charger le guide hors ligne validé. Ne vous fiez pas à des informations incomplètes ; appelez les secours locaux.';

  @override
  String get familyTitle => 'Groupe familial';

  @override
  String get familySecurityBody =>
      'Les membres sont vérifiés en personne avec un QR signé. Les noms et anciens identifiants seuls ne sont jamais fiables.';

  @override
  String get familyCreateGroup => 'CRÉER UN GROUPE';

  @override
  String get familyRenameGroup => 'RENOMMER LE GROUPE';

  @override
  String get familyGroupHint => 'Ex. Ma famille';

  @override
  String get familyGroupLabel => 'Groupe';

  @override
  String get familyConfirmTitle => 'Confirmer le proche';

  @override
  String familyFingerprint(String fingerprint) {
    return 'Code de sécurité : $fingerprint';
  }

  @override
  String get familyConfirmBody =>
      'Comparez ce code de sécurité sur les deux téléphones avant d’enregistrer.';

  @override
  String get familyAddMember => 'AJOUTER';

  @override
  String get familyRemoveTitle => 'Retirer ce proche ?';

  @override
  String familyRemoveBody(String nickname) {
    return '$nickname n’aura plus les alertes ni le marquage familial.';
  }

  @override
  String get familyRemoveAction => 'RETIRER';

  @override
  String familySaveError(String error) {
    return 'Impossible d’enregistrer le groupe familial : $error';
  }

  @override
  String get familyMembersTitle => 'Membres vérifiés';

  @override
  String get familyScanAction => 'Scanner le QR du proche';

  @override
  String get familyCreateFirst =>
      'Créez un groupe avant d’ajouter des membres.';

  @override
  String get familyNoMembers => 'Aucun membre vérifié.';

  @override
  String get familyMyQr => 'Mon QR de vérification';

  @override
  String get familyMyQrBody =>
      'Montrez ce QR en personne. Il contient votre clé publique de signature, jamais votre clé privée.';

  @override
  String get familyQrUnavailable =>
      'Activez le maillage pour rendre disponible votre QR signé.';

  @override
  String get familyScanTitle => 'Scanner le QR familial';

  @override
  String get familyQrInvalid =>
      'Ce QR est invalide ou sa signature n’a pas pu être vérifiée.';

  @override
  String get familyScanHint =>
      'Scannez le QR affiché sur le téléphone de votre proche.';

  @override
  String get familyAlertBadge => 'PROCHE VÉRIFIÉ';

  @override
  String get drillSafetyBanner => 'EXERCICE - ne demande aucun secours';

  @override
  String get drillModeTitle => 'Mode exercice';

  @override
  String get drillModeBody =>
      'Envoie uniquement des messages d’exercice clairement identifiés. N’envoie jamais de SOS, ne partage pas la position de secours, n’active aucune balise et n’utilise pas la passerelle internet.';

  @override
  String get drillConfirmTitle => 'Activer le mode exercice ?';

  @override
  String get drillConfirmBody =>
      'Les modes secours et survie seront désactivés. Les messages d’exercice sont publics, mais ne peuvent pas devenir de vraies alertes d’urgence.';

  @override
  String get drillEnableAction => 'ACTIVER L’EXERCICE';

  @override
  String get drillHoldToSend => 'MAINTENIR POUR L’EXERCICE';

  @override
  String get drillPracticeMessage => 'Demande d’aide d’exercice';

  @override
  String get drillReceivedTitle => 'Messages d’exercice';

  @override
  String get drillNoneReceived => 'Aucun message d’exercice reçu.';

  @override
  String get drillBadge => 'EXERCICE — PAS UNE URGENCE';

  @override
  String get drillInvalidMessage =>
      'Message d’exercice non reconnu ; il a été isolé des systèmes d’urgence.';

  @override
  String get drillCheckInTitle => 'Simuler une mise à jour d’état';

  @override
  String get drillCheckInBody =>
      'Ces mises à jour restent dans le canal d’exercice et sont exclues des alertes, cartes et exports de secours.';

  @override
  String get drillExitForRealTitle => 'Envoyer un vrai SOS ?';

  @override
  String get drillExitForRealBody =>
      'Cela mettra fin à l’exercice et activera une vraie demande de secours avec partage de position et SOS répétés.';

  @override
  String get drillSendRealSos => 'TERMINER L’EXERCICE ET ENVOYER SOS';

  @override
  String get drillDisableTitle => 'Terminer le mode exercice ?';

  @override
  String get drillDisableBody =>
      'Les messages d’exercice s’arrêteront et HearthBit reviendra au fonctionnement d’urgence réel.';

  @override
  String get drillDisableAction => 'TERMINER L’EXERCICE';

  @override
  String get mapNoLocationTitle => 'Aucune position disponible';

  @override
  String get mapNoLocationBody =>
      'Activez la localisation ou attendez qu’un nœud partage une position de secours valide. La carte n’utilisera jamais (0,0) par défaut.';

  @override
  String get voiceMicrophoneRequired =>
      'L’accès au microphone est requis pour enregistrer un message vocal.';

  @override
  String get actionOpenSettings => 'OUVRIR LES RÉGLAGES';

  @override
  String get opticalUnverifiedTitle => 'Origine non vérifiée';

  @override
  String get opticalUnverifiedBody =>
      'HearthBit ne peut pas associer ce transfert à une identité déjà authentifiée. Comparez l’empreinte avec l’expéditeur avant d’accepter.';

  @override
  String get opticalLegacyWarning =>
      'Cet expéditeur utilise l’ancien format optique non signé.';

  @override
  String opticalFingerprint(String fingerprint) {
    return 'Empreinte : $fingerprint';
  }

  @override
  String get opticalAcceptUnverified => 'ACCEPTER SANS VÉRIFICATION';

  @override
  String get opticalSignatureInvalid =>
      'La signature du manifeste optique ne correspond pas à l’expéditeur connu. Le fichier a été refusé.';

  @override
  String get opticalVerifiedSource => 'Expéditeur vérifié';

  @override
  String get gatewayPrivacyConfirm =>
      'Cette option envoie les messages d’urgence, les informations de l’expéditeur et toute position de secours incluse au service Internet configuré. Activez-la uniquement avec le consentement des personnes concernées.';

  @override
  String get gatewayEnableAction => 'ACTIVER LA PASSERELLE';

  @override
  String get gatewayTlsRequired =>
      'Obligatoire pour les données d’urgence ; les connexions non sécurisées sont bloquées.';

  @override
  String get locationExportConfirmTitle =>
      'Exporter les positions de secours ?';

  @override
  String get locationExportConfirmBody =>
      'Le CSV peut contenir des positions précises et des détails d’urgence. Partagez-le uniquement avec des secouristes de confiance et protégez le fichier.';

  @override
  String get locationExportConfirmAction => 'EXPORTER LES POSITIONS';

  @override
  String get lanGatewayConnected => 'Relais LAN connecté';

  @override
  String get lanGatewaySearching => 'Relais LAN activé · recherche locale';

  @override
  String get lanGatewayDisabled => 'Relais LAN désactivé';

  @override
  String get lanGatewayConfigure => 'CONFIGURER LE RELAIS LAN';

  @override
  String get lanGatewayDisable => 'DÉSACTIVER LE RELAIS LAN';

  @override
  String get lanGatewayPrivacy =>
      'Activation volontaire uniquement. La clé partagée doit correspondre à votre relais HearthBit Raspberry Pi de confiance. Les trames sont authentifiées et chiffrées sur le réseau local.';

  @override
  String get lanGatewayPsk => 'Clé d’appairage de 32 octets (base64)';

  @override
  String get lanGatewayGeneratePsk => 'GÉNÉRER UNE CLÉ';

  @override
  String get lanGatewayInvalidPsk =>
      'Saisissez une clé base64 valide de 32 octets.';

  @override
  String get emergencyContactsOpen => 'Numéros et liens officiels d’urgence';

  @override
  String get emergencyContactsTitle => 'Annuaire d’urgence';

  @override
  String get emergencyContactsSafetyNotice =>
      'Les numéros peuvent fonctionner sans données mobiles, mais nécessitent une couverture vocale. Les sites officiels nécessitent Internet.';

  @override
  String get emergencyContactsCountry => 'Pays ou territoire';

  @override
  String emergencyContactsAutomatic(String country) {
    return 'Automatique ($country)';
  }

  @override
  String get emergencyContactsNumbers => 'Numéros d’urgence';

  @override
  String get emergencyContactsOrganizations => 'Organismes officiels';

  @override
  String get emergencyContactsCall => 'APPELER';

  @override
  String get emergencyContactsWebsite => 'SITE WEB';

  @override
  String get emergencyContactsSources => 'Sources et vérification';

  @override
  String emergencyContactsReviewed(String date) {
    return 'Vérifié le $date';
  }

  @override
  String get emergencyContactsFallback =>
      'Cette traduction n’était pas disponible ; l’annuaire anglais vérifié est affiché.';

  @override
  String get emergencyContactsLoadError =>
      'Impossible de charger l’annuaire d’urgence hors ligne.';

  @override
  String get emergencyContactsOpenError =>
      'Ce téléphone n’a pas pu ouvrir ce numéro ou ce lien.';

  @override
  String get emergencyContactsRetry => 'RÉESSAYER';
}
