import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/controllers/emergency_gateway_controller.dart';

void main() {
  test('Matrix exige URL HTTPS y TLS', () {
    const valid = EmergencyGatewayConfig(
      kind: EmergencyGatewayKind.matrix,
      server: 'https://matrix.example.org',
      destination: '!rescue:example.org',
      username: '',
      port: 443,
      tls: true,
    );
    expect(valid.isValid, isTrue);
    expect(
      const EmergencyGatewayConfig(
        kind: EmergencyGatewayKind.matrix,
        server: 'http://matrix.example.org',
        destination: '!rescue:example.org',
        username: '',
        port: 80,
        tls: false,
      ).isValid,
      isFalse,
    );
  });

  test('MQTT exige hostname TLS y rechaza topics con comodines', () {
    expect(
      const EmergencyGatewayConfig(
        kind: EmergencyGatewayKind.mqtt,
        server: 'broker.example.org',
        destination: 'hearthbit/rescue',
        username: 'relay',
        port: 8883,
        tls: true,
      ).isValid,
      isTrue,
    );
    expect(
      const EmergencyGatewayConfig(
        kind: EmergencyGatewayKind.mqtt,
        server: 'mqtt://broker.example.org',
        destination: 'hearthbit/#',
        username: 'relay',
        port: 1883,
        tls: false,
      ).isValid,
      isFalse,
    );
  });
}
