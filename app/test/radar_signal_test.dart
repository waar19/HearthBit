import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/services/radar_fusion.dart';
import 'package:hearth_bit/services/radar_signal.dart';

void main() {
  group('RadarSignalProcessor', () {
    test('suaviza el RSSI con media móvil exponencial', () {
      final processor = RadarSignalProcessor();
      final start = DateTime(2026, 8, 12, 10);
      final first = processor.addSample(-70, start);
      expect(first.smoothedRssi, -70);
      // Un pico aislado de +20 dB no debe mover la señal 20 dB.
      final second = processor.addSample(
        -50,
        start.add(const Duration(milliseconds: 500)),
      );
      expect(second.smoothedRssi, greaterThan(-70));
      expect(second.smoothedRssi, lessThan(-60));
    });

    test('detecta acercamiento cuando la señal sube sostenidamente', () {
      final processor = RadarSignalProcessor();
      final start = DateTime(2026, 8, 12, 10);
      RadarReading? reading;
      for (var i = 0; i < 20; i++) {
        reading = processor.addSample(
          -90 + i * 2,
          start.add(Duration(milliseconds: 500 * i)),
        );
      }
      expect(reading!.trend, RadarTrend.approaching);
    });

    test('detecta alejamiento cuando la señal baja sostenidamente', () {
      final processor = RadarSignalProcessor();
      final start = DateTime(2026, 8, 12, 10);
      RadarReading? reading;
      for (var i = 0; i < 20; i++) {
        reading = processor.addSample(
          -50 - i * 2,
          start.add(Duration(milliseconds: 500 * i)),
        );
      }
      expect(reading!.trend, RadarTrend.receding);
    });

    test('señal constante reporta tendencia estable', () {
      final processor = RadarSignalProcessor();
      final start = DateTime(2026, 8, 12, 10);
      RadarReading? reading;
      for (var i = 0; i < 20; i++) {
        reading = processor.addSample(
          -70,
          start.add(Duration(milliseconds: 500 * i)),
        );
      }
      expect(reading!.trend, RadarTrend.steady);
    });

    test('clasifica bandas de proximidad según el RSSI', () {
      expect(
        RadarSignalProcessor().addSample(-45, DateTime.now()).proximity,
        RadarProximity.veryClose,
      );
      expect(
        RadarSignalProcessor().addSample(-65, DateTime.now()).proximity,
        RadarProximity.close,
      );
      expect(
        RadarSignalProcessor().addSample(-80, DateTime.now()).proximity,
        RadarProximity.inRange,
      );
      expect(
        RadarSignalProcessor().addSample(-95, DateTime.now()).proximity,
        RadarProximity.far,
      );
    });

    test('la distancia estimada crece al debilitarse la señal', () {
      final near = RadarSignalProcessor().addSample(-55, DateTime.now());
      final far = RadarSignalProcessor().addSample(-85, DateTime.now());
      expect(near.approxDistanceMeters, lessThan(far.approxDistanceMeters));
      expect(near.approxDistanceMeters, lessThan(2));
    });

    test('marca la señal como perdida tras el tiempo configurado', () {
      final processor = RadarSignalProcessor();
      final start = DateTime(2026, 8, 12, 10);
      processor.addSample(-70, start);
      expect(processor.isStale(start.add(const Duration(seconds: 2))), isFalse);
      expect(processor.isStale(start.add(const Duration(seconds: 6))), isTrue);
    });

    test('sin muestras nunca está perdida (aún buscando)', () {
      expect(RadarSignalProcessor().isStale(DateTime.now()), isFalse);
    });

    test('la fuerza queda acotada entre 0 y 1', () {
      expect(
        RadarSignalProcessor().addSample(-30, DateTime.now()).strength,
        1.0,
      );
      expect(
        RadarSignalProcessor().addSample(-110, DateTime.now()).strength,
        0.0,
      );
    });
  });

  group('SweepEstimator', () {
    test('estima el sector con señal más fuerte después de una vuelta', () {
      final estimator = SweepEstimator();
      for (var sector = 0; sector < 12; sector++) {
        final heading = 15.0 + sector * 30;
        final rssi = sector == 3 ? -50.0 : -75.0;
        estimator
          ..addSample(headingDegrees: heading, rssi: rssi)
          ..addSample(headingDegrees: heading, rssi: rssi - 1);
      }

      expect(estimator.isComplete, isTrue);
      expect(estimator.progress, 1);
      expect(estimator.estimate, isNotNull);
      expect(estimator.estimate!.headingDegrees, closeTo(105, 0.1));
      expect(estimator.estimate!.confidence, greaterThan(0.5));
    });

    test('reporta confianza baja cuando la señal es plana', () {
      final estimator = SweepEstimator();
      for (var sector = 0; sector < 12; sector++) {
        final heading = 15.0 + sector * 30;
        estimator
          ..addSample(headingDegrees: heading, rssi: -70)
          ..addSample(headingDegrees: heading, rssi: -70);
      }

      expect(estimator.isComplete, isTrue);
      expect(estimator.estimate!.confidence, closeTo(0, 0.001));
    });

    test('la mediana por sector ignora un pico BLE aislado', () {
      final estimator = SweepEstimator();
      for (var sector = 0; sector < 12; sector++) {
        final heading = 15.0 + sector * 30;
        estimator
          ..addSample(headingDegrees: heading, rssi: -75)
          ..addSample(headingDegrees: heading, rssi: -75)
          ..addSample(headingDegrees: heading, rssi: sector == 4 ? -30 : -75);
      }

      expect(estimator.isComplete, isTrue);
      expect(estimator.estimate!.confidence, closeTo(0, 0.001));
      expect(estimator.estimate!.hasUsableDirection, isFalse);
    });

    test('solo muestra dirección con contraste suficiente', () {
      expect(
        const SweepEstimate(
          headingDegrees: 30,
          confidence: 0.59,
        ).hasUsableDirection,
        isFalse,
      );
      expect(
        const SweepEstimate(
          headingDegrees: 30,
          confidence: 0.6,
        ).hasUsableDirection,
        isTrue,
      );
    });
  });

  group('RadarFusion', () {
    RadarFusionResult evaluate({
      RadarProximity proximity = RadarProximity.far,
      SweepEstimate? bleEstimate,
      double? heading = 0,
      double distance = 100,
      double? bleDistance,
      double localAccuracy = 3,
      double? targetAccuracy = 5,
      double targetLatitude = 0.001,
      double targetLongitude = 0,
    }) => RadarFusion.evaluate(
      proximity: proximity,
      bleEstimate: bleEstimate,
      headingDegrees: heading,
      localLatitude: 0,
      localLongitude: 0,
      localAccuracyMeters: localAccuracy,
      targetLatitude: targetLatitude,
      targetLongitude: targetLongitude,
      targetAccuracyMeters: targetAccuracy,
      gpsDistanceMeters: distance,
      bleApproxDistanceMeters: bleDistance,
    );

    test('calcula rumbo relativo cruzando cero grados', () {
      expect(RadarFusion.signedAngularDelta(350, 10), 20);
      expect(RadarFusion.signedAngularDelta(10, 350), -20);
      expect(RadarFusion.bearingBetween(0, 0, 1, 0), closeTo(0, 0.01));
      expect(RadarFusion.bearingBetween(0, 0, 0, 1), closeTo(90, 0.01));
    });

    test('prioriza GPS cuando la precisión es adecuada para la distancia', () {
      final result = evaluate();

      expect(result.gpsReliable, isTrue);
      expect(result.source, RadarDirectionSource.gps);
      expect(result.gpsBearingDegrees, closeTo(0, 0.01));
    });

    test('oculta el sector BLE cuando la señal indica menos de dos metros', () {
      final result = evaluate(
        proximity: RadarProximity.veryClose,
        bleEstimate: const SweepEstimate(headingDegrees: 180, confidence: 0.9),
        distance: 5,
      );

      expect(result.bleSuppressedVeryClose, isTrue);
      expect(result.showBleSector, isFalse);
      expect(result.source, RadarDirectionSource.none);
    });

    test(
      'oculta ambas direcciones cuando GPS y BLE fiables se contradicen',
      () {
        final result = evaluate(
          bleEstimate: const SweepEstimate(
            headingDegrees: 180,
            confidence: 0.9,
          ),
        );

        expect(result.sourcesDisagree, isTrue);
        expect(result.adjustedBleConfidence, closeTo(0.315, 0.001));
        expect(result.source, RadarDirectionSource.none);
        expect(result.gpsReliable, isFalse);
      },
    );

    test('usa BLE si GPS no es fiable a corta distancia', () {
      final result = evaluate(
        proximity: RadarProximity.close,
        bleEstimate: const SweepEstimate(headingDegrees: 60, confidence: 0.8),
        distance: 8,
      );

      expect(result.gpsReliable, isFalse);
      expect(result.source, RadarDirectionSource.ble);
      expect(result.showBleSector, isTrue);
    });

    test('descarta el rombo GPS si BLE cercano contradice la distancia', () {
      final result = evaluate(
        proximity: RadarProximity.close,
        distance: 48,
        bleDistance: 1.2,
        targetAccuracy: 15,
      );

      expect(result.gpsRangeConsistent, isFalse);
      expect(result.gpsReliable, isFalse);
      expect(result.source, RadarDirectionSource.none);
    });

    test('no usa rumbo alguno mientras la brújula carece de precisión', () {
      final result = evaluate(heading: null);

      expect(result.gpsReliable, isFalse);
      expect(result.gpsRelativeDegrees, isNull);
      expect(result.source, RadarDirectionSource.none);
    });
  });

  group('MeshMessage SOS', () {
    MeshMessage sos(String content) => MeshMessage(
      id: '1',
      sender: 'Ana',
      content: content,
      senderPeerId: 'abcdef0123456789',
      isPrivate: false,
      isMine: false,
      timestamp: DateTime(2026, 8, 12),
      channel: 'sos',
    );

    test('extrae descripción y coordenadas', () {
      final message = sos('SOS|Estoy atrapado|4.60971|-74.08175');
      expect(message.sosDescription, 'Estoy atrapado');
      expect(message.sosLatitude, closeTo(4.60971, 1e-9));
      expect(message.sosLongitude, closeTo(-74.08175, 1e-9));
    });

    test('sin GPS devuelve coordenadas nulas', () {
      final message = sos('SOS|Necesito ayuda||');
      expect(message.sosDescription, 'Necesito ayuda');
      expect(message.sosLatitude, isNull);
      expect(message.sosLongitude, isNull);
    });
  });
}
