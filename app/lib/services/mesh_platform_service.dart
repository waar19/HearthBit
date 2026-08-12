import 'dart:async';

import 'package:flutter/services.dart';

class MeshPlatformService {
  static const _methods = MethodChannel('com.emergencycom.mesh/methods');
  static const _events = EventChannel('com.emergencycom.mesh/events');

  Stream<Map<Object?, Object?>> get events => _events
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

  Future<List<Map<Object?, Object?>>> getPeers() async {
    final peers = await _methods.invokeListMethod<Object?>('getPeers');
    return peers?.whereType<Map<Object?, Object?>>().toList(growable: false) ??
        const [];
  }

  Future<void> panicWipe() => _methods.invokeMethod<void>('panicWipe');
}
