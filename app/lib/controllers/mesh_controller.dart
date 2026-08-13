import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../services/beacon_control_protocol.dart';
import '../services/mesh_platform_service.dart';
import '../services/message_repository.dart';
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
  }) : _platform = platform ?? MeshPlatformService(),
       _repository = repository ?? MessageRepository(),
       peerLocations = locationTracker ?? PeerLocationTracker() {
    peerLocations.addListener(_notifyLocationChanged);
  }

  /// Intervalo entre reenvíos de SOS con GPS fresco en modo rescate: lo
  /// bastante frecuente para seguir a una persona que se mueve, lo bastante
  /// espaciado para no agotar batería ni saturar la malla.
  static const Duration rescueInterval = Duration(minutes: 5);
  static const Duration radarLocationInterval = Duration(seconds: 20);
  static const int radarLocationDistanceMeters = 15;

  final MeshPlatformService _platform;
  final MessageRepository _repository;
  final PeerLocationTracker peerLocations;
  final List<MeshMessage> _messages = [];
  final List<MeshPeer> _peers = [];
  final List<GenericBlePresence> _presences = [];
  final Map<String, MeshPeer> _knownPeers = {};
  final List<PendingPrivateMessage> _privateMessageOutbox = [];
  final Random _random = Random.secure();

  StreamSubscription<Map<Object?, Object?>>? _subscription;
  StreamSubscription<Position>? _radarPositionSubscription;
  bool _drainingPrivateMessageOutbox = false;
  bool _privateMessageOutboxDrainRequested = false;
  bool _startingRadarLocationSharing = false;
  bool _sendingRadarLocation = false;
  Completer<void>? _privateMessageOutboxDrainCompleter;
  MeshConnectionStatus status = MeshConnectionStatus.stopped;
  String nickname = '';
  String peerId = '';
  MeshNodeRole localRole = MeshNodeRole.phoneRelay;
  String? lastError;
  bool supportsBackgroundRelay = false;
  DateTime? radarConsentUntil;
  PendingBeaconRequest? pendingBeaconRequest;
  bool localBeaconActive = false;
  DateTime? localBeaconExpiresAt;

  // Modo rescate: reenvía el SOS con ubicación actualizada periódicamente.
  bool rescueMode = false;
  bool activatingEmergency = false;
  DateTime? lastRescuePing;
  Timer? _rescueTimer;
  Timer? _consentTimer;
  Timer? _radarLocationTimer;
  Position? _latestRadarPosition;
  Position? _lastSharedRadarPosition;
  DateTime? _lastRadarLocationShareAt;

  /// Vacía significa «usar el texto por defecto localizado» ([sendSos]).
  String _rescueDescription = '';

  // Estado de energía/ubicación reportado por el sistema.
  bool ignoringBatteryOptimizations = true;
  bool lowPowerMode = false;
  bool backgroundLocationGranted = false;
  int batteryLevel = 100;
  MeshPowerProfile powerProfile = MeshPowerProfile.balanced;
  bool adaptivePowerSaving = false;
  bool survivalMode = false;

  List<MeshMessage> get messages => List.unmodifiable(_messages);
  List<MeshPeer> get peers => List.unmodifiable(_peers);
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

  bool isPeerOnline(String id) => _peers.any((peer) => peer.id == id);
  MeshPeer? peerById(String id) {
    for (final peer in _peers) {
      if (peer.id == id) return peer;
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
    final onlineById = {for (final peer in _peers) peer.id: peer};
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
    _privateMessageOutbox
      ..clear()
      ..addAll(await _repository.listPendingPrivateMessages());
    for (final pending in _privateMessageOutbox) {
      if (_messages.every((message) => message.id != pending.localId)) {
        _messages.add(_pendingMessage(pending));
      }
    }
    _messages.sort(
      (first, second) => first.timestamp.compareTo(second.timestamp),
    );
    _subscription = _platform.events.listen(_handleEvent);
    final capabilities = await _platform.getCapabilities();
    supportsBackgroundRelay = capabilities['backgroundRelay'] as bool? ?? false;
    await refreshPowerStatus();
    _consentTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (radarConsentUntil != null && !radarConsentActive) {
        radarConsentUntil = null;
        _syncRadarLocationSharing();
      }
      if (pendingBeaconRequest?.expiresAt.isAfter(DateTime.now()) == false) {
        pendingBeaconRequest = null;
      }
      notifyListeners();
    });
    _requestPrivateMessageOutboxDrain();
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
  }) async {
    if (!enabled) {
      _rescueTimer?.cancel();
      _rescueTimer = null;
      rescueMode = false;
      _stopRadarLocationSharing();
      await revokeRadarConsent();
      notifyListeners();
      return;
    }
    if (description != null && description.trim().isNotEmpty) {
      _rescueDescription = description.trim();
    }
    rescueMode = true;
    notifyListeners();
    await _platform.setRadarConsent(enabled: true, minutes: 10);
    await ensureAlwaysLocation();
    await _rescuePing();
    _rescueTimer?.cancel();
    _rescueTimer = Timer.periodic(
      interval ?? rescueInterval,
      (_) => unawaited(_rescuePing()),
    );
  }

  Future<void> _rescuePing() async {
    if (!rescueMode) return;
    await _platform.setRadarConsent(enabled: true, minutes: 10);
    await sendSos(_rescueDescription);
    lastRescuePing = DateTime.now();
    notifyListeners();
  }

  Future<void> start() async {
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
    } catch (error) {
      status = MeshConnectionStatus.error;
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await setRescueMode(false);
    _stopRadarLocationSharing();
    await _platform.stop();
    status = MeshConnectionStatus.stopped;
    _presences.clear();
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
    if (!peer.role.canChat || cleaned.isEmpty) {
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

    final messageId = await _run(
      () => _platform.sendPrivate(currentPeer.id, cleaned),
    );
    if (messageId == null || messageId.trim().isEmpty) {
      final error = lastError ?? currentL10n.errorUnknown;
      if (messageId != null) {
        lastError = error;
        notifyListeners();
      }
      return PrivateMessageSendResult.failed(error);
    }
    await _recordSentPrivateMessage(
      id: messageId,
      recipientPeerId: currentPeer.id,
      content: cleaned,
      timestamp: DateTime.now(),
    );
    return const PrivateMessageSendResult.sent();
  }

  Future<void> sendSos(String description) async {
    final position = await _currentPosition();
    await _run(
      () => _platform.sendSos(
        content: description.trim().isEmpty
            ? currentL10n.sosDefaultMessage
            : description.trim(),
        latitude: position?.latitude,
        longitude: position?.longitude,
      ),
    );
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
    await _run(() => _platform.sendPublic(content, channel: 'checkin'));
  }

  Future<void> activateEmergency({String? description}) async {
    if (activatingEmergency || rescueMode) return;
    activatingEmergency = true;
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
      );
    } catch (error) {
      lastError = error.toString();
    } finally {
      activatingEmergency = false;
      notifyListeners();
    }
  }

  Future<Position?> _currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> updateNickname(String value) async {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return;
    await _platform.setNickname(cleaned);
    nickname = cleaned;
    notifyListeners();
  }

  Future<void> updateNodeRole(MeshNodeRole role) async {
    await _platform.setNodeRole(role.wireName);
    localRole = role;
    notifyListeners();
  }

  Future<void> setSurvivalMode(bool enabled) async {
    if (enabled == survivalMode) return;
    if (enabled) {
      if (canSend) {
        await sendSos(currentL10n.sosDefaultMessage);
        await _platform.setRadarConsent(enabled: true, minutes: 20);
      }
      _rescueTimer?.cancel();
      _rescueTimer = null;
      rescueMode = false;
      await updateNodeRole(MeshNodeRole.phoneBeacon);
    } else {
      await updateNodeRole(MeshNodeRole.phoneRelay);
    }
    survivalMode = enabled;
    notifyListeners();
  }

  Future<void> allowRadarFor15Minutes() async {
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
    await _run<void>(
      () => _platform.startLocalBeacon(flags: flags, duration: duration),
    );
  }

  Future<void> stopLocalBeacon() async {
    await _run<void>(_platform.stopLocalBeacon);
  }

  Future<void> respondToBeaconRequest(bool accept) async {
    final request = pendingBeaconRequest;
    if (request == null) return;
    pendingBeaconRequest = null;
    notifyListeners();
    await _run<void>(
      () => _platform.respondToBeaconRequest(
        requestId: request.requestId,
        accept: accept,
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
        _radarPositionSubscription != null ||
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
      _radarPositionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: radarLocationDistanceMeters,
            ),
          ).listen((position) {
            _latestRadarPosition = position;
            unawaited(_shareRadarLocation(position));
          }, onError: (_) {});
      _radarLocationTimer ??= Timer.periodic(
        radarLocationInterval,
        (_) => unawaited(_shareLatestRadarLocation()),
      );
      final position = await _currentPosition();
      if (position != null) {
        _latestRadarPosition = position;
        await _shareRadarLocation(position, force: true);
      }
    } catch (_) {
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
    final position = _latestRadarPosition ?? await _currentPosition();
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
          (peer) => peer.secure && peer.role.canChat && peer.supportsTransfers,
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
        } catch (_) {
          // La ubicación es efímera: nunca se encola para entrega posterior.
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
    final subscription = _radarPositionSubscription;
    _radarPositionSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    _latestRadarPosition = null;
    _lastSharedRadarPosition = null;
    _lastRadarLocationShareAt = null;
  }

  Future<void> panicWipe() async {
    await setRescueMode(false);
    await _platform.panicWipe();
    await _repository.clear();
    _messages.clear();
    peerLocations.clear();
    _privateMessageOutbox.clear();
    _peers.clear();
    _knownPeers.clear();
    status = MeshConnectionStatus.stopped;
    nickname = '';
    peerId = '';
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
    String content,
  ) async {
    final pending = PendingPrivateMessage(
      localId: _newPrivateMessageLocalId(),
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
      deliveryStatus: MeshMessageDeliveryStatus.pending,
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
      final peer = peerById(original.recipientPeerId);
      if (peer == null || !peer.secure || !peer.role.canChat) continue;
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

  void _handleEvent(Map<Object?, Object?> event) {
    switch (event['type']) {
      case 'snapshot':
        _applyStatus(event);
        _replacePeers(event['peers']);
        _replacePresences(event['presences']);
        break;
      case 'status':
        _applyStatus(event);
        break;
      case 'power':
        batteryLevel = (event['batteryLevel'] as num?)?.toInt() ?? batteryLevel;
        powerProfile = MeshPowerProfile.fromWire(event['powerProfile']);
        adaptivePowerSaving =
            event['adaptivePowerSaving'] as bool? ?? powerProfile.savesPower;
        break;
      case 'peers':
        _replacePeers(event['peers']);
        break;
      case 'presences':
        _replacePresences(event['presences']);
        break;
      case 'radarConsent':
        _applyRadarConsent(event);
        _replacePeers(event['peers']);
        break;
      case 'beaconRequest':
        _applyBeaconRequest(event);
        break;
      case 'beaconRequestResolved':
        if (pendingBeaconRequest?.requestId == event['requestId']) {
          pendingBeaconRequest = null;
        }
        break;
      case 'beaconState':
        if (event['scope'] == 'local') {
          _applyLocalBeaconState(event);
        }
        break;
      case 'message':
        final rawMessage = event['message'];
        if (rawMessage is Map<Object?, Object?>) {
          final message = MeshMessage.fromMap(rawMessage);
          if (message.isRadarLocation) {
            peerLocations.ingestLive(message);
            break;
          }
          if (_messages.every((existing) => existing.id != message.id)) {
            _messages.add(message);
            _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
            peerLocations.ingestPersisted(message);
            unawaited(_repository.save(message));
          }
        }
        break;
      case 'error':
        lastError = event['message'] as String? ?? currentL10n.errorUnknown;
        if (status == MeshConnectionStatus.starting) {
          status = MeshConnectionStatus.error;
        }
        break;
      case 'wiped':
        _messages.clear();
        peerLocations.clear();
        _peers.clear();
        _presences.clear();
        _knownPeers.clear();
        status = MeshConnectionStatus.stopped;
        radarConsentUntil = null;
        pendingBeaconRequest = null;
        localBeaconActive = false;
        localBeaconExpiresAt = null;
        _stopRadarLocationSharing();
        break;
      case 'rssi':
        // Lecturas del radar de rescate: las consume RadarScreen directamente
        // del stream; evitar redibujar toda la app varias veces por segundo.
        return;
      default:
        break;
    }
    notifyListeners();
  }

  void _applyStatus(Map<Object?, Object?> event) {
    final couldSend = canSend;
    status = switch (event['status'] as String?) {
      'active' => MeshConnectionStatus.active,
      'degraded' => MeshConnectionStatus.degraded,
      'starting' => MeshConnectionStatus.starting,
      'error' => MeshConnectionStatus.error,
      _ => MeshConnectionStatus.stopped,
    };
    nickname = event['nickname'] as String? ?? nickname;
    peerId = event['peerId'] as String? ?? peerId;
    localRole = MeshNodeRole.fromWire(event['role']);
    survivalMode = localRole == MeshNodeRole.phoneBeacon;
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
    _applyRadarConsent(event);
    if (!couldSend && canSend) {
      _requestPrivateMessageOutboxDrain();
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
  }

  void _replacePeers(Object? value) {
    final previouslyEligible = {
      for (final peer in _peers)
        if (peer.secure && peer.role.canChat) peer.id,
    };
    final rawPeers = value as List<Object?>? ?? const [];
    _peers
      ..clear()
      ..addAll(
        rawPeers.whereType<Map<Object?, Object?>>().map(MeshPeer.fromMap),
      );
    for (final peer in _peers) {
      _knownPeers[peer.id] = peer;
    }
    if (_peers.isNotEmpty) {
      unawaited(_repository.saveKnownPeers(_peers));
    }
    final hasNewlyEligiblePeer = _peers.any(
      (peer) =>
          peer.secure &&
          peer.role.canChat &&
          !previouslyEligible.contains(peer.id),
    );
    if (hasNewlyEligiblePeer) {
      _requestPrivateMessageOutboxDrain();
    }
    final hasRadarRecipient = _peers.any(
      (peer) =>
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
      if (peer.secure ||
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
        rawPresences.whereType<Map<Object?, Object?>>().map(
          GenericBlePresence.fromMap,
        ),
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

  void _notifyLocationChanged() => notifyListeners();

  @override
  void dispose() {
    _rescueTimer?.cancel();
    _consentTimer?.cancel();
    _stopRadarLocationSharing();
    _subscription?.cancel();
    peerLocations.removeListener(_notifyLocationChanged);
    peerLocations.dispose();
    super.dispose();
  }
}
