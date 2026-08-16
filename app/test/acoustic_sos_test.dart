import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/acoustic_sos.dart';

void main() {
  test('FSK acústico recupera un SOS firmado con desfase y ruido', () {
    final payload = Uint8List.fromList(
      List<int>.generate(112, (index) => index * 37 & 0xff),
    );
    final encoded = AcousticSosModem.modulate(payload);
    final random = math.Random(7);
    final samples = Float64List(137 + encoded.length + 211);
    for (var index = 0; index < samples.length; index++) {
      samples[index] = (random.nextDouble() - 0.5) * 0.025;
    }
    for (var index = 0; index < encoded.length; index++) {
      samples[137 + index] += encoded[index];
    }

    expect(AcousticSosModem.demodulate(samples), payload);
  });

  test('FSK acústico rechaza CRC alterado y payloads demasiado grandes', () {
    expect(
      () => AcousticSosModem.modulate(
        Uint8List(AcousticSosModem.maximumPayloadBytes + 1),
      ),
      throwsFormatException,
    );

    final encoded = AcousticSosModem.modulate(Uint8List.fromList([1, 2, 3]));
    final damaged = Float64List.fromList(encoded);
    final start = damaged.length - AcousticSosModem.symbolSamples * 2;
    damaged.fillRange(start, damaged.length, 0);
    expect(AcousticSosModem.demodulate(damaged), isNull);
  });

  test('duración de la ráfaga queda acotada para emergencia', () {
    expect(
      AcousticSosModem.durationForPayload(120),
      lessThan(const Duration(seconds: 5)),
    );
    expect(
      AcousticSosModem.durationForPayload(AcousticSosModem.maximumPayloadBytes),
      lessThan(const Duration(seconds: 11)),
    );
  });
}
