import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/utils/avatar_utils.dart';
import 'package:hearth_bit/utils/emergency_backoff.dart';
import 'package:hearth_bit/utils/emergency_coordinates.dart';
import 'package:hearth_bit/utils/emergency_qr_fallback.dart';
import 'package:hearth_bit/utils/hex_encoding.dart';
import 'package:hearth_bit/utils/id_generator.dart';
import 'package:hearth_bit/utils/message_timeline.dart';
import 'package:hearth_bit/utils/mime_guess.dart';
import 'package:hearth_bit/utils/voice_formatting.dart';
import 'package:hearth_bit/controllers/transfer_controller.dart';
import 'package:hearth_bit/models/transfer_models.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/services/transfer_protocol.dart';

void main() {
  test('formatVoiceDuration muestra minutos y segundos', () {
    expect(formatVoiceDuration(const Duration(seconds: 65)), '1:05');
    expect(formatVoiceDuration(const Duration(seconds: 0)), '0:00');
  });

  test('avatarLetter usa la primera letra o ?', () {
    expect(avatarLetter('Ana'), 'A');
    expect(avatarLetter(''), '?');
  });

  test('coarsenEmergencyCoordinate redondea a tres decimales', () {
    expect(coarsenEmergencyCoordinate(4.609710), 4.610);
    expect(coarsenEmergencyCoordinate(-74.081750), -74.082);
  });

  test('emergencyRetryBackoff respeta el máximo', () {
    final backoff = emergencyRetryBackoff(
      attempts: 10,
      maximumBackoff: const Duration(minutes: 5),
    );
    expect(backoff, const Duration(minutes: 5));
    expect(
      emergencyRetryBackoff(
        attempts: 1,
        maximumBackoff: const Duration(minutes: 5),
      ),
      const Duration(seconds: 15),
    );
  });

  test('emergencyQrFallbackText incluye descripción y GPS', () {
    final text = emergencyQrFallbackText(
      content: 'SOS|Ayuda|4.610|-74.082',
      peerId: 'peer-1',
      defaultMessage: 'SOS',
    );
    expect(text, contains('Ayuda'));
    expect(text, contains('GPS: 4.610, -74.082'));
    expect(text, contains('peer-1'));
  });

  test('hex encoding hace round-trip', () {
    final bytes = hexToBytes('0102ff');
    expect(bytesToHex(bytes), '0102ff');
  });

  test('ids generados son únicos y prefijados', () {
    final random = Random(1);
    expect(newEmergencyLocalId(random), startsWith('EMG-'));
    expect(newPrivateMessageLocalId(random), startsWith('dm-'));
  });

  test('messageTimelineEntries agrupa por día', () {
    final messages = [
      MeshMessage(
        id: '1',
        sender: 'A',
        content: 'hola',
        senderPeerId: 'p1',
        isPrivate: false,
        isMine: false,
        timestamp: DateTime(2026, 8, 11, 22),
      ),
      MeshMessage(
        id: '2',
        sender: 'A',
        content: 'otro',
        senderPeerId: 'p1',
        isPrivate: false,
        isMine: false,
        timestamp: DateTime(2026, 8, 12, 1),
      ),
    ];
    final entries = messageTimelineEntries(messages);
    expect(entries.where((entry) => entry.day != null).length, 2);
    expect(entries.where((entry) => entry.message != null).length, 2);
  });

  test('guessMimeType reconoce apk e imágenes', () {
    expect(guessMimeType('foto.jpg'), 'image/jpeg');
    expect(guessMimeType('app.apk'), TransferController.androidPackageMimeType);
    expect(guessMimeType('bin'), 'application/octet-stream');
  });

  test('transferWireId y transferFromWireId son inversos', () {
    for (final transport in TransferTransport.values) {
      expect(transferFromWireId(transferWireId(transport)), transport);
    }
  });
}
