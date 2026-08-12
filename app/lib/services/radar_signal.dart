import 'dart:math' as math;

/// Qué tan cerca está el objetivo según la señal BLE suavizada.
enum RadarProximity { veryClose, close, inRange, far }

/// Hacia dónde evoluciona la señal en los últimos segundos.
enum RadarTrend { approaching, receding, steady, unknown }

/// Lectura procesada del radar: señal suavizada, banda de proximidad,
/// tendencia y una distancia orientativa (el BLE no es un metro láser).
class RadarReading {
  const RadarReading({
    required this.smoothedRssi,
    required this.strength,
    required this.proximity,
    required this.trend,
    required this.approxDistanceMeters,
    required this.at,
  });

  final double smoothedRssi;

  /// 0.0 (señal mínima utilizable) a 1.0 (pegado al dispositivo).
  final double strength;
  final RadarProximity proximity;
  final RadarTrend trend;
  final double approxDistanceMeters;
  final DateTime at;
}

/// Convierte lecturas RSSI crudas (ruidosas por naturaleza) en una señal
/// estable estilo AirTag: media móvil exponencial para el valor, comparación
/// con la señal de hace unos segundos para la tendencia (con histéresis para
/// no parpadear) y modelo log-distancia para estimar metros.
class RadarSignalProcessor {
  RadarSignalProcessor({
    this.smoothingFactor = 0.25,
    this.trendWindow = const Duration(seconds: 4),
    this.trendThresholdDb = 2.0,
    this.staleAfter = const Duration(seconds: 5),
    this.txPowerAtOneMeter = -59.0,
    this.pathLossExponent = 2.4,
  });

  final double smoothingFactor;

  /// Contra qué momento del pasado se compara la señal para la tendencia.
  final Duration trendWindow;

  /// Cambio mínimo en dB para declarar acercamiento/alejamiento.
  final double trendThresholdDb;

  /// Sin muestras durante este tiempo, la señal se considera perdida.
  final Duration staleAfter;

  /// RSSI esperado a 1 m; típico para teléfonos con TX medio.
  final double txPowerAtOneMeter;

  /// Exponente de pérdida: ~2 en campo abierto, 3-4 con escombros/paredes.
  final double pathLossExponent;

  final List<({DateTime at, double rssi})> _history = [];
  double? _smoothed;
  DateTime? _lastSampleAt;

  RadarReading? get last => _lastReading;
  RadarReading? _lastReading;

  int get sampleCount => _history.length;

  /// Procesa una muestra cruda y devuelve la lectura suavizada.
  RadarReading addSample(int rssi, DateTime at) {
    final previous = _smoothed;
    final smoothed = previous == null
        ? rssi.toDouble()
        : previous + smoothingFactor * (rssi - previous);
    _smoothed = smoothed;
    _lastSampleAt = at;
    _history.add((at: at, rssi: smoothed));
    _history.removeWhere((entry) => at.difference(entry.at) > trendWindow * 3);
    final reading = RadarReading(
      smoothedRssi: smoothed,
      strength: _strength(smoothed),
      proximity: _proximity(smoothed),
      trend: _trend(smoothed, at),
      approxDistanceMeters: _distance(smoothed),
      at: at,
    );
    _lastReading = reading;
    return reading;
  }

  /// true si no hay muestras recientes y la persona debe volver sobre sus pasos.
  bool isStale(DateTime now) {
    final lastAt = _lastSampleAt;
    if (lastAt == null) return false;
    return now.difference(lastAt) > staleAfter;
  }

  void reset() {
    _history.clear();
    _smoothed = null;
    _lastSampleAt = null;
    _lastReading = null;
  }

  double _strength(double rssi) =>
      ((rssi + 100.0) / 45.0).clamp(0.0, 1.0).toDouble();

  RadarProximity _proximity(double rssi) {
    if (rssi >= -55) return RadarProximity.veryClose;
    if (rssi >= -70) return RadarProximity.close;
    if (rssi >= -85) return RadarProximity.inRange;
    return RadarProximity.far;
  }

