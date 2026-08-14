import 'dart:math' as math;

enum RadarBannerKind {
  permissionExpired,
  startError,
  signalLost,
  compassCalibration,
  sourcesDisagree,
  sweepExpired,
  tentativeSignal,
}

RadarBannerKind? resolveRadarBanner({
  required bool permissionExpired,
  required bool hasStartError,
  required bool signalLost,
  required bool compassNeedsCalibration,
  required bool sourcesDisagree,
  required bool sweepExpired,
  required bool tentativeSignal,
}) {
  if (permissionExpired) return RadarBannerKind.permissionExpired;
  if (hasStartError) return RadarBannerKind.startError;
  if (signalLost) return RadarBannerKind.signalLost;
  if (compassNeedsCalibration) return RadarBannerKind.compassCalibration;
  if (sourcesDisagree) return RadarBannerKind.sourcesDisagree;
  if (sweepExpired) return RadarBannerKind.sweepExpired;
  if (tentativeSignal) return RadarBannerKind.tentativeSignal;
  return null;
}

class RadarSweepAnchor {
  const RadarSweepAnchor({
    required this.capturedAt,
    this.latitude,
    this.longitude,
  });

  final DateTime capturedAt;
  final double? latitude;
  final double? longitude;

  bool isFresh({
    required DateTime now,
    double? currentLatitude,
    double? currentLongitude,
    Duration maximumAge = const Duration(seconds: 90),
    double maximumDisplacementMeters = 15,
  }) {
    if (now.difference(capturedAt) > maximumAge) return false;
    if (latitude == null ||
        longitude == null ||
        currentLatitude == null ||
        currentLongitude == null) {
      return true;
    }
    return _distanceMeters(
          latitude!,
          longitude!,
          currentLatitude,
          currentLongitude,
        ) <=
        maximumDisplacementMeters;
  }

  static double _distanceMeters(
    double fromLatitude,
    double fromLongitude,
    double toLatitude,
    double toLongitude,
  ) {
    const earthRadiusMeters = 6371000.0;
    final fromLat = fromLatitude * math.pi / 180;
    final toLat = toLatitude * math.pi / 180;
    final deltaLat = (toLatitude - fromLatitude) * math.pi / 180;
    final deltaLon = (toLongitude - fromLongitude) * math.pi / 180;
    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(fromLat) *
            math.cos(toLat) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

class CircularHeadingFilter {
  CircularHeadingFilter({this.smoothingFactor = 0.2})
    : assert(smoothingFactor > 0 && smoothingFactor <= 1);

  final double smoothingFactor;
  double? _x;
  double? _y;

  double? get headingDegrees {
    final x = _x;
    final y = _y;
    if (x == null || y == null) return null;
    final degrees = math.atan2(y, x) * 180 / math.pi;
    return degrees < 0 ? degrees + 360 : degrees;
  }

  double add(double degrees) {
    final radians = _normalize(degrees) * math.pi / 180;
    final nextX = math.cos(radians);
    final nextY = math.sin(radians);
    _x = _x == null ? nextX : _x! + smoothingFactor * (nextX - _x!);
    _y = _y == null ? nextY : _y! + smoothingFactor * (nextY - _y!);
    return headingDegrees!;
  }

  void reset() {
    _x = null;
    _y = null;
  }

  static double _normalize(double degrees) {
    final normalized = degrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }
}
