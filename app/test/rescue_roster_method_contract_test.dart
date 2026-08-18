import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/models/rescue_roster_models.dart';
import 'package:hearth_bit/services/mesh_platform_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.hearthbit.mesh/methods');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('envía el batch completo al contrato importRescueRosterPins', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return null;
        });
    final key = Uint8List.fromList(List.generate(32, (index) => index + 1));

    await MeshPlatformService().importRescueRosterPins([
      RescueRosterMember(
        peerId: '0011223344556677',
        callsign: 'Norte 1',
        role: RescueRosterRole.leader,
        signingPublicKey: key,
      ),
    ]);

    expect(received?.method, 'importRescueRosterPins');
    final arguments = received?.arguments as Map<Object?, Object?>;
    final pins = arguments['pins'] as List<Object?>;
    final pin = pins.single as Map<Object?, Object?>;
    expect(pin['peerId'], '0011223344556677');
    expect(pin['signingPublicKey'], key);
  });

  test('verifica una firma contra una clave explícita', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'verifySignatureWithPublicKey');
          final arguments = call.arguments as Map<Object?, Object?>;
          expect(arguments['signingPublicKey'], Uint8List(32));
          expect(arguments['data'], Uint8List.fromList([1, 2]));
          expect(arguments['signature'], Uint8List(64));
          return true;
        });

    expect(
      await MeshPlatformService().verifySignatureWithPublicKey(
        signingPublicKey: Uint8List(32),
        data: Uint8List.fromList([1, 2]),
        signature: Uint8List(64),
      ),
      isTrue,
    );
  });
}
