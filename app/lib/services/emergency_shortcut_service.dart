import 'dart:async';

import 'package:flutter/services.dart';

class EmergencyShortcutService {
  EmergencyShortcutService._();

  static const _channel = MethodChannel('com.hearthbit.emergency/shortcut');
  static final _opens = StreamController<void>.broadcast();
  static var _configured = false;

  static Stream<void> get opens {
    _configure();
    return _opens.stream;
  }

  static Future<bool> consumeInitialOpen() async {
    _configure();
    try {
      return await _channel.invokeMethod<bool>('consumeInitialOpen') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  static void _configure() {
    if (_configured) return;
    _configured = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openEmergency') _opens.add(null);
    });
  }
}
