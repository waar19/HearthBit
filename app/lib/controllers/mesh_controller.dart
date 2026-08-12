import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/mesh_models.dart';
import '../services/mesh_platform_service.dart';
import '../services/message_repository.dart';

class MeshController extends ChangeNotifier {
  MeshController({MeshPlatformService? platform, MessageRepository? repository})
    : _platform = platform ?? MeshPlatformService(),
      _repository = repository ?? MessageRepository();

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
    notifyListeners();
  }

  Future<void> start() async {
    lastError = null;
    status = MeshConnectionStatus.starting;
    notifyListeners();
    try {
      if (!await _platform.requestPermissions()) {
        throw StateError(
          'Se necesitan permisos de Bluetooth y notificaciones para crear la malla.',
        );
      }
      await _platform.start();
    } catch (error) {
      status = MeshConnectionStatus.error;
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<void> stop() async {
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
            ? 'Necesito ayuda'
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
      case 'status':
        status = switch (event['status'] as String?) {
          'active' => MeshConnectionStatus.active,
          'degraded' => MeshConnectionStatus.degraded,
          'starting' => MeshConnectionStatus.starting,
          'error' => MeshConnectionStatus.error,
          _ => MeshConnectionStatus.stopped,
        };
        nickname = event['nickname'] as String? ?? nickname;
        peerId = event['peerId'] as String? ?? peerId;
        break;
      case 'peers':
        final rawPeers = event['peers'] as List<Object?>? ?? const [];
        _peers
          ..clear()
          ..addAll(
            rawPeers.whereType<Map<Object?, Object?>>().map(MeshPeer.fromMap),
          );
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
        lastError = event['message'] as String? ?? 'Error desconocido';
        if (status == MeshConnectionStatus.starting) {
          status = MeshConnectionStatus.error;
        }
        break;
      case 'wiped':
        _messages.clear();
        _peers.clear();
        status = MeshConnectionStatus.stopped;
        break;
      default:
        break;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
