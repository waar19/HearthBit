import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/lan_mesh_gateway.dart';
import '../services/secure_storage_config.dart';

class LanGatewayController extends ChangeNotifier {
  LanGatewayController({
    LanMeshGatewayService? service,
    SharedPreferencesAsync? preferences,
    FlutterSecureStorage? secureStorage,
  }) : _service = service ?? LanMeshGatewayService(),
       _preferences = preferences ?? SharedPreferencesAsync(),
       _secureStorage = secureStorage ?? hearthBitSecureStorage;

  static const _enabledKey = 'lanGateway.enabled.v1';
  static const _pskKey = 'lanGateway.psk.v1';

  final LanMeshGatewayService _service;
  final SharedPreferencesAsync _preferences;
  final FlutterSecureStorage _secureStorage;

  StreamSubscription<LanGatewayStatus>? _statusSubscription;
  List<int>? _psk;
  bool _configuredEnabled = false;
  bool emergencyMode = false;
  LanGatewayStatus status = const LanGatewayStatus(
    enabled: false,
    connected: false,
  );

  bool get enabled => status.enabled;

  Future<void> initialize() async {
    _statusSubscription = _service.statuses.listen((value) {
      status = value;
      notifyListeners();
    });
    final enabled = await _preferences.getBool(_enabledKey) ?? false;
    final encoded = await _secureStorage.read(key: _pskKey);
    final psk = _decodePsk(encoded);
    _configuredEnabled = enabled && psk != null;
    _psk = psk;
    if (!enabled || psk == null) {
      if (enabled) await _preferences.setBool(_enabledKey, false);
      return;
    }
    await _service.start(LanMeshGatewayConfig(enabled: true, psk: psk));
  }

  Future<void> enable(String encodedPsk) async {
    final psk = _decodePsk(encodedPsk);
    if (psk == null) {
      throw const FormatException('LAN PSK must be 32 bytes in base64');
    }
    await _secureStorage.write(key: _pskKey, value: base64Encode(psk));
    await _preferences.setBool(_enabledKey, true);
    _configuredEnabled = true;
    _psk = psk;
    await _restartService();
  }

  Future<void> disable() async {
    await _preferences.setBool(_enabledKey, false);
    _configuredEnabled = false;
    if (emergencyMode) {
      await _restartService();
    } else {
      await _service.stop();
    }
    if (!emergencyMode) {
      status = const LanGatewayStatus(enabled: false, connected: false);
    }
    notifyListeners();
  }

  Future<void> panicWipe() async {
    emergencyMode = false;
    await disable();
    await _secureStorage.delete(key: _pskKey);
    _psk = null;
  }

  Future<void> setEmergencyMode(bool active) async {
    if (emergencyMode == active) return;
    emergencyMode = active;
    await _restartService();
    notifyListeners();
  }

  Future<void> _restartService() async {
    final psk = _configuredEnabled ? _psk ?? const <int>[] : const <int>[];
    if (!_configuredEnabled && !emergencyMode) {
      await _service.stop();
      return;
    }
    await _service.start(
      LanMeshGatewayConfig(
        enabled: true,
        psk: psk,
        emergencyOpenMode: emergencyMode,
      ),
    );
  }

  String generatePairingKey() {
    final random = Random.secure();
    return base64Encode(List.generate(32, (_) => random.nextInt(256)));
  }

  List<int>? _decodePsk(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) return null;
    try {
      final bytes = base64Decode(encoded.trim());
      return bytes.length == 32 ? bytes : null;
    } on FormatException {
      return null;
    }
  }

  @override
  void dispose() {
    unawaited(_statusSubscription?.cancel());
    unawaited(_service.dispose());
    super.dispose();
  }
}
