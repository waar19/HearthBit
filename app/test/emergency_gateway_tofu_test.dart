import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/controllers/emergency_gateway_controller.dart';
import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/services/app_preferences.dart';
import 'package:hearth_bit/services/tls_peer_verifier.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _GatedSecureStorage extends FlutterSecureStorage {
  final writeGate = Completer<void>();
  final Map<String, String> data = {};
  var writes = 0;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes += 1;
    await writeGate.future;
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TOFU serializa la primera huella por endpoint', () async {
    final secureStorage = _GatedSecureStorage();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = AppPreferences();
    final mesh = MeshController(preferences: preferences);
    final controller = EmergencyGatewayController(
      mesh: mesh,
      preferences: preferences,
      secureStorage: secureStorage,
    );
    addTearDown(() {
      controller.dispose();
      mesh.dispose();
    });
    const config = EmergencyGatewayConfig(
      kind: EmergencyGatewayKind.mqtt,
      server: 'broker.example.org',
      destination: 'hearthbit/rescue',
      username: '',
      port: 8883,
      tls: true,
      trustMode: TlsTrustMode.tofu,
    );
    final first = '11' * 32;
    final conflicting = '22' * 32;

    expect(controller.claimTofuFingerprintForTest(config, first), isTrue);
    expect(
      controller.claimTofuFingerprintForTest(config, conflicting),
      isFalse,
    );
    expect(controller.claimTofuFingerprintForTest(config, first), isTrue);
    expect(secureStorage.writes, 1);

    secureStorage.writeGate.complete();
    await controller.awaitTofuPersistenceForTest(config);

    expect(secureStorage.data.values, contains(first));
  });
}
