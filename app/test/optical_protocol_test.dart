import 'dart:convert';
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

  group('manifiestos firmados (Hueco 2)', () {
    OpticalHeader _validSignedHeader({
      String senderPeerId = '0011223344556677',
      int protocolVersion = OpticalProtocol.version,
    }) {
      return OpticalHeader(
        transferId: Uint8List.fromList(List.generate(16, (i) => i * 7)),
        seed: 0x12345678,
        fileSize: 1024,
        chunkSize: 256,
        chunkCount: 4,
        sha256: Uint8List.fromList(List.generate(32, (i) => i * 3)),
        fileName: 'reporte.pdf',
        senderPeerId: senderPeerId,
        protocolVersion: protocolVersion,
        signature: Uint8List.fromList(List.generate(64, (i) => i * 5)),
      );
    }

    test(
      'v2 con firma truncada o ausente es rechazado por el decoder',
      () {
        final valid = _validSignedHeader();
        final encoded = base64Decode(OpticalProtocol.encodeHeader(valid));

        // Truncar la firma a 32 bytes (deberían ser 64).
        final truncated = Uint8List.sublistView(encoded, 0, encoded.length - 32);
        expect(OpticalProtocol.decode(base64Encode(truncated)), isNull);

        // Quitar la firma por completo.
        final noSignature = Uint8List.sublistView(
          encoded,
          0,
          encoded.length - OpticalProtocol.signatureLength,
        );
        expect(OpticalProtocol.decode(base64Encode(noSignature)), isNull);
      },
    );

    test(
      'v2 con senderPeerId vacío es rechazado (no se puede verificar origen)',
      () {
        final header = _validSignedHeader(senderPeerId: '');
        // encodeHeader debe fallar (incoherente) porque v2 exige peerId.
        expect(() => OpticalProtocol.encodeHeader(header), throwsArgumentError);
      },
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
