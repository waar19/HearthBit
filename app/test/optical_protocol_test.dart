import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/optical_protocol.dart';

void main() {
  test('SOS QR conserva anuncio, mensaje y texto legible', () {
    final bundle = OpticalEmergencyBundle(
      announcementFrame: _packet(1, [0xf1, 1, 1]),
      messageFrame: _packet(2, 'SOS|Necesito ayuda||'.codeUnits),
      fallbackText: 'HEARTHBIT SOS\nNecesito ayuda\nID: 00112233',
    );

    final encoded = OpticalProtocol.encodeEmergency(bundle);
    final decoded = OpticalProtocol.decode(encoded);

    expect(decoded, isA<OpticalEmergencyBundle>());
    final emergency = decoded! as OpticalEmergencyBundle;
    expect(emergency.announcementFrame, bundle.announcementFrame);
    expect(emergency.messageFrame, bundle.messageFrame);
    expect(emergency.fallbackText, bundle.fallbackText);
    expect(encoded, contains('\nHEARTHBIT SOS'));
  });

  test('SOS QR rechaza texto visible alterado y frames sobredimensionados', () {
    final bundle = OpticalEmergencyBundle(
      announcementFrame: _packet(1, [0xf1, 1, 1]),
      messageFrame: _packet(2, 'SOS|Ayuda||'.codeUnits),
      fallbackText: 'HEARTHBIT SOS\nAyuda',
    );
    final encoded = OpticalProtocol.encodeEmergency(bundle);

    expect(OpticalProtocol.decode('$encoded alterado'), isNull);
    expect(
      () => OpticalProtocol.encodeEmergency(
        OpticalEmergencyBundle(
          announcementFrame: Uint8List(
            OpticalProtocol.maximumEmergencyFrameLength + 1,
          ),
          messageFrame: Uint8List.fromList([2]),
          fallbackText: 'SOS',
        ),
      ),
      throwsArgumentError,
    );
  });

  test('QR drill exige flags y sender coincidentes', () {
    const content = 'SIMULACRO\n[HB-DRILL|1|CHECKIN|OK|1700000000000]';
    final bundle = OpticalEmergencyBundle(
      announcementFrame: _packet(1, [0xf1, 1, 1], drill: true),
      messageFrame: _packet(2, content.codeUnits, drill: true),
      fallbackText: content,
      isDrill: true,
    );

    final decoded = OpticalProtocol.decode(
      OpticalProtocol.encodeEmergency(bundle),
    );
    expect(decoded, isA<OpticalEmergencyBundle>());
    expect((decoded! as OpticalEmergencyBundle).isDrill, isTrue);

    final mismatched = OpticalEmergencyBundle(
      announcementFrame: bundle.announcementFrame,
      messageFrame: _packet(2, content.codeUnits, drill: true, senderSeed: 2),
      fallbackText: content,
      isDrill: true,
    );
    expect(
      OpticalProtocol.decode(OpticalProtocol.encodeEmergency(mismatched)),
      isNull,
    );
  });
}

Uint8List _packet(
  int type,
  List<int> payload, {
  bool drill = false,
  int senderSeed = 1,
}) {
  final output = Uint8List(22 + payload.length + 64);
  final data = ByteData.sublistView(output);
  output
    ..[0] = 1
    ..[1] = type
    ..[2] = 7
    ..[11] = 0x02 | (drill ? 0x20 : 0);
  data
    ..setUint64(3, 1)
    ..setUint16(12, payload.length);
  output.setRange(14, 22, List<int>.generate(8, (index) => index + senderSeed));
  output.setRange(22, 22 + payload.length, payload);
  output.fillRange(22 + payload.length, output.length, 0x55);
  return output;
}
