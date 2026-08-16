import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/optical_protocol.dart';

void main() {
  test('SOS QR conserva anuncio, mensaje y texto legible', () {
    final bundle = OpticalEmergencyBundle(
      announcementFrame: Uint8List.fromList([1, 2, 3, 4]),
      messageFrame: Uint8List.fromList([5, 6, 7]),
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
      announcementFrame: Uint8List.fromList([1]),
      messageFrame: Uint8List.fromList([2]),
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
}
