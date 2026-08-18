import 'dart:convert';

class SweptZonePoint {
  const SweptZonePoint({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
  });

  final double latitude;
  final double longitude;
  final DateTime recordedAt;
}

class SweptZone {
  const SweptZone({
    required this.version,
    required this.zoneId,
    required this.teamId,
    required this.actorPeerId,
    required this.callsign,
    required this.startedAt,
    required this.endedAt,
    required this.points,
  });

  final int version;
  final String zoneId;
  final String teamId;
  final String actorPeerId;
  final String callsign;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<SweptZonePoint> points;
}

abstract final class SweptZoneCodec {
  static const String marker = '[HB-ZONE|';
  static const int version = 1;
  static const int minimumPoints = 2;
  static const int maximumPoints = 256;
  static const int maximumPayloadBytes = 12 * 1024;
  static const int maximumCallsignBytes = 48;
  static const int maximumDurationSeconds = 24 * 60 * 60;
  static const int maximumTimestampMilliseconds = 8640000000000000;

  static final RegExp _zoneId = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _teamId = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _peerId = RegExp(r'^[0-9a-f]{16}$');

  static String encode(SweptZone zone) {
    _validate(zone);
    final startedMs = zone.startedAt.toUtc().millisecondsSinceEpoch;
    final payload = <String, Object>{
      'z': zone.zoneId,
      't': zone.teamId,
      'a': zone.actorPeerId,
      'c': zone.callsign,
      's': startedMs,
      'e': zone.endedAt.toUtc().millisecondsSinceEpoch,
      'p': zone.points
          .map(
            (point) => <int>[
              (point.latitude * 100000).round(),
              (point.longitude * 100000).round(),
              (point.recordedAt.toUtc().millisecondsSinceEpoch - startedMs) ~/
                  1000,
            ],
          )
          .toList(growable: false),
    };
    final encodedPayload = base64UrlEncode(
      utf8.encode(jsonEncode(payload)),
    ).replaceAll('=', '');
    final encoded = '$marker$version|$encodedPayload]';
    if (utf8.encode(encoded).length > maximumPayloadBytes) {
      throw const FormatException('Swept zone payload is too large');
    }
    return encoded;
  }

  static SweptZone? tryDecode(String value) {
    if (!value.startsWith(marker) ||
        !value.endsWith(']') ||
        utf8.encode(value).length > maximumPayloadBytes) {
      return null;
    }
    final body = value.substring(marker.length, value.length - 1);
    final separator = body.indexOf('|');
    if (separator <= 0 || body.substring(0, separator) != '$version') {
      return null;
    }
    try {
      final rawPayload = body.substring(separator + 1);
      if (rawPayload.isEmpty ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(rawPayload)) {
        return null;
      }
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(rawPayload))),
      );
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 7 ||
          decoded['z'] is! String ||
          decoded['t'] is! String ||
          decoded['a'] is! String ||
          decoded['c'] is! String ||
          decoded['s'] is! int ||
          decoded['e'] is! int ||
          decoded['p'] is! List<dynamic>) {
        return null;
      }
      final startedMs = decoded['s']! as int;
      final endedMs = decoded['e']! as int;
      final rawPoints = decoded['p']! as List<dynamic>;
      if (rawPoints.length < minimumPoints ||
          rawPoints.length > maximumPoints) {
        return null;
      }
      final points = <SweptZonePoint>[];
      for (final rawPoint in rawPoints) {
        if (rawPoint is! List<dynamic> ||
            rawPoint.length != 3 ||
            rawPoint.any((coordinate) => coordinate is! int)) {
          return null;
        }
        final latitudeE5 = rawPoint[0]! as int;
        final longitudeE5 = rawPoint[1]! as int;
        final offsetSeconds = rawPoint[2]! as int;
        points.add(
          SweptZonePoint(
            latitude: latitudeE5 / 100000,
            longitude: longitudeE5 / 100000,
            recordedAt: DateTime.fromMillisecondsSinceEpoch(
              startedMs + (offsetSeconds * 1000),
              isUtc: true,
            ),
          ),
        );
      }
      final zone = SweptZone(
        version: version,
        zoneId: decoded['z']! as String,
        teamId: decoded['t']! as String,
        actorPeerId: decoded['a']! as String,
        callsign: decoded['c']! as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(startedMs, isUtc: true),
        endedAt: DateTime.fromMillisecondsSinceEpoch(endedMs, isUtc: true),
        points: List.unmodifiable(points),
      );
      _validate(zone);
      return zone;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static void _validate(SweptZone zone) {
    final startedMs = zone.startedAt.toUtc().millisecondsSinceEpoch;
    final endedMs = zone.endedAt.toUtc().millisecondsSinceEpoch;
    if (zone.version != version ||
        !_zoneId.hasMatch(zone.zoneId) ||
        !_teamId.hasMatch(zone.teamId) ||
        !_peerId.hasMatch(zone.actorPeerId) ||
        zone.callsign.trim() != zone.callsign ||
        zone.callsign.isEmpty ||
        utf8.encode(zone.callsign).length > maximumCallsignBytes ||
        startedMs <= 0 ||
        endedMs < startedMs ||
        endedMs > maximumTimestampMilliseconds ||
        endedMs - startedMs > maximumDurationSeconds * 1000 ||
        zone.points.length < minimumPoints ||
        zone.points.length > maximumPoints) {
      throw const FormatException('Invalid swept zone');
    }
    var previousMs = startedMs;
    for (final point in zone.points) {
      final pointMs = point.recordedAt.toUtc().millisecondsSinceEpoch;
      if (!point.latitude.isFinite ||
          !point.longitude.isFinite ||
          point.latitude < -90 ||
          point.latitude > 90 ||
          point.longitude < -180 ||
          point.longitude > 180 ||
          pointMs < startedMs ||
          pointMs > endedMs ||
          pointMs < previousMs) {
        throw const FormatException('Invalid swept zone point');
      }
      previousMs = pointMs;
    }
  }
}
