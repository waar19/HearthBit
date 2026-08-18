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
  String get statusMeshPermissionsRevoked =>
      'Mesh suspended: Bluetooth or nearby-device permission was revoked.';

  @override
  String get statusMeshBatteryRestricted =>
      'Battery restrictions may suspend the mesh in the background.';

  @override
  String get statusMeshSuspended =>
      'Mesh suspended: messages remain queued until a route is available.';

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
  String get privacyTitle => 'Privacy';

  @override
  String get privacyPrivateDefaultBody =>
      'Private mode is on by default. HearthBit minimizes stable radio identifiers and limits identity announcements.';

  @override
  String get privacyBitchatInteropTitle => 'BitChat compatibility';

  @override
  String get privacyBitchatInteropOffBody =>
      'Off. BitChat public chat is hidden. External devices remain visible without chat, and only their public SOS alerts are shown.';

  @override
  String get privacyBitchatInteropWarning =>
      'On. Nearby observers can correlate this device through a stable radio identifier, and public messages remain readable by the mesh.';

  @override
  String get meshtasticInteropTitle => 'Meshtastic long-range radio';

  @override
  String get meshtasticInteropBody =>
      'Off by default. When enabled, HearthBit connects to one nearby Meshtastic radio. Private content stays end-to-end encrypted over its LoRa mesh.';

  @override
  String get externalPresenceNoChat => 'External network presence · no chat';

  @override
  String get externalNetworkBadge => 'EXTERNAL NETWORK';

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
  String get sosPrivacyTitle => 'Public SOS privacy';

  @override
  String get sosPrivacyPublicWarning =>
      'A public SOS reveals your message and cryptographic identity to mesh participants. Choose how much location to include.';

  @override
  String get sosLocationExact => 'Exact location';

  @override
  String get sosLocationExactBody =>
      'Best for immediate rescue; exposes precise coordinates.';

  @override
  String get sosLocationApproximate => 'Approximate location (recommended)';

  @override
  String get sosLocationApproximateBody =>
      'Rounds coordinates to roughly a neighborhood-sized area.';

  @override
  String get sosLocationNone => 'No location';

  @override
  String get sosLocationNoneBody => 'Sends only your SOS message.';

  @override
  String get sosSendPublic => 'SEND PUBLIC SOS';

  @override
  String get sosMedical => 'I need medical help';

  @override
  String get sosTrapped => 'I am trapped';

  @override
  String get sosImOk => 'I am OK';

  @override
  String get sosDefaultMessage => 'I need help';

  @override
  String get sosQrTitle => 'SOS by QR';

  @override
  String get sosQrShowInstructions =>
      'Show this code to another person. HearthBit can relay the SOS, and any camera can read the fallback text.';

  @override
  String get sosQrFallbackTitle => 'Readable information without the app';

  @override
  String get sosQrOpen => 'SHOW SOS QR';

  @override
  String get sosQrScan => 'SCAN AND RELAY SOS';

  @override
  String get acousticSosListen => 'LISTEN FOR SOUND SOS';

  @override
  String get acousticSosStopListening => 'STOP ACOUSTIC LISTENING';

  @override
  String get sosChannelsTitle => 'SOS sent or prepared through';

  @override
  String get sosQrRelayTitle => 'SOS found';

  @override
  String get sosQrRelayAction => 'RELAY SOS';

  @override
  String get sosQrInvalid =>
      'The QR does not contain a valid signed HearthBit SOS.';

  @override
  String get sosQrRelayed => 'SOS validated and added to the mesh';

  @override
  String get sosSentToMesh => 'SOS sent to the mesh.';

  @override
  String get sosQueuedWithoutRoute =>
      'SOS queued, but there is currently no route out of this phone.';

  @override
  String get emergencySmsOpen => 'Notify a trusted contact by SMS';

  @override
  String get emergencySmsTitle => 'Emergency SMS';

  @override
  String get emergencySmsBody =>
      'Prepare a text message for a trusted contact. Your messaging app will open so you can review and send it.';

  @override
  String get emergencySmsRecipient => 'Trusted contact phone number';

  @override
  String get emergencySmsMessage => 'Emergency message';

  @override
  String get emergencySmsDisclaimer =>
      'This does not send automatically and does not replace a call to official emergency services.';

  @override
  String get emergencySmsCompose => 'OPEN MESSAGING APP';

  @override
  String get emergencySmsUnavailable =>
      'No compatible messaging app is available';

  @override
  String get emergencySmsInvalidRecipient => 'Enter a valid phone number';

  @override
  String emergencySmsBodyWithoutLocation(String message) {
    return 'HearthBit emergency alert: $message. This SMS does not replace official emergency services.';
  }

  @override
  String emergencySmsBodyWithLocation(
    String message,
    String latitude,
    String longitude,
  ) {
    return 'HearthBit emergency alert: $message. Coordinates: $latitude, $longitude. This SMS does not replace official emergency services.';
  }

  @override
  String get sosReceivedTitle => 'Received alerts';

  @override
  String get sosNoneReceived => 'No SOS alerts received.';

  @override
  String get checkInPrivateBody =>
      'Sends an end-to-end encrypted update only to verified family members.';

  @override
  String get checkInNoCircle =>
      'Add a verified family member before sending a private check-in.';

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
  String get wipeDialogInstruction => 'To confirm, type BORRAR.';

  @override
  String get wipeDialogKeyword => 'Type BORRAR';

  @override
  String get wipeDialogComplete => 'Identity and sensitive data were erased.';

  @override
  String get wipeDialogError =>
      'The erase did not complete. Try again before handing over the device.';

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
  String get transportWifiDirect => 'Wi-Fi Direct';

  @override
  String get transportMultipeer => 'Multipeer';

  @override
  String get transportShare => 'Share with another app';

  @override
  String get transportOptical => 'Optical QR';

  @override
  String get transferExport => 'SHARE';

  @override
  String get transferImport => 'Open HearthBit package';

  @override
  String get sealedTransferSend => 'Send sealed through another app';

  @override
  String get sealedImportTitle => 'Verified sealed file';

  @override
  String sealedImportBody(String fileName, String sender) {
    return '$fileName was signed by verified contact $sender. Save it?';
  }

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
  String get radarNoSignalHint =>
      'No direct signal reading yet. Keep HearthBit open on both phones and walk slowly.';

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
      'HearthBit is a source-available emergency communication project, public for privacy and security review. Noncommercial use is licensed; commercial use requires permission.';

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
    return 'Join HearthBit, a publicly auditable emergency mesh that works without internet. Download it or contribute at $url';
  }

  @override
  String get tooltipShare => 'Invite people to HearthBit';

  @override
  String get shareInviteError => 'Could not open the sharing options';

  @override
  String get diagnosticsExportButton => 'Export diagnostics';

  @override
  String get diagnosticsExportSubject => 'HearthBit diagnostics';

  @override
  String get diagnosticsExportError => 'Could not export the diagnostic report';

  @override
  String get diagnosticsTitle => 'Diagnostics';

  @override
  String get diagnosticsRefreshTooltip => 'Refresh diagnostics';

  @override
  String get diagnosticsMeshSection => 'Mesh';

  @override
  String get diagnosticsPlatform => 'Platform';

  @override
  String get diagnosticsStatus => 'Status';

  @override
  String get diagnosticsIdentityRotation => 'Last identity rotation';

  @override
  String get diagnosticsNearbyDevices => 'Nearby devices';

  @override
  String get diagnosticsAdvertising => 'BLE advertising';

  @override
  String get diagnosticsMeshScan => 'Mesh scan';

  @override
  String get diagnosticsGenericScan => 'Generic signal scan';

  @override
  String get diagnosticsEnergySection => 'Energy';

  @override
  String get diagnosticsBattery => 'Battery';

  @override
  String get diagnosticsPowerProfile => 'Power profile';

  @override
  String get diagnosticsBleDutyCycle => 'BLE duty cycle';

  @override
  String get diagnosticsScanStarts => 'Scan starts';

  @override
  String get diagnosticsStoreForward => 'Store-and-forward queue';

  @override
  String get diagnosticsTransportsSection => 'Active transports';

  @override
  String get diagnosticsNoActiveTransports => 'No active transport reported';

  @override
  String get diagnosticsEventsSection => 'Recent events';

  @override
  String get diagnosticsNoEvents => 'No diagnostic events yet';

  @override
  String get diagnosticsEnabled => 'Active';

  @override
  String get diagnosticsDisabled => 'Inactive';

  @override
  String get diagnosticsTransportOutcomesSection => 'Transfer outcomes';

  @override
  String diagnosticsTransportOutcome(int success, int failure) {
    return '$success successful · $failure failed';
  }

  @override
  String get diagnosticsTransportAudio => 'Audio';

  @override
  String get diagnosticsTransportQr => 'QR';

  @override
  String get diagnosticsTransportExternal => 'External share';

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
  String get peerRoleInfraRelay => 'Infrastructure relay';

  @override
  String get peerRoleStorageAnchor => 'Message storage anchor';

  @override
  String get peerLongRangeTrunkActive => 'Long-range trunk active';

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
  String get radarSweepExpired =>
      'The direction changed or expired. Repeat the sweep from your current position.';

  @override
  String radarMeasuredDistance(String distance) {
    return 'Measured: $distance';
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
  String get radarActionBeacon => 'Beacon';

  @override
  String get radarActionDirection => 'Direction';

  @override
  String get radarActionSweeping => 'Sweeping';

  @override
  String get radarActionWaiting => 'Waiting';

  @override
  String get radarRadioStart => 'Measure distance by radio';

  @override
  String get radarRadioStop => 'Stop radio distance measurement';

  @override
  String get radarSonarStart => 'Measure with acoustic sonar';

  @override
  String get radarSonarStop => 'Stop acoustic sonar';

  @override
  String get radarSonarMicrophoneRequired =>
      'Microphone permission is required for acoustic sonar.';

  @override
  String get radarSonarTooNoisy =>
      'The chirps could not be measured. Reduce noise, keep both phones uncovered, and try again.';

  @override
  String get radarSonarRemoteMicrophoneRequired =>
      'The other phone did not allow microphone access for sonar.';

  @override
  String get radarSonarSelfChirpMissing =>
      'This phone could not detect its own signal. Disconnect Bluetooth headphones, uncover the speaker, and try again.';

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
      'GPS and BLE disagree; direction is hidden until you repeat the measurement.';

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
  String get emergencyDeliveryTitle => 'Broadcast alert status';

  @override
  String get deliveryPending => 'Pending broadcast';

  @override
  String get deliveryRelayed => 'Broadcast to the mesh';

  @override
  String get deliveryAcknowledged => 'Confirmed by HearthBit';

  @override
  String get deliveryExpired => 'Expired without confirmation';

  @override
  String get deliveryAttemptsLabel => 'Attempts';

  @override
  String get deliveryConfirmationsLabel => 'Confirmations';

  @override
  String get deliveryLastAttemptLabel => 'Last attempt';

  @override
  String get deliveryExpiresLabel => 'Expires';

  @override
  String get deliveryNoHearthBitConfirmation =>
      'No confirmation from another HearthBit; a BitChat node may still have received it.';

  @override
  String get deliveryRetry => 'Retry alert';

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
  String get onboardingAllowMicrophone => 'ALLOW MICROPHONE FOR VOICE RESCUE';

  @override
  String get onboardingMicrophoneReady =>
      'Voice notes and acoustic rescue tools are ready.';

  @override
  String get onboardingMicrophoneRequired =>
      'Required for voice notes and acoustic rescue tools.';

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
  String meshHealthTrunks(int count) {
    return '$count active long-range trunks';
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
  String get gatewayTrustTitle => 'TLS certificate trust';

  @override
  String get gatewayTrustSystem => 'System';

  @override
  String get gatewayTrustSystemBody =>
      'Uses the certificate authorities trusted by your device. This is compatible with public services, but does not lock the gateway to one certificate.';

  @override
  String get gatewayTrustTofu => 'TOFU';

  @override
  String get gatewayTrustTofuBody =>
      'Trusts the first certificate seen for this endpoint and rejects later changes. Verify the first connection is not being intercepted.';

  @override
  String get gatewayTrustPinned => 'Pinned';

  @override
  String get gatewayTrustPinnedBody =>
      'Only the exact SHA-256 certificate fingerprint is accepted. Certificate rotation will block delivery until this value is updated.';

  @override
  String get gatewayFingerprint => 'Certificate SHA-256 fingerprint';

  @override
  String get gatewayFingerprintHint =>
      '64 hexadecimal characters; separators are allowed';

  @override
  String get gatewayFingerprintInvalid =>
      'Enter a valid 64-character SHA-256 certificate fingerprint.';

  @override
  String get gatewayResetTofu => 'Forget first certificate';

  @override
  String get gatewayResetTofuDone => 'The saved TOFU certificate was removed.';

  @override
  String get gatewayPrivacyScopeTitle => 'Data shared with the gateway';

  @override
  String get gatewaySensitiveContentConsent =>
      'Share message content and sender identity';

  @override
  String get gatewaySensitiveContentConsentBody =>
      'Includes the emergency description, display name and peer identifier. Off by default.';

  @override
  String get gatewayCoordinatesConsent => 'Share precise coordinates';

  @override
  String get gatewayCoordinatesConsentBody =>
      'Includes latitude and longitude when present. This consent is separate from message content.';

  @override
  String get gatewayPrivacyScopeWarning =>
      'The gateway sends selected data to an internet service outside the local mesh. Enable each category only with informed consent.';

  @override
  String get mapOpen => 'Open offline map';

  @override
  String get mapOpenRescue => 'OPEN RESCUE MAP';

  @override
  String get mapTitle => 'Offline rescue map';

  @override
  String get mapMyLocation => 'Center on my location';

  @override
  String get mapPassiveCacheInfo =>
      'This map automatically keeps tiles you view for offline reuse. Regional downloads require an authorized provider or your own server.';

  @override
  String get mapTilePolicyAction => 'OSM policy';

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
  String get mapTileBlockedHint =>
      'The provider temporarily blocked map tiles. Rescue markers remain available; use an authorized source or your own server for offline maps.';

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

  @override
  String get familyTitle => 'Family group';

  @override
  String get familySecurityBody =>
      'Members are verified in person with a signed QR. Names and old device IDs alone are never trusted.';

  @override
  String get familyCreateGroup => 'CREATE GROUP';

  @override
  String get familyRenameGroup => 'RENAME GROUP';

  @override
  String get familyGroupHint => 'E.g. My family';

  @override
  String get familyGroupLabel => 'Group';

  @override
  String get familyConfirmTitle => 'Confirm family member';

  @override
  String familyFingerprint(String fingerprint) {
    return 'Security code: $fingerprint';
  }

  @override
  String get familyConfirmBody =>
      'Compare this security code on both phones before saving.';

  @override
  String get familyAddMember => 'ADD MEMBER';

  @override
  String get familyRemoveTitle => 'Remove family member?';

  @override
  String familyRemoveBody(String nickname) {
    return '$nickname will no longer receive family highlighting or alerts.';
  }

  @override
  String get familyRemoveAction => 'REMOVE';

  @override
  String familySaveError(String error) {
    return 'Could not save the family group: $error';
  }

  @override
  String get familyMembersTitle => 'Verified members';

  @override
  String get familyScanAction => 'Scan member QR';

  @override
  String get familyCreateFirst => 'Create a group before adding members.';

  @override
  String get familyNoMembers => 'No verified members yet.';

  @override
  String get familyMyQr => 'My verification QR';

  @override
  String get familyMyQrBody =>
      'Show this QR in person. It contains your public signing key, never your private key.';

  @override
  String get familyQrUnavailable =>
      'Turn on the mesh to make your signed verification QR available.';

  @override
  String get familyScanTitle => 'Scan family QR';

  @override
  String get familyQrInvalid =>
      'This QR is invalid or its signature could not be verified.';

  @override
  String get familyScanHint =>
      'Scan the QR shown on your family member\'s phone.';

  @override
  String get familyAlertBadge => 'VERIFIED FAMILY';

  @override
  String get drillSafetyBanner => 'DRILL - does not request rescue';

  @override
  String get drillModeTitle => 'Practice drill';

  @override
  String get drillModeBody =>
      'Sends clearly marked practice messages only. It never sends SOS, shares rescue location, activates a beacon or uses the internet gateway.';

  @override
  String get drillConfirmTitle => 'Turn on practice drill?';

  @override
  String get drillConfirmBody =>
      'Rescue and survival modes will be turned off. Practice messages are public, but cannot become real emergency alerts.';

  @override
  String get drillEnableAction => 'TURN ON DRILL';

  @override
  String get drillHoldToSend => 'HOLD TO SEND DRILL';

  @override
  String get drillPracticeMessage => 'Practice request for help';

  @override
  String get drillReceivedTitle => 'Practice drill messages';

  @override
  String get drillNoneReceived => 'No practice drill messages received.';

  @override
  String get drillBadge => 'DRILL — NOT AN EMERGENCY';

  @override
  String get drillInvalidMessage =>
      'Unrecognized drill message; it was isolated from emergency systems.';

  @override
  String get drillCheckInTitle => 'Practice a status update';

  @override
  String get drillCheckInBody =>
      'These updates remain in the drill channel and are excluded from rescue alerts, maps and exports.';

  @override
  String get drillExitForRealTitle => 'Send a real SOS?';

  @override
  String get drillExitForRealBody =>
      'This will end the drill and activate a real rescue request with location sharing and repeated SOS alerts.';

  @override
  String get drillSendRealSos => 'END DRILL AND SEND SOS';

  @override
  String get drillDisableTitle => 'End drill mode?';

  @override
  String get drillDisableBody =>
      'Practice messages will stop and HearthBit will return to real emergency operation.';

  @override
  String get drillDisableAction => 'END DRILL';

  @override
  String get mapNoLocationTitle => 'No location available';

  @override
  String get mapNoLocationBody =>
      'Turn on location or wait for a peer to share a valid rescue position. The map will never use (0,0) as a fallback.';

  @override
  String get voiceMicrophoneRequired =>
      'Microphone permission is required to record a voice note.';

  @override
  String get actionOpenSettings => 'OPEN SETTINGS';

  @override
  String get opticalUnverifiedTitle => 'Unverified source';

  @override
  String get opticalUnverifiedBody =>
      'HearthBit cannot match this transfer to a previously authenticated identity. Confirm the fingerprint with the sender before accepting the file.';

  @override
  String get opticalLegacyWarning =>
      'This sender uses the legacy unsigned optical format.';

  @override
  String opticalFingerprint(String fingerprint) {
    return 'Fingerprint: $fingerprint';
  }

  @override
  String get opticalAcceptUnverified => 'ACCEPT UNVERIFIED';

  @override
  String get opticalSignatureInvalid =>
      'The optical manifest signature does not match the known sender. The file was rejected.';

  @override
  String get opticalVerifiedSource => 'Verified sender';

  @override
  String get gatewayPrivacyConfirm =>
      'This sends emergency messages, sender details and any included rescue location to the configured internet service. Enable it only with the consent of affected people.';

  @override
  String get gatewayEnableAction => 'ENABLE GATEWAY';

  @override
  String get gatewayTlsRequired =>
      'Required for emergency data; insecure connections are blocked.';

  @override
  String get locationExportConfirmTitle => 'Export rescue locations?';

  @override
  String get locationExportConfirmBody =>
      'The CSV can contain precise locations and emergency details. Share it only with trusted responders and protect the exported file.';

  @override
  String get locationExportConfirmAction => 'EXPORT LOCATIONS';

  @override
  String get lanGatewayConnected => 'LAN relay connected';

  @override
  String get lanGatewaySearching => 'LAN relay enabled · searching locally';

  @override
  String get lanGatewayDisabled => 'LAN relay disabled';

  @override
  String get lanGatewayConfigure => 'CONFIGURE LAN RELAY';

  @override
  String get lanGatewayDisable => 'DISABLE LAN RELAY';

  @override
  String get lanGatewayPrivacy =>
      'Opt-in only. The shared key must match your trusted HearthBit Raspberry Pi relay. Mesh frames are authenticated and encrypted on the local network.';

  @override
  String get lanGatewayPsk => '32-byte pairing key (base64)';

  @override
  String get lanGatewayGeneratePsk => 'GENERATE KEY';

  @override
  String get lanGatewayInvalidPsk => 'Enter a valid 32-byte base64 key.';

  @override
  String get emergencyContactsOpen => 'Emergency numbers and official links';

  @override
  String get emergencyContactsTitle => 'Emergency directory';

  @override
  String get emergencyContactsSafetyNotice =>
      'Call numbers may work without mobile data, but they still require cellular voice coverage. Official websites require internet.';

  @override
  String get emergencyContactsCountry => 'Country or territory';

  @override
  String emergencyContactsAutomatic(String country) {
    return 'Automatic ($country)';
  }

  @override
  String get emergencyContactsNumbers => 'Emergency numbers';

  @override
  String get emergencyContactsOrganizations => 'Official organizations';

  @override
  String get emergencyContactsCall => 'CALL';

  @override
  String get emergencyContactsWebsite => 'WEBSITE';

  @override
  String get emergencyContactsSources => 'Sources and review';

  @override
  String emergencyContactsReviewed(String date) {
    return 'Reviewed $date';
  }

  @override
  String get emergencyContactsFallback =>
      'This translation was unavailable, so the verified English directory is shown.';

  @override
  String get emergencyContactsLoadError =>
      'The offline emergency directory could not be loaded.';

  @override
  String get emergencyContactsOpenError =>
      'This phone could not open that number or link.';

  @override
  String get emergencyContactsRetry => 'RETRY';
}
