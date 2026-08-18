import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/services/mesh_platform_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.hearthbit.mesh/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MeshPlatformService service;

  setUp(() {
    service = MeshPlatformService();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('retryEmergency devuelve el nuevo hash del contrato nativo', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'retryEmergency');
      expect(call.arguments, {'canonicalHash': 'old-hash'});
      return {'canonicalHash': 'ABC123'};
    });

    expect(await service.retryEmergency('old-hash'), 'abc123');
  });

  test('retryEmergency acepta bool del contrato nativo legado', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => true);
    expect(await service.retryEmergency('ABC123'), 'abc123');

    messenger.setMockMethodCallHandler(channel, (call) async => false);
    expect(await service.retryEmergency('ABC123'), isNull);
  });

  test('configureRescueMode usa cinco minutos en el contrato nativo', () async {
    expect(RescueModeContract.defaultInterval, const Duration(minutes: 5));
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'configureRescueMode');
      final arguments = call.arguments! as Map<Object?, Object?>;
      expect(arguments['intervalMs'], 300000);
      return {'active': true};
    });

    final state = await service.configureRescueMode(active: true);

    expect(state.active, isTrue);
  });

  test('estado de rescate distingue inactivo de nativo no disponible', () async {
    final state = await service.getRescueModeState();

    expect(state.active, isFalse);
    expect(state.available, isFalse);
  });
}
