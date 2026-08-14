import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/models/voice_note.dart';

void main() {
  test('conserva duración, transferencia y onda compacta', () {
    final envelope = VoiceNoteEnvelope(
      transferId: '00112233445566778899aabbccddeeff',
      durationSeconds: 20,
      waveform: List.generate(80, (index) => (index % 16) / 15),
    );

    final encoded = envelope.encode();
    final decoded = VoiceNoteEnvelope.tryParse(encoded);

    expect(decoded, isNotNull);
    expect(decoded!.transferId, envelope.transferId);
    expect(decoded.durationSeconds, 20);
    expect(decoded.waveform, hasLength(32));
    expect(
      decoded.waveform.every((sample) => sample >= .08 && sample <= 1),
      isTrue,
    );
  });

  test('mantiene compatibilidad con notas sin onda', () {
    final decoded = VoiceNoteEnvelope.tryParse(
      '[HB-VOICE|00112233445566778899aabbccddeeff|7]',
    );

    expect(decoded, isNotNull);
    expect(decoded!.waveform, isEmpty);
    expect(decoded.encode(), '[HB-VOICE|00112233445566778899aabbccddeeff|7]');
  });

  test('rechaza metadatos de voz inválidos', () {
    expect(
      VoiceNoteEnvelope.tryParse(
        '[HB-VOICE|00112233445566778899aabbccddeeff|0|abcdef12]',
      ),
      isNull,
    );
    expect(VoiceNoteEnvelope.tryParse('[HB-VOICE|not-a-transfer|10]'), isNull);
  });
}
