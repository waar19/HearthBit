import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/services/mesh_platform_service.dart';
import 'package:hearth_bit/services/message_repository.dart';

class _FakePlatform extends MeshPlatformService {
  final StreamController<Map<Object?, Object?>> _controller =
      StreamController.broadcast();

  int startCalls = 0;
  int stopCalls = 0;
  int sosCalls = 0;
  bool permissionsGranted = true;
  bool backgroundLocation = true;
  Object? startError;

  void emit(Map<Object?, Object?> event) => _controller.add(event);

  @override
  Stream<Map<Object?, Object?>> get events => _controller.stream;

  @override
  Future<Map<Object?, Object?>> getCapabilities() async => const {
    'backgroundRelay': true,
  };

  @override
  Future<bool> requestPermissions() async => permissionsGranted;

  @override
  Future<void> start() async {
    startCalls += 1;
    final error = startError;
    if (error != null) throw error;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<String> sendSos({
    required String content,
    double? latitude,
    double? longitude,
  }) async {
    sosCalls += 1;
    return 'sos-$sosCalls';
  }

  @override
  Future<Map<Object?, Object?>> getPowerStatus() async => {
    'ignoringBatteryOptimizations': false,
    'lowPowerMode': true,
    'backgroundLocation': backgroundLocation,
  };

  @override
  Future<bool> requestBackgroundLocation() async => backgroundLocation;

  @override
  Future<bool> requestDisableBatteryOptimizations() async => false;
}

class _FakeRepository extends MessageRepository {
  final List<MeshMessage> saved = [];

  @override
  Future<List<MeshMessage>> load() async => const [];

  @override
  Future<void> save(MeshMessage message) async {
    saved.add(message);
  }

  @override
  Future<void> clear() async {
    saved.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlatform platform;
  late MeshController controller;

  setUp(() async {
    platform = _FakePlatform();
    controller = MeshController(
      platform: platform,
      repository: _FakeRepository(),
    );
    await controller.initialize();
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpEvents() => Future<void>.delayed(Duration.zero);

  test('el estado degraded llega desde el nativo y permite enviar', () async {
    platform.emit({'type': 'status', 'status': 'degraded'});
    await pumpEvents();
    expect(controller.status, MeshConnectionStatus.degraded);
    expect(controller.canSend, isTrue);
  });

  test('active tras degraded recupera la malla completa', () async {
    platform.emit({'type': 'status', 'status': 'degraded'});
    platform.emit({'type': 'status', 'status': 'active'});
    await pumpEvents();
    expect(controller.status, MeshConnectionStatus.active);
  });

  test('snapshot resincroniza estado, identidad y cercanos', () async {
    platform.emit({
      'type': 'snapshot',
      'status': 'active',
      'nickname': 'Nodo 7',
      'peerId': '0102030405060708',
      'peers': [
        {
          'id': '1112131415161718',
          'nickname': 'Rescate',
          'lastSeen': 1234,
          'secure': true,
        },
      ],
    });
    await pumpEvents();

    expect(controller.status, MeshConnectionStatus.active);
    expect(controller.nickname, 'Nodo 7');
    expect(controller.peerId, '0102030405060708');
    expect(controller.peers.single.nickname, 'Rescate');
  });

  test('un error durante el arranque marca estado de error', () async {
    unawaited(controller.start());
    await pumpEvents();
    platform.emit({'type': 'error', 'message': 'Bluetooth apagado'});
    await pumpEvents();
    expect(controller.status, MeshConnectionStatus.error);
    expect(controller.lastError, contains('Bluetooth'));
  });

  test(
    'reintentar tras un fallo vuelve a invocar el arranque nativo',
    () async {
      platform.startError = StateError('sin adaptador');
      await controller.start();
      expect(controller.status, MeshConnectionStatus.error);

      platform.startError = null;
      await controller.start();
      expect(platform.startCalls, 2);
      expect(controller.lastError, isNull);

      platform.emit({'type': 'status', 'status': 'active'});
      await pumpEvents();
      expect(controller.status, MeshConnectionStatus.active);
    },
  );

  test('permisos rechazados no dejan la malla como activa', () async {
    platform.permissionsGranted = false;
    await controller.start();
    expect(controller.status, MeshConnectionStatus.error);
    expect(platform.startCalls, 0);
    expect(controller.canSend, isFalse);
  });

  test('el estado de energía llega desde el nativo', () async {
    await controller.refreshPowerStatus();
    expect(controller.ignoringBatteryOptimizations, isFalse);
    expect(controller.lowPowerMode, isTrue);
    expect(controller.backgroundLocationGranted, isTrue);
  });

  test('el modo rescate reenvía el SOS y se detiene al apagarse', () async {
    platform.emit({'type': 'status', 'status': 'active'});
    await pumpEvents();

    await controller.setRescueMode(
      true,
      interval: const Duration(milliseconds: 40),
    );
    expect(controller.rescueMode, isTrue);
    expect(platform.sosCalls, 1);
    expect(controller.lastRescuePing, isNotNull);

    await Future<void>.delayed(const Duration(milliseconds: 130));
    expect(platform.sosCalls, greaterThanOrEqualTo(2));

    await controller.setRescueMode(false);
    expect(controller.rescueMode, isFalse);
    final callsAtStop = platform.sosCalls;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(platform.sosCalls, callsAtStop);
  });

  test('detener la malla también apaga el modo rescate', () async {
    await controller.setRescueMode(true, interval: const Duration(minutes: 5));
    await controller.stop();
    expect(controller.rescueMode, isFalse);
    expect(platform.stopCalls, 1);
  });
}
