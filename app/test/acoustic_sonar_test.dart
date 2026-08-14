import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/acoustic_sonar.dart';

void main() {
  test('analiza el DSP fuera del isolate UI', () async {
    final wav = AcousticSonarDsp.chirpWavBytes();
    final pcm = Uint8List.sublistView(wav, 44);
    final analyzer = AcousticSonarStreamAnalyzer()..add(pcm);

    final detections = await analyzer.finishInIsolate(maximumDetections: 1);

    expect(detections, hasLength(1));
    expect(detections.single.sampleIndex, closeTo(0, 2));
  });
}
