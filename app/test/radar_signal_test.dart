import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/models/mesh_models.dart';
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
