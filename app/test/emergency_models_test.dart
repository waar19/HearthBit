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

  test('simulacro usa marcador versionado y nunca se clasifica como SOS', () {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    final content = DrillCheckIn.encode(
      status: CheckInStatus.needsHelp,
      readableMessage: 'Solicitud de ayuda de práctica',
      safetyNotice: 'SIMULACRO - no solicita rescate',
      timestamp: timestamp,
    );
    final message = MeshMessage(
      id: 'drill-1',
      sender: 'Ana',
      content: content,
      senderPeerId: 'peer-a',
      isPrivate: false,
      isMine: false,
      timestamp: timestamp,
      channel: 'drill',
    );

    expect(content, startsWith('SIMULACRO - no solicita rescate'));
    expect(content, contains('[HB-DRILL|1|CHECKIN|HELP|'));
    expect(content, isNot(startsWith('SOS|')));
    expect(message.isDrill, isTrue);
    expect(message.drill?.version, 1);
    expect(message.drill?.status, CheckInStatus.needsHelp);
    expect(message.isSos, isFalse);
    expect(message.isCheckIn, isFalse);
  });

  test('solo el canal derivado del flag firmado identifica simulacro', () {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    final hostile = MeshMessage(
      id: 'drill-hostile',
      sender: 'Ana',
      content: 'SOS|No debe escalar||',
      senderPeerId: 'peer-a',
      isPrivate: false,
      isMine: false,
      timestamp: timestamp,
      channel: 'drill',
    );
    final future = MeshMessage(
      id: 'drill-future',
      sender: 'Ana',
      content: 'Practice\n[HB-DRILL|99|CHECKIN|HELP|1700000000000]',
      senderPeerId: 'peer-a',
      isPrivate: false,
      isMine: false,
      timestamp: timestamp,
      channel: null,
    );

    expect(hostile.isDrill, isTrue);
    expect(hostile.isSos, isFalse);
    expect(hostile.drill, isNull);
    expect(future.isDrill, isFalse);
    expect(future.isSos, isFalse);
    expect(future.drill, isNull);
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

  test('ubicación de radar privada conserva GPS, precisión y fecha', () {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    final content = RadarLocationUpdate.encode(
      latitude: 4.609710,
      longitude: -74.081750,
      accuracyMeters: 4.2,
      timestamp: timestamp,
    );
    final message = MeshMessage(
      id: 'location-1',
      sender: 'Ana',
      content: content,
      senderPeerId: 'peer-a',
      isPrivate: true,
      isMine: false,
      timestamp: timestamp,
    );

    expect(message.isRadarLocation, isTrue);
    expect(message.radarLocation?.latitude, closeTo(4.609710, 0.000001));
    expect(message.radarLocation?.longitude, closeTo(-74.081750, 0.000001));
    expect(message.radarLocation?.accuracyMeters, 4.2);
    expect(message.radarLocation?.timestamp, timestamp);
  });

  test('rechaza ubicación de radar pública o fuera de rango', () {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    final publicMessage = MeshMessage(
      id: 'location-2',
      sender: 'Ana',
      content: RadarLocationUpdate.encode(
        latitude: 4,
        longitude: -74,
        accuracyMeters: 5,
        timestamp: timestamp,
      ),
      senderPeerId: 'peer-a',
      isPrivate: false,
      isMine: false,
      timestamp: timestamp,
    );

    expect(publicMessage.radarLocation, isNull);
    expect(
      RadarLocationUpdate.tryParse(
        '[HB-LOC|91.000000|-74.000000|5.0|1700000000000]',
      ),
      isNull,
    );
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

  test('gateway excluye simulacros del canal derivado del flag firmado', () {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    final message = MeshMessage(
      id: 'drill-channel',
      sender: 'Ana',
      content: 'SOS|Práctica||',
      senderPeerId: 'peer-a',
      isPrivate: false,
      isMine: false,
      timestamp: timestamp,
      channel: 'drill',
    );

    expect(EmergencyGatewayController.isEmergencyEligible(message), isFalse);
  });
}
