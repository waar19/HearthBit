// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'HearthBit';

  @override
  String storageOpenError(String error) {
    return 'Could not open local storage:\n$error';
  }

  @override
  String statusActiveLabel(String nickname, int count) {
    return '$nickname · $count nearby';
  }

  @override
  String statusDegradedLabel(String nickname) {
    return '$nickname · receive-only (no BLE advertising)';
  }

  @override
  String get statusBannerYou => 'You';

  @override
  String get statusStarting => 'Starting mesh…';

  @override
  String get statusError => 'Mesh error';

  @override
  String get statusStopped => 'Mesh stopped';

  @override
  String get actionStop => 'STOP';

  @override
  String get actionRestart => 'RESTART';

  @override
  String get actionActivate => 'TURN ON';

  @override
  String get actionRetry => 'RETRY';

  @override
  String get tooltipChangeName => 'Change name';

  @override
  String get tooltipPanicWipe => 'Emergency wipe';

  @override
  String get tabChannel => 'Channel';

  @override
  String get tabNearby => 'Nearby';

  @override
  String get tabFiles => 'Files';

  @override
  String get tabSos => 'SOS';

  @override
  String get emptyChatTitle => 'No messages yet';

  @override
  String get emptyChatBody =>
      'Turn on the mesh. Messages will hop between nearby phones without using the internet.';

  @override
  String get composerPublicHint => 'Message for everyone nearby';

  @override
  String get composerPrivateHint => 'Encrypted message';

  @override
  String get privateChatIntro =>
      'The first message will start a Noise XX handshake.';

  @override
  String get secureChatUnavailableHint =>
      'Waiting for the encrypted channel to become available.';

  @override
  String get privateMessagePending => 'Pending';

  @override
  String privateMessageSendError(String error) {
    return 'Could not send the message: $error';
  }

  @override
  String get emptyPeersTitle => 'No nearby devices';

  @override
  String get emptyPeersBody =>
      'Keep Bluetooth on and bring another phone with HearthBit or BitChat nearby.';

  @override
  String get peerSecure => 'encrypted channel ready';

  @override
  String get peerTapToEncrypt => 'tap to encrypt';

  @override
  String get tooltipRadar => 'Proximity radar';

  @override
  String get tooltipSendFile => 'Send a file';

  @override
  String get peerDoesNotSupportTransfers =>
      'This person uses BitChat; files require HearthBit. Use QR transfer instead.';

  @override
  String get sosCardTitle => 'Send priority alert';

  @override
  String get sosCardBody =>
      'Your GPS location will be attached if possible. The alert is public and relayed across the mesh.';

  @override
  String get sosMedical => 'I need medical help';

  @override
  String get sosTrapped => 'I am trapped';

  @override
  String get sosImOk => 'I am OK';

  @override
  String get sosDefaultMessage => 'I need help';

  @override
  String get sosReceivedTitle => 'Received alerts';

  @override
  String get sosNoneReceived => 'No SOS alerts received.';

  @override
  String get actionTrack => 'TRACK';

  @override
  String get rescueModeTitle => 'Rescue mode';

  @override
  String rescueModeActive(int minutes) {
    return 'Re-sending your SOS with location every $minutes min.';
  }

  @override
  String rescueModeLastPing(String time) {
    return 'Last sent: $time.';
  }

  @override
  String rescueModeInactive(int minutes) {
    return 'Re-sends your SOS with fresh GPS every $minutes minutes, even with the screen off.';
  }

  @override
  String get rescueModeNoBackgroundLocation =>
      'Without always-on location, GPS only updates while the app is open.';

  @override
  String get actionAllow => 'ALLOW';

  @override
  String get powerCardTitle => 'Battery & location';

  @override
  String get powerCardSubtitle =>
      'Settings that keep the mesh beating and help rescuers find you.';

  @override
  String get powerBatteryOptimization =>
      'Battery optimization disabled for HearthBit';

  @override
  String get actionDisable => 'DISABLE';

  @override
  String get powerLocationAndroid => 'Location allowed \"all the time\"';

  @override
  String get powerLocationIos => 'Location allowed \"always\"';

  @override
  String get powerSaverAndroid =>
      'The system battery saver is on and may shut down the mesh';

  @override
  String get powerSaverIos =>
      'Low Power Mode is on and reduces background Bluetooth';

  @override
  String get powerTipsTitle => 'Battery saving tips';

  @override
  String get actionAdjust => 'ADJUST';

  @override
  String get powerTipBrightness =>
      'Lower the screen brightness to the minimum and shorten the lock timeout.';

  @override
  String get powerTipMobileData =>
      'If there is no internet, turn off mobile data and 5G: the mesh does not use them and searching for signal drains the battery.';

  @override
  String get powerTipCloseApps =>
      'Close apps you do not need; keep Bluetooth and location on.';

  @override
  String get powerTipAndroidRecents =>
      'Do not swipe HearthBit away from recents: the system would kill the mesh.';

  @override
  String get powerTipAndroidVendor =>
      'Some manufacturers (Xiaomi, Huawei, Samsung) have their own battery saver: exclude HearthBit there too.';

  @override
  String get powerTipAndroidSync =>
      'Turn off automatic account sync while the emergency lasts.';

  @override
  String get powerTipIosForceClose =>
      'Do not force-quit HearthBit: iOS will not relaunch it on its own.';

  @override
  String get powerTipIosBackgroundRefresh =>
      'Turn off Background App Refresh for other apps in Settings.';

  @override
  String get powerTipIosLowPower =>
      'Avoid Low Power Mode unless HearthBit is on screen: it reduces background Bluetooth.';

  @override
  String get powerTipShareBattery =>
      'Share power banks between neighbors: a single phone that stays on keeps the whole block linked.';

  @override
  String get nicknameDialogTitle => 'Display name';

  @override
  String get nicknameDialogHint => 'E.g. House 12 or Ana';

  @override
  String get actionCancel => 'CANCEL';

  @override
  String get actionSave => 'SAVE';

  @override
  String get wipeDialogTitle => 'Erase all identity?';

  @override
  String get wipeDialogBody =>
      'Keys, history and pending messages will be deleted. This cannot be undone.';

  @override
  String get actionWipe => 'ERASE EVERYTHING';

  @override
  String get photoProfileTitle => 'Emergency profile';

  @override
  String photoProfileBody(String size) {
    return 'The photo is $size MiB. Compressing it speeds up delivery and saves battery across the mesh.';
  }

  @override
  String get actionSendOriginal => 'SEND ORIGINAL';

  @override
  String get actionCompress => 'COMPRESS';

  @override
  String offerFileError(String error) {
    return 'Could not offer the file: $error';
  }

  @override
  String get terrPeerDoesNotSupportTransfers =>
      'The recipient does not support HearthBit file transfers. Use QR transfer instead.';

  @override
  String get terrOfferExpiredNoHbt =>
      'The offer expired because the recipient does not support HearthBit file transfers.';

  @override
  String get sendByQr => 'Send via QR';

  @override
  String get receiveByQr => 'Receive via QR';

  @override
  String get emptyTransfersTitle => 'No transfers';

  @override
  String get emptyTransfersBody =>
      'Tap the paper clip next to a nearby device to offer it a file. The offer travels encrypted over the mesh and the content uses the fastest transport available. QR mode even works with no radios at all.';

  @override
  String transferFrom(String nickname) {
    return 'From $nickname';
  }

  @override
  String transferTo(String nickname) {
    return 'To $nickname';
  }

  @override
  String transferProgress(String done, String total) {
    return '$done of $total';
  }

  @override
  String transferSavedAt(String path) {
    return 'Saved to $path';
  }

  @override
  String get stateOffered => 'Offer';

  @override
  String get stateConnecting => 'Connecting';

  @override
  String get stateTransferring => 'Sending';

  @override
  String get stateCompleted => 'Done';

  @override
  String get stateRejected => 'Rejected';

  @override
  String get stateCancelled => 'Cancelled';

  @override
  String get stateFailed => 'Failed';

  @override
  String get transportBle => 'Bluetooth';

  @override
  String get transportLan => 'Local Wi-Fi';

  @override
  String get transportNearby => 'Nearby';

  @override
  String get transportWifiAware => 'Wi-Fi Aware';

  @override
  String get transportOptical => 'Optical QR';

  @override
  String get actionReject => 'REJECT';

  @override
  String get actionAccept => 'ACCEPT';

  @override
  String get actionDelete => 'REMOVE';

  @override
  String get opticalFileEmpty => 'The file is empty';

  @override
  String opticalSendStats(String fileName, int chunks, int symbol) {
    return '$fileName · $chunks chunks · symbol $symbol';
  }

  @override
  String get opticalConfirmed => 'The receiver confirmed reception over BLE';

  @override
  String get opticalSpeedLabel => 'Speed';

  @override
  String opticalFps(int fps) {
    return '$fps QR/s';
  }

  @override
  String get densityCompact => 'Compact';

  @override
  String get densityMedium => 'Medium';

  @override
  String get densityHigh => 'High';

  @override
  String get opticalSendHint =>
      'If the receiving camera misses many frames, lower the speed or density. The code is rateless: repeating symbols never corrupts the transfer.';

  @override
  String get opticalShaFailed =>
      'SHA-256 verification failed; restart the send';

  @override
  String opticalSavedTitle(String fileName) {
    return '$fileName verified and saved';
  }

  @override
  String get genericFile => 'File';

  @override
  String get actionDone => 'DONE';

  @override
  String get opticalScanHint =>
      'Point the camera at the sender\'s QR. The header repeats every few frames.';

  @override
  String opticalReceiveStats(
    String fileName,
    int decoded,
    int total,
    int symbols,
  ) {
    return '$fileName · $decoded of $total chunks · $symbols symbols';
  }

  @override
  String radarTitle(String nickname) {
    return 'Radar · $nickname';
  }

  @override
  String beaconRequestTitle(String nickname) {
    return '$nickname asks you to become visible';
  }

  @override
  String get beaconRequestBody =>
      'Accept to use the flashlight, alarm and vibration for up to 5 minutes. Nothing turns on without your consent.';

  @override
  String get beaconMakeVisible => 'MAKE ME VISIBLE';

  @override
  String get beaconStopVisible => 'STOP PHYSICAL BEACON';

  @override
  String get beaconRequestRemote => 'REQUEST BEACON';

  @override
  String get beaconStopRemote => 'STOP BEACON';

  @override
  String get radarSignalLost => 'SIGNAL LOST';

  @override
  String get radarSignalLostHint =>
      'Walk back slowly along your path until the signal returns.';

  @override
  String get radarSearching => 'Searching for signal…';

  @override
  String get radarSearchingHint =>
      'Walk slowly in a wide circle. The radar picks up the direct Bluetooth signal (tens of meters).';

  @override
  String get proximityVeryClose => 'VERY CLOSE';

  @override
  String get proximityClose => 'CLOSE';

  @override
  String get proximityInRange => 'IN RANGE';

  @override
  String get proximityFar => 'FAR';

  @override
  String get trendApproaching => 'You are getting closer';

  @override
  String get trendReceding => 'The signal is getting weaker';

  @override
  String get trendSteady => 'Signal steady';

  @override
  String get trendUnknown => 'Measuring signal…';

  @override
  String get distanceVeryNear => 'less than 2 m away';

  @override
  String distanceApprox(int meters) {
    return '≈ $meters m';
  }

  @override
  String get distanceFar => 'more than 15 m away';

  @override
  String radarDbm(int dbm) {
    return 'Signal $dbm dBm';
  }

  @override
  String radarGpsDistance(String distance) {
    return 'Last reported GPS: $distance away in a straight line';
  }

  @override
  String get errorPermissions =>
      'Bluetooth and notification permissions are required to build the mesh.';

  @override
  String get errorLocationOff => 'Turn on system location for rescue mode';

  @override
  String get errorUnknown => 'Unknown error';

  @override
  String get tooltipSupport => 'Support HearthBit';

  @override
  String get aboutTitle => 'About HearthBit';

  @override
  String get aboutBody =>
      'HearthBit is an open-source emergency communication project. Your support helps fund device testing and resilient relay hardware.';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutSourceCode => 'Source code';

  @override
  String get supportButton => 'Buy me a coffee';

  @override
  String get shareInviteButton => 'Share HearthBit';

  @override
  String shareInviteMessage(String url) {
    return 'Join HearthBit, an open-source emergency mesh that works without internet. Download it or contribute at $url';
  }

  @override
  String get tooltipShare => 'Invite people to HearthBit';

  @override
  String get shareInviteError => 'Could not open the sharing options';

  @override
  String get openLinkError => 'Could not open the link';

  @override
  String get actionClose => 'Close';

  @override
  String get terrInterrupted => 'Interrupted when the app closed';

  @override
  String get terrFileSize => 'The file must be between 1 byte and 512 MiB';

  @override
  String get terrOfferExpired => 'The offer expired without an answer';

  @override
  String get terrNoTransport => 'No transport compatible with the sender';

  @override
  String get terrInvalidSignature =>
      'An offer with an invalid signature was discarded';

  @override
  String get terrUnsupportedTransport =>
      'Transport not supported in this version';

  @override
  String get terrLanIncomplete => 'The LAN connection ended incomplete';

  @override
  String terrLanFailed(String error) {
    return 'LAN failed: $error';
  }

  @override
  String terrBleChunk(String error) {
    return 'Invalid BLE chunk: $error';
  }

  @override
  String get terrTransport => 'Transport error';

  @override
  String terrNearbyStart(String error) {
    return 'Could not start Nearby: $error';
  }

  @override
  String terrWifiAwareStart(String error) {
    return 'Could not start Wi-Fi Aware: $error';
  }

  @override
  String terrBleInterrupted(String error) {
    return 'BLE send interrupted: $error';
  }

  @override
  String get terrReceiverSilent => 'The receiver stopped acknowledging chunks';

  @override
  String terrNearbyUnavailable(String error) {
    return 'Nearby unavailable: $error';
  }

  @override
  String terrWifiAwareUnavailable(String error) {
    return 'Wi-Fi Aware unavailable: $error';
  }

  @override
  String get terrContainerIncomplete => 'The container arrived incomplete';

  @override
  String terrContainerDecrypt(String error) {
    return 'Could not decrypt the container: $error';
  }

  @override
  String get terrShaMismatch => 'SHA-256 verification failed; file discarded';

  @override
  String terrNoMeshSession(String error) {
    return 'No mesh connection with the peer: $error';
  }

  @override
  String get terrTransportTimeout => 'The transport did not respond';

  @override
  String get recentChatsTitle => 'Recent conversations';

  @override
  String get nearbyPeopleTitle => 'Nearby people';

  @override
  String get peerOnline => 'Online';

  @override
  String get peerOffline => 'Offline';

  @override
  String get offlineChatHint =>
      'This person is offline. You can read the history and send when they reconnect.';

  @override
  String get radarConsentTitle => 'Radar privacy';

  @override
  String get radarConsentOff => 'Radar location is blocked by default';

  @override
  String radarConsentActive(int minutes) {
    return 'Others may use radar for $minutes more min';
  }

  @override
  String get radarConsentAllow => 'Allow radar for 15 minutes';

  @override
  String get radarConsentRevoke => 'Revoke now';

  @override
  String get radarPrivacyWarning =>
      'This limits HearthBit only. Other software may still measure Bluetooth signals emitted by your phone.';

  @override
  String get rescueRadarWarning =>
      'Rescue mode shares fresh SOS locations and allows nearby HearthBit rescuers to measure your signal while SOS remains active.';

  @override
  String get radarConsentRequired => 'Requires this person\'s consent';

  @override
  String get radarConsentSos => 'Available because of a recent SOS';

  @override
  String get radarConsentTemporary => 'Temporarily authorized by this person';

  @override
  String radarConsentExpires(String time) {
    return 'Permission expires at $time';
  }

  @override
  String get radarNotDirection =>
      'The point shows proximity, not direction. Move slowly and compare whether the signal gets stronger.';

  @override
  String get radarPermissionExpired =>
      'Radar permission expired or was revoked.';

  @override
  String get radarTentativeSignal =>
      'Tentative signal: verifying that this iPhone is the selected person.';

  @override
  String get radarSweepStart => 'FIND DIRECTION';

  @override
  String get radarSweepRestart => 'REPEAT SWEEP';

  @override
  String get radarSweepHoldTitle => 'How to hold the phone';

  @override
  String get radarSweepInstruction =>
      'Keep it flat in front of your chest, screen up and top edge pointing forward. Slowly turn your whole body.';

  @override
  String radarSweepProgress(int percent) {
    return 'Sweep progress: $percent%';
  }

  @override
  String radarSweepResult(int heading) {
    return 'Probable signal sector: $heading° (±30°)';
  }

  @override
  String radarSweepConfidence(int percent) {
    return 'Confidence: $percent%';
  }

  @override
  String get radarSweepInconclusive =>
      'No reliable sector was found. Turn more slowly and move away from metal or electronic equipment.';

  @override
  String get radarSweepEstimateWarning =>
      'BLE can only estimate a broad sector, not an exact direction. Confirm it by moving and repeating the sweep.';

  @override
  String get radarCompassUnavailable =>
      'This phone has no usable compass sensor. Proximity radar remains available.';

  @override
  String get radarCompassCalibration =>
      'Move the phone away from metal or electronics and trace a figure eight to calibrate the compass.';

  @override
  String get radarDirectionGps =>
      'GPS-guided bearing · follow the blue diamond';

  @override
  String get radarDirectionBle => 'Sector estimated by BLE sweep';

  @override
  String get radarDirectionVeryClose =>
      'You are very close: the BLE sector is hidden because it is no longer reliable. Turn and follow the vibration.';

  @override
  String get radarSourcesDisagree =>
      'GPS and BLE disagree; the GPS bearing takes priority.';

  @override
  String get dateToday => 'Today';

  @override
  String get dateYesterday => 'Yesterday';

  @override
  String get genericPresenceSectionTitle => 'Other Bluetooth signals';

  @override
  String get genericPresenceNoChat => 'Presence detected, no chat';

  @override
  String genericPresenceSignal(int rssi) {
    return 'Generic Bluetooth signal · $rssi dBm';
  }

  @override
  String genericPresenceSummary(int count, int rssi) {
    return '$count nearby Bluetooth signals · strongest $rssi dBm';
  }

  @override
  String get genericPresenceExpand => 'Show signal details';

  @override
  String get nodeModeTooltip => 'Node mode';

  @override
  String get nodeModeTitle => 'How should this phone participate?';

  @override
  String get nodeModeRelayTitle => 'Mesh relay';

  @override
  String get nodeModeRelayBody =>
      'Chat normally and relay messages for nearby people.';

  @override
  String get nodeModeBeaconTitle => 'Presence only';

  @override
  String get nodeModeBeaconBody =>
      'Save power and advertise your presence without chat or message relay. On Android, data links are also disabled.';

  @override
  String get tabEmergency => 'Emergency';

  @override
  String get emergencyHeadline => 'Emergency mode';

  @override
  String get emergencyInstructions =>
      'Press and hold SOS for 2 seconds. HearthBit will turn on the mesh, share your location and repeat the alert.';

  @override
  String get emergencyHoldSos => 'HOLD FOR SOS';

  @override
  String get emergencySosActive => 'SOS ACTIVE';

  @override
  String get emergencyStopRescue => 'Stop rescue mode';

  @override
  String get errorEmergencyMeshUnavailable =>
      'The Bluetooth mesh could not be activated. Check Bluetooth permissions and try again.';

  @override
  String get checkInTitle => 'Tell people your status';

  @override
  String get checkInBody =>
      'A short update is relayed through the mesh with your time and location when available.';

  @override
  String get checkInOk => 'I am OK';

  @override
  String get checkInNeedsHelp => 'I need help';

  @override
  String get checkInInjured => 'I am injured';

  @override
  String get checkInRecentTitle => 'Latest check-ins';

  @override
  String get checkInNone => 'No one has shared a status yet.';

  @override
  String get onboardingWelcomeTitle => 'Communication when networks fail';

  @override
  String get onboardingWelcomeBody =>
      'HearthBit relays emergency messages between nearby phones using Bluetooth, without mobile service or internet.';

  @override
  String get onboardingMeshTitle => 'Keep the emergency mesh alive';

  @override
  String get onboardingMeshBody =>
      'Bluetooth, nearby-device and notification permissions let your phone find people and relay their messages.';

  @override
  String get onboardingReadyTitle => 'Prepare before an emergency';

  @override
  String get onboardingReadyBody =>
      'Allow background location and exempt HearthBit from battery restrictions so SOS positions can stay current.';

  @override
  String get onboardingNicknameLabel => 'Your visible name (optional)';

  @override
  String get onboardingNext => 'NEXT';

  @override
  String get onboardingBack => 'BACK';

  @override
  String get onboardingAllowMesh => 'ALLOW AND TURN ON MESH';

  @override
  String get onboardingAllowLocation => 'ALLOW EMERGENCY LOCATION';

  @override
  String get onboardingFinish => 'FINISH SETUP';

  @override
  String get appearanceTitle => 'Display & accessibility';

  @override
  String get appearanceAmoled => 'AMOLED black theme';

  @override
  String get appearanceAmoledBody =>
      'Uses a true black background to save power on OLED screens.';

  @override
  String get appearanceHighContrast => 'High contrast and larger controls';

  @override
  String get appearanceHighContrastBody =>
      'Improves readability and enlarges critical actions.';

  @override
  String get tooltipAppearance => 'Display and accessibility';

  @override
  String get meshHealthTitle => 'Mesh health';

  @override
  String meshHealthDirect(int count) {
    return '$count direct peers';
  }

  @override
  String meshHealthRelays(int count) {
    return '$count phones relaying messages';
  }

  @override
  String meshHealthAnchors(int count) {
    return '$count message storage points';
  }

  @override
  String meshHealthSignals(int count) {
    return '$count other Bluetooth signals';
  }

  @override
  String get meshHealthAnchorReady => 'A message storage point is nearby.';

  @override
  String get meshHealthNoAnchor =>
      'No nearby message storage point is visible.';

  @override
  String get adaptivePowerTitle => 'Adaptive battery mode';

  @override
  String get adaptivePowerNormal => 'Full mesh performance';

  @override
  String get adaptivePowerSaving => 'Battery saving: scanning in short bursts';

  @override
  String get powerProfilePerformance => 'Performance: fast discovery';

  @override
  String get powerProfileBalanced => 'Balanced: full mesh coverage';

  @override
  String get powerProfilePowerSaver => 'Power saving: scanning in intervals';

  @override
  String get powerProfileCritical =>
      'Critical: minimum connections and scanning';

  @override
  String get powerProfileSurvival => 'Survival: SOS beacon only';

  @override
  String get survivalModeTitle => 'Survival mode';

  @override
  String get survivalModeBody =>
      'Keep only an SOS presence beacon active for maximum battery life. Chat and relay stop.';

  @override
  String get survivalModeEnable => 'ENABLE SURVIVAL MODE';

  @override
  String get survivalModeDisable => 'RETURN TO MESH MODE';

  @override
  String get survivalModeSuggestion =>
      'Battery is critical. Enable survival mode to remain detectable longer.';

  @override
  String get gatewayTitle => 'Emergency internet gateway';

  @override
  String get gatewayBody =>
      'When internet returns, this phone can publish queued SOS and check-ins through a gateway you configure.';

  @override
  String get gatewayOptIn => 'Allow this phone to offer internet exit';

  @override
  String get gatewayAvailable => 'Internet transport detected';

  @override
  String get gatewayUnavailable => 'No internet transport detected';

  @override
  String get gatewayPrivacy =>
      'Only SOS and check-ins are eligible. Nothing is uploaded until you configure and enable a trusted gateway.';

  @override
  String gatewayPending(int count) {
    return '$count emergency items pending';
  }

  @override
  String get gatewayConfigure => 'Configure trusted gateway';

  @override
  String get gatewayKindMatrix => 'Matrix';

  @override
  String get gatewayKindMqtt => 'MQTT';

  @override
  String get gatewayHomeserver => 'Matrix homeserver URL';

  @override
  String get gatewayBroker => 'MQTT broker host';

  @override
  String get gatewayRoom => 'Matrix room ID';

  @override
  String get gatewayTopic => 'MQTT topic';

  @override
  String get gatewayUsername => 'Username';

  @override
  String get gatewayAccessToken => 'Access token';

  @override
  String get gatewayPassword => 'Password';

  @override
  String get gatewayPort => 'Port';

  @override
  String get gatewayTls => 'Use encrypted TLS connection';

  @override
  String get mapOpen => 'Open offline map';

  @override
  String get mapOpenRescue => 'OPEN RESCUE MAP';

  @override
  String get mapTitle => 'Offline rescue map';

  @override
  String get mapMyLocation => 'Center on my location';

  @override
  String get mapDownloadVisible => 'Download visible area';

  @override
  String mapDownloadComplete(int count) {
    return '$count map tiles saved for offline use.';
  }

  @override
  String mapDownloadTooLarge(int maximum) {
    return 'This area is too large. Zoom in; the safe limit is $maximum tiles.';
  }

  @override
  String mapDownloadError(String error) {
    return 'Could not download the map area: $error';
  }

  @override
  String mapDownloading(int completed, int total) {
    return 'Saving map tiles: $completed/$total';
  }

  @override
  String mapCacheError(String error) {
    return 'Could not open the offline map cache: $error';
  }

  @override
  String get mapYouAreHere => 'You are here';

  @override
  String get mapOfflineHint =>
      'Network unavailable. Already saved map tiles remain visible.';

  @override
  String get mapShowOnMap => 'Show on map';

  @override
  String get rescueListTitle => 'Rescue queue · nearest first';

  @override
  String get rescueListEmpty => 'No SOS alerts or check-ins with rescue data.';

  @override
  String get rescueExportCsv => 'Share rescue CSV';

  @override
  String get rescueExportSubject => 'HearthBit rescue queue';

  @override
  String rescueExportError(String error) {
    return 'Could not share the rescue list: $error';
  }

  @override
  String get rescueDistanceUnknown => 'distance unknown';

  @override
  String rescueDistanceMeters(int meters) {
    return '$meters m away';
  }

  @override
  String rescueDistanceKilometers(String kilometers) {
    return '$kilometers km away';
  }

  @override
  String get voiceRecord => 'Record voice note';

  @override
  String get voiceStop => 'Stop recording';

  @override
  String get voiceTooLong => 'Voice notes are limited to 20 seconds.';

  @override
  String get voiceUnsupported =>
      'Voice notes require HearthBit on the recipient\'s device.';

  @override
  String get voicePlay => 'Play voice note';

  @override
  String get voicePause => 'Pause voice note';

  @override
  String get shareApkButton => 'Share installed APK';

  @override
  String get sendApkToPeer => 'Send HearthBit APK';

  @override
  String get apkSafetyTitle => 'Share the Android installer?';

  @override
  String apkSendToPeerWarning(String peer) {
    return '$peer will receive the HearthBit Android installer.';
  }

  @override
  String get apkInstallWarning =>
      'The recipient must allow app installation from the receiving source in Android settings. HearthBit will not install anything automatically.';

  @override
  String get apkSignatureWarning =>
      'An APK signed with a different key cannot update the installed app. Verify the source and signature before installing.';

  @override
  String get apkTransportWarning =>
      'APK transfer does not use BLE. It requires local Wi-Fi, Nearby or Wi-Fi Aware; the transfer will report an error if none is available.';

  @override
  String get apkConfirmShare => 'CONTINUE';

  @override
  String get apkPreparing => 'Preparing a safe APK copy…';

  @override
  String get apkSplitUnavailable =>
      'This installation uses split APKs. Sharing only the base APK would create an incomplete installer, so HearthBit will not share it. Offer the GitHub link instead.';

  @override
  String get apkUnsupported =>
      'Sharing an installed APK is only available on Android.';

  @override
  String apkShareError(String error) {
    return 'Could not prepare or share the APK: $error';
  }

  @override
  String get apkShareMessage =>
      'HearthBit Android installer. Android requires permission to install from this source. A differently signed APK cannot update an existing installation; verify the source and signature first.';

  @override
  String apkOfferSent(String peer) {
    return 'APK offered to $peer. The transfer will show an error if no suitable high-speed transport is available.';
  }
}
