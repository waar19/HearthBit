import 'dart:async';

import 'package:flutter/services.dart';

/// Puente al canal nativo de transferencias (`com.hearthbit.transfer/*`).
///
/// Cubre Nearby Connections, Wi‑Fi Aware, Wi‑Fi Direct y
/// MultipeerConnectivity según las capacidades de cada plataforma.
class TransferPlatformService {
  static const _methods = MethodChannel('com.hearthbit.transfer/methods');
  static const _events = EventChannel('com.hearthbit.transfer/events');

  Stream<Map<Object?, Object?>> get events => _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .cast<Map<Object?, Object?>>();

  /// Capacidades reales del dispositivo.
  Future<Map<Object?, Object?>> getTransferCapabilities() async {
    try {
      final result = await _methods.invokeMapMethod<Object?, Object?>(
        'getTransferCapabilities',
      );
      return result ?? const {};
    } on MissingPluginException {
      return const {
        'nearby': false,
        'wifiAware': false,
        'wifiDirect': false,
        'multipeer': false,
      };
    } on PlatformException {
      return const {
        'nearby': false,
        'wifiAware': false,
        'wifiDirect': false,
        'multipeer': false,
      };
    }
  }

  Future<String?> consumeInitialHbtImport() async {
    try {
      return await _methods.invokeMethod<String>('consumeInitialHbtImport');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
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

  Future<void> wifiDirectSendFile({
    required String transferId,
    required String filePath,
  }) {
    return _methods.invokeMethod<void>('wifiDirectSendFile', {
      'transferId': transferId,
      'filePath': filePath,
    });
  }

  Future<void> wifiDirectReceiveFile({
    required String transferId,
    required String destinationPath,
  }) {
    return _methods.invokeMethod<void>('wifiDirectReceiveFile', {
      'transferId': transferId,
      'destinationPath': destinationPath,
    });
  }

  Future<void> wifiDirectStop(String transferId) async {
    try {
      await _methods.invokeMethod<void>('wifiDirectStop', {
        'transferId': transferId,
      });
    } on MissingPluginException {
      // Plataforma sin Wi-Fi Direct.
    }
  }

  Future<void> multipeerSendFile({
    required String transferId,
    required String filePath,
  }) {
    return _methods.invokeMethod<void>('multipeerSendFile', {
      'transferId': transferId,
      'filePath': filePath,
    });
  }

  Future<void> multipeerReceiveFile({
    required String transferId,
    required String destinationPath,
  }) {
    return _methods.invokeMethod<void>('multipeerReceiveFile', {
      'transferId': transferId,
      'destinationPath': destinationPath,
    });
  }

  Future<void> multipeerStop(String transferId) async {
    try {
      await _methods.invokeMethod<void>('multipeerStop', {
        'transferId': transferId,
      });
    } on MissingPluginException {
      // Plataforma sin MultipeerConnectivity.
    }
  }
}
