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
}
