import 'dart:async';

import 'package:flutter/services.dart';

/// Puente al canal nativo de transferencias (`com.hearthbit.transfer/*`).
///
/// Hoy cubre Nearby Connections (Android) y la detección de Wi‑Fi Aware.
/// En iOS los métodos Nearby responden `nearbyUnavailable`, y el selector de
/// transporte cae automáticamente a LAN, BLE u óptico.
class TransferPlatformService {
  static const _methods = MethodChannel('com.hearthbit.transfer/methods');
  static const _events = EventChannel('com.hearthbit.transfer/events');

  Stream<Map<Object?, Object?>> get events => _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .cast<Map<Object?, Object?>>();

  /// Capacidades reales del dispositivo: {nearby: bool, wifiAware: bool}.
  Future<Map<Object?, Object?>> getTransferCapabilities() async {
    try {
      final result = await _methods.invokeMapMethod<Object?, Object?>(
        'getTransferCapabilities',
      );
      return result ?? const {};
    } on MissingPluginException {
      return const {'nearby': false, 'wifiAware': false};
    } on PlatformException {
      return const {'nearby': false, 'wifiAware': false};
    }
  }

  /// Anuncia y envía [filePath] al peer con Nearby Connections.
  Future<void> nearbySendFile({
    required String peerId,
    required String transferId,
    required String filePath,
  }) {
    return _methods.invokeMethod<void>('nearbySendFile', {
      'peerId': peerId,
      'transferId': transferId,
      'filePath': filePath,
    });
  }

  /// Descubre al peer y recibe el archivo en [destinationPath].
  Future<void> nearbyReceiveFile({
    required String peerId,
    required String transferId,
    required String destinationPath,
  }) {
    return _methods.invokeMethod<void>('nearbyReceiveFile', {
      'peerId': peerId,
      'transferId': transferId,
      'destinationPath': destinationPath,
    });
  }

  Future<void> nearbyStop(String transferId) async {
    try {
      await _methods.invokeMethod<void>('nearbyStop', {
        'transferId': transferId,
      });
    } on MissingPluginException {
      // iOS aún no implementa Nearby; no hay nada que detener.
    }
  }

  /// Publica el servicio Wi-Fi Aware y sirve [filePath] por el data path.
  Future<void> wifiAwareSendFile({
    required String transferId,
    required String filePath,
  }) {
    return _methods.invokeMethod<void>('wifiAwareSendFile', {
      'transferId': transferId,
      'filePath': filePath,
    });
  }

  /// Se suscribe al servicio Wi-Fi Aware y descarga en [destinationPath].
  Future<void> wifiAwareReceiveFile({
    required String transferId,
    required String destinationPath,
  }) {
    return _methods.invokeMethod<void>('wifiAwareReceiveFile', {
      'transferId': transferId,
      'destinationPath': destinationPath,
    });
  }

  Future<void> wifiAwareStop(String transferId) async {
    try {
      await _methods.invokeMethod<void>('wifiAwareStop', {
        'transferId': transferId,
      });
    } on MissingPluginException {
      // Plataforma sin Wi-Fi Aware; no hay nada que detener.
    }
  }
}
