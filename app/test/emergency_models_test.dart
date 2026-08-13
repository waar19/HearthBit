import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/controllers/emergency_gateway_controller.dart';
import 'package:hearth_bit/models/mesh_models.dart';

void main() {
  test('reconoce únicamente el formato de nombre automático SOS', () {
    expect(isDefaultMeshNickname('SOS-83cf'), isTrue);
    expect(isDefaultMeshNickname('SOS-83CF'), isTrue);
    expect(isDefaultMeshNickname('Ana'), isFalse);
    expect(isDefaultMeshNickname('SOS-ayuda'), isFalse);
  });

  test('decodifica todos los perfiles de energía nativos', () {
    for (final profile in MeshPowerProfile.values) {
      expect(MeshPowerProfile.fromWire(profile.wireName), profile);
    }
    expect(
      MeshPowerProfile.fromWire('future-profile'),
      MeshPowerProfile.balanced,
    );
  });

  test('check-in conserva texto legible y metadatos estructurados', () {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    final content = EmergencyCheckIn.encode(
      status: CheckInStatus.injured,
      readableMessage: 'Estoy herido',
      timestamp: timestamp,
      latitude: 4.123456,
      longitude: -74.123456,
    );
    final parsed = MeshMessage(
      id: 'check-1',
      sender: 'Ana',
      content: content,
      senderPeerId: 'peer-a',
      isPrivate: false,
      isMine: false,
      timestamp: timestamp,
      channel: 'checkin',
    ).checkIn;

    expect(content, startsWith('Estoy herido\n'));
    expect(parsed?.status, CheckInStatus.injured);
    expect(parsed?.latitude, closeTo(4.123456, 0.000001));
    expect(parsed?.longitude, closeTo(-74.123456, 0.000001));
  });

  test('nota de voz referencia una transferencia HBT sin incrustar audio', () {
    const transferId = '00112233445566778899aabbccddeeff';
    final message = MeshMessage(
      id: 'voice-1',
      sender: 'Ana',
      content: '[HB-VOICE|$transferId|14]',
      senderPeerId: 'peer-a',
      isPrivate: true,
      isMine: false,
      timestamp: DateTime.now(),
    );

    expect(message.isVoiceNote, isTrue);
    expect(message.voiceTransferId, transferId);
    expect(message.voiceDurationSeconds, 14);
  });

  test('configuración de gateway exige servidor, destino y puerto', () {
    const valid = EmergencyGatewayConfig(
      kind: EmergencyGatewayKind.matrix,
      server: 'https://matrix.example',
      destination: '!room:example',
      username: '',
      port: 443,
      tls: true,
    );
    const invalid = EmergencyGatewayConfig(
      kind: EmergencyGatewayKind.mqtt,
      server: '',
      destination: 'hearthbit/sos',
      username: '',
      port: 8883,
      tls: true,
    );

    expect(valid.isValid, isTrue);
    expect(invalid.isValid, isFalse);
  });
}
