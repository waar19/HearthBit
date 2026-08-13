import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('ja'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'HearthBit'**
  String get appTitle;

  /// No description provided for @storageOpenError.
  ///
  /// In en, this message translates to:
  /// **'Could not open local storage:\n{error}'**
  String storageOpenError(String error);

  /// No description provided for @statusActiveLabel.
  ///
  /// In en, this message translates to:
  /// **'{nickname} · {count} nearby'**
  String statusActiveLabel(String nickname, int count);

  /// No description provided for @statusDegradedLabel.
  ///
  /// In en, this message translates to:
  /// **'{nickname} · receive-only (no BLE advertising)'**
  String statusDegradedLabel(String nickname);

  /// No description provided for @statusBannerYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get statusBannerYou;

  /// No description provided for @statusStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting mesh…'**
  String get statusStarting;

  /// No description provided for @statusError.
  ///
  /// In en, this message translates to:
  /// **'Mesh error'**
  String get statusError;

  /// No description provided for @statusStopped.
  ///
  /// In en, this message translates to:
  /// **'Mesh stopped'**
  String get statusStopped;

  /// No description provided for @actionStop.
  ///
  /// In en, this message translates to:
  /// **'STOP'**
  String get actionStop;

  /// No description provided for @actionRestart.
  ///
  /// In en, this message translates to:
  /// **'RESTART'**
  String get actionRestart;

  /// No description provided for @actionActivate.
  ///
  /// In en, this message translates to:
  /// **'TURN ON'**
  String get actionActivate;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'RETRY'**
  String get actionRetry;

  /// No description provided for @tooltipChangeName.
  ///
  /// In en, this message translates to:
  /// **'Change name'**
  String get tooltipChangeName;

  /// No description provided for @tooltipPanicWipe.
  ///
  /// In en, this message translates to:
  /// **'Emergency wipe'**
  String get tooltipPanicWipe;

  /// No description provided for @tabChannel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get tabChannel;

  /// No description provided for @tabNearby.
  ///
  /// In en, this message translates to:
  /// **'Nearby'**
  String get tabNearby;

  /// No description provided for @tabFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get tabFiles;

  /// No description provided for @tabSos.
  ///
  /// In en, this message translates to:
  /// **'SOS'**
  String get tabSos;

  /// No description provided for @emptyChatTitle.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get emptyChatTitle;

  /// No description provided for @emptyChatBody.
  ///
  /// In en, this message translates to:
  /// **'Turn on the mesh. Messages will hop between nearby phones without using the internet.'**
  String get emptyChatBody;

  /// No description provided for @composerPublicHint.
  ///
  /// In en, this message translates to:
  /// **'Message for everyone nearby'**
  String get composerPublicHint;

  /// No description provided for @composerPrivateHint.
  ///
  /// In en, this message translates to:
  /// **'Encrypted message'**
  String get composerPrivateHint;

  /// No description provided for @privateChatIntro.
  ///
  /// In en, this message translates to:
  /// **'The first message will start a Noise XX handshake.'**
  String get privateChatIntro;

  /// No description provided for @secureChatUnavailableHint.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the encrypted channel to become available.'**
  String get secureChatUnavailableHint;

  /// No description provided for @privateMessagePending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get privateMessagePending;

  /// No description provided for @privateMessageSendError.
  ///
  /// In en, this message translates to:
  /// **'Could not send the message: {error}'**
  String privateMessageSendError(String error);

  /// No description provided for @emptyPeersTitle.
  ///
  /// In en, this message translates to:
  /// **'No nearby devices'**
  String get emptyPeersTitle;

  /// No description provided for @emptyPeersBody.
  ///
  /// In en, this message translates to:
  /// **'Keep Bluetooth on and bring another phone with HearthBit or BitChat nearby.'**
  String get emptyPeersBody;

  /// No description provided for @peerSecure.
  ///
  /// In en, this message translates to:
  /// **'encrypted channel ready'**
  String get peerSecure;

  /// No description provided for @peerTapToEncrypt.
  ///
  /// In en, this message translates to:
  /// **'tap to encrypt'**
  String get peerTapToEncrypt;

  /// No description provided for @tooltipRadar.
  ///
  /// In en, this message translates to:
  /// **'Proximity radar'**
  String get tooltipRadar;

  /// No description provided for @tooltipSendFile.
  ///
  /// In en, this message translates to:
  /// **'Send a file'**
  String get tooltipSendFile;

  /// No description provided for @peerDoesNotSupportTransfers.
  ///
  /// In en, this message translates to:
  /// **'This person uses BitChat; files require HearthBit. Use QR transfer instead.'**
  String get peerDoesNotSupportTransfers;

  /// No description provided for @sosCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Send priority alert'**
  String get sosCardTitle;

  /// No description provided for @sosCardBody.
  ///
  /// In en, this message translates to:
  /// **'Your GPS location will be attached if possible. The alert is public and relayed across the mesh.'**
  String get sosCardBody;

  /// No description provided for @sosMedical.
  ///
  /// In en, this message translates to:
  /// **'I need medical help'**
  String get sosMedical;

  /// No description provided for @sosTrapped.
  ///
  /// In en, this message translates to:
  /// **'I am trapped'**
  String get sosTrapped;

  /// No description provided for @sosImOk.
  ///
  /// In en, this message translates to:
  /// **'I am OK'**
  String get sosImOk;

  /// No description provided for @sosDefaultMessage.
  ///
  /// In en, this message translates to:
  /// **'I need help'**
  String get sosDefaultMessage;

  /// No description provided for @sosReceivedTitle.
  ///
  /// In en, this message translates to:
  /// **'Received alerts'**
  String get sosReceivedTitle;

  /// No description provided for @sosNoneReceived.
  ///
  /// In en, this message translates to:
  /// **'No SOS alerts received.'**
  String get sosNoneReceived;

  /// No description provided for @actionTrack.
  ///
  /// In en, this message translates to:
  /// **'TRACK'**
  String get actionTrack;

  /// No description provided for @rescueModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Rescue mode'**
  String get rescueModeTitle;

  /// No description provided for @rescueModeActive.
  ///
  /// In en, this message translates to:
  /// **'Re-sending your SOS with location every {minutes} min.'**
  String rescueModeActive(int minutes);

  /// No description provided for @rescueModeLastPing.
  ///
  /// In en, this message translates to:
  /// **'Last sent: {time}.'**
  String rescueModeLastPing(String time);

  /// No description provided for @rescueModeInactive.
  ///
  /// In en, this message translates to:
  /// **'Re-sends your SOS with fresh GPS every {minutes} minutes, even with the screen off.'**
  String rescueModeInactive(int minutes);

  /// No description provided for @rescueModeNoBackgroundLocation.
  ///
  /// In en, this message translates to:
  /// **'Without always-on location, GPS only updates while the app is open.'**
  String get rescueModeNoBackgroundLocation;

  /// No description provided for @actionAllow.
  ///
  /// In en, this message translates to:
  /// **'ALLOW'**
  String get actionAllow;

  /// No description provided for @powerCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Battery & location'**
  String get powerCardTitle;

  /// No description provided for @powerCardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Settings that keep the mesh beating and help rescuers find you.'**
  String get powerCardSubtitle;

  /// No description provided for @powerBatteryOptimization.
  ///
  /// In en, this message translates to:
  /// **'Battery optimization disabled for HearthBit'**
  String get powerBatteryOptimization;

  /// No description provided for @actionDisable.
  ///
  /// In en, this message translates to:
  /// **'DISABLE'**
  String get actionDisable;

  /// No description provided for @powerLocationAndroid.
  ///
  /// In en, this message translates to:
  /// **'Location allowed \"all the time\"'**
  String get powerLocationAndroid;

  /// No description provided for @powerLocationIos.
  ///
  /// In en, this message translates to:
  /// **'Location allowed \"always\"'**
  String get powerLocationIos;

  /// No description provided for @powerSaverAndroid.
  ///
  /// In en, this message translates to:
  /// **'The system battery saver is on and may shut down the mesh'**
  String get powerSaverAndroid;

  /// No description provided for @powerSaverIos.
  ///
  /// In en, this message translates to:
  /// **'Low Power Mode is on and reduces background Bluetooth'**
  String get powerSaverIos;

  /// No description provided for @powerTipsTitle.
  ///
  /// In en, this message translates to:
  /// **'Battery saving tips'**
  String get powerTipsTitle;

  /// No description provided for @actionAdjust.
  ///
  /// In en, this message translates to:
  /// **'ADJUST'**
  String get actionAdjust;

  /// No description provided for @powerTipBrightness.
  ///
  /// In en, this message translates to:
  /// **'Lower the screen brightness to the minimum and shorten the lock timeout.'**
  String get powerTipBrightness;

  /// No description provided for @powerTipMobileData.
  ///
  /// In en, this message translates to:
  /// **'If there is no internet, turn off mobile data and 5G: the mesh does not use them and searching for signal drains the battery.'**
  String get powerTipMobileData;

  /// No description provided for @powerTipCloseApps.
  ///
  /// In en, this message translates to:
  /// **'Close apps you do not need; keep Bluetooth and location on.'**
  String get powerTipCloseApps;

  /// No description provided for @powerTipAndroidRecents.
  ///
  /// In en, this message translates to:
  /// **'Do not swipe HearthBit away from recents: the system would kill the mesh.'**
  String get powerTipAndroidRecents;

  /// No description provided for @powerTipAndroidVendor.
  ///
  /// In en, this message translates to:
  /// **'Some manufacturers (Xiaomi, Huawei, Samsung) have their own battery saver: exclude HearthBit there too.'**
  String get powerTipAndroidVendor;

  /// No description provided for @powerTipAndroidSync.
  ///
  /// In en, this message translates to:
  /// **'Turn off automatic account sync while the emergency lasts.'**
  String get powerTipAndroidSync;

  /// No description provided for @powerTipIosForceClose.
  ///
  /// In en, this message translates to:
  /// **'Do not force-quit HearthBit: iOS will not relaunch it on its own.'**
  String get powerTipIosForceClose;

  /// No description provided for @powerTipIosBackgroundRefresh.
  ///
  /// In en, this message translates to:
  /// **'Turn off Background App Refresh for other apps in Settings.'**
  String get powerTipIosBackgroundRefresh;

  /// No description provided for @powerTipIosLowPower.
  ///
  /// In en, this message translates to:
  /// **'Avoid Low Power Mode unless HearthBit is on screen: it reduces background Bluetooth.'**
  String get powerTipIosLowPower;

  /// No description provided for @powerTipShareBattery.
  ///
  /// In en, this message translates to:
  /// **'Share power banks between neighbors: a single phone that stays on keeps the whole block linked.'**
  String get powerTipShareBattery;

  /// No description provided for @nicknameDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get nicknameDialogTitle;

  /// No description provided for @nicknameDialogHint.
  ///
  /// In en, this message translates to:
  /// **'E.g. House 12 or Ana'**
  String get nicknameDialogHint;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get actionCancel;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get actionSave;

  /// No description provided for @wipeDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Erase all identity?'**
  String get wipeDialogTitle;

  /// No description provided for @wipeDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Keys, history and pending messages will be deleted. This cannot be undone.'**
  String get wipeDialogBody;

  /// No description provided for @actionWipe.
  ///
  /// In en, this message translates to:
  /// **'ERASE EVERYTHING'**
  String get actionWipe;

  /// No description provided for @photoProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Emergency profile'**
  String get photoProfileTitle;

  /// No description provided for @photoProfileBody.
  ///
  /// In en, this message translates to:
  /// **'The photo is {size} MiB. Compressing it speeds up delivery and saves battery across the mesh.'**
  String photoProfileBody(String size);

  /// No description provided for @actionSendOriginal.
  ///
  /// In en, this message translates to:
  /// **'SEND ORIGINAL'**
  String get actionSendOriginal;

  /// No description provided for @actionCompress.
  ///
  /// In en, this message translates to:
  /// **'COMPRESS'**
  String get actionCompress;

  /// No description provided for @offerFileError.
  ///
  /// In en, this message translates to:
  /// **'Could not offer the file: {error}'**
  String offerFileError(String error);

  /// No description provided for @terrPeerDoesNotSupportTransfers.
  ///
  /// In en, this message translates to:
  /// **'The recipient does not support HearthBit file transfers. Use QR transfer instead.'**
  String get terrPeerDoesNotSupportTransfers;

  /// No description provided for @terrOfferExpiredNoHbt.
  ///
  /// In en, this message translates to:
  /// **'The offer expired because the recipient does not support HearthBit file transfers.'**
  String get terrOfferExpiredNoHbt;

  /// No description provided for @sendByQr.
  ///
  /// In en, this message translates to:
  /// **'Send via QR'**
  String get sendByQr;

  /// No description provided for @receiveByQr.
  ///
  /// In en, this message translates to:
  /// **'Receive via QR'**
  String get receiveByQr;

  /// No description provided for @emptyTransfersTitle.
  ///
  /// In en, this message translates to:
  /// **'No transfers'**
  String get emptyTransfersTitle;

  /// No description provided for @emptyTransfersBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the paper clip next to a nearby device to offer it a file. The offer travels encrypted over the mesh and the content uses the fastest transport available. QR mode even works with no radios at all.'**
  String get emptyTransfersBody;

  /// No description provided for @transferFrom.
  ///
  /// In en, this message translates to:
  /// **'From {nickname}'**
  String transferFrom(String nickname);

  /// No description provided for @transferTo.
  ///
  /// In en, this message translates to:
  /// **'To {nickname}'**
  String transferTo(String nickname);

  /// No description provided for @transferProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total}'**
  String transferProgress(String done, String total);

  /// No description provided for @transferSavedAt.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String transferSavedAt(String path);

  /// No description provided for @stateOffered.
  ///
  /// In en, this message translates to:
  /// **'Offer'**
  String get stateOffered;

  /// No description provided for @stateConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get stateConnecting;

  /// No description provided for @stateTransferring.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get stateTransferring;

  /// No description provided for @stateCompleted.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get stateCompleted;

  /// No description provided for @stateRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get stateRejected;

  /// No description provided for @stateCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get stateCancelled;

  /// No description provided for @stateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get stateFailed;

  /// No description provided for @transportBle.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get transportBle;

  /// No description provided for @transportLan.
  ///
  /// In en, this message translates to:
  /// **'Local Wi-Fi'**
  String get transportLan;

  /// No description provided for @transportNearby.
  ///
  /// In en, this message translates to:
  /// **'Nearby'**
  String get transportNearby;

  /// No description provided for @transportWifiAware.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi Aware'**
  String get transportWifiAware;

  /// No description provided for @transportOptical.
  ///
  /// In en, this message translates to:
  /// **'Optical QR'**
  String get transportOptical;

  /// No description provided for @actionReject.
  ///
  /// In en, this message translates to:
  /// **'REJECT'**
  String get actionReject;

  /// No description provided for @actionAccept.
  ///
  /// In en, this message translates to:
  /// **'ACCEPT'**
  String get actionAccept;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'REMOVE'**
  String get actionDelete;

  /// No description provided for @opticalFileEmpty.
  ///
  /// In en, this message translates to:
  /// **'The file is empty'**
  String get opticalFileEmpty;

  /// No description provided for @opticalSendStats.
  ///
  /// In en, this message translates to:
  /// **'{fileName} · {chunks} chunks · symbol {symbol}'**
  String opticalSendStats(String fileName, int chunks, int symbol);

  /// No description provided for @opticalConfirmed.
  ///
  /// In en, this message translates to:
  /// **'The receiver confirmed reception over BLE'**
  String get opticalConfirmed;

  /// No description provided for @opticalSpeedLabel.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get opticalSpeedLabel;

  /// No description provided for @opticalFps.
  ///
  /// In en, this message translates to:
  /// **'{fps} QR/s'**
  String opticalFps(int fps);

  /// No description provided for @densityCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get densityCompact;

  /// No description provided for @densityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get densityMedium;

  /// No description provided for @densityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get densityHigh;

  /// No description provided for @opticalSendHint.
  ///
  /// In en, this message translates to:
  /// **'If the receiving camera misses many frames, lower the speed or density. The code is rateless: repeating symbols never corrupts the transfer.'**
  String get opticalSendHint;

  /// No description provided for @opticalShaFailed.
  ///
  /// In en, this message translates to:
  /// **'SHA-256 verification failed; restart the send'**
  String get opticalShaFailed;

  /// No description provided for @opticalSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'{fileName} verified and saved'**
  String opticalSavedTitle(String fileName);

  /// No description provided for @genericFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get genericFile;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'DONE'**
  String get actionDone;

  /// No description provided for @opticalScanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the sender\'s QR. The header repeats every few frames.'**
  String get opticalScanHint;

  /// No description provided for @opticalReceiveStats.
  ///
  /// In en, this message translates to:
  /// **'{fileName} · {decoded} of {total} chunks · {symbols} symbols'**
  String opticalReceiveStats(
    String fileName,
    int decoded,
    int total,
    int symbols,
  );

  /// No description provided for @radarTitle.
  ///
  /// In en, this message translates to:
  /// **'Radar · {nickname}'**
  String radarTitle(String nickname);

  /// No description provided for @beaconRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'{nickname} asks you to become visible'**
  String beaconRequestTitle(String nickname);

  /// No description provided for @beaconRequestBody.
  ///
  /// In en, this message translates to:
  /// **'Accept to use the flashlight, alarm and vibration for up to 5 minutes. Nothing turns on without your consent.'**
  String get beaconRequestBody;

  /// No description provided for @beaconMakeVisible.
  ///
  /// In en, this message translates to:
  /// **'MAKE ME VISIBLE'**
  String get beaconMakeVisible;

  /// No description provided for @beaconStopVisible.
  ///
  /// In en, this message translates to:
  /// **'STOP PHYSICAL BEACON'**
  String get beaconStopVisible;

  /// No description provided for @beaconRequestRemote.
  ///
  /// In en, this message translates to:
  /// **'REQUEST BEACON'**
  String get beaconRequestRemote;

  /// No description provided for @beaconStopRemote.
  ///
  /// In en, this message translates to:
  /// **'STOP BEACON'**
  String get beaconStopRemote;

  /// No description provided for @radarSignalLost.
  ///
  /// In en, this message translates to:
  /// **'SIGNAL LOST'**
  String get radarSignalLost;

  /// No description provided for @radarSignalLostHint.
  ///
  /// In en, this message translates to:
  /// **'Walk back slowly along your path until the signal returns.'**
  String get radarSignalLostHint;

  /// No description provided for @radarSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching for signal…'**
  String get radarSearching;

  /// No description provided for @radarSearchingHint.
  ///
  /// In en, this message translates to:
  /// **'Walk slowly in a wide circle. The radar picks up the direct Bluetooth signal (tens of meters).'**
  String get radarSearchingHint;

  /// No description provided for @proximityVeryClose.
  ///
  /// In en, this message translates to:
  /// **'VERY CLOSE'**
  String get proximityVeryClose;

  /// No description provided for @proximityClose.
  ///
  /// In en, this message translates to:
  /// **'CLOSE'**
  String get proximityClose;

  /// No description provided for @proximityInRange.
  ///
  /// In en, this message translates to:
  /// **'IN RANGE'**
  String get proximityInRange;

  /// No description provided for @proximityFar.
  ///
  /// In en, this message translates to:
  /// **'FAR'**
  String get proximityFar;

  /// No description provided for @trendApproaching.
  ///
  /// In en, this message translates to:
  /// **'You are getting closer'**
  String get trendApproaching;

  /// No description provided for @trendReceding.
  ///
  /// In en, this message translates to:
  /// **'The signal is getting weaker'**
  String get trendReceding;

  /// No description provided for @trendSteady.
  ///
  /// In en, this message translates to:
  /// **'Signal steady'**
  String get trendSteady;

  /// No description provided for @trendUnknown.
  ///
  /// In en, this message translates to:
  /// **'Measuring signal…'**
  String get trendUnknown;

  /// No description provided for @distanceVeryNear.
  ///
  /// In en, this message translates to:
  /// **'less than 2 m away'**
  String get distanceVeryNear;

  /// No description provided for @distanceApprox.
  ///
  /// In en, this message translates to:
  /// **'≈ {meters} m'**
  String distanceApprox(int meters);

  /// No description provided for @distanceFar.
  ///
  /// In en, this message translates to:
  /// **'more than 15 m away'**
  String get distanceFar;

  /// No description provided for @radarDbm.
  ///
  /// In en, this message translates to:
  /// **'Signal {dbm} dBm'**
  String radarDbm(int dbm);

  /// No description provided for @radarGpsDistance.
  ///
  /// In en, this message translates to:
  /// **'Last reported GPS: {distance} away in a straight line'**
  String radarGpsDistance(String distance);

  /// No description provided for @errorPermissions.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth and notification permissions are required to build the mesh.'**
  String get errorPermissions;

  /// No description provided for @errorLocationOff.
  ///
  /// In en, this message translates to:
  /// **'Turn on system location for rescue mode'**
  String get errorLocationOff;

  /// No description provided for @errorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get errorUnknown;

  /// No description provided for @tooltipSupport.
  ///
  /// In en, this message translates to:
  /// **'Support HearthBit'**
  String get tooltipSupport;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About HearthBit'**
  String get aboutTitle;

  /// No description provided for @aboutBody.
  ///
  /// In en, this message translates to:
  /// **'HearthBit is an open-source emergency communication project. Your support helps fund device testing and resilient relay hardware.'**
  String get aboutBody;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// No description provided for @aboutSourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get aboutSourceCode;

  /// No description provided for @supportButton.
  ///
  /// In en, this message translates to:
  /// **'Buy me a coffee'**
  String get supportButton;

  /// No description provided for @shareInviteButton.
  ///
  /// In en, this message translates to:
  /// **'Share HearthBit'**
  String get shareInviteButton;

  /// No description provided for @shareInviteMessage.
  ///
  /// In en, this message translates to:
  /// **'Join HearthBit, an open-source emergency mesh that works without internet. Download it or contribute at {url}'**
  String shareInviteMessage(String url);

  /// No description provided for @tooltipShare.
  ///
  /// In en, this message translates to:
  /// **'Invite people to HearthBit'**
  String get tooltipShare;

  /// No description provided for @shareInviteError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the sharing options'**
  String get shareInviteError;

  /// No description provided for @openLinkError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the link'**
  String get openLinkError;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @terrInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Interrupted when the app closed'**
  String get terrInterrupted;

  /// No description provided for @terrFileSize.
  ///
  /// In en, this message translates to:
  /// **'The file must be between 1 byte and 512 MiB'**
  String get terrFileSize;

  /// No description provided for @terrOfferExpired.
  ///
  /// In en, this message translates to:
  /// **'The offer expired without an answer'**
  String get terrOfferExpired;

  /// No description provided for @terrNoTransport.
  ///
  /// In en, this message translates to:
  /// **'No transport compatible with the sender'**
  String get terrNoTransport;

  /// No description provided for @terrInvalidSignature.
  ///
  /// In en, this message translates to:
  /// **'An offer with an invalid signature was discarded'**
  String get terrInvalidSignature;

  /// No description provided for @terrUnsupportedTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport not supported in this version'**
  String get terrUnsupportedTransport;

  /// No description provided for @terrLanIncomplete.
  ///
  /// In en, this message translates to:
  /// **'The LAN connection ended incomplete'**
  String get terrLanIncomplete;

  /// No description provided for @terrLanFailed.
  ///
  /// In en, this message translates to:
  /// **'LAN failed: {error}'**
  String terrLanFailed(String error);

  /// No description provided for @terrBleChunk.
  ///
  /// In en, this message translates to:
  /// **'Invalid BLE chunk: {error}'**
  String terrBleChunk(String error);

  /// No description provided for @terrTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport error'**
  String get terrTransport;

  /// No description provided for @terrNearbyStart.
  ///
  /// In en, this message translates to:
  /// **'Could not start Nearby: {error}'**
  String terrNearbyStart(String error);

  /// No description provided for @terrWifiAwareStart.
  ///
  /// In en, this message translates to:
  /// **'Could not start Wi-Fi Aware: {error}'**
  String terrWifiAwareStart(String error);

  /// No description provided for @terrBleInterrupted.
  ///
  /// In en, this message translates to:
  /// **'BLE send interrupted: {error}'**
  String terrBleInterrupted(String error);

  /// No description provided for @terrReceiverSilent.
  ///
  /// In en, this message translates to:
  /// **'The receiver stopped acknowledging chunks'**
  String get terrReceiverSilent;

  /// No description provided for @terrNearbyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Nearby unavailable: {error}'**
  String terrNearbyUnavailable(String error);

  /// No description provided for @terrWifiAwareUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi Aware unavailable: {error}'**
  String terrWifiAwareUnavailable(String error);

  /// No description provided for @terrContainerIncomplete.
  ///
  /// In en, this message translates to:
  /// **'The container arrived incomplete'**
  String get terrContainerIncomplete;

  /// No description provided for @terrContainerDecrypt.
  ///
  /// In en, this message translates to:
  /// **'Could not decrypt the container: {error}'**
  String terrContainerDecrypt(String error);

  /// No description provided for @terrShaMismatch.
  ///
  /// In en, this message translates to:
  /// **'SHA-256 verification failed; file discarded'**
  String get terrShaMismatch;

  /// No description provided for @terrNoMeshSession.
  ///
  /// In en, this message translates to:
  /// **'No mesh connection with the peer: {error}'**
  String terrNoMeshSession(String error);

  /// No description provided for @terrTransportTimeout.
  ///
  /// In en, this message translates to:
  /// **'The transport did not respond'**
  String get terrTransportTimeout;

  /// No description provided for @recentChatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent conversations'**
  String get recentChatsTitle;

  /// No description provided for @nearbyPeopleTitle.
  ///
  /// In en, this message translates to:
  /// **'Nearby people'**
  String get nearbyPeopleTitle;

  /// No description provided for @peerOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get peerOnline;

  /// No description provided for @peerOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get peerOffline;

  /// No description provided for @offlineChatHint.
  ///
  /// In en, this message translates to:
  /// **'This person is offline. You can read the history and send when they reconnect.'**
  String get offlineChatHint;

  /// No description provided for @radarConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Radar privacy'**
  String get radarConsentTitle;

  /// No description provided for @radarConsentOff.
  ///
  /// In en, this message translates to:
  /// **'Radar location is blocked by default'**
  String get radarConsentOff;

  /// No description provided for @radarConsentActive.
  ///
  /// In en, this message translates to:
  /// **'Others may use radar for {minutes} more min'**
  String radarConsentActive(int minutes);

  /// No description provided for @radarConsentAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow radar for 15 minutes'**
  String get radarConsentAllow;

  /// No description provided for @radarConsentRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke now'**
  String get radarConsentRevoke;

  /// No description provided for @radarPrivacyWarning.
  ///
  /// In en, this message translates to:
  /// **'This limits HearthBit only. Other software may still measure Bluetooth signals emitted by your phone.'**
  String get radarPrivacyWarning;

  /// No description provided for @rescueRadarWarning.
  ///
  /// In en, this message translates to:
  /// **'Rescue mode shares fresh SOS locations and allows nearby HearthBit rescuers to measure your signal while SOS remains active.'**
  String get rescueRadarWarning;

  /// No description provided for @radarConsentRequired.
  ///
  /// In en, this message translates to:
  /// **'Requires this person\'s consent'**
  String get radarConsentRequired;

  /// No description provided for @radarConsentSos.
  ///
  /// In en, this message translates to:
  /// **'Available because of a recent SOS'**
  String get radarConsentSos;

  /// No description provided for @radarConsentTemporary.
  ///
  /// In en, this message translates to:
  /// **'Temporarily authorized by this person'**
  String get radarConsentTemporary;

  /// No description provided for @radarConsentExpires.
  ///
  /// In en, this message translates to:
  /// **'Permission expires at {time}'**
  String radarConsentExpires(String time);

  /// No description provided for @radarNotDirection.
  ///
  /// In en, this message translates to:
  /// **'The point shows proximity, not direction. Move slowly and compare whether the signal gets stronger.'**
  String get radarNotDirection;

  /// No description provided for @radarPermissionExpired.
  ///
  /// In en, this message translates to:
  /// **'Radar permission expired or was revoked.'**
  String get radarPermissionExpired;

  /// No description provided for @radarTentativeSignal.
  ///
  /// In en, this message translates to:
  /// **'Tentative signal: verifying that this iPhone is the selected person.'**
  String get radarTentativeSignal;

  /// No description provided for @radarSweepStart.
  ///
  /// In en, this message translates to:
  /// **'FIND DIRECTION'**
  String get radarSweepStart;

  /// No description provided for @radarSweepRestart.
  ///
  /// In en, this message translates to:
  /// **'REPEAT SWEEP'**
  String get radarSweepRestart;

  /// No description provided for @radarSweepHoldTitle.
  ///
  /// In en, this message translates to:
  /// **'How to hold the phone'**
  String get radarSweepHoldTitle;

  /// No description provided for @radarSweepInstruction.
  ///
  /// In en, this message translates to:
  /// **'Keep it flat in front of your chest, screen up and top edge pointing forward. Slowly turn your whole body.'**
  String get radarSweepInstruction;

  /// No description provided for @radarSweepProgress.
  ///
  /// In en, this message translates to:
  /// **'Sweep progress: {percent}%'**
  String radarSweepProgress(int percent);

  /// No description provided for @radarSweepResult.
  ///
  /// In en, this message translates to:
  /// **'Probable signal sector: {heading}° (±30°)'**
  String radarSweepResult(int heading);

  /// No description provided for @radarSweepConfidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence: {percent}%'**
  String radarSweepConfidence(int percent);

  /// No description provided for @radarSweepInconclusive.
  ///
  /// In en, this message translates to:
  /// **'No reliable sector was found. Turn more slowly and move away from metal or electronic equipment.'**
  String get radarSweepInconclusive;

  /// No description provided for @radarSweepEstimateWarning.
  ///
  /// In en, this message translates to:
  /// **'BLE can only estimate a broad sector, not an exact direction. Confirm it by moving and repeating the sweep.'**
  String get radarSweepEstimateWarning;

  /// No description provided for @radarCompassUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This phone has no usable compass sensor. Proximity radar remains available.'**
  String get radarCompassUnavailable;

  /// No description provided for @radarCompassCalibration.
  ///
  /// In en, this message translates to:
  /// **'Move the phone away from metal or electronics and trace a figure eight to calibrate the compass.'**
  String get radarCompassCalibration;

  /// No description provided for @radarDirectionGps.
  ///
  /// In en, this message translates to:
  /// **'GPS-guided bearing · follow the blue diamond'**
  String get radarDirectionGps;

  /// No description provided for @radarDirectionBle.
  ///
  /// In en, this message translates to:
  /// **'Sector estimated by BLE sweep'**
  String get radarDirectionBle;

  /// No description provided for @radarDirectionVeryClose.
  ///
  /// In en, this message translates to:
  /// **'You are very close: the BLE sector is hidden because it is no longer reliable. Turn and follow the vibration.'**
  String get radarDirectionVeryClose;

  /// No description provided for @radarSourcesDisagree.
  ///
  /// In en, this message translates to:
  /// **'GPS and BLE disagree; the GPS bearing takes priority.'**
  String get radarSourcesDisagree;

  /// No description provided for @dateToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dateToday;

  /// No description provided for @dateYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get dateYesterday;

  /// No description provided for @genericPresenceSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Other Bluetooth signals'**
  String get genericPresenceSectionTitle;

  /// No description provided for @genericPresenceNoChat.
  ///
  /// In en, this message translates to:
  /// **'Presence detected, no chat'**
  String get genericPresenceNoChat;

  /// No description provided for @genericPresenceSignal.
  ///
  /// In en, this message translates to:
  /// **'Generic Bluetooth signal · {rssi} dBm'**
  String genericPresenceSignal(int rssi);

  /// No description provided for @genericPresenceSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} nearby Bluetooth signals · strongest {rssi} dBm'**
  String genericPresenceSummary(int count, int rssi);

  /// No description provided for @genericPresenceExpand.
  ///
  /// In en, this message translates to:
  /// **'Show signal details'**
  String get genericPresenceExpand;

  /// No description provided for @nodeModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Node mode'**
  String get nodeModeTooltip;

  /// No description provided for @nodeModeTitle.
  ///
  /// In en, this message translates to:
  /// **'How should this phone participate?'**
  String get nodeModeTitle;

  /// No description provided for @nodeModeRelayTitle.
  ///
  /// In en, this message translates to:
  /// **'Mesh relay'**
  String get nodeModeRelayTitle;

  /// No description provided for @nodeModeRelayBody.
  ///
  /// In en, this message translates to:
  /// **'Chat normally and relay messages for nearby people.'**
  String get nodeModeRelayBody;

  /// No description provided for @nodeModeBeaconTitle.
  ///
  /// In en, this message translates to:
  /// **'Presence only'**
  String get nodeModeBeaconTitle;

  /// No description provided for @nodeModeBeaconBody.
  ///
  /// In en, this message translates to:
  /// **'Save power and advertise your presence without chat or message relay. On Android, data links are also disabled.'**
  String get nodeModeBeaconBody;

  /// No description provided for @tabEmergency.
  ///
  /// In en, this message translates to:
  /// **'Emergency'**
  String get tabEmergency;

  /// No description provided for @emergencyHeadline.
  ///
  /// In en, this message translates to:
  /// **'Emergency mode'**
  String get emergencyHeadline;

  /// No description provided for @emergencyInstructions.
  ///
  /// In en, this message translates to:
  /// **'Press and hold SOS for 2 seconds. HearthBit will turn on the mesh, share your location and repeat the alert.'**
  String get emergencyInstructions;

  /// No description provided for @emergencyHoldSos.
  ///
  /// In en, this message translates to:
  /// **'HOLD FOR SOS'**
  String get emergencyHoldSos;

  /// No description provided for @emergencySosActive.
  ///
  /// In en, this message translates to:
  /// **'SOS ACTIVE'**
  String get emergencySosActive;

  /// No description provided for @emergencyStopRescue.
  ///
  /// In en, this message translates to:
  /// **'Stop rescue mode'**
  String get emergencyStopRescue;

  /// No description provided for @errorEmergencyMeshUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The Bluetooth mesh could not be activated. Check Bluetooth permissions and try again.'**
  String get errorEmergencyMeshUnavailable;

  /// No description provided for @checkInTitle.
  ///
  /// In en, this message translates to:
  /// **'Tell people your status'**
  String get checkInTitle;

  /// No description provided for @checkInBody.
  ///
  /// In en, this message translates to:
  /// **'A short update is relayed through the mesh with your time and location when available.'**
  String get checkInBody;

  /// No description provided for @checkInOk.
  ///
  /// In en, this message translates to:
  /// **'I am OK'**
  String get checkInOk;

  /// No description provided for @checkInNeedsHelp.
  ///
  /// In en, this message translates to:
  /// **'I need help'**
  String get checkInNeedsHelp;

  /// No description provided for @checkInInjured.
  ///
  /// In en, this message translates to:
  /// **'I am injured'**
  String get checkInInjured;

  /// No description provided for @checkInRecentTitle.
  ///
  /// In en, this message translates to:
  /// **'Latest check-ins'**
  String get checkInRecentTitle;

  /// No description provided for @checkInNone.
  ///
  /// In en, this message translates to:
  /// **'No one has shared a status yet.'**
  String get checkInNone;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Communication when networks fail'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'HearthBit relays emergency messages between nearby phones using Bluetooth, without mobile service or internet.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingMeshTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep the emergency mesh alive'**
  String get onboardingMeshTitle;

  /// No description provided for @onboardingMeshBody.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth, nearby-device and notification permissions let your phone find people and relay their messages.'**
  String get onboardingMeshBody;

  /// No description provided for @onboardingReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Prepare before an emergency'**
  String get onboardingReadyTitle;

  /// No description provided for @onboardingReadyBody.
  ///
  /// In en, this message translates to:
  /// **'Allow background location and exempt HearthBit from battery restrictions so SOS positions can stay current.'**
  String get onboardingReadyBody;

  /// No description provided for @onboardingNicknameLabel.
  ///
  /// In en, this message translates to:
  /// **'Your visible name (optional)'**
  String get onboardingNicknameLabel;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'NEXT'**
  String get onboardingNext;

  /// No description provided for @onboardingBack.
  ///
  /// In en, this message translates to:
  /// **'BACK'**
  String get onboardingBack;

  /// No description provided for @onboardingAllowMesh.
  ///
  /// In en, this message translates to:
  /// **'ALLOW AND TURN ON MESH'**
  String get onboardingAllowMesh;

  /// No description provided for @onboardingAllowLocation.
  ///
  /// In en, this message translates to:
  /// **'ALLOW EMERGENCY LOCATION'**
  String get onboardingAllowLocation;

  /// No description provided for @onboardingFinish.
  ///
  /// In en, this message translates to:
  /// **'FINISH SETUP'**
  String get onboardingFinish;

  /// No description provided for @appearanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Display & accessibility'**
  String get appearanceTitle;

  /// No description provided for @appearanceAmoled.
  ///
  /// In en, this message translates to:
  /// **'AMOLED black theme'**
  String get appearanceAmoled;

  /// No description provided for @appearanceAmoledBody.
  ///
  /// In en, this message translates to:
  /// **'Uses a true black background to save power on OLED screens.'**
  String get appearanceAmoledBody;

  /// No description provided for @appearanceHighContrast.
  ///
  /// In en, this message translates to:
  /// **'High contrast and larger controls'**
  String get appearanceHighContrast;

  /// No description provided for @appearanceHighContrastBody.
  ///
  /// In en, this message translates to:
  /// **'Improves readability and enlarges critical actions.'**
  String get appearanceHighContrastBody;

  /// No description provided for @tooltipAppearance.
  ///
  /// In en, this message translates to:
  /// **'Display and accessibility'**
  String get tooltipAppearance;

  /// No description provided for @meshHealthTitle.
  ///
  /// In en, this message translates to:
  /// **'Mesh health'**
  String get meshHealthTitle;

  /// No description provided for @meshHealthDirect.
  ///
  /// In en, this message translates to:
  /// **'{count} direct peers'**
  String meshHealthDirect(int count);

  /// No description provided for @meshHealthRelays.
  ///
  /// In en, this message translates to:
  /// **'{count} phones relaying messages'**
  String meshHealthRelays(int count);

  /// No description provided for @meshHealthAnchors.
  ///
  /// In en, this message translates to:
  /// **'{count} message storage points'**
  String meshHealthAnchors(int count);

  /// No description provided for @meshHealthSignals.
  ///
  /// In en, this message translates to:
  /// **'{count} other Bluetooth signals'**
  String meshHealthSignals(int count);

  /// No description provided for @meshHealthAnchorReady.
  ///
  /// In en, this message translates to:
  /// **'A message storage point is nearby.'**
  String get meshHealthAnchorReady;

  /// No description provided for @meshHealthNoAnchor.
  ///
  /// In en, this message translates to:
  /// **'No nearby message storage point is visible.'**
  String get meshHealthNoAnchor;

  /// No description provided for @adaptivePowerTitle.
  ///
  /// In en, this message translates to:
  /// **'Adaptive battery mode'**
  String get adaptivePowerTitle;

  /// No description provided for @adaptivePowerNormal.
  ///
  /// In en, this message translates to:
  /// **'Full mesh performance'**
  String get adaptivePowerNormal;

  /// No description provided for @adaptivePowerSaving.
  ///
  /// In en, this message translates to:
  /// **'Battery saving: scanning in short bursts'**
  String get adaptivePowerSaving;

  /// No description provided for @powerProfilePerformance.
  ///
  /// In en, this message translates to:
  /// **'Performance: fast discovery'**
  String get powerProfilePerformance;

  /// No description provided for @powerProfileBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced: full mesh coverage'**
  String get powerProfileBalanced;

  /// No description provided for @powerProfilePowerSaver.
  ///
  /// In en, this message translates to:
  /// **'Power saving: scanning in intervals'**
  String get powerProfilePowerSaver;

  /// No description provided for @powerProfileCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical: minimum connections and scanning'**
  String get powerProfileCritical;

  /// No description provided for @powerProfileSurvival.
  ///
  /// In en, this message translates to:
  /// **'Survival: SOS beacon only'**
  String get powerProfileSurvival;

  /// No description provided for @survivalModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Survival mode'**
  String get survivalModeTitle;

  /// No description provided for @survivalModeBody.
  ///
  /// In en, this message translates to:
  /// **'Keep only an SOS presence beacon active for maximum battery life. Chat and relay stop.'**
  String get survivalModeBody;

  /// No description provided for @survivalModeEnable.
  ///
  /// In en, this message translates to:
  /// **'ENABLE SURVIVAL MODE'**
  String get survivalModeEnable;

  /// No description provided for @survivalModeDisable.
  ///
  /// In en, this message translates to:
  /// **'RETURN TO MESH MODE'**
  String get survivalModeDisable;

  /// No description provided for @survivalModeSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Battery is critical. Enable survival mode to remain detectable longer.'**
  String get survivalModeSuggestion;

  /// No description provided for @gatewayTitle.
  ///
  /// In en, this message translates to:
  /// **'Emergency internet gateway'**
  String get gatewayTitle;

  /// No description provided for @gatewayBody.
  ///
  /// In en, this message translates to:
  /// **'When internet returns, this phone can publish queued SOS and check-ins through a gateway you configure.'**
  String get gatewayBody;

  /// No description provided for @gatewayOptIn.
  ///
  /// In en, this message translates to:
  /// **'Allow this phone to offer internet exit'**
  String get gatewayOptIn;

  /// No description provided for @gatewayAvailable.
  ///
  /// In en, this message translates to:
  /// **'Internet transport detected'**
  String get gatewayAvailable;

  /// No description provided for @gatewayUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No internet transport detected'**
  String get gatewayUnavailable;

  /// No description provided for @gatewayPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Only SOS and check-ins are eligible. Nothing is uploaded until you configure and enable a trusted gateway.'**
  String get gatewayPrivacy;

  /// No description provided for @gatewayPending.
  ///
  /// In en, this message translates to:
  /// **'{count} emergency items pending'**
  String gatewayPending(int count);

  /// No description provided for @gatewayConfigure.
  ///
  /// In en, this message translates to:
  /// **'Configure trusted gateway'**
  String get gatewayConfigure;

  /// No description provided for @gatewayKindMatrix.
  ///
  /// In en, this message translates to:
  /// **'Matrix'**
  String get gatewayKindMatrix;

  /// No description provided for @gatewayKindMqtt.
  ///
  /// In en, this message translates to:
  /// **'MQTT'**
  String get gatewayKindMqtt;

  /// No description provided for @gatewayHomeserver.
  ///
  /// In en, this message translates to:
  /// **'Matrix homeserver URL'**
  String get gatewayHomeserver;

  /// No description provided for @gatewayBroker.
  ///
  /// In en, this message translates to:
  /// **'MQTT broker host'**
  String get gatewayBroker;

  /// No description provided for @gatewayRoom.
  ///
  /// In en, this message translates to:
  /// **'Matrix room ID'**
  String get gatewayRoom;

  /// No description provided for @gatewayTopic.
  ///
  /// In en, this message translates to:
  /// **'MQTT topic'**
  String get gatewayTopic;

  /// No description provided for @gatewayUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get gatewayUsername;

  /// No description provided for @gatewayAccessToken.
  ///
  /// In en, this message translates to:
  /// **'Access token'**
  String get gatewayAccessToken;

  /// No description provided for @gatewayPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get gatewayPassword;

  /// No description provided for @gatewayPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get gatewayPort;

  /// No description provided for @gatewayTls.
  ///
  /// In en, this message translates to:
  /// **'Use encrypted TLS connection'**
  String get gatewayTls;

  /// No description provided for @mapOpen.
  ///
  /// In en, this message translates to:
  /// **'Open offline map'**
  String get mapOpen;

  /// No description provided for @mapOpenRescue.
  ///
  /// In en, this message translates to:
  /// **'OPEN RESCUE MAP'**
  String get mapOpenRescue;

  /// No description provided for @mapTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline rescue map'**
  String get mapTitle;

  /// No description provided for @mapMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Center on my location'**
  String get mapMyLocation;

  /// No description provided for @mapDownloadVisible.
  ///
  /// In en, this message translates to:
  /// **'Download visible area'**
  String get mapDownloadVisible;

  /// No description provided for @mapDownloadComplete.
  ///
  /// In en, this message translates to:
  /// **'{count} map tiles saved for offline use.'**
  String mapDownloadComplete(int count);

  /// No description provided for @mapDownloadTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This area is too large. Zoom in; the safe limit is {maximum} tiles.'**
  String mapDownloadTooLarge(int maximum);

  /// No description provided for @mapDownloadError.
  ///
  /// In en, this message translates to:
  /// **'Could not download the map area: {error}'**
  String mapDownloadError(String error);

  /// No description provided for @mapDownloading.
  ///
  /// In en, this message translates to:
  /// **'Saving map tiles: {completed}/{total}'**
  String mapDownloading(int completed, int total);

  /// No description provided for @mapCacheError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the offline map cache: {error}'**
  String mapCacheError(String error);

  /// No description provided for @mapYouAreHere.
  ///
  /// In en, this message translates to:
  /// **'You are here'**
  String get mapYouAreHere;

  /// No description provided for @mapOfflineHint.
  ///
  /// In en, this message translates to:
  /// **'Network unavailable. Already saved map tiles remain visible.'**
  String get mapOfflineHint;

  /// No description provided for @mapShowOnMap.
  ///
  /// In en, this message translates to:
  /// **'Show on map'**
  String get mapShowOnMap;

  /// No description provided for @rescueListTitle.
  ///
  /// In en, this message translates to:
  /// **'Rescue queue · nearest first'**
  String get rescueListTitle;

  /// No description provided for @rescueListEmpty.
  ///
  /// In en, this message translates to:
  /// **'No SOS alerts or check-ins with rescue data.'**
  String get rescueListEmpty;

  /// No description provided for @rescueExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Share rescue CSV'**
  String get rescueExportCsv;

  /// No description provided for @rescueExportSubject.
  ///
  /// In en, this message translates to:
  /// **'HearthBit rescue queue'**
  String get rescueExportSubject;

  /// No description provided for @rescueExportError.
  ///
  /// In en, this message translates to:
  /// **'Could not share the rescue list: {error}'**
  String rescueExportError(String error);

  /// No description provided for @rescueDistanceUnknown.
  ///
  /// In en, this message translates to:
  /// **'distance unknown'**
  String get rescueDistanceUnknown;

  /// No description provided for @rescueDistanceMeters.
  ///
  /// In en, this message translates to:
  /// **'{meters} m away'**
  String rescueDistanceMeters(int meters);

  /// No description provided for @rescueDistanceKilometers.
  ///
  /// In en, this message translates to:
  /// **'{kilometers} km away'**
  String rescueDistanceKilometers(String kilometers);

  /// No description provided for @voiceRecord.
  ///
  /// In en, this message translates to:
  /// **'Record voice note'**
  String get voiceRecord;

  /// No description provided for @voiceStop.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get voiceStop;

  /// No description provided for @voiceTooLong.
  ///
  /// In en, this message translates to:
  /// **'Voice notes are limited to 20 seconds.'**
  String get voiceTooLong;

  /// No description provided for @voiceUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Voice notes require HearthBit on the recipient\'s device.'**
  String get voiceUnsupported;

  /// No description provided for @voicePlay.
  ///
  /// In en, this message translates to:
  /// **'Play voice note'**
  String get voicePlay;

  /// No description provided for @voicePause.
  ///
  /// In en, this message translates to:
  /// **'Pause voice note'**
  String get voicePause;

  /// No description provided for @shareApkButton.
  ///
  /// In en, this message translates to:
  /// **'Share installed APK'**
  String get shareApkButton;

  /// No description provided for @sendApkToPeer.
  ///
  /// In en, this message translates to:
  /// **'Send HearthBit APK'**
  String get sendApkToPeer;

  /// No description provided for @apkSafetyTitle.
  ///
  /// In en, this message translates to:
  /// **'Share the Android installer?'**
  String get apkSafetyTitle;

  /// No description provided for @apkSendToPeerWarning.
  ///
  /// In en, this message translates to:
  /// **'{peer} will receive the HearthBit Android installer.'**
  String apkSendToPeerWarning(String peer);

  /// No description provided for @apkInstallWarning.
  ///
  /// In en, this message translates to:
  /// **'The recipient must allow app installation from the receiving source in Android settings. HearthBit will not install anything automatically.'**
  String get apkInstallWarning;

  /// No description provided for @apkSignatureWarning.
  ///
  /// In en, this message translates to:
  /// **'An APK signed with a different key cannot update the installed app. Verify the source and signature before installing.'**
  String get apkSignatureWarning;

  /// No description provided for @apkTransportWarning.
  ///
  /// In en, this message translates to:
  /// **'APK transfer does not use BLE. It requires local Wi-Fi, Nearby or Wi-Fi Aware; the transfer will report an error if none is available.'**
  String get apkTransportWarning;

  /// No description provided for @apkConfirmShare.
  ///
  /// In en, this message translates to:
  /// **'CONTINUE'**
  String get apkConfirmShare;

  /// No description provided for @apkPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing a safe APK copy…'**
  String get apkPreparing;

  /// No description provided for @apkSplitUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This installation uses split APKs. Sharing only the base APK would create an incomplete installer, so HearthBit will not share it. Offer the GitHub link instead.'**
  String get apkSplitUnavailable;

  /// No description provided for @apkUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Sharing an installed APK is only available on Android.'**
  String get apkUnsupported;

  /// No description provided for @apkShareError.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare or share the APK: {error}'**
  String apkShareError(String error);

  /// No description provided for @apkShareMessage.
  ///
  /// In en, this message translates to:
  /// **'HearthBit Android installer. Android requires permission to install from this source. A differently signed APK cannot update an existing installation; verify the source and signature first.'**
  String get apkShareMessage;

  /// No description provided for @apkOfferSent.
  ///
  /// In en, this message translates to:
  /// **'APK offered to {peer}. The transfer will show an error if no suitable high-speed transport is available.'**
  String apkOfferSent(String peer);

  /// No description provided for @firstAidOpen.
  ///
  /// In en, this message translates to:
  /// **'OPEN OFFLINE FIRST AID'**
  String get firstAidOpen;

  /// No description provided for @firstAidTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline first aid'**
  String get firstAidTitle;

  /// No description provided for @firstAidDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Call local emergency services. This guide does not replace professional help or training. Local practices vary: follow the operator and local authorities.'**
  String get firstAidDisclaimer;

  /// No description provided for @firstAidChooseTopic.
  ///
  /// In en, this message translates to:
  /// **'Choose what is happening'**
  String get firstAidChooseTopic;

  /// No description provided for @firstAidEnglishFallback.
  ///
  /// In en, this message translates to:
  /// **'This translation could not be verified. Showing the validated English guide.'**
  String get firstAidEnglishFallback;

  /// No description provided for @firstAidSteps.
  ///
  /// In en, this message translates to:
  /// **'Act now'**
  String get firstAidSteps;

  /// No description provided for @firstAidWarnings.
  ///
  /// In en, this message translates to:
  /// **'Avoid'**
  String get firstAidWarnings;

  /// No description provided for @firstAidSources.
  ///
  /// In en, this message translates to:
  /// **'Sources and review information'**
  String get firstAidSources;

  /// No description provided for @firstAidReviewed.
  ///
  /// In en, this message translates to:
  /// **'Content reviewed {date}'**
  String firstAidReviewed(String date);

  /// No description provided for @firstAidLoadError.
  ///
  /// In en, this message translates to:
  /// **'The validated offline guide could not be loaded. Do not rely on incomplete information; call local emergency services.'**
  String get firstAidLoadError;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'ja',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