  RadarTrend _trend(double current, DateTime at) {
    // Referencia: la muestra suavizada más antigua dentro de la ventana.
    ({DateTime at, double rssi})? reference;
    for (final entry in _history) {
      final age = at.difference(entry.at);
      if (age >= trendWindow) {
        reference = entry;
      } else if (reference == null && age >= trendWindow ~/ 2) {
        reference = entry;
      }
    }
    if (reference == null) return RadarTrend.unknown;
    final delta = current - reference.rssi;
    if (delta >= trendThresholdDb) return RadarTrend.approaching;
    if (delta <= -trendThresholdDb) return RadarTrend.receding;
    return RadarTrend.steady;
  }

  double _distance(double rssi) => math
      .pow(10, (txPowerAtOneMeter - rssi) / (10 * pathLossExponent))
      .toDouble();
}

class SweepEstimate {
  const SweepEstimate({required this.headingDegrees, required this.confidence});

  /// Rumbo magnético aproximado (0° norte, 90° este).
  final double headingDegrees;

  /// Contraste relativo entre el sector más fuerte y el promedio, de 0 a 1.
  final double confidence;
}

/// Estima el rumbo de una señal BLE mientras la persona gira lentamente.
///
/// No mide ángulo de llegada: aprovecha la atenuación que producen el cuerpo
/// y el teléfono para comparar RSSI por sectores de brújula.
class SweepEstimator {
  SweepEstimator({
    this.sectorCount = 12,
    this.minimumSamplesPerSector = 2,
    this.minimumRotationDegrees = 330,
    this.confidenceScaleDb = 12,
  }) : assert(sectorCount > 2),
       assert(minimumSamplesPerSector > 0),
       assert(minimumRotationDegrees > 0),
       assert(confidenceScaleDb > 0),
       _rssiBySector = List.generate(sectorCount, (_) => <double>[]);

  final int sectorCount;
  final int minimumSamplesPerSector;
  final double minimumRotationDegrees;
  final double confidenceScaleDb;
  final List<List<double>> _rssiBySector;

  double? _lastHeading;
  double _rotationDegrees = 0;

  int get coveredSectors => _rssiBySector
      .where((samples) => samples.length >= minimumSamplesPerSector)
      .length;

  List<bool> get sectorCoverage => List.unmodifiable(
    _rssiBySector.map((samples) => samples.length >= minimumSamplesPerSector),
  );

  double get progress {
    final coverage = coveredSectors / sectorCount;
    final rotation = (_rotationDegrees / minimumRotationDegrees).clamp(
      0.0,
      1.0,
    );
    return math.min(coverage, rotation);
  }

  bool get isComplete =>
      coveredSectors == sectorCount &&
      _rotationDegrees >= minimumRotationDegrees;

  SweepEstimate? get estimate {
    if (!isComplete) return null;
    final averages = _rssiBySector
        .map((samples) => samples.reduce((a, b) => a + b) / samples.length)
        .toList(growable: false);
    var strongestSector = 0;
    for (var index = 1; index < averages.length; index++) {
      if (averages[index] > averages[strongestSector]) {
        strongestSector = index;
      }
    }
    final average = averages.reduce((a, b) => a + b) / averages.length;
    final contrastDb = averages[strongestSector] - average;
    return SweepEstimate(
      headingDegrees: (strongestSector + 0.5) * (360 / sectorCount),
      confidence: (contrastDb / confidenceScaleDb).clamp(0.0, 1.0),
    );
  }

  void addSample({required double headingDegrees, required double rssi}) {
    final heading = _normalizeHeading(headingDegrees);
    final previous = _lastHeading;
    if (previous != null) {
      var delta = (heading - previous).abs();
      if (delta > 180) delta = 360 - delta;
      // Saltos grandes suelen ser interferencia magnética, no un giro real.
      if (delta <= 60) _rotationDegrees += delta;
    }
    _lastHeading = heading;
    final sectorWidth = 360 / sectorCount;
    final sector = (heading / sectorWidth)
        .floor()
        .clamp(0, sectorCount - 1)
        .toInt();
    _rssiBySector[sector].add(rssi);
  }

  void reset() {
    for (final samples in _rssiBySector) {
      samples.clear();
    }
    _lastHeading = null;
    _rotationDegrees = 0;
  }

  static double _normalizeHeading(double heading) {
    final normalized = heading % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }
}
