import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../services/acoustic_sos.dart';
import '../services/app_preferences.dart';
import '../services/beacon_control_protocol.dart';
import '../services/diagnostics_log.dart';
import '../services/mesh_native_event.dart';
import '../services/mesh_platform_service.dart';
import '../services/message_repository.dart';
import '../services/optical_protocol.dart';
import '../services/peer_location_tracker.dart';

enum PrivateMessageSendDisposition { sent, queued, failed }

class PrivateMessageSendResult {
  const PrivateMessageSendResult._(this.disposition, {this.error});

  const PrivateMessageSendResult.sent()
    : this._(PrivateMessageSendDisposition.sent);

  const PrivateMessageSendResult.queued()
    : this._(PrivateMessageSendDisposition.queued);

  const PrivateMessageSendResult.failed(String error)
    : this._(PrivateMessageSendDisposition.failed, error: error);

  final PrivateMessageSendDisposition disposition;
  final String? error;

  bool get accepted => disposition != PrivateMessageSendDisposition.failed;
}

class PendingBeaconRequest {
  const PendingBeaconRequest({
    required this.requestId,
    required this.peerId,
    required this.nickname,
    required this.expiresAt,
    required this.flags,
  });

  final String requestId;
  final String peerId;
  final String nickname;
  final DateTime expiresAt;
  final int flags;

  bool get wantsFlash => flags & BeaconControlFlags.flash != 0;
  bool get wantsSound => flags & BeaconControlFlags.sound != 0;
  bool get wantsVibration => flags & BeaconControlFlags.vibrate != 0;
}

class MeshController extends ChangeNotifier {
  MeshController({
    MeshPlatformService? platform,
    MessageRepository? repository,
    PeerLocationTracker? locationTracker,
    AppPreferences? preferences,
    AcousticSosTransportPort? acousticSos,
  }) : _platform = platform ?? MeshPlatformService(),
       _repository = repository ?? MessageRepository(),
       _providedAcousticSos = acousticSos,
       _preferences = preferences,
       _drillModeEnabled = preferences?.drillModeEnabled ?? false,
       _privateMode = preferences?.privacyPrivateMode ?? true,
       _bitchatInteropEnabled = preferences?.bitchatInteropEnabled ?? false,
       _meshtasticEnabled = preferences?.meshtasticEnabled ?? false,
       peerLocations = locationTracker ?? PeerLocationTracker() {
    peerLocations.addListener(_notifyLocationChanged);
    preferences?.addListener(_handlePreferencesChanged);
  }

  /// Intervalo entre reenvíos de SOS con GPS fresco en modo rescate: lo
  /// bastante frecuente para seguir a una persona que se mueve, lo bastante
  /// espaciado para no agotar batería ni saturar la malla.
  static const Duration rescueInterval = RescueModeContract.defaultInterval;
  static const Duration radarLocationInterval = Duration(seconds: 20);
  static const int radarLocationDistanceMeters = 15;
  static const Duration peerReachabilityWindow = Duration(minutes: 4);
  static const int maximumMessagesInMemory = 500;
  static const Duration topologyNotificationInterval = Duration(seconds: 1);
  static const Duration emergencySosLifetime = Duration(hours: 24);
  static const Duration emergencyCheckInLifetime = Duration(hours: 12);
  static const Duration emergencyMaximumBackoff = Duration(minutes: 5);

  final MeshPlatformService _platform;
  final MessageRepository _repository;
  final AcousticSosTransportPort? _providedAcousticSos;
  AcousticSosTransportPort? _createdAcousticSos;
  AcousticSosTransportPort get _acousticSos =>
      _providedAcousticSos ?? (_createdAcousticSos ??= AcousticSosTransport());
  final AppPreferences? _preferences;
  final PeerLocationTracker peerLocations;
  final List<MeshMessage> _messages = [];
  final List<MeshPeer> _peers = [];
  final List<GenericBlePresence> _presences = [];
  final Map<String, MeshPeer> _knownPeers = {};
  final List<PendingPrivateMessage> _privateMessageOutbox = [];
  final List<EmergencyDelivery> _emergencyDeliveries = [];
  final Random _random = Random.secure();

  StreamSubscription<MeshNativeEvent>? _subscription;
  bool _drainingPrivateMessageOutbox = false;
  bool _privateMessageOutboxDrainRequested = false;
  bool _drainingEmergencyOutbox = false;
  bool _emergencyOutboxDrainRequested = false;
  bool _startingRadarLocationSharing = false;
  bool _sendingRadarLocation = false;
  Completer<void>? _privateMessageOutboxDrainCompleter;
  MeshConnectionStatus status = MeshConnectionStatus.stopped;
  String nickname = '';
  String peerId = '';
  Uint8List? signingPublicKey;
  MeshNodeRole localRole = MeshNodeRole.phoneRelay;
  String? lastError;
  bool supportsBackgroundRelay = false;
  bool supportsMeshtastic = false;
  String platformName = 'unknown';
  bool supportsAcousticSonar = false;
  bool supportsRadioRanging = false;
  bool meshAdvertising = false;
  bool meshScanActive = false;
  bool genericScanActive = false;
  bool genericScanEnabled = false;
  int bleDutyCyclePercent = 0;
  int activeBleScans = 0;
  int scanStarts = 0;
  int storeForwardEntries = 0;
  Set<String> activeTransports = const {};
  DateTime? radarConsentUntil;
  PendingBeaconRequest? pendingBeaconRequest;
  bool localBeaconActive = false;
  DateTime? localBeaconExpiresAt;
  OpticalEmergencyBundle? latestSosQr;
  bool acousticSosListening = false;
  bool acousticSosBroadcasting = false;

  // Modo rescate: reenvía el SOS con ubicación actualizada periódicamente.
  bool rescueMode = false;
  bool activatingEmergency = false;
  DateTime? rescueStartedAt;
  DateTime? rescueExpiresAt;
  DateTime? lastRescuePing;
  Timer? _consentTimer;
  Timer? _radarLocationTimer;
  Timer? _topologyNotificationTimer;
  Timer? _emergencyRetryTimer;
  DateTime? _lastTopologyNotificationAt;
  Position? _latestRadarPosition;
  Position? _lastSharedRadarPosition;
  DateTime? _lastRadarLocationShareAt;

  /// Vacía significa «usar el texto por defecto localizado» ([sendSos]).
  String _rescueDescription = '';
  SosLocationPrecision _rescueLocationPrecision =
      SosLocationPrecision.approximate;

  // Estado de energía/ubicación reportado por el sistema.
  bool ignoringBatteryOptimizations = true;
  bool lowPowerMode = false;
  bool backgroundLocationGranted = false;
  int batteryLevel = 100;
  MeshPowerProfile powerProfile = MeshPowerProfile.balanced;
  bool adaptivePowerSaving = false;
  bool survivalMode = false;
  bool _drillModeEnabled;
  bool _privateMode;
  bool _bitchatInteropEnabled;
  bool _meshtasticEnabled;

  List<MeshMessage> get messages => List.unmodifiable(_messages);
  bool get bitchatInteropEnabled => _bitchatInteropEnabled;
  bool get meshtasticEnabled => _meshtasticEnabled;
  List<EmergencyDelivery> get emergencyDeliveries =>
      List.unmodifiable(_emergencyDeliveries);
  bool get drillModeEnabled => _drillModeEnabled;
  List<MeshMessage> get drillMessages => List.unmodifiable(
    _messages.where((message) => message.isDrill).toList().reversed,
  );
  List<MeshPeer> get peers {
    final now = DateTime.now();
    return List.unmodifiable(_peers.where((peer) => _isPeerOnline(peer, now)));
  }

  List<EmergencyCheckIn> get latestCheckIns {
    final latestByPeer = <String, EmergencyCheckIn>{};
    for (final message in _messages) {
      final checkIn = message.checkIn;
      if (checkIn == null) continue;
      final existing = latestByPeer[checkIn.peerId];
      if (existing == null || checkIn.timestamp.isAfter(existing.timestamp)) {
        latestByPeer[checkIn.peerId] = checkIn;
      }
    }
    final checkIns = latestByPeer.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return List.unmodifiable(checkIns);
  }

