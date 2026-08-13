import 'dart:async';

import 'package:flutter/services.dart';

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

  Future<Map<Object?, Object?>> getCapabilities() async {
    final result = await _methods.invokeMapMethod<Object?, Object?>(
      'getCapabilities',
    );
    return result ?? const {};
  }

  Future<bool> requestPermissions() async {
    return await _methods.invokeMethod<bool>('requestPermissions') ?? false;
  }

  Future<void> start() => _methods.invokeMethod<void>('startMesh');

  Future<void> stop() => _methods.invokeMethod<void>('stopMesh');

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

  Future<void> setLanDiscoveryEnabled(bool enabled) {
    return _methods.invokeMethod<void>('setLanDiscoveryEnabled', {
      'enabled': enabled,
    });
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

  Future<String> sendPublic(String content, {String? channel}) async {
    return (await _methods.invokeMethod<String>('sendPublic', {
      'content': content,
      'channel': channel,
    }))!;
  }

  Future<String> sendPrivate(String peerId, String content) async {
    return (await _methods.invokeMethod<String>('sendPrivate', {
      'peerId': peerId,
      'content': content,
    }))!;
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

  Future<void> panicWipe() => _methods.invokeMethod<void>('panicWipe');

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

  Future<void> setRadarConsent({required bool enabled, int minutes = 15}) {
    return _methods.invokeMethod<void>('setRadarConsent', {
      'enabled': enabled,
      'minutes': minutes,
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
