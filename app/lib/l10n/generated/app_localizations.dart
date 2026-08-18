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

  /// No description provided for @statusMeshPermissionsRevoked.
  ///
  /// In en, this message translates to:
  /// **'Mesh suspended: Bluetooth or nearby-device permission was revoked.'**
  String get statusMeshPermissionsRevoked;

  /// No description provided for @statusMeshBatteryRestricted.
  ///
  /// In en, this message translates to:
  /// **'Battery restrictions may suspend the mesh in the background.'**
  String get statusMeshBatteryRestricted;

  /// No description provided for @statusMeshSuspended.
  ///
  /// In en, this message translates to:
  /// **'Mesh suspended: messages remain queued until a route is available.'**
  String get statusMeshSuspended;

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

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacyTitle;

  /// No description provided for @privacyPrivateDefaultBody.
  ///
  /// In en, this message translates to:
  /// **'Private mode is on by default. HearthBit minimizes stable radio identifiers and limits identity announcements.'**
  String get privacyPrivateDefaultBody;

  /// No description provided for @privacyBitchatInteropTitle.
  ///
  /// In en, this message translates to:
  /// **'BitChat compatibility'**
  String get privacyBitchatInteropTitle;

  /// No description provided for @privacyBitchatInteropOffBody.
  ///
  /// In en, this message translates to:
  /// **'Off. BitChat public chat is hidden. External devices remain visible without chat, and only their public SOS alerts are shown.'**
  String get privacyBitchatInteropOffBody;

  /// No description provided for @privacyBitchatInteropWarning.
  ///
  /// In en, this message translates to:
  /// **'On. Nearby observers can correlate this device through a stable radio identifier, and public messages remain readable by the mesh.'**
  String get privacyBitchatInteropWarning;

  /// No description provided for @meshtasticInteropTitle.
  ///
  /// In en, this message translates to:
  /// **'Meshtastic long-range radio'**
  String get meshtasticInteropTitle;

  /// No description provided for @meshtasticInteropBody.
  ///
  /// In en, this message translates to:
  /// **'Off by default. When enabled, HearthBit connects to one nearby Meshtastic radio. Private content stays end-to-end encrypted over its LoRa mesh.'**
  String get meshtasticInteropBody;

  /// No description provided for @externalPresenceNoChat.
  ///
  /// In en, this message translates to:
  /// **'External network presence · no chat'**
  String get externalPresenceNoChat;

  /// No description provided for @externalNetworkBadge.
  ///
  /// In en, this message translates to:
  /// **'EXTERNAL NETWORK'**
  String get externalNetworkBadge;

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

  /// No description provided for @sosPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Public SOS privacy'**
  String get sosPrivacyTitle;

  /// No description provided for @sosPrivacyPublicWarning.
  ///
  /// In en, this message translates to:
  /// **'A public SOS reveals your message and cryptographic identity to mesh participants. Choose how much location to include.'**
  String get sosPrivacyPublicWarning;

  /// No description provided for @sosLocationExact.
  ///
  /// In en, this message translates to:
  /// **'Exact location'**
  String get sosLocationExact;

  /// No description provided for @sosLocationExactBody.
  ///
  /// In en, this message translates to:
  /// **'Best for immediate rescue; exposes precise coordinates.'**
  String get sosLocationExactBody;

  /// No description provided for @sosLocationApproximate.
  ///
  /// In en, this message translates to:
  /// **'Approximate location (recommended)'**
  String get sosLocationApproximate;

  /// No description provided for @sosLocationApproximateBody.
  ///
  /// In en, this message translates to:
  /// **'Rounds coordinates to roughly a neighborhood-sized area.'**
  String get sosLocationApproximateBody;

  /// No description provided for @sosLocationNone.
  ///
  /// In en, this message translates to:
  /// **'No location'**
  String get sosLocationNone;

  /// No description provided for @sosLocationNoneBody.
  ///
  /// In en, this message translates to:
  /// **'Sends only your SOS message.'**
  String get sosLocationNoneBody;

  /// No description provided for @sosSendPublic.
  ///
  /// In en, this message translates to:
  /// **'SEND PUBLIC SOS'**
  String get sosSendPublic;

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

  /// No description provided for @sosQrTitle.
  ///
  /// In en, this message translates to:
  /// **'SOS by QR'**
  String get sosQrTitle;

  /// No description provided for @sosQrShowInstructions.
  ///
  /// In en, this message translates to:
  /// **'Show this code to another person. HearthBit can relay the SOS, and any camera can read the fallback text.'**
  String get sosQrShowInstructions;

  /// No description provided for @sosQrFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Readable information without the app'**
  String get sosQrFallbackTitle;

  /// No description provided for @sosQrOpen.
  ///
  /// In en, this message translates to:
  /// **'SHOW SOS QR'**
  String get sosQrOpen;

  /// No description provided for @sosQrScan.
  ///
  /// In en, this message translates to:
  /// **'SCAN AND RELAY SOS'**
  String get sosQrScan;

  /// No description provided for @acousticSosListen.
  ///
  /// In en, this message translates to:
  /// **'LISTEN FOR SOUND SOS'**
  String get acousticSosListen;

  /// No description provided for @acousticSosStopListening.
  ///
  /// In en, this message translates to:
  /// **'STOP ACOUSTIC LISTENING'**
  String get acousticSosStopListening;

  /// No description provided for @sosChannelsTitle.
  ///
  /// In en, this message translates to:
  /// **'SOS sent or prepared through'**
  String get sosChannelsTitle;

  /// No description provided for @sosQrRelayTitle.
  ///
  /// In en, this message translates to:
  /// **'SOS found'**
  String get sosQrRelayTitle;

  /// No description provided for @sosQrRelayAction.
  ///
  /// In en, this message translates to:
  /// **'RELAY SOS'**
  String get sosQrRelayAction;

  /// No description provided for @sosQrInvalid.
  ///
  /// In en, this message translates to:
  /// **'The QR does not contain a valid signed HearthBit SOS.'**
  String get sosQrInvalid;

  /// No description provided for @sosQrRelayed.
  ///
  /// In en, this message translates to:
  /// **'SOS validated and added to the mesh'**
  String get sosQrRelayed;

  /// No description provided for @sosSentToMesh.
  ///
  /// In en, this message translates to:
  /// **'SOS sent to the mesh.'**
  String get sosSentToMesh;

  /// No description provided for @sosQueuedWithoutRoute.
  ///
  /// In en, this message translates to:
  /// **'SOS queued, but there is currently no route out of this phone.'**
  String get sosQueuedWithoutRoute;

  /// No description provided for @emergencySmsOpen.
  ///
  /// In en, this message translates to:
  /// **'Notify a trusted contact by SMS'**
  String get emergencySmsOpen;

  /// No description provided for @emergencySmsTitle.
  ///
  /// In en, this message translates to:
  /// **'Emergency SMS'**
  String get emergencySmsTitle;

  /// No description provided for @emergencySmsBody.
  ///
  /// In en, this message translates to:
  /// **'Prepare a text message for a trusted contact. Your messaging app will open so you can review and send it.'**
  String get emergencySmsBody;

  /// No description provided for @emergencySmsRecipient.
  ///
  /// In en, this message translates to:
  /// **'Trusted contact phone number'**
  String get emergencySmsRecipient;

  /// No description provided for @emergencySmsMessage.
  ///
  /// In en, this message translates to:
  /// **'Emergency message'**
  String get emergencySmsMessage;

  /// No description provided for @emergencySmsDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'This does not send automatically and does not replace a call to official emergency services.'**
  String get emergencySmsDisclaimer;

  /// No description provided for @emergencySmsCompose.
  ///
  /// In en, this message translates to:
  /// **'OPEN MESSAGING APP'**
  String get emergencySmsCompose;

  /// No description provided for @emergencySmsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No compatible messaging app is available'**
  String get emergencySmsUnavailable;

  /// No description provided for @emergencySmsInvalidRecipient.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number'**
  String get emergencySmsInvalidRecipient;

  /// No description provided for @emergencySmsBodyWithoutLocation.
  ///
  /// In en, this message translates to:
  /// **'HearthBit emergency alert: {message}. This SMS does not replace official emergency services.'**
  String emergencySmsBodyWithoutLocation(String message);

  /// No description provided for @emergencySmsBodyWithLocation.
  ///
  /// In en, this message translates to:
  /// **'HearthBit emergency alert: {message}. Coordinates: {latitude}, {longitude}. This SMS does not replace official emergency services.'**
  String emergencySmsBodyWithLocation(
    String message,
    String latitude,
    String longitude,
  );

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

  /// No description provided for @sosTriageTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick rescue details'**
  String get sosTriageTitle;

  /// No description provided for @sosTriageOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional. Choose one need or send SOS immediately.'**
  String get sosTriageOptional;

  /// No description provided for @sosTriageNone.
  ///
  /// In en, this message translates to:
  /// **'No structured details'**
  String get sosTriageNone;

  /// No description provided for @sosTriageMedical.
  ///
  /// In en, this message translates to:
  /// **'Medical'**
  String get sosTriageMedical;

  /// No description provided for @sosTriageWater.
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get sosTriageWater;

  /// No description provided for @sosTriageExtraction.
  ///
  /// In en, this message translates to:
  /// **'Extraction'**
  String get sosTriageExtraction;

  /// No description provided for @sosTriageShelter.
  ///
  /// In en, this message translates to:
  /// **'Shelter'**
  String get sosTriageShelter;

  /// No description provided for @sosTriageOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get sosTriageOther;

  /// No description provided for @sosTriageDetails.
  ///
  /// In en, this message translates to:
  /// **'Add details'**
  String get sosTriageDetails;

  /// No description provided for @sosTriagePeople.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get sosTriagePeople;

  /// No description provided for @sosTriageInjuries.
  ///
  /// In en, this message translates to:
  /// **'Injured'**
  String get sosTriageInjuries;

  /// No description provided for @sosTriageTrapped.
  ///
  /// In en, this message translates to:
  /// **'Trapped'**
  String get sosTriageTrapped;

  /// No description provided for @sosTriageUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get sosTriageUnknown;

  /// No description provided for @sosTriageNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get sosTriageNo;

  /// No description provided for @sosTriageYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get sosTriageYes;

  /// No description provided for @sosTriageSave.
  ///
  /// In en, this message translates to:
  /// **'SAVE DETAILS'**
  String get sosTriageSave;

  /// No description provided for @sosTriageSummary.
  ///
  /// In en, this message translates to:
  /// **'People: {people} · Injured: {injured} · Trapped: {trapped} · Need: {need}'**
  String sosTriageSummary(
    String people,
    String injured,
    String trapped,
    String need,
  );

  /// No description provided for @checkInPrivateBody.
  ///
  /// In en, this message translates to:
  /// **'Sends an end-to-end encrypted update only to verified family members.'**
  String get checkInPrivateBody;

  /// No description provided for @checkInNoCircle.
  ///
  /// In en, this message translates to:
  /// **'Add a verified family member before sending a private check-in.'**
  String get checkInNoCircle;

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

  /// No description provided for @wipeDialogInstruction.
  ///
  /// In en, this message translates to:
  /// **'To confirm, type BORRAR.'**
  String get wipeDialogInstruction;

  /// No description provided for @wipeDialogKeyword.
  ///
  /// In en, this message translates to:
  /// **'Type BORRAR'**
  String get wipeDialogKeyword;

  /// No description provided for @wipeDialogComplete.
  ///
  /// In en, this message translates to:
  /// **'Identity and sensitive data were erased.'**
  String get wipeDialogComplete;

  /// No description provided for @wipeDialogError.
  ///
  /// In en, this message translates to:
  /// **'The erase did not complete. Try again before handing over the device.'**
  String get wipeDialogError;

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

  /// No description provided for @transportWifiDirect.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi Direct'**
  String get transportWifiDirect;

  /// No description provided for @transportMultipeer.
  ///
  /// In en, this message translates to:
  /// **'Multipeer'**
  String get transportMultipeer;

  /// No description provided for @transportShare.
  ///
  /// In en, this message translates to:
  /// **'Share with another app'**
  String get transportShare;

  /// No description provided for @transportOptical.
  ///
  /// In en, this message translates to:
  /// **'Optical QR'**
  String get transportOptical;

  /// No description provided for @transferExport.
  ///
  /// In en, this message translates to:
  /// **'SHARE'**
  String get transferExport;

  /// No description provided for @transferImport.
  ///
  /// In en, this message translates to:
  /// **'Open HearthBit package'**
  String get transferImport;

  /// No description provided for @sealedTransferSend.
  ///
  /// In en, this message translates to:
  /// **'Send sealed through another app'**
  String get sealedTransferSend;

  /// No description provided for @sealedImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Verified sealed file'**
  String get sealedImportTitle;

  /// No description provided for @sealedImportBody.
  ///
  /// In en, this message translates to:
  /// **'{fileName} was signed by verified contact {sender}. Save it?'**
  String sealedImportBody(String fileName, String sender);

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

  /// No description provided for @radarNoSignalHint.
  ///
  /// In en, this message translates to:
  /// **'No direct signal reading yet. Keep HearthBit open on both phones and walk slowly.'**
  String get radarNoSignalHint;

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
  /// **'HearthBit is a source-available emergency communication project, public for privacy and security review. Noncommercial use is licensed; commercial use requires permission.'**
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
  /// **'Join HearthBit, a publicly auditable emergency mesh that works without internet. Download it or contribute at {url}'**
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

  /// No description provided for @diagnosticsExportButton.
  ///
  /// In en, this message translates to:
  /// **'Export diagnostics'**
  String get diagnosticsExportButton;

  /// No description provided for @diagnosticsExportSubject.
  ///
  /// In en, this message translates to:
  /// **'HearthBit diagnostics'**
  String get diagnosticsExportSubject;

  /// No description provided for @diagnosticsExportError.
  ///
  /// In en, this message translates to:
  /// **'Could not export the diagnostic report'**
  String get diagnosticsExportError;

  /// No description provided for @diagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsTitle;

  /// No description provided for @diagnosticsRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh diagnostics'**
  String get diagnosticsRefreshTooltip;

  /// No description provided for @diagnosticsMeshSection.
  ///
  /// In en, this message translates to:
  /// **'Mesh'**
  String get diagnosticsMeshSection;

  /// No description provided for @diagnosticsPlatform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get diagnosticsPlatform;

  /// No description provided for @diagnosticsStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get diagnosticsStatus;

  /// No description provided for @diagnosticsIdentityRotation.
  ///
  /// In en, this message translates to:
  /// **'Last identity rotation'**
  String get diagnosticsIdentityRotation;

  /// No description provided for @diagnosticsNearbyDevices.
  ///
  /// In en, this message translates to:
  /// **'Nearby devices'**
  String get diagnosticsNearbyDevices;

  /// No description provided for @diagnosticsAdvertising.
  ///
  /// In en, this message translates to:
  /// **'BLE advertising'**
  String get diagnosticsAdvertising;

  /// No description provided for @diagnosticsMeshScan.
  ///
  /// In en, this message translates to:
  /// **'Mesh scan'**
  String get diagnosticsMeshScan;

  /// No description provided for @diagnosticsGenericScan.
  ///
  /// In en, this message translates to:
  /// **'Generic signal scan'**
  String get diagnosticsGenericScan;

  /// No description provided for @diagnosticsEnergySection.
  ///
  /// In en, this message translates to:
  /// **'Energy'**
  String get diagnosticsEnergySection;

  /// No description provided for @diagnosticsBattery.
  ///
  /// In en, this message translates to:
  /// **'Battery'**
  String get diagnosticsBattery;

  /// No description provided for @diagnosticsPowerProfile.
  ///
  /// In en, this message translates to:
  /// **'Power profile'**
  String get diagnosticsPowerProfile;

  /// No description provided for @diagnosticsBleDutyCycle.
  ///
  /// In en, this message translates to:
  /// **'BLE duty cycle'**
  String get diagnosticsBleDutyCycle;

  /// No description provided for @diagnosticsScanStarts.
  ///
  /// In en, this message translates to:
  /// **'Scan starts'**
  String get diagnosticsScanStarts;

  /// No description provided for @diagnosticsStoreForward.
  ///
  /// In en, this message translates to:
  /// **'Store-and-forward queue'**
  String get diagnosticsStoreForward;

  /// No description provided for @diagnosticsOperationalCountersSection.
  ///
  /// In en, this message translates to:
  /// **'Operational counters'**
  String get diagnosticsOperationalCountersSection;

  /// No description provided for @diagnosticsOpenSosLimitedKnown.
  ///
  /// In en, this message translates to:
  /// **'Known SOS rate-limited'**
  String get diagnosticsOpenSosLimitedKnown;

  /// No description provided for @diagnosticsOpenSosLimitedUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown SOS rate-limited'**
  String get diagnosticsOpenSosLimitedUnknown;

  /// No description provided for @diagnosticsRelaySuppressed.
  ///
  /// In en, this message translates to:
  /// **'Relays suppressed by damping'**
  String get diagnosticsRelaySuppressed;

  /// No description provided for @diagnosticsRelayScheduled.
  ///
  /// In en, this message translates to:
  /// **'Relays scheduled'**
  String get diagnosticsRelayScheduled;

  /// No description provided for @diagnosticsRelayExpired.
  ///
  /// In en, this message translates to:
  /// **'Relay timers completed'**
  String get diagnosticsRelayExpired;

  /// No description provided for @diagnosticsTrustEvictions.
  ///
  /// In en, this message translates to:
  /// **'Trust pins evicted'**
  String get diagnosticsTrustEvictions;

  /// No description provided for @diagnosticsTrustConflicts.
  ///
  /// In en, this message translates to:
  /// **'Trust conflicts'**
  String get diagnosticsTrustConflicts;

  /// No description provided for @diagnosticsTransportsSection.
  ///
  /// In en, this message translates to:
  /// **'Active transports'**
  String get diagnosticsTransportsSection;

  /// No description provided for @diagnosticsNoActiveTransports.
  ///
  /// In en, this message translates to:
  /// **'No active transport reported'**
  String get diagnosticsNoActiveTransports;

  /// No description provided for @diagnosticsEventsSection.
  ///
  /// In en, this message translates to:
  /// **'Recent events'**
  String get diagnosticsEventsSection;

  /// No description provided for @diagnosticsNoEvents.
  ///
  /// In en, this message translates to:
  /// **'No diagnostic events yet'**
  String get diagnosticsNoEvents;

  /// No description provided for @diagnosticsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get diagnosticsEnabled;

  /// No description provided for @diagnosticsDisabled.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get diagnosticsDisabled;

  /// No description provided for @diagnosticsTransportOutcomesSection.
  ///
  /// In en, this message translates to:
  /// **'Transfer outcomes'**
  String get diagnosticsTransportOutcomesSection;

  /// No description provided for @diagnosticsTransportOutcome.
  ///
  /// In en, this message translates to:
  /// **'{success} successful · {failure} failed'**
  String diagnosticsTransportOutcome(int success, int failure);

  /// No description provided for @diagnosticsTransportAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get diagnosticsTransportAudio;

  /// No description provided for @diagnosticsTransportQr.
  ///
  /// In en, this message translates to:
  /// **'QR'**
  String get diagnosticsTransportQr;

  /// No description provided for @diagnosticsTransportExternal.
  ///
  /// In en, this message translates to:
  /// **'External share'**
  String get diagnosticsTransportExternal;

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

  /// No description provided for @peerRoleInfraRelay.
  ///
  /// In en, this message translates to:
  /// **'Infrastructure relay'**
  String get peerRoleInfraRelay;

  /// No description provided for @peerRoleStorageAnchor.
  ///
  /// In en, this message translates to:
  /// **'Message storage anchor'**
  String get peerRoleStorageAnchor;

  /// No description provided for @peerLongRangeTrunkActive.
  ///
  /// In en, this message translates to:
  /// **'Long-range trunk active'**
  String get peerLongRangeTrunkActive;

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

  /// No description provided for @radarSweepExpired.
  ///
  /// In en, this message translates to:
  /// **'The direction changed or expired. Repeat the sweep from your current position.'**
  String get radarSweepExpired;

  /// No description provided for @radarMeasuredDistance.
  ///
  /// In en, this message translates to:
  /// **'Measured: {distance}'**
  String radarMeasuredDistance(String distance);

  /// No description provided for @radarGpsDistanceMargin.
  ///
  /// In en, this message translates to:
  /// **'≈{distance} ±{accuracy} GPS'**
  String radarGpsDistanceMargin(String distance, String accuracy);

  /// No description provided for @radarActionRadio.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get radarActionRadio;

  /// No description provided for @radarActionSonar.
  ///
  /// In en, this message translates to:
  /// **'Sonar'**
  String get radarActionSonar;

  /// No description provided for @radarActionBeacon.
  ///
  /// In en, this message translates to:
  /// **'Beacon'**
  String get radarActionBeacon;

  /// No description provided for @radarActionDirection.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get radarActionDirection;

  /// No description provided for @radarActionSweeping.
  ///
  /// In en, this message translates to:
  /// **'Sweeping'**
  String get radarActionSweeping;

  /// No description provided for @radarActionWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get radarActionWaiting;

  /// No description provided for @radarRadioStart.
  ///
  /// In en, this message translates to:
  /// **'Measure distance by radio'**
  String get radarRadioStart;

  /// No description provided for @radarRadioStop.
  ///
  /// In en, this message translates to:
  /// **'Stop radio distance measurement'**
  String get radarRadioStop;

  /// No description provided for @radarSonarStart.
  ///
  /// In en, this message translates to:
  /// **'Measure with acoustic sonar'**
  String get radarSonarStart;

  /// No description provided for @radarSonarStop.
  ///
  /// In en, this message translates to:
  /// **'Stop acoustic sonar'**
  String get radarSonarStop;

  /// No description provided for @radarSonarMicrophoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required for acoustic sonar.'**
  String get radarSonarMicrophoneRequired;

  /// No description provided for @radarSonarTooNoisy.
  ///
  /// In en, this message translates to:
  /// **'The chirps could not be measured. Reduce noise, keep both phones uncovered, and try again.'**
  String get radarSonarTooNoisy;

  /// No description provided for @radarSonarRemoteMicrophoneRequired.
  ///
  /// In en, this message translates to:
  /// **'The other phone did not allow microphone access for sonar.'**
  String get radarSonarRemoteMicrophoneRequired;

  /// No description provided for @radarSonarSelfChirpMissing.
  ///
  /// In en, this message translates to:
  /// **'This phone could not detect its own signal. Disconnect Bluetooth headphones, uncover the speaker, and try again.'**
  String get radarSonarSelfChirpMissing;

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
  /// **'GPS and BLE disagree; direction is hidden until you repeat the measurement.'**
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

  /// No description provided for @emergencyDeliveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Broadcast alert status'**
  String get emergencyDeliveryTitle;

  /// No description provided for @deliveryPending.
  ///
  /// In en, this message translates to:
  /// **'Pending broadcast'**
  String get deliveryPending;

  /// No description provided for @deliveryRelayed.
  ///
  /// In en, this message translates to:
  /// **'Broadcast to the mesh'**
  String get deliveryRelayed;

  /// No description provided for @deliveryAcknowledged.
  ///
  /// In en, this message translates to:
  /// **'Confirmed by HearthBit'**
  String get deliveryAcknowledged;

  /// No description provided for @deliveryExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired without confirmation'**
  String get deliveryExpired;

  /// No description provided for @deliveryAttemptsLabel.
  ///
  /// In en, this message translates to:
  /// **'Attempts'**
  String get deliveryAttemptsLabel;

  /// No description provided for @deliveryConfirmationsLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirmations'**
  String get deliveryConfirmationsLabel;

  /// No description provided for @deliveryLastAttemptLabel.
  ///
  /// In en, this message translates to:
  /// **'Last attempt'**
  String get deliveryLastAttemptLabel;

  /// No description provided for @deliveryExpiresLabel.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get deliveryExpiresLabel;

  /// No description provided for @deliveryNoHearthBitConfirmation.
  ///
  /// In en, this message translates to:
  /// **'No confirmation from another HearthBit; a BitChat node may still have received it.'**
  String get deliveryNoHearthBitConfirmation;

  /// No description provided for @deliveryRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry alert'**
  String get deliveryRetry;

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

  /// No description provided for @onboardingAllowMicrophone.
  ///
  /// In en, this message translates to:
  /// **'ALLOW MICROPHONE FOR VOICE RESCUE'**
  String get onboardingAllowMicrophone;

  /// No description provided for @onboardingMicrophoneReady.
  ///
  /// In en, this message translates to:
  /// **'Voice notes and acoustic rescue tools are ready.'**
  String get onboardingMicrophoneReady;

  /// No description provided for @onboardingMicrophoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Required for voice notes and acoustic rescue tools.'**
  String get onboardingMicrophoneRequired;

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

  /// No description provided for @meshHealthTrunks.
  ///
  /// In en, this message translates to:
  /// **'{count} active long-range trunks'**
  String meshHealthTrunks(int count);

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

  /// No description provided for @gatewayTrustTitle.
  ///
  /// In en, this message translates to:
  /// **'TLS certificate trust'**
  String get gatewayTrustTitle;

  /// No description provided for @gatewayTrustSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get gatewayTrustSystem;

  /// No description provided for @gatewayTrustSystemBody.
  ///
  /// In en, this message translates to:
  /// **'Uses the certificate authorities trusted by your device. This is compatible with public services, but does not lock the gateway to one certificate.'**
  String get gatewayTrustSystemBody;

  /// No description provided for @gatewayTrustTofu.
  ///
  /// In en, this message translates to:
  /// **'TOFU'**
  String get gatewayTrustTofu;

  /// No description provided for @gatewayTrustTofuBody.
  ///
  /// In en, this message translates to:
  /// **'Trusts the first certificate seen for this endpoint and rejects later changes. Verify the first connection is not being intercepted.'**
  String get gatewayTrustTofuBody;

  /// No description provided for @gatewayTrustPinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get gatewayTrustPinned;

  /// No description provided for @gatewayTrustPinnedBody.
  ///
  /// In en, this message translates to:
  /// **'Only the exact SHA-256 certificate fingerprint is accepted. Certificate rotation will block delivery until this value is updated.'**
  String get gatewayTrustPinnedBody;

  /// No description provided for @gatewayFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Certificate SHA-256 fingerprint'**
  String get gatewayFingerprint;

  /// No description provided for @gatewayFingerprintHint.
  ///
  /// In en, this message translates to:
  /// **'64 hexadecimal characters; separators are allowed'**
  String get gatewayFingerprintHint;

  /// No description provided for @gatewayFingerprintInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 64-character SHA-256 certificate fingerprint.'**
  String get gatewayFingerprintInvalid;

  /// No description provided for @gatewayResetTofu.
  ///
  /// In en, this message translates to:
  /// **'Forget first certificate'**
  String get gatewayResetTofu;

  /// No description provided for @gatewayResetTofuDone.
  ///
  /// In en, this message translates to:
  /// **'The saved TOFU certificate was removed.'**
  String get gatewayResetTofuDone;

  /// No description provided for @gatewayPrivacyScopeTitle.
  ///
  /// In en, this message translates to:
  /// **'Data shared with the gateway'**
  String get gatewayPrivacyScopeTitle;

  /// No description provided for @gatewaySensitiveContentConsent.
  ///
  /// In en, this message translates to:
  /// **'Share message content and sender identity'**
  String get gatewaySensitiveContentConsent;

  /// No description provided for @gatewaySensitiveContentConsentBody.
  ///
  /// In en, this message translates to:
  /// **'Includes the emergency description, display name and peer identifier. Off by default.'**
  String get gatewaySensitiveContentConsentBody;

  /// No description provided for @gatewayCoordinatesConsent.
  ///
  /// In en, this message translates to:
  /// **'Share precise coordinates'**
  String get gatewayCoordinatesConsent;

  /// No description provided for @gatewayCoordinatesConsentBody.
  ///
  /// In en, this message translates to:
  /// **'Includes latitude and longitude when present. This consent is separate from message content.'**
  String get gatewayCoordinatesConsentBody;

  /// No description provided for @gatewayPrivacyScopeWarning.
  ///
  /// In en, this message translates to:
  /// **'The gateway sends selected data to an internet service outside the local mesh. Enable each category only with informed consent.'**
  String get gatewayPrivacyScopeWarning;

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

  /// No description provided for @mapPassiveCacheInfo.
  ///
  /// In en, this message translates to:
  /// **'This map automatically keeps tiles you view for offline reuse. Regional downloads require an authorized provider or your own server.'**
  String get mapPassiveCacheInfo;

  /// No description provided for @mapTilePolicyAction.
  ///
  /// In en, this message translates to:
  /// **'OSM policy'**
  String get mapTilePolicyAction;

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

  /// No description provided for @mapTileBlockedHint.
  ///
  /// In en, this message translates to:
  /// **'The provider temporarily blocked map tiles. Rescue markers remain available; use an authorized source or your own server for offline maps.'**
  String get mapTileBlockedHint;

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

  /// No description provided for @familyTitle.
  ///
  /// In en, this message translates to:
  /// **'Family group'**
  String get familyTitle;

  /// No description provided for @familySecurityBody.
  ///
  /// In en, this message translates to:
  /// **'Members are verified in person with a signed QR. Names and old device IDs alone are never trusted.'**
  String get familySecurityBody;

  /// No description provided for @familyCreateGroup.
  ///
  /// In en, this message translates to:
  /// **'CREATE GROUP'**
  String get familyCreateGroup;

  /// No description provided for @familyRenameGroup.
  ///
  /// In en, this message translates to:
  /// **'RENAME GROUP'**
  String get familyRenameGroup;

  /// No description provided for @familyGroupHint.
  ///
  /// In en, this message translates to:
  /// **'E.g. My family'**
  String get familyGroupHint;

  /// No description provided for @familyGroupLabel.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get familyGroupLabel;

  /// No description provided for @familyConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm family member'**
  String get familyConfirmTitle;

  /// No description provided for @familyFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Security code: {fingerprint}'**
  String familyFingerprint(String fingerprint);

  /// No description provided for @familyConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Compare this security code on both phones before saving.'**
  String get familyConfirmBody;

  /// No description provided for @familyAddMember.
  ///
  /// In en, this message translates to:
  /// **'ADD MEMBER'**
  String get familyAddMember;

  /// No description provided for @familyRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove family member?'**
  String get familyRemoveTitle;

  /// No description provided for @familyRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'{nickname} will no longer receive family highlighting or alerts.'**
  String familyRemoveBody(String nickname);

  /// No description provided for @familyRemoveAction.
  ///
  /// In en, this message translates to:
  /// **'REMOVE'**
  String get familyRemoveAction;

  /// No description provided for @familySaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save the family group: {error}'**
  String familySaveError(String error);

  /// No description provided for @familyMembersTitle.
  ///
  /// In en, this message translates to:
  /// **'Verified members'**
  String get familyMembersTitle;

  /// No description provided for @familyScanAction.
  ///
  /// In en, this message translates to:
  /// **'Scan member QR'**
  String get familyScanAction;

  /// No description provided for @familyCreateFirst.
  ///
  /// In en, this message translates to:
  /// **'Create a group before adding members.'**
  String get familyCreateFirst;

  /// No description provided for @familyNoMembers.
  ///
  /// In en, this message translates to:
  /// **'No verified members yet.'**
  String get familyNoMembers;

  /// No description provided for @familyMyQr.
  ///
  /// In en, this message translates to:
  /// **'My verification QR'**
  String get familyMyQr;

  /// No description provided for @familyMyQrBody.
  ///
  /// In en, this message translates to:
  /// **'Show this QR in person. It contains your public signing key, never your private key.'**
  String get familyMyQrBody;

  /// No description provided for @familyQrUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Turn on the mesh to make your signed verification QR available.'**
  String get familyQrUnavailable;

  /// No description provided for @familyScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan family QR'**
  String get familyScanTitle;

  /// No description provided for @familyQrInvalid.
  ///
  /// In en, this message translates to:
  /// **'This QR is invalid or its signature could not be verified.'**
  String get familyQrInvalid;

  /// No description provided for @familyScanHint.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR shown on your family member\'s phone.'**
  String get familyScanHint;

  /// No description provided for @familyAlertBadge.
  ///
  /// In en, this message translates to:
  /// **'VERIFIED FAMILY'**
  String get familyAlertBadge;

  /// No description provided for @drillSafetyBanner.
  ///
  /// In en, this message translates to:
  /// **'DRILL - does not request rescue'**
  String get drillSafetyBanner;

  /// No description provided for @drillModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Practice drill'**
  String get drillModeTitle;

  /// No description provided for @drillModeBody.
  ///
  /// In en, this message translates to:
  /// **'Sends clearly marked practice messages only. It never sends SOS, shares rescue location, activates a beacon or uses the internet gateway.'**
  String get drillModeBody;

  /// No description provided for @drillConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn on practice drill?'**
  String get drillConfirmTitle;

  /// No description provided for @drillConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Rescue and survival modes will be turned off. Practice messages are public, but cannot become real emergency alerts.'**
  String get drillConfirmBody;

  /// No description provided for @drillEnableAction.
  ///
  /// In en, this message translates to:
  /// **'TURN ON DRILL'**
  String get drillEnableAction;

  /// No description provided for @drillHoldToSend.
  ///
  /// In en, this message translates to:
  /// **'HOLD TO SEND DRILL'**
  String get drillHoldToSend;

  /// No description provided for @drillPracticeMessage.
  ///
  /// In en, this message translates to:
  /// **'Practice request for help'**
  String get drillPracticeMessage;

  /// No description provided for @drillReceivedTitle.
  ///
  /// In en, this message translates to:
  /// **'Practice drill messages'**
  String get drillReceivedTitle;

  /// No description provided for @drillNoneReceived.
  ///
  /// In en, this message translates to:
  /// **'No practice drill messages received.'**
  String get drillNoneReceived;

  /// No description provided for @drillBadge.
  ///
  /// In en, this message translates to:
  /// **'DRILL — NOT AN EMERGENCY'**
  String get drillBadge;

  /// No description provided for @drillInvalidMessage.
  ///
  /// In en, this message translates to:
  /// **'Unrecognized drill message; it was isolated from emergency systems.'**
  String get drillInvalidMessage;

  /// No description provided for @drillCheckInTitle.
  ///
  /// In en, this message translates to:
  /// **'Practice a status update'**
  String get drillCheckInTitle;

  /// No description provided for @drillCheckInBody.
  ///
  /// In en, this message translates to:
  /// **'These updates remain in the drill channel and are excluded from rescue alerts, maps and exports.'**
  String get drillCheckInBody;

  /// No description provided for @drillExitForRealTitle.
  ///
  /// In en, this message translates to:
  /// **'Send a real SOS?'**
  String get drillExitForRealTitle;

  /// No description provided for @drillExitForRealBody.
  ///
  /// In en, this message translates to:
  /// **'This will end the drill and activate a real rescue request with location sharing and repeated SOS alerts.'**
  String get drillExitForRealBody;

  /// No description provided for @drillSendRealSos.
  ///
  /// In en, this message translates to:
  /// **'END DRILL AND SEND SOS'**
  String get drillSendRealSos;

  /// No description provided for @drillDisableTitle.
  ///
  /// In en, this message translates to:
  /// **'End drill mode?'**
  String get drillDisableTitle;

  /// No description provided for @drillDisableBody.
  ///
  /// In en, this message translates to:
  /// **'Practice messages will stop and HearthBit will return to real emergency operation.'**
  String get drillDisableBody;

  /// No description provided for @drillDisableAction.
  ///
  /// In en, this message translates to:
  /// **'END DRILL'**
  String get drillDisableAction;

  /// No description provided for @mapNoLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'No location available'**
  String get mapNoLocationTitle;

  /// No description provided for @mapNoLocationBody.
  ///
  /// In en, this message translates to:
  /// **'Turn on location or wait for a peer to share a valid rescue position. The map will never use (0,0) as a fallback.'**
  String get mapNoLocationBody;

  /// No description provided for @voiceMicrophoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required to record a voice note.'**
  String get voiceMicrophoneRequired;

  /// No description provided for @actionOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'OPEN SETTINGS'**
  String get actionOpenSettings;

  /// No description provided for @opticalUnverifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unverified source'**
  String get opticalUnverifiedTitle;

  /// No description provided for @opticalUnverifiedBody.
  ///
  /// In en, this message translates to:
  /// **'HearthBit cannot match this transfer to a previously authenticated identity. Confirm the fingerprint with the sender before accepting the file.'**
  String get opticalUnverifiedBody;

  /// No description provided for @opticalLegacyWarning.
  ///
  /// In en, this message translates to:
  /// **'This sender uses the legacy unsigned optical format.'**
  String get opticalLegacyWarning;

  /// No description provided for @opticalFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint: {fingerprint}'**
  String opticalFingerprint(String fingerprint);

  /// No description provided for @opticalAcceptUnverified.
  ///
  /// In en, this message translates to:
  /// **'ACCEPT UNVERIFIED'**
  String get opticalAcceptUnverified;

  /// No description provided for @opticalSignatureInvalid.
  ///
  /// In en, this message translates to:
  /// **'The optical manifest signature does not match the known sender. The file was rejected.'**
  String get opticalSignatureInvalid;

  /// No description provided for @opticalVerifiedSource.
  ///
  /// In en, this message translates to:
  /// **'Verified sender'**
  String get opticalVerifiedSource;

  /// No description provided for @gatewayPrivacyConfirm.
  ///
  /// In en, this message translates to:
  /// **'This sends emergency messages, sender details and any included rescue location to the configured internet service. Enable it only with the consent of affected people.'**
  String get gatewayPrivacyConfirm;

  /// No description provided for @gatewayEnableAction.
  ///
  /// In en, this message translates to:
  /// **'ENABLE GATEWAY'**
  String get gatewayEnableAction;

  /// No description provided for @gatewayTlsRequired.
  ///
  /// In en, this message translates to:
  /// **'Required for emergency data; insecure connections are blocked.'**
  String get gatewayTlsRequired;

  /// No description provided for @locationExportConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Export rescue locations?'**
  String get locationExportConfirmTitle;

  /// No description provided for @locationExportConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The export can contain precise locations, identities and emergency details. Share it only with trusted responders and protect the file.'**
  String get locationExportConfirmBody;

  /// No description provided for @locationExportConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'EXPORT LOCATIONS'**
  String get locationExportConfirmAction;

  /// No description provided for @mapExport.
  ///
  /// In en, this message translates to:
  /// **'Export operational data'**
  String get mapExport;

  /// No description provided for @mapExportFormatTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose export format'**
  String get mapExportFormatTitle;

  /// No description provided for @mapExportCsv.
  ///
  /// In en, this message translates to:
  /// **'CSV · active rescue cases'**
  String get mapExportCsv;

  /// No description provided for @mapExportGeoJson.
  ///
  /// In en, this message translates to:
  /// **'GeoJSON · active cases and swept zones'**
  String get mapExportGeoJson;

  /// No description provided for @mapExportSubject.
  ///
  /// In en, this message translates to:
  /// **'HearthBit rescue operations'**
  String get mapExportSubject;

  /// No description provided for @mapExportError.
  ///
  /// In en, this message translates to:
  /// **'Could not export rescue operations: {error}'**
  String mapExportError(String error);

  /// No description provided for @lanGatewayConnected.
  ///
  /// In en, this message translates to:
  /// **'LAN relay connected'**
  String get lanGatewayConnected;

  /// No description provided for @lanGatewaySearching.
  ///
  /// In en, this message translates to:
  /// **'LAN relay enabled · searching locally'**
  String get lanGatewaySearching;

  /// No description provided for @lanGatewayDisabled.
  ///
  /// In en, this message translates to:
  /// **'LAN relay disabled'**
  String get lanGatewayDisabled;

  /// No description provided for @lanGatewayConfigure.
  ///
  /// In en, this message translates to:
  /// **'CONFIGURE LAN RELAY'**
  String get lanGatewayConfigure;

  /// No description provided for @lanGatewayDisable.
  ///
  /// In en, this message translates to:
  /// **'DISABLE LAN RELAY'**
  String get lanGatewayDisable;

  /// No description provided for @lanGatewayPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Opt-in only. The shared key must match your trusted HearthBit Raspberry Pi relay. Mesh frames are authenticated and encrypted on the local network.'**
  String get lanGatewayPrivacy;

  /// No description provided for @lanGatewayPsk.
  ///
  /// In en, this message translates to:
  /// **'32-byte pairing key (base64)'**
  String get lanGatewayPsk;

  /// No description provided for @lanGatewayGeneratePsk.
  ///
  /// In en, this message translates to:
  /// **'GENERATE KEY'**
  String get lanGatewayGeneratePsk;

  /// No description provided for @lanGatewayInvalidPsk.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 32-byte base64 key.'**
  String get lanGatewayInvalidPsk;

  /// No description provided for @emergencyContactsOpen.
  ///
  /// In en, this message translates to:
  /// **'Emergency numbers and official links'**
  String get emergencyContactsOpen;

  /// No description provided for @emergencyContactsTitle.
  ///
  /// In en, this message translates to:
  /// **'Emergency directory'**
  String get emergencyContactsTitle;

  /// No description provided for @emergencyContactsSafetyNotice.
  ///
  /// In en, this message translates to:
  /// **'Call numbers may work without mobile data, but they still require cellular voice coverage. Official websites require internet.'**
  String get emergencyContactsSafetyNotice;

  /// No description provided for @emergencyContactsCountry.
  ///
  /// In en, this message translates to:
  /// **'Country or territory'**
  String get emergencyContactsCountry;

  /// No description provided for @emergencyContactsAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic ({country})'**
  String emergencyContactsAutomatic(String country);

  /// No description provided for @emergencyContactsNumbers.
  ///
  /// In en, this message translates to:
  /// **'Emergency numbers'**
  String get emergencyContactsNumbers;

  /// No description provided for @emergencyContactsOrganizations.
  ///
  /// In en, this message translates to:
  /// **'Official organizations'**
  String get emergencyContactsOrganizations;

  /// No description provided for @emergencyContactsCall.
  ///
  /// In en, this message translates to:
  /// **'CALL'**
  String get emergencyContactsCall;

  /// No description provided for @emergencyContactsWebsite.
  ///
  /// In en, this message translates to:
  /// **'WEBSITE'**
  String get emergencyContactsWebsite;

  /// No description provided for @emergencyContactsSources.
  ///
  /// In en, this message translates to:
  /// **'Sources and review'**
  String get emergencyContactsSources;

  /// No description provided for @emergencyContactsReviewed.
  ///
  /// In en, this message translates to:
  /// **'Reviewed {date}'**
  String emergencyContactsReviewed(String date);

  /// No description provided for @emergencyContactsFallback.
  ///
  /// In en, this message translates to:
  /// **'This translation was unavailable, so the verified English directory is shown.'**
  String get emergencyContactsFallback;

  /// No description provided for @emergencyContactsLoadError.
  ///
  /// In en, this message translates to:
  /// **'The offline emergency directory could not be loaded.'**
  String get emergencyContactsLoadError;

  /// No description provided for @emergencyContactsOpenError.
  ///
  /// In en, this message translates to:
  /// **'This phone could not open that number or link.'**
  String get emergencyContactsOpenError;

  /// No description provided for @emergencyContactsRetry.
  ///
  /// In en, this message translates to:
  /// **'RETRY'**
  String get emergencyContactsRetry;

  /// No description provided for @rescueRosterTitle.
  ///
  /// In en, this message translates to:
  /// **'Rescue team roster'**
  String get rescueRosterTitle;

  /// No description provided for @rescueRosterSecurityBody.
  ///
  /// In en, this message translates to:
  /// **'A roster is signed by its team leader. A person is shown as a verified rescuer only when both their peer ID and Ed25519 signing key match.'**
  String get rescueRosterSecurityBody;

  /// No description provided for @rescueRosterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No rescue team roster is active on this phone.'**
  String get rescueRosterEmpty;

  /// No description provided for @rescueRosterCreate.
  ///
  /// In en, this message translates to:
  /// **'CREATE ROSTER'**
  String get rescueRosterCreate;

  /// No description provided for @rescueRosterTeamName.
  ///
  /// In en, this message translates to:
  /// **'Team name'**
  String get rescueRosterTeamName;

  /// No description provided for @rescueRosterCallsign.
  ///
  /// In en, this message translates to:
  /// **'Leader callsign'**
  String get rescueRosterCallsign;

  /// No description provided for @rescueRosterAddMember.
  ///
  /// In en, this message translates to:
  /// **'ADD NEARBY MEMBER'**
  String get rescueRosterAddMember;

  /// No description provided for @rescueRosterNoEligiblePeers.
  ///
  /// In en, this message translates to:
  /// **'No nearby HearthBit identity with a signing key is available to add.'**
  String get rescueRosterNoEligiblePeers;

  /// No description provided for @rescueRosterNearbyIdentity.
  ///
  /// In en, this message translates to:
  /// **'Nearby identity'**
  String get rescueRosterNearbyIdentity;

  /// No description provided for @rescueRosterMemberCallsign.
  ///
  /// In en, this message translates to:
  /// **'Member callsign'**
  String get rescueRosterMemberCallsign;

  /// No description provided for @rescueRosterMemberRole.
  ///
  /// In en, this message translates to:
  /// **'Rescue role'**
  String get rescueRosterMemberRole;

  /// No description provided for @rescueRosterRemoveMemberTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove roster member?'**
  String get rescueRosterRemoveMemberTitle;

  /// No description provided for @rescueRosterRemoveMemberBody.
  ///
  /// In en, this message translates to:
  /// **'{callsign} will no longer be a verified rescuer in this roster.'**
  String rescueRosterRemoveMemberBody(String callsign);

  /// No description provided for @rescueRosterMemberCount.
  ///
  /// In en, this message translates to:
  /// **'{count} verified members'**
  String rescueRosterMemberCount(int count);

  /// No description provided for @rescueRosterImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import signed roster'**
  String get rescueRosterImportTitle;

  /// No description provided for @rescueRosterImportText.
  ///
  /// In en, this message translates to:
  /// **'Paste QR text'**
  String get rescueRosterImportText;

  /// No description provided for @rescueRosterPasteHint.
  ///
  /// In en, this message translates to:
  /// **'HBRT1:…'**
  String get rescueRosterPasteHint;

  /// No description provided for @rescueRosterImport.
  ///
  /// In en, this message translates to:
  /// **'IMPORT'**
  String get rescueRosterImport;

  /// No description provided for @rescueRosterImportFile.
  ///
  /// In en, this message translates to:
  /// **'Open roster file'**
  String get rescueRosterImportFile;

  /// No description provided for @rescueRosterScanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan roster QR'**
  String get rescueRosterScanQr;

  /// No description provided for @rescueRosterScanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at a signed HBRT1 rescue roster QR.'**
  String get rescueRosterScanHint;

  /// No description provided for @rescueRosterImported.
  ///
  /// In en, this message translates to:
  /// **'The signed rescue roster was verified and activated.'**
  String get rescueRosterImported;

  /// No description provided for @rescueRosterExported.
  ///
  /// In en, this message translates to:
  /// **'The rescue roster file was saved.'**
  String get rescueRosterExported;

  /// No description provided for @rescueRosterExportQr.
  ///
  /// In en, this message translates to:
  /// **'Show QR and text'**
  String get rescueRosterExportQr;

  /// No description provided for @rescueRosterQrTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This roster is too large for one QR. Export it as a file or copy the signed text.'**
  String get rescueRosterQrTooLarge;

  /// No description provided for @rescueRosterExportFile.
  ///
  /// In en, this message translates to:
  /// **'Save roster file'**
  String get rescueRosterExportFile;

  /// No description provided for @rescueRosterRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove active rescue roster?'**
  String get rescueRosterRemoveTitle;

  /// No description provided for @rescueRosterRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'Members will no longer appear as verified rescuers and their protected native pins will be removed.'**
  String get rescueRosterRemoveBody;

  /// No description provided for @rescueRosterError.
  ///
  /// In en, this message translates to:
  /// **'Could not process the rescue roster: {error}'**
  String rescueRosterError(String error);

  /// No description provided for @rescueRosterRoleLeader.
  ///
  /// In en, this message translates to:
  /// **'Team leader'**
  String get rescueRosterRoleLeader;

  /// No description provided for @rescueRosterRoleResponder.
  ///
  /// In en, this message translates to:
  /// **'Responder'**
  String get rescueRosterRoleResponder;

  /// No description provided for @rescueRosterRoleMedic.
  ///
  /// In en, this message translates to:
  /// **'Medic'**
  String get rescueRosterRoleMedic;

  /// No description provided for @rescueRosterRoleSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get rescueRosterRoleSearch;

  /// No description provided for @rescueRosterRoleLogistics.
  ///
  /// In en, this message translates to:
  /// **'Logistics'**
  String get rescueRosterRoleLogistics;

  /// No description provided for @rescueRosterRoleCommunications.
  ///
  /// In en, this message translates to:
  /// **'Communications'**
  String get rescueRosterRoleCommunications;

  /// No description provided for @rescueRosterRoleAuthority.
  ///
  /// In en, this message translates to:
  /// **'Authority'**
  String get rescueRosterRoleAuthority;

  /// No description provided for @authorityTitle.
  ///
  /// In en, this message translates to:
  /// **'Authority announcements'**
  String get authorityTitle;

  /// No description provided for @authorityTrustBody.
  ///
  /// In en, this message translates to:
  /// **'Only members assigned the Authority role in the active signed roster can issue these authenticated team announcements. Team leaders are not authorized automatically.'**
  String get authorityTrustBody;

  /// No description provided for @authorityCreate.
  ///
  /// In en, this message translates to:
  /// **'Create announcement'**
  String get authorityCreate;

  /// No description provided for @authorityPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get authorityPriority;

  /// No description provided for @authorityPriorityInfo.
  ///
  /// In en, this message translates to:
  /// **'INFORMATION'**
  String get authorityPriorityInfo;

  /// No description provided for @authorityPriorityWarning.
  ///
  /// In en, this message translates to:
  /// **'WARNING'**
  String get authorityPriorityWarning;

  /// No description provided for @authorityPriorityEvacuate.
  ///
  /// In en, this message translates to:
  /// **'EVACUATE'**
  String get authorityPriorityEvacuate;

  /// No description provided for @authorityBody.
  ///
  /// In en, this message translates to:
  /// **'Official instruction'**
  String get authorityBody;

  /// No description provided for @authorityDuration.
  ///
  /// In en, this message translates to:
  /// **'Valid for'**
  String get authorityDuration;

  /// No description provided for @authorityDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes'**
  String authorityDurationMinutes(int minutes);

  /// No description provided for @authorityDurationHours.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{1 hour} other{{hours} hours}}'**
  String authorityDurationHours(int hours);

  /// No description provided for @authoritySend.
  ///
  /// In en, this message translates to:
  /// **'ISSUE ANNOUNCEMENT'**
  String get authoritySend;

  /// No description provided for @authoritySent.
  ///
  /// In en, this message translates to:
  /// **'The signed authority announcement was sent.'**
  String get authoritySent;

  /// No description provided for @authoritySendError.
  ///
  /// In en, this message translates to:
  /// **'Could not send the authority announcement: {error}'**
  String authoritySendError(String error);

  /// No description provided for @authorityHistory.
  ///
  /// In en, this message translates to:
  /// **'Announcement history'**
  String get authorityHistory;

  /// No description provided for @authorityHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No authenticated authority announcements have been received.'**
  String get authorityHistoryEmpty;

  /// No description provided for @authorityActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get authorityActive;

  /// No description provided for @authorityExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get authorityExpired;

  /// No description provided for @authorityExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String authorityExpires(String date);

  /// No description provided for @authorityBannerSemantics.
  ///
  /// In en, this message translates to:
  /// **'Active authenticated authority announcement'**
  String get authorityBannerSemantics;

  /// No description provided for @verifiedRescuerBadge.
  ///
  /// In en, this message translates to:
  /// **'VERIFIED RESCUER'**
  String get verifiedRescuerBadge;

  /// No description provided for @rescueRosterFileType.
  ///
  /// In en, this message translates to:
  /// **'HearthBit rescue roster'**
  String get rescueRosterFileType;

  /// No description provided for @rescueOperationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Rescue operations'**
  String get rescueOperationsTitle;

  /// No description provided for @rescueOperationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No SOS cases have been received.'**
  String get rescueOperationsEmpty;

  /// No description provided for @rescueOperationsError.
  ///
  /// In en, this message translates to:
  /// **'Could not update rescue operations: {error}'**
  String rescueOperationsError(String error);

  /// No description provided for @rescueOperationsAssignMe.
  ///
  /// In en, this message translates to:
  /// **'ASSIGN TO ME'**
  String get rescueOperationsAssignMe;

  /// No description provided for @rescueOperationsEnRoute.
  ///
  /// In en, this message translates to:
  /// **'EN ROUTE'**
  String get rescueOperationsEnRoute;

  /// No description provided for @rescueOperationsAttended.
  ///
  /// In en, this message translates to:
  /// **'ATTENDED'**
  String get rescueOperationsAttended;

  /// No description provided for @rescueOperationsClose.
  ///
  /// In en, this message translates to:
  /// **'CLOSE'**
  String get rescueOperationsClose;

  /// No description provided for @rescueOperationsNoActions.
  ///
  /// In en, this message translates to:
  /// **'No authorized actions'**
  String get rescueOperationsNoActions;

  /// No description provided for @rescueOperationsAssignee.
  ///
  /// In en, this message translates to:
  /// **'Assigned to {callsign}'**
  String rescueOperationsAssignee(String callsign);

  /// No description provided for @rescueOperationsReceivedAt.
  ///
  /// In en, this message translates to:
  /// **'Received {date}'**
  String rescueOperationsReceivedAt(String date);

  /// No description provided for @rescueOperationsTriage.
  ///
  /// In en, this message translates to:
  /// **'Priority: {need} · people: {people}'**
  String rescueOperationsTriage(String need, String people);

  /// No description provided for @rescueCaseStateNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get rescueCaseStateNew;

  /// No description provided for @rescueCaseStateAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get rescueCaseStateAssigned;

  /// No description provided for @rescueCaseStateEnRoute.
  ///
  /// In en, this message translates to:
  /// **'En route'**
  String get rescueCaseStateEnRoute;

  /// No description provided for @rescueCaseStateAttended.
  ///
  /// In en, this message translates to:
  /// **'Attended'**
  String get rescueCaseStateAttended;

  /// No description provided for @rescueCaseStateClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get rescueCaseStateClosed;

  /// No description provided for @rescueTriageMedical.
  ///
  /// In en, this message translates to:
  /// **'Medical'**
  String get rescueTriageMedical;

  /// No description provided for @rescueTriageWater.
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get rescueTriageWater;

  /// No description provided for @rescueTriageExtraction.
  ///
  /// In en, this message translates to:
  /// **'Extraction'**
  String get rescueTriageExtraction;

  /// No description provided for @rescueTriageShelter.
  ///
  /// In en, this message translates to:
  /// **'Shelter'**
  String get rescueTriageShelter;

  /// No description provided for @rescueTriageOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get rescueTriageOther;

  /// No description provided for @mapFilterActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get mapFilterActive;

  /// No description provided for @mapFilterUnassigned.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get mapFilterUnassigned;

  /// No description provided for @mapFilterAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get mapFilterAssigned;

  /// No description provided for @mapFilterClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get mapFilterClosed;

  /// No description provided for @mapOperationalCases.
  ///
  /// In en, this message translates to:
  /// **'{count} operational cases'**
  String mapOperationalCases(int count);

  /// No description provided for @mapCasesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No cases match this filter.'**
  String get mapCasesEmpty;

  /// No description provided for @mapClusterTooltip.
  ///
  /// In en, this message translates to:
  /// **'{count} SOS cases · maximum priority: {priority}'**
  String mapClusterTooltip(int count, String priority);

  /// No description provided for @mapPriorityLow.
  ///
  /// In en, this message translates to:
  /// **'Low priority'**
  String get mapPriorityLow;

  /// No description provided for @mapPriorityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium priority'**
  String get mapPriorityMedium;

  /// No description provided for @mapPriorityHigh.
  ///
  /// In en, this message translates to:
  /// **'High priority'**
  String get mapPriorityHigh;

  /// No description provided for @mapPriorityCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical priority'**
  String get mapPriorityCritical;

  /// No description provided for @mapCaseNoCoordinates.
  ///
  /// In en, this message translates to:
  /// **'This case has no coordinates'**
  String get mapCaseNoCoordinates;

  /// No description provided for @mapZoneConsent.
  ///
  /// In en, this message translates to:
  /// **'Record a swept route only while this control remains visibly active.'**
  String get mapZoneConsent;

  /// No description provided for @mapZoneStart.
  ///
  /// In en, this message translates to:
  /// **'RECORD ROUTE'**
  String get mapZoneStart;

  /// No description provided for @mapZoneRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording swept route · {count}/{maximum} points'**
  String mapZoneRecording(int count, int maximum);

  /// No description provided for @mapZoneVisibleOnly.
  ///
  /// In en, this message translates to:
  /// **'Location recording stops when you cancel, publish, or leave this map.'**
  String get mapZoneVisibleOnly;

  /// No description provided for @mapZoneFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish and share route'**
  String get mapZoneFinish;

  /// No description provided for @mapZonePublished.
  ///
  /// In en, this message translates to:
  /// **'Swept route shared with the verified team.'**
  String get mapZonePublished;

  /// No description provided for @mapZoneLocationRequired.
  ///
  /// In en, this message translates to:
  /// **'Location permission and services are required to record a route.'**
  String get mapZoneLocationRequired;

  /// No description provided for @mapZoneError.
  ///
  /// In en, this message translates to:
  /// **'Could not record or share the swept route: {error}'**
  String mapZoneError(String error);
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
