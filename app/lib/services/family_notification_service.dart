import 'package:flutter/services.dart';

abstract interface class FamilyNotificationSink {
  Future<bool> requestPermission();

  Future<void> show({
    required String messageId,
    required String nickname,
    required String status,
  });
}

class FamilyNotificationService implements FamilyNotificationSink {
  static const _methods = MethodChannel('com.hearthbit.mesh/methods');

  @override
  Future<bool> requestPermission() async {
    try {
      return await _methods.invokeMethod<bool>(
            'requestFamilyNotificationPermission',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> show({
    required String messageId,
    required String nickname,
    required String status,
  }) async {
    try {
      await _methods.invokeMethod<void>('showFamilyNotification', {
        'messageId': messageId,
        'nickname': nickname,
        'status': status,
      });
    } on MissingPluginException {
      // El aviso destacado dentro de la app sigue disponible.
    } on PlatformException {
      // Permiso denegado o notificaciones no disponibles.
    }
  }
}
