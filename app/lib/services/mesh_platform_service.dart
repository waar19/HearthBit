import 'dart:async';

import 'package:flutter/services.dart';

import 'beacon_control_protocol.dart';
import '../models/mesh_models.dart';
import 'mesh_native_event.dart';

String normalizeSmsRecipient(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'[\s()\-]'), '');
  if (!RegExp(r'^\+?[0-9]{5,15}$').hasMatch(normalized)) {
    throw const FormatException('invalid_sms_recipient');
  }
  return normalized;
}

abstract final class RescueModeContract {
  static const Duration defaultInterval = Duration(minutes: 5);
}

class EmergencyTransmission {
  const EmergencyTransmission({
    required this.messageId,
    this.canonicalHash,
    this.announcementFrame,
    this.messageFrame,
  });

  final String messageId;
  final String? canonicalHash;
  final Uint8List? announcementFrame;
  final Uint8List? messageFrame;

  bool get hasQrFrames =>
      announcementFrame?.isNotEmpty == true && messageFrame?.isNotEmpty == true;
}

class NativeRescueState {
  const NativeRescueState({
    required this.active,
    this.description,
    this.startedAt,
    this.lastPingAt,
    this.expiresAt,
    this.expectedPings = 0,
    this.executedPings = 0,
    this.locationPrecision = SosLocationPrecision.approximate,
  });

  factory NativeRescueState.fromMap(Map<Object?, Object?>? map) {
    DateTime? date(String key) {
      final value = map?[key];
      return value is int && value > 0
          ? DateTime.fromMillisecondsSinceEpoch(value)
          : null;
    }

    return NativeRescueState(
      active: map?['active'] == true,
      description: map?['description'] as String?,
      startedAt: date('startedAt'),
      lastPingAt: date('lastPingAt'),
      expiresAt: date('expiresAt'),
      expectedPings: (map?['expectedPings'] as num?)?.toInt() ?? 0,
      executedPings: (map?['executedPings'] as num?)?.toInt() ?? 0,
      locationPrecision: SosLocationPrecision.values.firstWhere(
        (value) => value.wireName == map?['locationPrecision'],
        orElse: () => SosLocationPrecision.approximate,
      ),
    );
  }

  final bool active;
  final String? description;
  final DateTime? startedAt;
  final DateTime? lastPingAt;
  final DateTime? expiresAt;
  final int expectedPings;
  final int executedPings;
  final SosLocationPrecision locationPrecision;
}

class MeshPlatformService {
  static const _methods = MethodChannel('com.hearthbit.mesh/methods');
  static const _events = EventChannel('com.hearthbit.mesh/events');

  /// Stream compartido por todos los consumidores (malla, transferencias,
  /// radar). Un EventChannel solo admite un handler Dart por canal: si cada
  /// consumidor llamara a receiveBroadcastStream() por su cuenta, el último
  /// en suscribirse dejaría mudos a los demás y el primero en cancelar
  /// cerraría el canal para todos.
  static Stream<Map<Object?, Object?>>? _eventStream;

  Stream<Map<Object?, Object?>> get events => _eventStream ??= _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .cast<Map<Object?, Object?>>();

  Stream<MeshNativeEvent> get nativeEvents => events.map(MeshNativeEvent.parse);

  Future<Map<Object?, Object?>> getCapabilities() async {
    final result = await _methods.invokeMapMethod<Object?, Object?>(
      'getCapabilities',
    );
    return result ?? const {};
  }

  Future<bool> requestPermissions() async {
    return await _methods.invokeMethod<bool>('requestPermissions') ?? false;
  }

