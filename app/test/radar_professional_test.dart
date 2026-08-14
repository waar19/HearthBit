import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/acoustic_sonar.dart';
import 'package:hearth_bit/services/compass_calibration_gate.dart';
import 'package:hearth_bit/services/radar_fusion.dart';
import 'package:hearth_bit/services/radar_signal.dart';
import 'package:hearth_bit/services/radar_ui_state.dart';
import 'package:hearth_bit/services/ranging_control_protocol.dart';

void main() {
  group('CompassCalibrationGate', () {
    test('usa histéresis y exige dos segundos sostenidos', () {
      final gate = CompassCalibrationGate();
      final start = DateTime(2026, 8, 13);

      expect(gate.update(30, start), isFalse);
      expect(
        gate.update(30, start.add(const Duration(milliseconds: 1900))),
        isFalse,
      );
      expect(gate.update(30, start.add(const Duration(seconds: 2))), isTrue);
      expect(gate.update(20, start.add(const Duration(seconds: 5))), isTrue);
      expect(gate.update(10, start.add(const Duration(seconds: 6))), isTrue);
      expect(gate.update(10, start.add(const Duration(seconds: 8))), isFalse);
    });
  });

  test('el filtro circular cruza cero sin saltar hacia 180 grados', () {
    final filter = CircularHeadingFilter(smoothingFactor: 0.5);
    filter.add(359);
    final value = filter.add(1);
    expect(math.min(value, 360 - value), lessThan(2));
  });

  group('estado estable del radar', () {
    test('el banner respeta la prioridad de seguridad', () {
      expect(
        resolveRadarBanner(
          permissionExpired: false,
          hasStartError: false,
          signalLost: true,
          compassNeedsCalibration: true,
          sourcesDisagree: true,
          sweepExpired: true,
          tentativeSignal: true,
        ),
        RadarBannerKind.signalLost,
      );
    });

    test('el barrido caduca por tiempo o desplazamiento', () {
      final start = DateTime(2026, 8, 13);
      final anchor = RadarSweepAnchor(
        capturedAt: start,
        latitude: 4.6,
        longitude: -74.08,
      );
      expect(
        anchor.isFresh(
          now: start.add(const Duration(seconds: 80)),
          currentLatitude: 4.60001,
          currentLongitude: -74.08,
        ),
        isTrue,
      );
      expect(
        anchor.isFresh(
          now: start.add(const Duration(seconds: 91)),
          currentLatitude: 4.6,
          currentLongitude: -74.08,
        ),
        isFalse,
      );
      expect(
        anchor.isFresh(
          now: start.add(const Duration(seconds: 20)),
          currentLatitude: 4.6002,
          currentLongitude: -74.08,
        ),
        isFalse,
      );
    });
  });

  test('la mediana rechaza un pico RSSI aislado antes del EMA', () {
    final processor = RadarSignalProcessor();
    final start = DateTime(2026, 8, 13);
    for (var index = 0; index < 5; index++) {
      processor.addSample(-70, start.add(Duration(milliseconds: index * 500)));
    }
    final reading = processor.addSample(
      -20,
      start.add(const Duration(seconds: 3)),
    );
    expect(reading.smoothedRssi, closeTo(-70, 0.01));
  });

  test('la distancia precisa prevalece sobre el cálculo RSSI', () {
    final result = RadarFusion.evaluate(
      proximity: RadarProximity.close,
      bleEstimate: null,
      headingDegrees: null,
      localLatitude: null,
      localLongitude: null,
      localAccuracyMeters: null,
      targetLatitude: null,
      targetLongitude: null,
      targetAccuracyMeters: null,
      gpsDistanceMeters: null,
      bleApproxDistanceMeters: 8,
      precisionDistanceMeters: 2.4,
      precisionDistanceErrorMeters: 0.2,
      precisionDistanceConfidence: 0.9,
      precisionSource: RadarPrecisionSource.radio,
    );
    expect(result.preferredDistanceMeters, 2.4);
    expect(result.hasMeasuredDistance, isTrue);
    expect(result.distanceErrorMeters, 0.2);
  });

  group('RangingControlProtocol', () {
    test('codifica y decodifica payload con datos OOB', () {
      final nonce = Uint8List.fromList(
        List<int>.generate(16, (index) => index),
      );
      final encoded = RangingControlProtocol.encode(
        action: RangingControlAction.result,
        technology: RangingTechnology.acoustic,
        sessionNonce: nonce,
        round: 2,
        value: 3.25,
        errorMeters: 0.15,
        confidence: 0.88,
        opaqueData: Uint8List.fromList([1, 2, 3]),
      );
      final decoded = RangingControlProtocol.decode(encoded)!;
      expect(decoded.action, RangingControlAction.result);
      expect(decoded.technology, RangingTechnology.acoustic);
      expect(decoded.round, 2);
      expect(decoded.value, closeTo(3.25, 0.0001));
      expect(decoded.errorMeters, closeTo(0.15, 0.0001));
      expect(decoded.opaqueData, [1, 2, 3]);
    });
  });

  group('AcousticSonarDsp', () {
    test('detecta dos chirridos en una señal sintética con ruido', () {
      final chirp = AcousticSonarDsp.generateChirp();
      final samples = List<double>.generate(
        14000,
        (index) => math.sin(index * 0.37) * 0.002,
      );
      for (final start in [1200, 8200]) {
        for (var index = 0; index < chirp.length; index++) {
          samples[start + index] += chirp[index];
        }
      }
      final detections = AcousticSonarDsp.detectChirps(samples);
      expect(detections, hasLength(2));
      expect(detections[0].sampleIndex, closeTo(1200, 3));
      expect(detections[1].sampleIndex, closeTo(8200, 3));
    });

    test('BeepBeep elimina el desfase entre relojes', () {
      const local = AcousticRoundObservation(
        selfChirpSample: 1000,
        remoteChirpSample: 11000,
        confidence: 0.9,
      );
      const remote = AcousticRoundObservation(
        selfChirpSample: 10000,
        remoteChirpSample: 840,
        confidence: 0.8,
      );
      final measurement = AcousticSonarDsp.combineRound(
        local: local,
        remote: remote,
      )!;
      expect(measurement.distanceMeters, closeTo(3.0, 0.02));
      expect(measurement.confidence, 0.8);
    });
  });
}
