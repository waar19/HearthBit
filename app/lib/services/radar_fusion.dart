import 'dart:math' as math;

import 'radar_signal.dart';

enum RadarDirectionSource { gps, ble, none }

enum RadarPrecisionSource { radio, acoustic }

class RadarFusionResult {
  const RadarFusionResult({
    required this.source,
    required this.gpsBearingDegrees,
    required this.gpsRelativeDegrees,
    required this.gpsReliable,
    required this.gpsRangeConsistent,
    required this.showBleSector,
    required this.adjustedBleConfidence,
    required this.bleSuppressedVeryClose,
    required this.sourcesDisagree,
    required this.preferredDistanceMeters,
    required this.distanceErrorMeters,
    required this.precisionSource,
    required this.distanceConfidence,
  });

  final RadarDirectionSource source;
  final double? gpsBearingDegrees;
  final double? gpsRelativeDegrees;
  final bool gpsReliable;
  final bool gpsRangeConsistent;
  final bool showBleSector;
  final double adjustedBleConfidence;
  final bool bleSuppressedVeryClose;
  final bool sourcesDisagree;
  final double? preferredDistanceMeters;
  final double? distanceErrorMeters;
  final RadarPrecisionSource? precisionSource;
  final double distanceConfidence;

  bool get hasMeasuredDistance => precisionSource != null;
}

/// Combina navegación GPS de largo alcance con proximidad y barrido BLE.
///
/// GPS aporta un rumbo geográfico cuando su error es pequeño frente a la
/// distancia. BLE solo aporta un sector experimental; a muy corta distancia
/// se oculta porque reflexiones, cuerpo y orientación de antena lo dominan.
class RadarFusion {
  const RadarFusion._();

  static const double minimumGpsDistanceMeters = 10;
  static const double maximumCombinedGpsAccuracyMeters = 35;
  static const double gpsAccuracySafetyFactor = 2;
  static const double maximumSourceAgreementDegrees = 90;
  static const double unknownTargetAccuracyMeters = 15;

