import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../services/mesh_platform_service.dart';
import '../services/message_repository.dart';

class MeshController extends ChangeNotifier {
  MeshController({MeshPlatformService? platform, MessageRepository? repository})
    : _platform = platform ?? MeshPlatformService(),
      _repository = repository ?? MessageRepository();

  /// Intervalo entre reenvíos de SOS con GPS fresco en modo rescate: lo
  /// bastante frecuente para seguir a una persona que se mueve, lo bastante
  /// espaciado para no agotar batería ni saturar la malla.
  static const Duration rescueInterval = Duration(minutes: 5);

  final MeshPlatformService _platform;
  final MessageRepository _repository;
  final List<MeshMessage> _messages = [];
  final List<MeshPeer> _peers = [];

  StreamSubscription<Map<Object?, Object?>>? _subscription;
  MeshConnectionStatus status = MeshConnectionStatus.stopped;
  String nickname = '';
  String peerId = '';
  String? lastError;
  bool supportsBackgroundRelay = false;

  // Modo rescate: reenvía el SOS con ubicación actualizada periódicamente.
  bool rescueMode = false;
  DateTime? lastRescuePing;
  Timer? _rescueTimer;

  /// Vacía significa «usar el texto por defecto localizado» ([sendSos]).
  String _rescueDescription = '';

  // Estado de energía/ubicación reportado por el sistema.
  bool ignoringBatteryOptimizations = true;
  bool lowPowerMode = false;
  bool backgroundLocationGranted = false;

  List<MeshMessage> get messages => List.unmodifiable(_messages);
  List<MeshPeer> get peers => List.unmodifiable(_peers);

  /// La malla puede enviar mensajes: anuncio completo o modo solo recepción,
  /// donde las conexiones salientes hacia otros nodos siguen funcionando.
  bool get canSend =>
      status == MeshConnectionStatus.active ||
      status == MeshConnectionStatus.degraded;

  Future<void> initialize() async {
    _messages
      ..clear()
      ..addAll(await _repository.load());
    _subscription = _platform.events.listen(_handleEvent);
    final capabilities = await _platform.getCapabilities();
    supportsBackgroundRelay = capabilities['backgroundRelay'] as bool? ?? false;
    await refreshPowerStatus();
    notifyListeners();
  }

  Future<void> refreshPowerStatus() async {
    final power = await _platform.getPowerStatus();
    ignoringBatteryOptimizations =
        power['ignoringBatteryOptimizations'] as bool? ?? true;
    lowPowerMode = power['lowPowerMode'] as bool? ?? false;
    backgroundLocationGranted = power['backgroundLocation'] as bool? ?? false;
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
      notifyListeners();
      return;
    }
    if (description != null && description.trim().isNotEmpty) {
      _rescueDescription = description.trim();
    }
    rescueMode = true;
    notifyListeners();
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
    await _platform.stop();
    status = MeshConnectionStatus.stopped;
    notifyListeners();
  }

  Future<void> sendPublic(String content) async {
    if (content.trim().isEmpty) return;
    await _run(() => _platform.sendPublic(content.trim()));
  }

  Future<void> sendPrivate(MeshPeer peer, String content) async {
    if (content.trim().isEmpty) return;
    await _run(() => _platform.sendPrivate(peer.id, content.trim()));
  }

  Future<void> sendSos(String description) async {
    Position? position;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10),
            ),
          );
        }
      }
    } catch (_) {
      position = null;
    }
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

  Future<void> updateNickname(String value) async {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return;
    await _platform.setNickname(cleaned);
    nickname = cleaned;
    notifyListeners();
  }

  Future<void> panicWipe() async {
    await setRescueMode(false);
    await _platform.panicWipe();
    await _repository.clear();
    _messages.clear();
    _peers.clear();
    status = MeshConnectionStatus.stopped;
    nickname = '';
    peerId = '';
    notifyListeners();
  }

  Future<void> _run(Future<String> Function() action) async {
    lastError = null;
    try {
      await action();
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  void _handleEvent(Map<Object?, Object?> event) {
    switch (event['type']) {
      case 'snapshot':
        _applyStatus(event);
        _replacePeers(event['peers']);
        break;
      case 'status':
        _applyStatus(event);
        break;
      case 'peers':
        _replacePeers(event['peers']);
        break;
      case 'message':
        final rawMessage = event['message'];
        if (rawMessage is Map<Object?, Object?>) {
          final message = MeshMessage.fromMap(rawMessage);
          if (_messages.every((existing) => existing.id != message.id)) {
            _messages.add(message);
            _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
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
        _peers.clear();
        status = MeshConnectionStatus.stopped;
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
    status = switch (event['status'] as String?) {
      'active' => MeshConnectionStatus.active,
      'degraded' => MeshConnectionStatus.degraded,
      'starting' => MeshConnectionStatus.starting,
      'error' => MeshConnectionStatus.error,
      _ => MeshConnectionStatus.stopped,
    };
    nickname = event['nickname'] as String? ?? nickname;
    peerId = event['peerId'] as String? ?? peerId;
  }

  void _replacePeers(Object? value) {
    final rawPeers = value as List<Object?>? ?? const [];
    _peers
      ..clear()
      ..addAll(
        rawPeers.whereType<Map<Object?, Object?>>().map(MeshPeer.fromMap),
      );
  }

  @override
  void dispose() {
    _rescueTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
