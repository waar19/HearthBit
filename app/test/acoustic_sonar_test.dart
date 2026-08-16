import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/acoustic_sonar.dart';

void main() {
  test('el pasa-banda conserva el chirp y atenúa voz grave', () {
    const count = AcousticSonarDsp.sampleRate;
    final inBand = Float64List.fromList(
      List<double>.generate(
        count,
        (index) =>
            math.sin(2 * math.pi * 17500 * index / AcousticSonarDsp.sampleRate),
      ),
    );
    final lowFrequency = Float64List.fromList(
      List<double>.generate(
        count,
        (index) =>
            math.sin(2 * math.pi * 1000 * index / AcousticSonarDsp.sampleRate),
      ),
    );

    final filteredInBand = AcousticSonarDsp.bandPassFilter(inBand);
    final filteredLow = AcousticSonarDsp.bandPassFilter(lowFrequency);

    expect(_rms(filteredInBand), greaterThan(0.45));
    expect(_rms(filteredLow), lessThan(0.03));
  });

  test('detecta el chirp entre ruido grave intenso', () {
    final chirp = AcousticSonarDsp.generateChirp();
    final samples = Float64List(AcousticSonarDsp.sampleRate * 2);
    for (var index = 0; index < samples.length; index++) {
      samples[index] =
          0.8 *
          math.sin(2 * math.pi * 850 * index / AcousticSonarDsp.sampleRate);
    }
    const chirpOffset = 18000;
    for (var index = 0; index < chirp.length; index++) {
      samples[chirpOffset + index] += chirp[index];
    }

    final detections = AcousticSonarDsp.detectChirps(
      samples,
      maximumDetections: 1,
    );

    expect(detections, hasLength(1));
    expect(detections.single.sampleIndex, closeTo(chirpOffset, 3));
  });

  test('mantiene la detección a distintos SNR de ruido blanco', () {
    final chirp = AcousticSonarDsp.generateChirp();
    for (final amplitude in [1.0, 0.55]) {
      final random = math.Random(42);
      final samples = Float64List.fromList(
        List<double>.generate(
          30000,
          (_) => (random.nextDouble() * 2 - 1) * 0.03,
        ),
      );
      const offset = 14000;
      for (var index = 0; index < chirp.length; index++) {
        samples[offset + index] += chirp[index] * amplitude;
      }

      final detections = AcousticSonarDsp.detectChirps(
        samples,
        maximumDetections: 1,
      );

      expect(detections, hasLength(1), reason: 'amplitude=$amplitude');
      expect(
        detections.single.sampleIndex,
        closeTo(offset, 3),
        reason: 'amplitude=$amplitude',
      );
    }
  });

  test('un eco multipath cercano no reemplaza el chirp remoto', () {
    final chirp = AcousticSonarDsp.generateChirp();
    final samples = Float64List(36000);
    const selfOffset = 5000;
    const echoOffset = selfOffset + 1200;
    const remoteOffset = 23000;
    for (var index = 0; index < chirp.length; index++) {
      samples[selfOffset + index] += chirp[index];
      samples[echoOffset + index] += chirp[index] * 0.65;
      samples[remoteOffset + index] += chirp[index] * 0.8;
    }

    final detections = AcousticSonarDsp.detectChirps(
      samples,
      maximumDetections: 4,
    );
    final assignment = AcousticSonarDsp.assignChirps(
      detections: detections,
      expectedSelfSample: selfOffset,
    );

    expect(assignment, isNotNull);
    expect(assignment!.self.sampleIndex, closeTo(selfOffset, 3));
    expect(assignment.remote.sampleIndex, closeTo(remoteOffset, 3));
  });

  test('asigna el chirp propio por timing y descarta su eco cercano', () {
    const expectedSelf = 12000;
    final assignment = AcousticSonarDsp.assignChirps(
      expectedSelfSample: expectedSelf,
      detections: const [
        AcousticDetection(
          sampleIndex: 5000,
          confidence: 0.7,
          peak: 8,
          noiseFloor: 1,
        ),
        AcousticDetection(
          sampleIndex: 12120,
          confidence: 0.95,
          peak: 12,
          noiseFloor: 1,
        ),
        AcousticDetection(
          sampleIndex: 12600,
          confidence: 0.99,
          peak: 13,
          noiseFloor: 1,
        ),
      ],
    );

    expect(assignment, isNotNull);
    expect(assignment!.self.sampleIndex, 12120);
    expect(assignment.remote.sampleIndex, 5000);
  });

  test('reporta que falta el chirp propio fuera de la ventana', () {
    final assignment = AcousticSonarDsp.assignChirps(
      expectedSelfSample: 30000,
      detections: const [
        AcousticDetection(
          sampleIndex: 1000,
          confidence: 0.9,
          peak: 9,
          noiseFloor: 1,
        ),
        AcousticDetection(
          sampleIndex: 5000,
          confidence: 0.8,
          peak: 8,
          noiseFloor: 1,
        ),
      ],
    );

    expect(assignment, isNull);
  });

  test('analiza el DSP fuera del isolate UI', () async {
    final wav = AcousticSonarDsp.chirpWavBytes();
    final pcm = Uint8List.sublistView(wav, 44);
    final analyzer = AcousticSonarStreamAnalyzer()..add(pcm);

    final detections = await analyzer.finishInIsolate(maximumDetections: 1);

    expect(detections, hasLength(1));
    expect(detections.single.sampleIndex, closeTo(0, 2));
  });
}

double _rms(List<double> samples) {
  final start = math.min(1000, samples.length);
  var sum = 0.0;
  for (var index = start; index < samples.length; index++) {
    sum += samples[index] * samples[index];
  }
  return math.sqrt(sum / (samples.length - start));
}
