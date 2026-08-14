import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/controllers/emergency_gateway_controller.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/services/tls_peer_verifier.dart';

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

  test('pinning exige una huella SHA-256 completa', () {
    expect(
      const EmergencyGatewayConfig(
        kind: EmergencyGatewayKind.mqtt,
        server: 'broker.example.org',
        destination: 'hearthbit/rescue',
        username: '',
        port: 8883,
        tls: true,
        trustMode: TlsTrustMode.pinned,
        certificateSha256: 'aa:bb',
      ).isValid,
      isFalse,
    );
    expect(
      EmergencyGatewayConfig(
        kind: EmergencyGatewayKind.mqtt,
        server: 'broker.example.org',
        destination: 'hearthbit/rescue',
        username: '',
        port: 8883,
        tls: true,
        trustMode: TlsTrustMode.pinned,
        certificateSha256: 'ab' * 32,
      ).isValid,
      isTrue,
    );
  });

  test('el payload mínimo omite identidad, contenido y coordenadas', () {
    final message = MeshMessage(
      id: 'sos-1',
      sender: 'Ana',
      content: 'SOS|Herida|4.7|-74.1',
      senderPeerId: 'peer-secret',
      isPrivate: false,
      isMine: true,
      timestamp: DateTime.utc(2026),
      channel: 'sos',
    );
    const minimal = EmergencyGatewayConfig(
      kind: EmergencyGatewayKind.matrix,
      server: 'https://matrix.example.org',
      destination: '!rescue:example.org',
      username: '',
      port: 443,
      tls: true,
    );

    final payload = EmergencyGatewayController.buildPayloadForTest(
      minimal,
      message,
    );

    expect(payload.keys, containsAll(['schema', 'id', 'timestamp', 'type']));
    expect(payload, isNot(contains('sender')));
    expect(payload, isNot(contains('content')));
    expect(payload, isNot(contains('latitude')));
  });

  test('solo incluye datos sensibles con consentimiento explícito', () {
    final message = MeshMessage(
      id: 'sos-2',
      sender: 'Ana',
      content: 'SOS|Herida|4.7|-74.1',
      senderPeerId: 'peer-secret',
      isPrivate: false,
      isMine: true,
      timestamp: DateTime.utc(2026),
      channel: 'sos',
    );
    const consented = EmergencyGatewayConfig(
      kind: EmergencyGatewayKind.matrix,
      server: 'https://matrix.example.org',
      destination: '!rescue:example.org',
      username: '',
      port: 443,
      tls: true,
      includeSensitiveContent: true,
      includeCoordinates: true,
    );

    final payload = EmergencyGatewayController.buildPayloadForTest(
      consented,
      message,
    );

    expect(payload['sender'], 'Ana');
    expect(payload['content'], message.content);
    expect(payload['latitude'], 4.7);
    expect(payload['longitude'], -74.1);
  });
}
