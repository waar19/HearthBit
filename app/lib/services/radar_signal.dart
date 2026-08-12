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