  List<GenericBlePresence> get genericPresences {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 45));
    return List.unmodifiable(
      _presences.where((presence) => presence.lastSeen.isAfter(cutoff)),
    );
  }

  bool isPeerOnline(String id) {
    final now = DateTime.now();
    return _peers.any((peer) => peer.id == id && _isPeerOnline(peer, now));
  }

  MeshPeer? peerById(String id) {
    final now = DateTime.now();
    for (final peer in _peers) {
      if (peer.id == id && _isPeerOnline(peer, now)) return peer;
    }
    return null;
  }

  MeshPeer? knownPeerById(String id) => _knownPeers[id];

  bool get radarConsentActive =>
      radarConsentUntil?.isAfter(DateTime.now()) ?? false;

  List<MeshConversation> get conversations {
    final latestByPeer = <String, MeshMessage>{};
    for (final message in _messages) {
      if (message.isPrivate) {
        latestByPeer[message.senderPeerId] = message;
      }
    }
    final onlineById = {for (final peer in peers) peer.id: peer};
    final conversations = latestByPeer.entries.map((entry) {
      final online = onlineById[entry.key];
      final known = _knownPeers[entry.key];
      final peer =
          online ??
          known ??
          MeshPeer(
            id: entry.key,
            nickname: _conversationNickname(entry.key),
            lastSeen: entry.value.timestamp,
            secure: false,
          );
      return MeshConversation(
        peer: peer,
        lastMessage: entry.value,
        isOnline: online != null,
      );
    }).toList();
    conversations.sort(
      (first, second) =>
          second.lastMessage.timestamp.compareTo(first.lastMessage.timestamp),
    );
    return List.unmodifiable(conversations);
  }

  /// La malla puede enviar mensajes: anuncio completo o modo solo recepción,
  /// donde las conexiones salientes hacia otros nodos siguen funcionando.
  bool get canSend =>
      localRole.canChat &&
      (status == MeshConnectionStatus.active ||
          status == MeshConnectionStatus.degraded);

  bool canChatWithPeer(MeshPeer peer) =>
      peer.role.canChat && (_bitchatInteropEnabled || peer.hearthbitVerified);

  Future<void> initialize() async {
    _messages
      ..clear()
      ..addAll(await _repository.load());
    peerLocations.replacePersisted(_messages);
    _knownPeers
      ..clear()
      ..addEntries(
        (await _repository.loadKnownPeers()).map(
          (peer) => MapEntry(peer.id, peer),
        ),
      );
    await _repository.expirePrivateMessageOutbox(DateTime.now());
    _privateMessageOutbox
      ..clear()
      ..addAll(await _repository.listPendingPrivateMessages());
    await _repository.expireEmergencyDeliveries(DateTime.now());
    _emergencyDeliveries
      ..clear()
      ..addAll(await _repository.loadEmergencyDeliveries());
    for (final pending in _privateMessageOutbox) {
      if (_messages.every((message) => message.id != pending.localId)) {
        _messages.add(_pendingMessage(pending));
      }
    }
    _messages.sort(
      (first, second) => first.timestamp.compareTo(second.timestamp),
    );
    _trimMessagesInMemory();
    _subscription = _platform.nativeEvents.listen(_handleEventSafely);
    final capabilities = await _platform.getCapabilities();
    platformName = capabilities['platform'] as String? ?? platformName;
    supportsBackgroundRelay = capabilities['backgroundRelay'] as bool? ?? false;
    supportsMeshtastic = capabilities['meshtastic'] as bool? ?? false;
    supportsAcousticSonar = capabilities['acousticSonar'] as bool? ?? false;
    supportsRadioRanging = capabilities['radioRanging'] as bool? ?? false;
    await _platform.configurePrivacyMode(
      privateMode: _privateMode,
      bitchatInteropEnabled: _bitchatInteropEnabled,
    );
    if (_meshtasticEnabled && supportsMeshtastic) {
      await _platform.configureMeshtasticBridge(enabled: true);
    }
    await _restoreNativeRescueMode();
    await refreshPowerStatus();
    if (_preferences?.meshDesiredActive == true) {
      await _restoreRequestedMesh();
    }
    _consentTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      var changed = false;
      if (radarConsentUntil != null && !radarConsentActive) {
        radarConsentUntil = null;
        _syncRadarLocationSharing();
        changed = true;
      }
      if (pendingBeaconRequest?.expiresAt.isAfter(DateTime.now()) == false) {
        pendingBeaconRequest = null;
        changed = true;
      }
      if (changed) notifyListeners();
    });
    _requestPrivateMessageOutboxDrain();
    _requestEmergencyOutboxDrain();
    DiagnosticsLog.instance.info(
      'storage.queue.stats',
      data: {
        'privateOutbox': _privateMessageOutbox.length,
        'emergencyOutbox': _emergencyDeliveries.length,
      },
    );
    notifyListeners();
  }

  Future<void> refreshPowerStatus() async {
    final power = await _platform.getPowerStatus();
    ignoringBatteryOptimizations =
        power['ignoringBatteryOptimizations'] as bool? ?? true;
    lowPowerMode = power['lowPowerMode'] as bool? ?? false;
    backgroundLocationGranted = power['backgroundLocation'] as bool? ?? false;
    batteryLevel = (power['batteryLevel'] as num?)?.toInt() ?? batteryLevel;
    powerProfile = MeshPowerProfile.fromWire(power['powerProfile']);
    adaptivePowerSaving =
        power['adaptivePowerSaving'] as bool? ?? powerProfile.savesPower;
    notifyListeners();
  }

  Future<void> refreshDiagnostics({bool notify = true}) async {
    final diagnostics = await _platform.getMeshDiagnostics();
    if (diagnostics.isEmpty) return;
    platformName = diagnostics['platform'] as String? ?? platformName;
    meshAdvertising = diagnostics['advertising'] as bool? ?? meshAdvertising;
    meshScanActive = diagnostics['meshScanActive'] as bool? ?? meshScanActive;
    genericScanActive =
        diagnostics['genericScanActive'] as bool? ?? genericScanActive;
    genericScanEnabled =
        diagnostics['genericScanEnabled'] as bool? ?? genericScanEnabled;
    batteryLevel =
        (diagnostics['batteryLevel'] as num?)?.toInt() ?? batteryLevel;
    powerProfile = MeshPowerProfile.fromWire(
      diagnostics['powerProfile'] ?? powerProfile.wireName,
    );
    adaptivePowerSaving =
        diagnostics['adaptivePowerSaving'] as bool? ?? adaptivePowerSaving;
    bleDutyCyclePercent =
        (diagnostics['bleDutyCyclePercent'] as num?)?.toInt() ??
        bleDutyCyclePercent;
    activeBleScans =
        (diagnostics['activeScans'] as num?)?.toInt() ?? activeBleScans;
    scanStarts = (diagnostics['scanStarts'] as num?)?.toInt() ?? scanStarts;
    storeForwardEntries =
        (diagnostics['storeForwardEntries'] as num?)?.toInt() ??
        storeForwardEntries;
    final transports = diagnostics['transports'];
    if (transports is List<Object?>) {
      activeTransports = transports
          .whereType<String>()
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toSet();
    }
    if (notify) notifyListeners();
  }

  /// Abre el diálogo de optimización de batería (Android). El resultado real
  /// se conoce al volver a la app, con [refreshPowerStatus].
  Future<void> requestDisableBatteryOptimizations() async {
    ignoringBatteryOptimizations = await _platform
        .requestDisableBatteryOptimizations();
    notifyListeners();
  }

  /// Solicita ubicación permanente en dos pasos: primero el permiso en
  /// primer plano (diálogo de geolocator) y luego «todo el tiempo»/«siempre».
  Future<bool> ensureAlwaysLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        lastError = currentL10n.errorLocationOff;
        notifyListeners();
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        backgroundLocationGranted = false;
        notifyListeners();
        return false;
      }
    } catch (_) {
      // Sin plugin de ubicación (tests); se sigue con el paso nativo.
    }
    backgroundLocationGranted = await _platform.requestBackgroundLocation();
    notifyListeners();
    return backgroundLocationGranted;
  }

  /// Modo rescate: envía un SOS inmediato y lo reenvía con GPS fresco cada
  /// [rescueInterval] para que los rescatistas sigan la posición. Requiere
  /// que la malla y el servicio en primer plano sigan vivos.
  Future<void> setRescueMode(
    bool enabled, {
    String? description,
    Duration? interval,
    SosLocationPrecision? locationPrecision,
  }) async {
    if (!enabled) {
      final wasRescueActive = rescueMode;
      await _platform.configureRescueMode(active: false);
      rescueMode = false;
      rescueStartedAt = null;
      rescueExpiresAt = null;
      latestSosQr = null;
      await (_providedAcousticSos ?? _createdAcousticSos)?.stopBroadcast();
      acousticSosBroadcasting = false;
      _stopRadarLocationSharing();
      if (wasRescueActive || radarConsentActive) {
        await revokeRadarConsent();
      }
      notifyListeners();
      return;
    }
    if (drillModeEnabled) await deactivateDrill();
    if (description != null && description.trim().isNotEmpty) {
      _rescueDescription = description.trim();
    }
    if (locationPrecision != null) {
      _rescueLocationPrecision = locationPrecision;
    }
    final now = DateTime.now();
    rescueMode = true;
    rescueStartedAt ??= now;
    rescueExpiresAt = now.add(const Duration(hours: 24));
    notifyListeners();
    await _platform.setRadarConsent(enabled: true, minutes: 30);
    await ensureAlwaysLocation();
    await _rescuePing();
    final state = await _platform.configureRescueMode(
      active: true,
      description: _rescueDescription,
      startedAt: rescueStartedAt,
      lastPingAt: lastRescuePing,
      expiresAt: rescueExpiresAt,
      interval: interval ?? rescueInterval,
      locationPrecision: _rescueLocationPrecision,
    );
    _applyNativeRescueState(state);
  }

  Future<void> _rescuePing() async {
    if (!rescueMode) return;
    await _platform.setRadarConsent(enabled: true, minutes: 30);
    await sendSos(
      _rescueDescription,
      locationPrecision: _rescueLocationPrecision,
    );
    lastRescuePing = DateTime.now();
    notifyListeners();
  }

  Future<void> _restoreNativeRescueMode() async {
    final state = await _platform.getRescueModeState();
    final expiresAt = state.expiresAt;
    if (!state.active ||
        expiresAt == null ||
        !expiresAt.isAfter(DateTime.now())) {
      if (state.active) {
        await _platform.configureRescueMode(active: false);
      }
      return;
    }
    _applyNativeRescueState(state);
  }

  void _applyNativeRescueState(NativeRescueState state) {
    rescueMode = state.active;
    if (!state.active) return;
    DiagnosticsLog.instance.info(
      'rescue.scheduler.stats',
      data: {
        'expectedPings': state.expectedPings,
        'executedPings': state.executedPings,
      },
    );
    rescueStartedAt = state.startedAt;
    rescueExpiresAt = state.expiresAt;
    lastRescuePing = state.lastPingAt;
    _rescueLocationPrecision = state.locationPrecision;
    final description = state.description?.trim();
    if (description != null && description.isNotEmpty) {
      _rescueDescription = description;
    }
  }

  Future<void> _restoreRequestedMesh() async {
    lastError = null;
    status = MeshConnectionStatus.starting;
    notifyListeners();
    try {
      await _platform.start();
      DiagnosticsLog.instance.info('mesh.start.restored');
    } catch (error) {
      status = MeshConnectionStatus.error;
      lastError = error.toString();
      DiagnosticsLog.instance.error('mesh.start.restore.failed', error: error);
      notifyListeners();
    }
  }

  Future<void> start() async {
    DiagnosticsLog.instance.info('mesh.start.requested');
    lastError = null;
    status = MeshConnectionStatus.starting;
    notifyListeners();
    try {
      if (!await _platform.requestPermissions()) {
        status = MeshConnectionStatus.error;
        lastError = currentL10n.errorPermissions;
        notifyListeners();
        return;
      }
      await _platform.start();
      try {
        await _preferences?.setMeshDesiredActive(true);
      } catch (error) {
        DiagnosticsLog.instance.error(
          'mesh.preference.persist.failed',
          error: error,
        );
      }
    } catch (error) {
      status = MeshConnectionStatus.error;
      lastError = error.toString();
      DiagnosticsLog.instance.error('mesh.start.failed', error: error);
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await setRescueMode(false);
    _stopRadarLocationSharing();
    await _preferences?.setMeshDesiredActive(false);
    await _platform.stop();
    status = MeshConnectionStatus.stopped;
    _presences.clear();
    DiagnosticsLog.instance.info('mesh.stopped');
    notifyListeners();
  }

  Future<void> sendPublic(String content) async {
    if (content.trim().isEmpty) return;
    await _run(() => _platform.sendPublic(content.trim()));
  }

  Future<PrivateMessageSendResult> sendPrivate(
    MeshPeer peer,
    String content,
  ) async {
    final cleaned = content.trim();
    if (!canChatWithPeer(peer) || cleaned.isEmpty) {
      return PrivateMessageSendResult.failed(currentL10n.errorUnknown);
    }
    final currentPeer = peerById(peer.id);
    if (!canSend || currentPeer == null) {
      return _enqueuePrivateMessage(peer.id, cleaned);
    }
    if (!currentPeer.secure) {
      final queued = await _enqueuePrivateMessage(currentPeer.id, cleaned);
      if (queued.disposition == PrivateMessageSendDisposition.queued) {
        await _run<void>(() => _platform.ensurePrivateChannel(currentPeer.id));
      }
      return queued;
    }

    final localId = _newPrivateMessageLocalId();
    final messageId = await _run(
      () => _platform.sendPrivate(currentPeer.id, cleaned, messageId: localId),
    );
    if (messageId == null || messageId.trim().isEmpty) {
      final queued = await _enqueuePrivateMessage(
        currentPeer.id,
        cleaned,
        localId: localId,
      );
      if (!isPeerOnline(currentPeer.id)) return queued;
      return PrivateMessageSendResult.failed(
        lastError ?? currentL10n.errorUnknown,
      );
    }
    await _recordSentPrivateMessage(
      id: messageId,
      recipientPeerId: currentPeer.id,
      content: cleaned,
      timestamp: DateTime.now(),
    );
    return const PrivateMessageSendResult.sent();
  }

  Future<void> sendSos(
    String description, {
    SosLocationPrecision locationPrecision = SosLocationPrecision.approximate,
  }) async {
    DiagnosticsLog.instance.info('sos.send.started');
    final position = locationPrecision == SosLocationPrecision.none
        ? null
        : await _currentPosition();
    final readable = description.trim().isEmpty
        ? currentL10n.sosDefaultMessage
        : description.trim();
    final coordinates = position == null
        ? null
        : switch (locationPrecision) {
            SosLocationPrecision.exact => (
              position.latitude,
              position.longitude,
            ),
            SosLocationPrecision.approximate => (
              coarsenEmergencyCoordinate(position.latitude),
              coarsenEmergencyCoordinate(position.longitude),
            ),
            SosLocationPrecision.none => null,
          };
    final location = coordinates == null
        ? '||'
        : '|${coordinates.$1}|${coordinates.$2}';
    final delivery = await _enqueueEmergency(
      kind: EmergencyDeliveryKind.sos,
      content: 'SOS|$readable$location',
      lifetime: emergencySosLifetime,
    );
    await _transmitEmergency(delivery, force: true);
    final accepted = _emergencyDeliveries.any(
      (item) =>
          item.localId == delivery.localId &&
          item.state == EmergencyDeliveryState.relayed,
    );
    if (accepted) {
      DiagnosticsLog.instance.info(
        'sos.send.accepted_by_mesh',
        data: {
          'gpsAttached': coordinates != null,
          'precision': locationPrecision.wireName,
        },
      );
    } else {
      DiagnosticsLog.instance.warning('sos.send.failed');
    }
  }

  Future<bool> composeEmergencySms({
    required String recipient,
    required String message,
    SosLocationPrecision locationPrecision = SosLocationPrecision.approximate,
  }) async {
    final readable = message.trim().isEmpty
        ? currentL10n.sosDefaultMessage
        : message.trim();
    final position = locationPrecision == SosLocationPrecision.none
        ? null
        : await _currentPosition();
    final coordinates = position == null
        ? null
        : switch (locationPrecision) {
            SosLocationPrecision.exact => (
              position.latitude.toStringAsFixed(6),
              position.longitude.toStringAsFixed(6),
            ),
            SosLocationPrecision.approximate => (
              coarsenEmergencyCoordinate(position.latitude).toStringAsFixed(3),
              coarsenEmergencyCoordinate(position.longitude).toStringAsFixed(3),
            ),
            SosLocationPrecision.none => null,
          };
    final body = coordinates == null
        ? currentL10n.emergencySmsBodyWithoutLocation(readable)
        : currentL10n.emergencySmsBodyWithLocation(
            readable,
            coordinates.$1,
            coordinates.$2,
          );
    final opened = await _platform.composeEmergencySms(
      recipient: recipient,
      body: body,
    );
    DiagnosticsLog.instance.info(
      'emergency.sms.composer',
      data: {'opened': opened, 'locationPrecision': locationPrecision},
    );
    return opened;
  }

  Future<void> sendCheckIn(CheckInStatus status, String readableMessage) async {
    final position = await _currentPosition();
    final content = EmergencyCheckIn.encode(
      status: status,
      readableMessage: readableMessage,
      timestamp: DateTime.now(),
      latitude: position?.latitude,
      longitude: position?.longitude,
    );
    final delivery = await _enqueueEmergency(
      kind: EmergencyDeliveryKind.checkIn,
      content: content,
      lifetime: emergencyCheckInLifetime,
    );
    await _transmitEmergency(delivery, force: true);
  }

  Future<int> sendCircleCheckIn(
    CheckInStatus status,
    String readableMessage,
    Iterable<String> trustedPeerIds,
  ) async {
    final recipients = trustedPeerIds
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty && value != peerId.toLowerCase())
        .toSet();
    if (recipients.isEmpty) return 0;
    final position = await _currentPosition();
    final content = EmergencyCheckIn.encode(
      status: status,
      readableMessage: readableMessage,
      timestamp: DateTime.now(),
      latitude: position?.latitude,
      longitude: position?.longitude,
    );
    var accepted = 0;
    for (final recipient in recipients) {
      final peer =
          peerById(recipient) ??
          knownPeerById(recipient) ??
          MeshPeer(
            id: recipient,
            nickname: recipient.substring(0, min(8, recipient.length)),
            lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
            secure: false,
            hearthbitVerified: true,
          );
      final result = await sendPrivate(peer, content);
      if (result.disposition != PrivateMessageSendDisposition.failed) {
        accepted += 1;
      }
    }
    return accepted;
  }

  Future<void> retryEmergency(String localId) async {
    final existing = _emergencyDeliveries
        .where((delivery) => delivery.localId == localId)
        .firstOrNull;
    if (existing == null) return;
    if (existing.state == EmergencyDeliveryState.expired) {
      final replacement = await _enqueueEmergency(
        kind: existing.kind,
        content: existing.content,
        lifetime: existing.kind == EmergencyDeliveryKind.sos
            ? emergencySosLifetime
            : emergencyCheckInLifetime,
      );
      await _transmitEmergency(replacement, force: true);
      return;
    }
    final retrying = existing.copyWith(
      state: EmergencyDeliveryState.pending,
      nextAttemptAt: DateTime.now(),
      clearLastError: true,
    );
    await _replaceEmergencyDelivery(retrying);
    await _transmitEmergency(retrying, force: true);
  }

  Future<void> activateDrill() async {
    await _enforceDrillIsolation();
    if (_drillModeEnabled) return;
    _drillModeEnabled = true;
    await _preferences?.setDrillModeEnabled(true);
    notifyListeners();
  }

  Future<void> deactivateDrill() async {
    if (!_drillModeEnabled && _preferences?.drillModeEnabled != true) return;
    _drillModeEnabled = false;
    await _preferences?.setDrillModeEnabled(false);
    notifyListeners();
  }

  Future<void> sendDrillCheckIn(
    CheckInStatus status,
    String readableMessage,
  ) async {
    if (!drillModeEnabled) {
      throw StateError('Drill mode is not active');
    }
    final content = DrillCheckIn.encode(
      status: status,
      readableMessage: readableMessage,
      safetyNotice: currentL10n.drillSafetyBanner,
      timestamp: DateTime.now(),
    );
    await _run(() => _platform.sendPublic(content, channel: 'drill'));
  }

  Future<void> _enforceDrillIsolation() async {
    if (rescueMode) await setRescueMode(false);
    if (survivalMode) await setSurvivalMode(false);
    if (localBeaconActive) await stopLocalBeacon();
  }

  Future<void> activateEmergency({
    String? description,
    SosLocationPrecision locationPrecision = SosLocationPrecision.approximate,
  }) async {
    if (activatingEmergency || rescueMode) return;
    if (drillModeEnabled) await deactivateDrill();
    activatingEmergency = true;
    DiagnosticsLog.instance.info('sos.activation.started');
    lastError = null;
    notifyListeners();
    try {
      if (localRole != MeshNodeRole.phoneRelay) {
        await updateNodeRole(MeshNodeRole.phoneRelay);
      }
      if (!canSend) {
        await start();
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (!canSend && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      if (!canSend) {
        throw StateError(currentL10n.errorEmergencyMeshUnavailable);
      }
      await setRescueMode(
        true,
        description: description ?? currentL10n.sosDefaultMessage,
        locationPrecision: locationPrecision,
      );
      DiagnosticsLog.instance.info('sos.activation.completed');
    } catch (error) {
      lastError = error.toString();
      DiagnosticsLog.instance.error('sos.activation.failed', error: error);
    } finally {
      activatingEmergency = false;
      notifyListeners();
    }
  }

  Future<Position?> _currentPosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        return await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: accuracy,
            timeLimit: const Duration(seconds: 10),
          ),
        );
      }
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.warning(
        'location.current.unavailable',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
    return null;
  }

  static double coarsenEmergencyCoordinate(double value) =>
      (value * 1000).round() / 1000;

  Future<void> updateNickname(String value) async {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return;
    await _platform.setNickname(cleaned);
    nickname = cleaned;
    notifyListeners();
  }

  Future<Uint8List> signPayload(Uint8List payload) =>
      _platform.signPayload(payload);

  Future<void> updateNodeRole(MeshNodeRole role) async {
    await _platform.setNodeRole(role.wireName);
    localRole = role;
    notifyListeners();
  }

  Future<void> setGenericPresenceScanEnabled(bool enabled) async {
    try {
      await _platform.setGenericPresenceScanEnabled(enabled);
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.warning(
        'mesh.generic_scan.unavailable',
        error: error,
        stackTrace: stackTrace,
        data: {'requestedEnabled': enabled},
      );
    }
  }

  Future<void> setSurvivalMode(bool enabled) async {
    if (enabled == survivalMode) return;
    if (enabled) {
      if (drillModeEnabled) await deactivateDrill();
      if (canSend) {
        await sendSos(currentL10n.sosDefaultMessage);
        await _platform.setRadarConsent(enabled: true, minutes: 20);
      }
      await _platform.configureRescueMode(active: false);
      rescueMode = false;
      rescueStartedAt = null;
      rescueExpiresAt = null;
      await updateNodeRole(MeshNodeRole.phoneBeacon);
    } else {
      await updateNodeRole(MeshNodeRole.phoneRelay);
    }
    survivalMode = enabled;
    notifyListeners();
  }

  Future<void> allowRadarFor15Minutes() async {
    if (drillModeEnabled) return;
    await _platform.setRadarConsent(enabled: true);
    radarConsentUntil = DateTime.now().add(const Duration(minutes: 15));
    await ensureAlwaysLocation();
    _syncRadarLocationSharing();
    notifyListeners();
  }

  Future<void> revokeRadarConsent() async {
    await _platform.setRadarConsent(enabled: false);
    radarConsentUntil = null;
    _stopRadarLocationSharing();
    notifyListeners();
  }

  Future<void> startLocalBeacon({
    int flags = BeaconControlFlags.all,
    Duration duration = BeaconControlProtocol.maximumDuration,
  }) async {
    if (drillModeEnabled) return;
    await _run<void>(
      () => _platform.startLocalBeacon(flags: flags, duration: duration),
    );
    if (lastError != null) return;
    final sos = latestSosQr;
    if (flags & BeaconControlFlags.sound != 0 && sos != null) {
      acousticSosBroadcasting = await _acousticSos.startBroadcast([
        sos.announcementFrame,
        sos.messageFrame,
      ]);
      notifyListeners();
    }
  }

  Future<void> stopLocalBeacon() async {
    await _run<void>(_platform.stopLocalBeacon);
    await (_providedAcousticSos ?? _createdAcousticSos)?.stopBroadcast();
    acousticSosBroadcasting = false;
    notifyListeners();
  }

  Future<bool> startAcousticSosListening() async {
    final started =
        await _run<bool>(
          () => _acousticSos.startListening((frame) async {
            await _run<void>(() => _platform.injectEmergencyLanFrame(frame));
          }),
        ) ??
        false;
    acousticSosListening = started;
    notifyListeners();
    return started;
  }

  Future<void> stopAcousticSosListening() async {
    await _acousticSos.stopListening();
    acousticSosListening = false;
    notifyListeners();
  }

  Future<void> respondToBeaconRequest(bool accept) async {
    final request = pendingBeaconRequest;
    if (request == null) return;
    pendingBeaconRequest = null;
    notifyListeners();
    await _run<void>(
      () => _platform.respondToBeaconRequest(
        requestId: request.requestId,
        accept: accept && !drillModeEnabled,
      ),
    );
  }

  void _syncRadarLocationSharing() {
    if (radarConsentActive && canSend) {
      unawaited(_startRadarLocationSharing());
    } else {
      _stopRadarLocationSharing();
    }
  }

  Future<void> _startRadarLocationSharing() async {
    if (_startingRadarLocationSharing ||
        _radarLocationTimer != null ||
        !radarConsentActive ||
        !canSend) {
      return;
    }
    _startingRadarLocationSharing = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }
      _radarLocationTimer ??= Timer.periodic(
        radarLocationInterval,
        (_) => unawaited(_shareLatestRadarLocation()),
      );
      final position = await _currentPosition(
        accuracy: rescueMode ? LocationAccuracy.high : LocationAccuracy.medium,
      );
      if (position != null) {
        _latestRadarPosition = position;
        await _shareRadarLocation(position, force: true);
      }
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.warning(
        'radar.location_sharing.stopped',
        error: error,
        stackTrace: stackTrace,
      );
      _stopRadarLocationSharing();
    } finally {
      _startingRadarLocationSharing = false;
    }
  }

  Future<void> _shareLatestRadarLocation() async {
    if (!radarConsentActive || !canSend) {
      _stopRadarLocationSharing();
      return;
    }
    final position = await _currentPosition(
      accuracy: rescueMode ? LocationAccuracy.high : LocationAccuracy.medium,
    );
    if (position != null) {
      _latestRadarPosition = position;
      await _shareRadarLocation(position);
    }
  }

  Future<void> _shareRadarLocation(
    Position position, {
    bool force = false,
  }) async {
    if (_sendingRadarLocation || !radarConsentActive || !canSend) return;
    final now = DateTime.now();
    final previous = _lastSharedRadarPosition;
    final moved = previous == null
        ? double.infinity
        : Geolocator.distanceBetween(
            previous.latitude,
            previous.longitude,
            position.latitude,
            position.longitude,
          );
    final elapsed = now.difference(
      _lastRadarLocationShareAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
    if (!force &&
        moved < radarLocationDistanceMeters &&
        elapsed < radarLocationInterval) {
      return;
    }
    final recipients = _peers
        .where(
          (peer) =>
              _isPeerOnline(peer, now) &&
              peer.secure &&
              peer.role.canChat &&
              peer.supportsTransfers,
        )
        .toList(growable: false);
    if (recipients.isEmpty) return;

    _sendingRadarLocation = true;
    var delivered = false;
    final content = RadarLocationUpdate.encode(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      timestamp: now,
    );
    try {
      for (final peer in recipients) {
        try {
          await _platform.sendPrivate(peer.id, content);
          delivered = true;
        } catch (error, stackTrace) {
          // La ubicación es efímera: nunca se encola para entrega posterior.
          DiagnosticsLog.instance.warning(
            'radar.location_update.not_delivered',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      if (delivered) {
        _lastSharedRadarPosition = position;
        _lastRadarLocationShareAt = now;
      }
    } finally {
      _sendingRadarLocation = false;
    }
  }

  void _stopRadarLocationSharing() {
    _radarLocationTimer?.cancel();
    _radarLocationTimer = null;
    _latestRadarPosition = null;
    _lastSharedRadarPosition = null;
    _lastRadarLocationShareAt = null;
  }

  Future<EmergencyDelivery> _enqueueEmergency({
    required EmergencyDeliveryKind kind,
    required String content,
    required Duration lifetime,
  }) async {
    final now = DateTime.now();
    final delivery = EmergencyDelivery(
      localId: _newEmergencyLocalId(),
      kind: kind,
      content: content,
      createdAt: now,
      expiresAt: now.add(lifetime),
      nextAttemptAt: now,
      state: EmergencyDeliveryState.pending,
    );
    await _repository.insertEmergencyDelivery(delivery);
    _emergencyDeliveries.insert(0, delivery);
    if (_emergencyDeliveries.length > 200) {
      _emergencyDeliveries.removeRange(200, _emergencyDeliveries.length);
    }
    notifyListeners();
    return delivery;
  }

  Future<void> _transmitEmergency(
    EmergencyDelivery requested, {
    required bool force,
  }) async {
    final index = _emergencyDeliveries.indexWhere(
      (delivery) => delivery.localId == requested.localId,
    );
    if (index < 0) return;
    var delivery = _emergencyDeliveries[index];
    final now = DateTime.now();
    if (delivery.state == EmergencyDeliveryState.acknowledged) return;
    if (!delivery.expiresAt.isAfter(now)) {
      await _replaceEmergencyDelivery(
        delivery.copyWith(state: EmergencyDeliveryState.expired),
      );
      return;
    }
    if (!force && (!canSend || delivery.nextAttemptAt.isAfter(now))) {
      _scheduleEmergencyRetry();
      return;
    }

    final attempt = delivery.attempts + 1;
    try {
      String? canonicalHash = delivery.canonicalHash;
      var transmitted = false;
      EmergencyTransmission? transmission;
      if (canonicalHash != null) {
        final retryHash = await _platform.retryEmergency(canonicalHash);
        if (retryHash != null) {
          canonicalHash = retryHash;
          transmitted = true;
        }
      }
      if (!transmitted) {
        transmission = await _platform.sendEmergency(
          messageId: delivery.localId,
          content: delivery.content,
          channel: delivery.kind == EmergencyDeliveryKind.sos
              ? 'sos'
              : 'checkin',
        );
        canonicalHash = transmission.canonicalHash;
      }
      if (delivery.kind == EmergencyDeliveryKind.sos &&
          transmission?.hasQrFrames == true) {
        latestSosQr = OpticalEmergencyBundle(
          announcementFrame: transmission!.announcementFrame!,
          messageFrame: transmission.messageFrame!,
          fallbackText: _emergencyQrFallback(delivery.content),
        );
      }
      delivery = delivery.copyWith(
        state: EmergencyDeliveryState.relayed,
        attempts: attempt,
        lastAttemptAt: now,
        nextAttemptAt: now.add(_emergencyBackoff(attempt)),
        canonicalHash: canonicalHash,
        clearLastError: true,
      );
      // El nativo transmite antes de devolver el hash. Persistirlo sin otro
      // await reduce al mínimo la carrera con un ACK que ya viene en camino.
      await _replaceEmergencyDelivery(delivery);
      DiagnosticsLog.instance.info(
        'emergency.outbox.relayed',
        data: {'kind': delivery.kind, 'attempt': attempt},
      );
    } catch (error, stackTrace) {
      delivery = delivery.copyWith(
        state: EmergencyDeliveryState.pending,
        attempts: attempt,
        lastAttemptAt: now,
        nextAttemptAt: now.add(_emergencyBackoff(attempt)),
        lastError: error.runtimeType.toString(),
      );
      await _replaceEmergencyDelivery(delivery);
      DiagnosticsLog.instance.warning(
        'emergency.outbox.transmit_failed',
        error: error,
        stackTrace: stackTrace,
        data: {'kind': delivery.kind, 'attempt': attempt},
      );
    }
    _scheduleEmergencyRetry();
  }

  Duration _emergencyBackoff(int attempts) {
    final exponent = min(max(attempts - 1, 0), 5);
    final seconds = min(
      15 * (1 << exponent),
      emergencyMaximumBackoff.inSeconds,
    );
    return Duration(seconds: seconds);
  }

  String _emergencyQrFallback(String content) {
    final fields = content.split('|');
    final description = fields.length > 1 && fields[1].trim().isNotEmpty
        ? fields[1].trim()
        : currentL10n.sosDefaultMessage;
    final coordinates =
        fields.length > 3 &&
            fields[2].trim().isNotEmpty &&
            fields[3].trim().isNotEmpty
        ? '\nGPS: ${fields[2].trim()}, ${fields[3].trim()}'
        : '';
    return 'HEARTHBIT SOS\n$description$coordinates\nID: $peerId';
  }

  Future<void> _replaceEmergencyDelivery(EmergencyDelivery delivery) async {
    await _repository.updateEmergencyDelivery(delivery);
    final index = _emergencyDeliveries.indexWhere(
      (item) => item.localId == delivery.localId,
    );
    if (index >= 0) {
      _emergencyDeliveries[index] = delivery;
    } else {
      _emergencyDeliveries.insert(0, delivery);
    }
    notifyListeners();
  }

  void _requestEmergencyOutboxDrain() {
    _emergencyOutboxDrainRequested = true;
    if (_drainingEmergencyOutbox) return;
    unawaited(_drainEmergencyOutbox());
  }

  Future<void> _drainEmergencyOutbox() async {
    _drainingEmergencyOutbox = true;
    try {
      while (_emergencyOutboxDrainRequested) {
        _emergencyOutboxDrainRequested = false;
        await _repository.expireEmergencyDeliveries(DateTime.now());
        _emergencyDeliveries
          ..clear()
          ..addAll(await _repository.loadEmergencyDeliveries());
        if (!canSend) break;
        final now = DateTime.now();
        final due = _emergencyDeliveries
            .where(
              (delivery) =>
                  !delivery.isTerminal && !delivery.nextAttemptAt.isAfter(now),
            )
            .toList(growable: false);
        for (final delivery in due) {
          await _transmitEmergency(delivery, force: false);
        }
      }
    } finally {
      _drainingEmergencyOutbox = false;
      _scheduleEmergencyRetry();
    }
  }

  void _scheduleEmergencyRetry() {
    _emergencyRetryTimer?.cancel();
    _emergencyRetryTimer = null;
    final active = _emergencyDeliveries
        .where((delivery) => !delivery.isTerminal)
        .toList(growable: false);
    if (active.isEmpty) return;
    active.sort(
      (first, second) => first.nextAttemptAt.compareTo(second.nextAttemptAt),
    );
    final delay = active.first.nextAttemptAt.difference(DateTime.now());
    _emergencyRetryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      _requestEmergencyOutboxDrain,
    );
  }

  String _newEmergencyLocalId() {
    final randomPart = List.generate(
      8,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'EMG-${DateTime.now().microsecondsSinceEpoch}-$randomPart';
  }

  Future<void> panicWipe() async {
    await setRescueMode(false);
    await (_providedAcousticSos ?? _createdAcousticSos)?.stopListening();
    acousticSosListening = false;
    await _preferences?.setMeshDesiredActive(false);
    final freshIdentity = await _platform.panicWipe();
    await _repository.destroy();
    _messages.clear();
    peerLocations.clear();
    _privateMessageOutbox.clear();
    _emergencyDeliveries.clear();
    _emergencyRetryTimer?.cancel();
    _emergencyRetryTimer = null;
    _peers.clear();
    _knownPeers.clear();
    _presences.clear();
    lastError = null;
    if (freshIdentity.isEmpty) {
      status = MeshConnectionStatus.stopped;
      nickname = '';
      peerId = '';
      signingPublicKey = null;
    } else {
      _applyStatus(freshIdentity);
    }
    radarConsentUntil = null;
    pendingBeaconRequest = null;
    localBeaconActive = false;
    localBeaconExpiresAt = null;
    _stopRadarLocationSharing();
    notifyListeners();
  }

  Future<T?> _run<T>(Future<T> Function() action) async {
    final hadError = lastError != null;
    lastError = null;
    try {
      final result = await action();
      if (hadError) notifyListeners();
      return result;
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<PrivateMessageSendResult> _enqueuePrivateMessage(
    String recipientPeerId,
    String content, {
    String? localId,
  }) async {
    final pending = PendingPrivateMessage(
      localId: localId ?? _newPrivateMessageLocalId(),
      recipientPeerId: recipientPeerId,
      content: content,
      createdAt: DateTime.now(),
    );
    try {
      await _repository.insertPendingPrivateMessage(pending);
      _privateMessageOutbox.add(pending);
      _messages.add(_pendingMessage(pending));
      _messages.sort(
        (first, second) => first.timestamp.compareTo(second.timestamp),
      );
      _trimMessagesInMemory();
      notifyListeners();
      return const PrivateMessageSendResult.queued();
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return PrivateMessageSendResult.failed(lastError!);
    }
  }

  String _newPrivateMessageLocalId() {
    final randomPart = _random.nextInt(0x7fffffff).toRadixString(16);
    return 'dm-${DateTime.now().microsecondsSinceEpoch}-$randomPart';
  }

  MeshMessage _pendingMessage(PendingPrivateMessage pending) {
    return MeshMessage(
      id: pending.localId,
      sender: nickname,
      content: pending.content,
      senderPeerId: pending.recipientPeerId,
      isPrivate: true,
      isMine: true,
      timestamp: pending.createdAt,
      deliveryStatus: pending.status == PrivateMessageOutboxStatus.expired
          ? MeshMessageDeliveryStatus.expired
          : MeshMessageDeliveryStatus.pending,
    );
  }

  Future<void> _recordSentPrivateMessage({
    required String id,
    required String recipientPeerId,
    required String content,
    required DateTime timestamp,
  }) async {
    if (_messages.any((message) => message.id == id)) return;
    final message = MeshMessage(
      id: id,
      sender: nickname,
      content: content,
      senderPeerId: recipientPeerId,
      isPrivate: true,
      isMine: true,
      timestamp: timestamp,
    );
    _messages.add(message);
    _messages.sort(
      (first, second) => first.timestamp.compareTo(second.timestamp),
    );
    _trimMessagesInMemory();
    await _repository.save(message);
    notifyListeners();
  }

  void _requestPrivateMessageOutboxDrain() {
    _privateMessageOutboxDrainRequested = true;
    if (!_drainingPrivateMessageOutbox) {
      unawaited(_drainPrivateMessageOutbox());
    }
  }

  Future<void> retryPendingPrivateMessages() async {
    _privateMessageOutboxDrainRequested = true;
    final activeDrain = _privateMessageOutboxDrainCompleter;
    if (activeDrain != null) {
      await activeDrain.future;
      return;
    }
    await _drainPrivateMessageOutbox();
  }

  Future<void> _drainPrivateMessageOutbox() async {
    if (_drainingPrivateMessageOutbox) {
      await _privateMessageOutboxDrainCompleter?.future;
      return;
    }
    _drainingPrivateMessageOutbox = true;
    final completer = Completer<void>();
    _privateMessageOutboxDrainCompleter = completer;
    try {
      do {
        _privateMessageOutboxDrainRequested = false;
        await _drainPrivateMessageOutboxOnce();
      } while (_privateMessageOutboxDrainRequested);
    } finally {
      _drainingPrivateMessageOutbox = false;
      _privateMessageOutboxDrainCompleter = null;
      completer.complete();
    }
  }

  Future<void> _drainPrivateMessageOutboxOnce() async {
    if (!canSend || _privateMessageOutbox.isEmpty) return;
    for (final original in List<PendingPrivateMessage>.of(
      _privateMessageOutbox,
    )) {
      if (original.status == PrivateMessageOutboxStatus.expired) continue;
      if (original.attempts >= 20 ||
          original.createdAt.isBefore(
            DateTime.now().subtract(const Duration(days: 7)),
          )) {
        final expired = original.copyWith(
          status: PrivateMessageOutboxStatus.expired,
        );
        _replacePendingOutboxEntry(expired);
        await _repository.updatePendingPrivateMessage(expired);
        final messageIndex = _messages.indexWhere(
          (message) => message.id == expired.localId,
        );
        if (messageIndex >= 0) {
          _messages[messageIndex] = _pendingMessage(expired);
        }
        notifyListeners();
        continue;
      }
      final peer = peerById(original.recipientPeerId);
      if (peer == null || !peer.secure || !canChatWithPeer(peer)) continue;
      var pending = original.copyWith(
        attempts: original.attempts + 1,
        status: PrivateMessageOutboxStatus.retrying,
        lastError: null,
      );
      try {
        await _repository.updatePendingPrivateMessage(pending);
        _replacePendingOutboxEntry(pending);
        final messageId = await _platform.sendPrivate(
          pending.recipientPeerId,
          pending.content,
          messageId: pending.localId,
        );
        if (messageId.trim().isEmpty) {
          throw StateError(currentL10n.errorUnknown);
        }
        await _repository.deletePendingPrivateMessage(pending.localId);
        _privateMessageOutbox.removeWhere(
          (item) => item.localId == pending.localId,
        );
        _messages.removeWhere((message) => message.id == pending.localId);
        await _recordSentPrivateMessage(
          id: messageId,
          recipientPeerId: pending.recipientPeerId,
          content: pending.content,
          timestamp: pending.createdAt,
        );
      } catch (error) {
        pending = pending.copyWith(
          status: PrivateMessageOutboxStatus.pending,
          lastError: error.toString(),
        );
        _replacePendingOutboxEntry(pending);
        await _repository.updatePendingPrivateMessage(pending);
        notifyListeners();
      }
    }
  }

  void _replacePendingOutboxEntry(PendingPrivateMessage pending) {
    final index = _privateMessageOutbox.indexWhere(
      (item) => item.localId == pending.localId,
    );
    if (index >= 0) _privateMessageOutbox[index] = pending;
  }

  void _trimMessagesInMemory() {
    if (_messages.length <= maximumMessagesInMemory) return;
    final pendingIds = _privateMessageOutbox
        .map((message) => message.localId)
        .toSet();
    while (_messages.length > maximumMessagesInMemory) {
      final removable = _messages.indexWhere(
        (message) => !pendingIds.contains(message.id),
      );
      _messages.removeAt(removable >= 0 ? removable : 0);
    }
  }

  void _scheduleTopologyNotification() {
    final now = DateTime.now();
    final last = _lastTopologyNotificationAt;
    final elapsed = last == null
        ? topologyNotificationInterval
        : now.difference(last);
    if (elapsed >= topologyNotificationInterval) {
      _topologyNotificationTimer?.cancel();
      _topologyNotificationTimer = null;
      _lastTopologyNotificationAt = now;
      notifyListeners();
      return;
    }
    if (_topologyNotificationTimer != null) return;
    _topologyNotificationTimer = Timer(
      topologyNotificationInterval - elapsed,
      () {
        _topologyNotificationTimer = null;
        _lastTopologyNotificationAt = DateTime.now();
        notifyListeners();
      },
    );
  }

  void _handleEvent(MeshNativeEvent event) {
    switch (event) {
      case MeshSnapshotEvent():
        _applyStatus(event.raw);
        _replacePeers(event.raw['peers']);
        _replacePresences(event.raw['presences']);
      case MeshStatusEvent():
        _applyStatus(event.raw);
      case MeshPowerEvent():
        batteryLevel = event.batteryLevel ?? batteryLevel;
        powerProfile = MeshPowerProfile.fromWire(event.powerProfile);
        adaptivePowerSaving =
            event.adaptivePowerSaving ?? powerProfile.savesPower;
      case MeshPeersEvent():
        _replacePeers(event.peers);
        _scheduleTopologyNotification();
        return;
      case MeshPresencesEvent():
        _replacePresences(event.presences);
        _scheduleTopologyNotification();
        return;
      case MeshRadarConsentEvent():
        _applyRadarConsent(event.raw);
        _replacePeers(event.raw['peers']);
      case MeshBeaconRequestEvent():
        _applyBeaconRequest(event.raw);
      case MeshBeaconRequestResolvedEvent():
        if (pendingBeaconRequest?.requestId == event.requestId) {
          pendingBeaconRequest = null;
        }
      case MeshBeaconStateEvent():
        if (event.scope == 'local') {
          _applyLocalBeaconState(event.raw);
        }
      case MeshMessageEvent():
        final message = event.message;
        if (message == null) break;
        if (message.isRadarLocation) {
          peerLocations.ingestLive(message);
          break;
        }
        if (_messages.every((existing) => existing.id != message.id)) {
          _messages.add(message);
          _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          _trimMessagesInMemory();
          peerLocations.ingestPersisted(message);
          unawaited(_repository.save(message));
        }
      case MeshErrorEvent():
        lastError = event.message ?? currentL10n.errorUnknown;
        DiagnosticsLog.instance.warning(
          'mesh.native.error',
          data: {'whileStarting': status == MeshConnectionStatus.starting},
        );
        if (status == MeshConnectionStatus.starting) {
          status = MeshConnectionStatus.error;
        }
      case MeshWipedEvent():
        _messages.clear();
        peerLocations.clear();
        _peers.clear();
        _presences.clear();
        _knownPeers.clear();
        _applyStatus(event.raw);
        radarConsentUntil = null;
        pendingBeaconRequest = null;
        localBeaconActive = false;
        localBeaconExpiresAt = null;
        _stopRadarLocationSharing();
      case MeshEmergencyAckEvent():
        final canonicalHash = event.canonicalHash;
        final acknowledgingPeerId = event.peerId;
        if (canonicalHash != null && acknowledgingPeerId != null) {
          unawaited(
            _recordEmergencyAcknowledgement(canonicalHash, acknowledgingPeerId),
          );
        }
      case MeshRescuePingEvent():
        final timestamp = event.timestamp;
        if (timestamp != null && timestamp > 0) {
          lastRescuePing = DateTime.fromMillisecondsSinceEpoch(timestamp);
        }
      case MeshRssiEvent() || MeshRadarDiagnosticEvent():
        // Lecturas y avisos del radar de rescate: los consume RadarScreen
        // directamente del stream; evitar redibujar toda la app.
        return;
      case MeshRangingMeasurementEvent() ||
          MeshRadioRangingStateEvent() ||
          MeshRangingControlEvent() ||
          MeshRadarExpiredEvent() ||
          MeshUnknownEvent():
        break;
    }
    notifyListeners();
  }

  void _handleEventSafely(MeshNativeEvent event) {
    try {
      _handleEvent(event);
    } on FormatException catch (error, stackTrace) {
      DiagnosticsLog.instance.warning(
        'mesh.event.invalid',
        error: error,
        stackTrace: stackTrace,
      );
    } on TypeError catch (error, stackTrace) {
      DiagnosticsLog.instance.warning(
        'mesh.event.invalid_type',
        error: error,
        stackTrace: stackTrace,
      );
    } on RangeError catch (error, stackTrace) {
      DiagnosticsLog.instance.warning(
        'mesh.event.invalid_range',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.warning(
        'mesh.event.rejected',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _recordEmergencyAcknowledgement(
    String canonicalHash,
    String acknowledgingPeerId,
  ) async {
    var localId = await _repository.recordEmergencyAcknowledgement(
      canonicalHash: canonicalHash,
      peerId: acknowledgingPeerId,
      acknowledgedAt: DateTime.now(),
    );
    if (localId == null) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      localId = await _repository.recordEmergencyAcknowledgement(
        canonicalHash: canonicalHash,
        peerId: acknowledgingPeerId,
        acknowledgedAt: DateTime.now(),
      );
    }
    if (localId == null) return;
    _emergencyDeliveries
      ..clear()
      ..addAll(await _repository.loadEmergencyDeliveries());
    _scheduleEmergencyRetry();
    DiagnosticsLog.instance.info('emergency.outbox.acknowledged');
    notifyListeners();
  }

  void _applyStatus(Map<Object?, Object?> event) {
    final couldSend = canSend;
    final previousStatus = status;
    status = switch (event['status'] as String?) {
      'active' => MeshConnectionStatus.active,
      'degraded' => MeshConnectionStatus.degraded,
      'starting' => MeshConnectionStatus.starting,
      'error' => MeshConnectionStatus.error,
      _ => MeshConnectionStatus.stopped,
    };
    if (status != previousStatus) {
      DiagnosticsLog.instance.info(
        'mesh.status.changed',
        data: {'from': previousStatus, 'to': status},
      );
    }
    nickname = event['nickname'] as String? ?? nickname;
    peerId = event['peerId'] as String? ?? peerId;
    signingPublicKey = switch (event['signingPublicKey']) {
      final Uint8List value when value.length == 32 => value,
      final List<int> value when value.length == 32 => Uint8List.fromList(
        value,
      ),
      _ => signingPublicKey,
    };
    localRole = MeshNodeRole.fromWire(event['role']);
    survivalMode = localRole == MeshNodeRole.phoneBeacon && !drillModeEnabled;
    if (drillModeEnabled && localRole == MeshNodeRole.phoneBeacon) {
      unawaited(updateNodeRole(MeshNodeRole.phoneRelay));
    }
    if (event.containsKey('localBeaconActive')) {
      localBeaconActive = event['localBeaconActive'] as bool? ?? false;
      final expiresAt = (event['localBeaconExpiresAt'] as num?)?.toInt() ?? 0;
      localBeaconExpiresAt = localBeaconActive && expiresAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(expiresAt)
          : null;
    }
    batteryLevel = (event['batteryLevel'] as num?)?.toInt() ?? batteryLevel;
    powerProfile = MeshPowerProfile.fromWire(event['powerProfile']);
    adaptivePowerSaving =
        event['adaptivePowerSaving'] as bool? ?? powerProfile.savesPower;
    final metrics = event['resourceMetrics'];
    if (metrics is Map<Object?, Object?>) {
      bleDutyCyclePercent =
          (metrics['bleDutyCyclePercent'] as num?)?.toInt() ??
          bleDutyCyclePercent;
      activeBleScans =
          (metrics['activeScans'] as num?)?.toInt() ?? activeBleScans;
      meshScanActive = activeBleScans > 0;
      scanStarts = (metrics['scanStarts'] as num?)?.toInt() ?? scanStarts;
      storeForwardEntries =
          (metrics['storeForwardEntries'] as num?)?.toInt() ??
          storeForwardEntries;
      DiagnosticsLog.instance.info(
        'mesh.resource.stats',
        data: {
          'bleDutyCyclePercent':
              (metrics['bleDutyCyclePercent'] as num?)?.toInt() ?? -1,
          'activeScans': (metrics['activeScans'] as num?)?.toInt() ?? -1,
          'scanStarts': (metrics['scanStarts'] as num?)?.toInt() ?? -1,
          'storeForwardEntries':
              (metrics['storeForwardEntries'] as num?)?.toInt() ?? -1,
        },
      );
    }
    final links = event['links'];
    if (links is List<Object?>) {
      activeTransports = links
          .whereType<Map<Object?, Object?>>()
          .map((link) => link['kind'])
          .whereType<String>()
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toSet();
    }
    _applyRadarConsent(event);
    if (!couldSend && canSend) {
      _requestPrivateMessageOutboxDrain();
      _requestEmergencyOutboxDrain();
    }
    _syncRadarLocationSharing();
  }

  void _applyRadarConsent(Map<Object?, Object?> event) {
    final value = event['radarConsentUntil'];
    if (value is num) {
      radarConsentUntil = value.toInt() > 0
          ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
          : null;
      _syncRadarLocationSharing();
    }
  }

  void _applyBeaconRequest(Map<Object?, Object?> event) {
    if (event['autoAccepted'] == true) return;
    final requestId = event['requestId'] as String?;
    final peerId = event['peerId'] as String?;
    final expiresAt = (event['expiresAt'] as num?)?.toInt();
    final flags = (event['flags'] as num?)?.toInt();
    if (requestId == null ||
        peerId == null ||
        expiresAt == null ||
        flags == null ||
        expiresAt <= DateTime.now().millisecondsSinceEpoch) {
      return;
    }
    pendingBeaconRequest = PendingBeaconRequest(
      requestId: requestId,
      peerId: peerId,
      nickname:
          event['nickname'] as String? ??
          (peerId.length > 8 ? peerId.substring(0, 8) : peerId),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt),
      flags: flags,
    );
  }

  void _applyLocalBeaconState(Map<Object?, Object?> event) {
    localBeaconActive = event['status'] == 'active';
    final expiresAt = (event['expiresAt'] as num?)?.toInt() ?? 0;
    localBeaconExpiresAt = localBeaconActive && expiresAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(expiresAt)
        : null;
    if (drillModeEnabled && localBeaconActive) {
      unawaited(stopLocalBeacon());
    }
  }

  void _replacePeers(Object? value) {
    final now = DateTime.now();
    final previouslyEligible = {
      for (final peer in _peers)
        if (_isPeerOnline(peer, now) && peer.secure && peer.role.canChat)
          peer.id,
    };
    final rawPeers = value as List<Object?>? ?? const [];
    _peers
      ..clear()
      ..addAll(
        rawPeers
            .whereType<Map<Object?, Object?>>()
            .map(MeshPeer.tryParse)
            .whereType<MeshPeer>(),
      );
    for (final peer in _peers) {
      _knownPeers[peer.id] = peer;
    }
    if (_peers.isNotEmpty) {
      unawaited(_repository.saveKnownPeers(_peers));
    }
    final hasNewlyEligiblePeer = _peers.any(
      (peer) =>
          _isPeerOnline(peer, now) &&
          peer.secure &&
          peer.role.canChat &&
          !previouslyEligible.contains(peer.id),
    );
    if (hasNewlyEligiblePeer) {
      _requestPrivateMessageOutboxDrain();
    }
    final hasRadarRecipient = _peers.any(
      (peer) =>
          _isPeerOnline(peer, now) &&
          peer.secure &&
          peer.role.canChat &&
          peer.supportsTransfers &&
          !previouslyEligible.contains(peer.id),
    );
    if (hasRadarRecipient && radarConsentActive) {
      final position = _latestRadarPosition;
      if (position != null) {
        unawaited(_shareRadarLocation(position, force: true));
      } else {
        _syncRadarLocationSharing();
      }
    }
    _ensurePendingPrivateChannels();
  }

  void _ensurePendingPrivateChannels() {
    if (!canSend || _privateMessageOutbox.isEmpty) return;
    final pendingRecipients = _privateMessageOutbox
        .map((message) => message.recipientPeerId)
        .toSet();
    for (final peer in _peers) {
      if (!_isPeerOnline(peer, DateTime.now()) ||
          peer.secure ||
          !peer.role.canChat ||
          !pendingRecipients.contains(peer.id)) {
        continue;
      }
      unawaited(_run<void>(() => _platform.ensurePrivateChannel(peer.id)));
    }
  }

  void _replacePresences(Object? value) {
    final rawPresences = value as List<Object?>? ?? const [];
    _presences
      ..clear()
      ..addAll(
        rawPresences
            .whereType<Map<Object?, Object?>>()
            .map(GenericBlePresence.tryParse)
            .whereType<GenericBlePresence>(),
      );
  }

  String _conversationNickname(String peerId) {
    for (final message in _messages.reversed) {
      if (message.isPrivate &&
          message.senderPeerId == peerId &&
          !message.isMine) {
        return message.sender;
      }
    }
    return peerId.length >= 8 ? peerId.substring(0, 8) : peerId;
  }

  bool _isPeerOnline(MeshPeer peer, DateTime now) =>
      peer.isOnlineAt(now, freshnessWindow: peerReachabilityWindow);

  void _notifyLocationChanged() => notifyListeners();

  void _handlePreferencesChanged() {
    final enabled = _preferences?.drillModeEnabled ?? false;
    var changed = false;
    if (enabled != _drillModeEnabled) {
      _drillModeEnabled = enabled;
      if (enabled) unawaited(_enforceDrillIsolation());
      changed = true;
    }
    final privateMode = _preferences?.privacyPrivateMode ?? true;
    final interop = _preferences?.bitchatInteropEnabled ?? false;
    if (privateMode != _privateMode || interop != _bitchatInteropEnabled) {
      _privateMode = privateMode;
      _bitchatInteropEnabled = interop;
      unawaited(
        _platform.configurePrivacyMode(
          privateMode: privateMode,
          bitchatInteropEnabled: interop,
        ),
      );
      changed = true;
    }
    final meshtastic = _preferences?.meshtasticEnabled ?? false;
    if (meshtastic != _meshtasticEnabled) {
      _meshtasticEnabled = meshtastic;
      if (supportsMeshtastic) {
        unawaited(_platform.configureMeshtasticBridge(enabled: meshtastic));
      }
      changed = true;
    }
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _consentTimer?.cancel();
    _topologyNotificationTimer?.cancel();
    _emergencyRetryTimer?.cancel();
    _stopRadarLocationSharing();
    _subscription?.cancel();
    _preferences?.removeListener(_handlePreferencesChanged);
    peerLocations.removeListener(_notifyLocationChanged);
    peerLocations.dispose();
    unawaited(_repository.close());
    final acousticSos = _providedAcousticSos ?? _createdAcousticSos;
    if (acousticSos != null) unawaited(acousticSos.dispose());
    super.dispose();
  }
}