  /// Returns the current mobile-network country on Android when available.
  /// iOS intentionally returns null because its carrier-country API is
  /// deprecated; callers must fall back to the system region.
  Future<String?> getSimCountry() async {
    try {
      final country = await _methods.invokeMethod<String>('getSimCountry');
      final normalized = country?.trim().toUpperCase();
      return normalized == null || normalized.isEmpty ? null : normalized;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> start() => _methods.invokeMethod<void>('startMesh');

  Future<void> stop() => _methods.invokeMethod<void>('stopMesh');

  Future<NativeRescueState> configureRescueMode({
    required bool active,
    String? description,
    DateTime? startedAt,
    DateTime? lastPingAt,
    DateTime? expiresAt,
    Duration interval = RescueModeContract.defaultInterval,
    SosLocationPrecision locationPrecision = SosLocationPrecision.approximate,
  }) async {
    try {
      final result = await _methods
          .invokeMapMethod<Object?, Object?>('configureRescueMode', {
            'active': active,
            'description': description,
            'startedAt': startedAt?.millisecondsSinceEpoch,
            'lastPingAt': lastPingAt?.millisecondsSinceEpoch,
            'expiresAt': expiresAt?.millisecondsSinceEpoch,
            'intervalMs': interval.inMilliseconds,
            'locationPrecision': locationPrecision.wireName,
          });
      return NativeRescueState.fromMap(result);
    } on MissingPluginException {
      return NativeRescueState(active: active);
    }
  }

  Future<NativeRescueState> getRescueModeState() async {
    try {
      return NativeRescueState.fromMap(
        await _methods.invokeMapMethod<Object?, Object?>('getRescueModeState'),
      );
    } catch (_) {
      return const NativeRescueState(active: false);
    }
  }

  /// Habilita el puente de frames completos para el cliente LAN opt-in.
  ///
  /// El transporte y la clave permanecen en Dart; native solo expone una
  /// frontera explícita y acotada hacia el motor de malla.
  Future<void> configureLanBridge({
    required bool enabled,
    String? gatewayId,
    int maxFrameSize = 2048,
  }) {
    return _methods.invokeMethod<void>('configureLanBridge', {
      'enabled': enabled,
      'gatewayId': gatewayId,
      'maxFrameSize': maxFrameSize,
    });
  }

  /// Conecta, con consentimiento explícito, un nodo Meshtastic cercano como
  /// troncal LoRa. En plataformas sin soporte el método es un no-op seguro.
  Future<void> configureMeshtasticBridge({required bool enabled}) async {
    try {
      await _methods.invokeMethod<void>('configureMeshtasticBridge', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Plataforma sin cliente Meshtastic nativo.
    } on PlatformException {
      // El controlador mostrará la ausencia del enlace mediante el snapshot.
    }
  }

  Future<void> setLanDiscoveryEnabled(bool enabled) {
    return _methods.invokeMethod<void>('setLanDiscoveryEnabled', {
      'enabled': enabled,
    });
  }

  Future<void> setGenericPresenceScanEnabled(bool enabled) {
    return _methods.invokeMethod<void>('setGenericPresenceScanEnabled', {
      'enabled': enabled,
    });
  }

  Future<void> configurePrivacyMode({
    required bool privateMode,
    required bool bitchatInteropEnabled,
  }) async {
    try {
      await _methods.invokeMethod<void>('configurePrivacyMode', {
        'privateMode': privateMode,
        'bitchatInteropEnabled': bitchatInteropEnabled,
      });
    } on MissingPluginException {
      // Tests y versiones nativas antiguas conservan defaults privados.
    } on PlatformException catch (error) {
      if (error.code != 'not_implemented') rethrow;
    } catch (_) {
      // Algunos tests unitarios no inicializan ServicesBinding.
    }
  }

  Future<void> injectRawMeshFrame({
    required String gatewayId,
    required Uint8List frame,
  }) {
    return _methods.invokeMethod<void>('injectRawMeshFrame', {
      'gatewayId': gatewayId,
      'frame': frame,
    });
  }

  Future<void> injectEmergencyQrFrames({
    required Uint8List announcementFrame,
    required Uint8List messageFrame,
  }) {
    return _methods.invokeMethod<void>('injectEmergencyQrFrames', {
      'announcementFrame': announcementFrame,
      'messageFrame': messageFrame,
    });
  }

  Future<String> sendPublic(String content, {String? channel}) async {
    return (await _methods.invokeMethod<String>('sendPublic', {
      'content': content,
      'channel': channel,
    }))!;
  }

  Future<String> sendPrivate(
    String peerId,
    String content, {
    String? messageId,
  }) async {
    return (await _methods.invokeMethod<String>('sendPrivate', {
      'peerId': peerId,
      'content': content,
      'messageId': messageId,
    }))!;
  }

  /// Inicia o recupera Noise sin enviar todavía el mensaje encolado.
  ///
  /// Evita el bloqueo circular donde Flutter esperaba `secure=true` antes de
  /// llamar al nativo, aunque era precisamente el nativo quien debía iniciar
  /// el handshake.
  Future<void> ensurePrivateChannel(String peerId) {
    return _methods.invokeMethod<void>('ensurePrivateChannel', {
      'peerId': peerId,
    });
  }

  Future<String> sendSos({
    required String content,
    double? latitude,
    double? longitude,
  }) async {
    return (await _methods.invokeMethod<String>('sendSos', {
      'content': content,
      'latitude': latitude,
      'longitude': longitude,
    }))!;
  }

  Future<EmergencyTransmission> sendEmergency({
    required String messageId,
    required String content,
    required String channel,
  }) async {
    try {
      final result = await _methods.invokeMapMethod<Object?, Object?>(
        'sendEmergency',
        {'messageId': messageId, 'content': content, 'channel': channel},
      );
      final returnedId = result?['messageId'] as String? ?? messageId;
      return EmergencyTransmission(
        messageId: returnedId,
        canonicalHash: (result?['canonicalHash'] as String?)?.toLowerCase(),
        announcementFrame: result?['announcementFrame'] as Uint8List?,
        messageFrame: result?['messageFrame'] as Uint8List?,
      );
    } on MissingPluginException {
      return EmergencyTransmission(
        messageId: await sendPublic(content, channel: channel),
      );
    } on PlatformException catch (error) {
      if (error.code != 'not_implemented') rethrow;
      return EmergencyTransmission(
        messageId: await sendPublic(content, channel: channel),
      );
    }
  }

  Future<String?> retryEmergency(String canonicalHash) async {
    try {
      final result = await _methods.invokeMethod<Object?>('retryEmergency', {
        'canonicalHash': canonicalHash,
      });
      if (result is Map<Object?, Object?>) {
        return (result['canonicalHash'] as String?)?.toLowerCase();
      }
      if (result is bool) {
        return result ? canonicalHash.toLowerCase() : null;
      }
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      if (error.code == 'not_implemented') return null;
      rethrow;
    }
  }

  Future<void> setNickname(String nickname) {
    return _methods.invokeMethod<void>('setNickname', {'nickname': nickname});
  }

  Future<void> setNodeRole(String role) {
    return _methods.invokeMethod<void>('setNodeRole', {'role': role});
  }

  Future<List<Map<Object?, Object?>>> getPeers() async {
    final peers = await _methods.invokeListMethod<Object?>('getPeers');
    return peers?.whereType<Map<Object?, Object?>>().toList(growable: false) ??
        const [];
  }

  Future<Map<Object?, Object?>> panicWipe() async {
    return await _methods.invokeMapMethod<Object?, Object?>('panicWipe') ??
        const {};
  }

  /// Estado de energía/ubicación del sistema:
  /// {ignoringBatteryOptimizations, lowPowerMode, backgroundLocation}.
  Future<Map<Object?, Object?>> getPowerStatus() async {
    try {
      final result = await _methods.invokeMapMethod<Object?, Object?>(
        'getPowerStatus',
      );
      return result ?? const {};
    } on MissingPluginException {
      return const {};
    } on PlatformException {
      return const {};
    }
  }

  /// Snapshot agregado para soporte en campo. No contiene identidades,
  /// direcciones, mensajes, claves ni coordenadas.
  Future<Map<Object?, Object?>> getMeshDiagnostics() async {
    try {
      final result = await _methods.invokeMapMethod<Object?, Object?>(
        'getMeshDiagnostics',
      );
      return result ?? const {};
    } on MissingPluginException {
      return const {};
    } on PlatformException {
      return const {};
    }
  }

  Future<bool> composeEmergencySms({
    required String recipient,
    required String body,
  }) async {
    final normalizedRecipient = normalizeSmsRecipient(recipient);
    try {
      return await _methods.invokeMethod<bool>('composeEmergencySms', {
            'recipient': normalizedRecipient,
            'body': body,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Android: abre el diálogo del sistema para excluir la app de la
  /// optimización de batería. Devuelve true si ya estaba excluida.
  Future<bool> requestDisableBatteryOptimizations() async {
    try {
      return await _methods.invokeMethod<bool>(
            'requestDisableBatteryOptimizations',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Pide ubicación «todo el tiempo» (Android) o «siempre» (iOS).
  Future<bool> requestBackgroundLocation() async {
    try {
      return await _methods.invokeMethod<bool>('requestBackgroundLocation') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Radar de rescate: el nativo empieza a emitir eventos
  /// {type: 'rssi', peerId, rssi, at} para el peer objetivo.
  Future<void> startRadar(String peerId) {
    return _methods.invokeMethod<void>('startRadar', {'peerId': peerId});
  }

  Future<void> stopRadar() => _methods.invokeMethod<void>('stopRadar');

  Future<Map<Object?, Object?>> getRangingCapabilities() async {
    final result = await _methods.invokeMapMethod<Object?, Object?>(
      'getRangingCapabilities',
    );
    return result ?? const {};
  }

  Future<void> startRadioRanging(String peerId) {
    return _methods.invokeMethod<void>('startRadioRanging', {'peerId': peerId});
  }

  Future<void> stopRadioRanging() {
    return _methods.invokeMethod<void>('stopRadioRanging');
  }

  Future<void> setRadarConsent({required bool enabled, int minutes = 15}) {
    return _methods.invokeMethod<void>('setRadarConsent', {
      'enabled': enabled,
      'minutes': minutes,
    });
  }

  Future<void> startLocalBeacon({
    int flags = BeaconControlFlags.all,
    Duration duration = BeaconControlProtocol.maximumDuration,
  }) {
    return _methods.invokeMethod<void>('startLocalBeacon', {
      'flags': flags,
      'durationSeconds': duration.inSeconds,
    });
  }

  Future<void> stopLocalBeacon() {
    return _methods.invokeMethod<void>('stopLocalBeacon');
  }

  Future<String> requestRemoteBeacon(
    String peerId, {
    int flags = BeaconControlFlags.all,
    Duration duration = BeaconControlProtocol.maximumDuration,
  }) async {
    return (await _methods.invokeMethod<String>('requestRemoteBeacon', {
      'peerId': peerId,
      'flags': flags,
      'durationSeconds': duration.inSeconds,
    }))!;
  }

  Future<void> respondToBeaconRequest({
    required String requestId,
    required bool accept,
  }) {
    return _methods.invokeMethod<void>('respondToBeaconRequest', {
      'requestId': requestId,
      'accept': accept,
    });
  }

  Future<void> stopRemoteBeacon({
    required String peerId,
    required String requestId,
  }) {
    return _methods.invokeMethod<void>('stopRemoteBeacon', {
      'peerId': peerId,
      'requestId': requestId,
    });
  }

  Future<void> sendRangingControl(String peerId, Uint8List payload) {
    return _methods.invokeMethod<void>('sendRangingControl', {
      'peerId': peerId,
      'payload': payload,
    });
  }

  /// Envía una trama HBT (plano de control de transferencias) por la sesión
  /// Noise de la malla.
  Future<void> sendTransferFrame(String peerId, Uint8List frame) {
    return _methods.invokeMethod<void>('sendTransferFrame', {
      'peerId': peerId,
      'frame': frame,
    });
  }

  /// Firma Ed25519 con la identidad local (ofertas y boletines ópticos).
  Future<Uint8List> signPayload(Uint8List data) async {
    return (await _methods.invokeMethod<Uint8List>('signPayload', {
      'data': data,
    }))!;
  }

  Future<bool> verifyPeerSignature(
    String peerId,
    Uint8List data,
    Uint8List signature,
  ) async {
    return await _methods.invokeMethod<bool>('verifyPeerSignature', {
          'peerId': peerId,
          'data': data,
          'signature': signature,
        }) ??
        false;
  }
}