  static RadarFusionResult evaluate({
    required RadarProximity? proximity,
    required SweepEstimate? bleEstimate,
    required double? headingDegrees,
    required double? localLatitude,
    required double? localLongitude,
    required double? localAccuracyMeters,
    required double? targetLatitude,
    required double? targetLongitude,
    required double? targetAccuracyMeters,
    required double? gpsDistanceMeters,
    required double? bleApproxDistanceMeters,
    double? precisionDistanceMeters,
    double? precisionDistanceErrorMeters,
    double precisionDistanceConfidence = 0,
    RadarPrecisionSource? precisionSource,
  }) {
    final hasGpsCoordinates =
        localLatitude != null &&
        localLongitude != null &&
        targetLatitude != null &&
        targetLongitude != null;
    final gpsBearing = hasGpsCoordinates
        ? bearingBetween(
            localLatitude,
            localLongitude,
            targetLatitude,
            targetLongitude,
          )
        : null;
    final gpsRelative = gpsBearing != null && headingDegrees != null
        ? signedAngularDelta(headingDegrees, gpsBearing)
        : null;
    final localAccuracy = localAccuracyMeters;
    final combinedAccuracy = localAccuracy == null
        ? null
        : math.sqrt(
            localAccuracy * localAccuracy +
                math.pow(
                  targetAccuracyMeters ?? unknownTargetAccuracyMeters,
                  2,
                ),
          );
    final gpsQualityAdequate =
        gpsBearing != null &&
        gpsRelative != null &&
        gpsDistanceMeters != null &&
        combinedAccuracy != null &&
        gpsDistanceMeters >= minimumGpsDistanceMeters &&
        combinedAccuracy <= maximumCombinedGpsAccuracyMeters &&
        gpsDistanceMeters >= combinedAccuracy * gpsAccuracySafetyFactor;

    final veryClose = proximity == RadarProximity.veryClose;
    final rawBleConfidence = bleEstimate?.confidence ?? 0;
    final gpsRangeConsistent = _gpsAndBleRangesAgree(
      proximity: proximity,
      gpsDistanceMeters: gpsDistanceMeters,
      bleApproxDistanceMeters: bleApproxDistanceMeters,
      combinedGpsAccuracyMeters: combinedAccuracy,
    );
    final sourcesDisagree =
        gpsQualityAdequate &&
        gpsRangeConsistent &&
        bleEstimate != null &&
        bleEstimate.hasUsableDirection &&
        angularDistance(gpsBearing, bleEstimate.headingDegrees) >
            maximumSourceAgreementDegrees;
    final adjustedBleConfidence = sourcesDisagree
        ? rawBleConfidence * 0.35
        : rawBleConfidence;
    final gpsReliable =
        gpsQualityAdequate && gpsRangeConsistent && !sourcesDisagree;
    final bleUsable =
        !veryClose &&
        bleEstimate != null &&
        adjustedBleConfidence >= SweepEstimate.minimumDirectionalConfidence;
    final source = gpsReliable
        ? RadarDirectionSource.gps
        : bleUsable
        ? RadarDirectionSource.ble
        : RadarDirectionSource.none;

    return RadarFusionResult(
      source: source,
      gpsBearingDegrees: gpsBearing,
      gpsRelativeDegrees: gpsRelative,
      gpsReliable: gpsReliable,
      gpsRangeConsistent: gpsRangeConsistent,
      showBleSector: source == RadarDirectionSource.ble,
      adjustedBleConfidence: adjustedBleConfidence,
      bleSuppressedVeryClose: veryClose && bleEstimate != null,
      sourcesDisagree: sourcesDisagree,
      preferredDistanceMeters:
          precisionDistanceMeters ??
          bleApproxDistanceMeters ??
          gpsDistanceMeters,
      distanceErrorMeters: precisionDistanceMeters == null
          ? null
          : precisionDistanceErrorMeters,
      precisionSource: precisionDistanceMeters == null ? null : precisionSource,
      distanceConfidence: precisionDistanceMeters == null
          ? 0
          : precisionDistanceConfidence.clamp(0.0, 1.0),
    );
  }

  /// Rumbo inicial geográfico: 0° norte, 90° este.
  static double bearingBetween(
    double fromLatitude,
    double fromLongitude,
    double toLatitude,
    double toLongitude,
  ) {
    final lat1 = _radians(fromLatitude);
    final lat2 = _radians(toLatitude);
    final deltaLongitude = _radians(toLongitude - fromLongitude);
    final y = math.sin(deltaLongitude) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLongitude);
    return normalizeDegrees(math.atan2(y, x) * 180 / math.pi);
  }

  /// Ángulo de [from] hacia [to] en el intervalo [-180°, 180°).
  static double signedAngularDelta(double from, double to) {
    final delta = normalizeDegrees(to) - normalizeDegrees(from);
    return ((delta + 540) % 360) - 180;
  }

  static double angularDistance(double first, double second) =>
      signedAngularDelta(first, second).abs();

  static bool _gpsAndBleRangesAgree({
    required RadarProximity? proximity,
    required double? gpsDistanceMeters,
    required double? bleApproxDistanceMeters,
    required double? combinedGpsAccuracyMeters,
  }) {
    if (gpsDistanceMeters == null ||
        proximity == null ||
        proximity == RadarProximity.far) {
      return true;
    }
    final proximityUpperBound = switch (proximity) {
      RadarProximity.veryClose => 4.0,
      RadarProximity.close => 12.0,
      RadarProximity.inRange => 35.0,
      RadarProximity.far => double.infinity,
    };
    final bleUpperBound = bleApproxDistanceMeters == null
        ? proximityUpperBound
        : math.max(proximityUpperBound, bleApproxDistanceMeters * 3);
    final uncertaintyBound = (combinedGpsAccuracyMeters ?? 0) * 2;
    return gpsDistanceMeters <= math.max(bleUpperBound, uncertaintyBound);
  }

  static double normalizeDegrees(double degrees) {
    final normalized = degrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
