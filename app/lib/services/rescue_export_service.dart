import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/mesh_models.dart';
import '../models/rescue_case_models.dart';
import '../models/swept_zone_models.dart';
import 'rescue_case_clusterer.dart';

enum RescueExportFormat {
  csv(extension: 'csv', mimeType: 'text/csv'),
  geoJson(extension: 'geojson', mimeType: 'application/geo+json');

  const RescueExportFormat({required this.extension, required this.mimeType});

  final String extension;
  final String mimeType;
}

abstract final class RescueExportPolicy {
  static Iterable<RescueCase> operationalCases(Iterable<RescueCase> cases) =>
      cases.where((rescueCase) => rescueCase.state != RescueCaseState.closed);
}

enum RescueIncidentKind { sos, checkIn }

class RescueIncident {
  const RescueIncident({
    required this.id,
    required this.kind,
    required this.sender,
    required this.peerId,
    required this.message,
    required this.timestamp,
    this.checkInStatus,
    this.latitude,
    this.longitude,
    this.distanceMeters,
    this.triage,
  });

  final String id;
  final RescueIncidentKind kind;
  final String sender;
  final String peerId;
  final String message;
  final DateTime timestamp;
  final CheckInStatus? checkInStatus;
  final double? latitude;
  final double? longitude;
  final double? distanceMeters;
  final SosTriage? triage;

  RescueIncident copyWithDistance(double? value) => RescueIncident(
    id: id,
    kind: kind,
    sender: sender,
    peerId: peerId,
    message: message,
    timestamp: timestamp,
    checkInStatus: checkInStatus,
    latitude: latitude,
    longitude: longitude,
    distanceMeters: value,
    triage: triage,
  );
}

class RescueIncidentList {
  RescueIncidentList._();

  static List<RescueIncident> fromMessages(
    Iterable<MeshMessage> messages, {
    double? originLatitude,
    double? originLongitude,
  }) {
    final incidents = <RescueIncident>[];
    for (final message in messages) {
      if (message.isDrill) continue;
      final checkIn = message.checkIn;
      RescueIncident? incident;
      if (checkIn != null) {
        final coordinates = _coordinates(checkIn.latitude, checkIn.longitude);
        incident = RescueIncident(
          id: message.id,
          kind: RescueIncidentKind.checkIn,
          sender: checkIn.sender,
          peerId: checkIn.peerId,
          message: checkIn.message,
          timestamp: checkIn.timestamp,
          checkInStatus: checkIn.status,
          latitude: coordinates.$1,
          longitude: coordinates.$2,
        );
      } else if (message.isSos) {
        final coordinates = _coordinates(
          message.sosLatitude,
          message.sosLongitude,
        );
        incident = RescueIncident(
          id: message.id,
          kind: RescueIncidentKind.sos,
          sender: message.sender,
          peerId: message.senderPeerId,
          message: message.sosDescription,
          timestamp: message.timestamp,
          latitude: coordinates.$1,
          longitude: coordinates.$2,
          triage: message.sosTriage,
        );
      }
      if (incident == null) continue;
      final latitude = incident.latitude;
      final longitude = incident.longitude;
      if (_validCoordinates(originLatitude, originLongitude) &&
          latitude != null &&
          longitude != null) {
        incident = incident.copyWithDistance(
          distanceBetween(
            originLatitude!,
            originLongitude!,
            latitude,
            longitude,
          ),
        );
      }
      incidents.add(incident);
    }
    incidents.sort((a, b) {
      final aDistance = a.distanceMeters;
      final bDistance = b.distanceMeters;
      if (aDistance != null && bDistance != null) {
        final distanceOrder = aDistance.compareTo(bDistance);
        if (distanceOrder != 0) return distanceOrder;
      } else if (aDistance != null) {
        return -1;
      } else if (bDistance != null) {
        return 1;
      }
      return b.timestamp.compareTo(a.timestamp);
    });
    return List.unmodifiable(incidents);
  }

  static (double?, double?) _coordinates(double? latitude, double? longitude) =>
      _validCoordinates(latitude, longitude)
      ? (latitude, longitude)
      : (null, null);

  static bool _validCoordinates(double? latitude, double? longitude) =>
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  static double distanceBetween(
    double firstLatitude,
    double firstLongitude,
    double secondLatitude,
    double secondLongitude,
  ) {
    const earthRadiusMeters = 6371008.8;
    double radians(double degrees) => degrees * math.pi / 180;
    final latitudeDelta = radians(secondLatitude - firstLatitude);
    final longitudeDelta = radians(secondLongitude - firstLongitude);
    final firstRadians = radians(firstLatitude);
    final secondRadians = radians(secondLatitude);
    final haversine =
        math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(firstRadians) *
            math.cos(secondRadians) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    return earthRadiusMeters *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }
}

class RescueCsv {
  RescueCsv._();

  static String build(Iterable<RescueIncident> incidents) {
    final rows = <List<String>>[
      [
        'type',
        'status',
        'sender',
        'peer_id',
        'message',
        'timestamp_utc',
        'latitude',
        'longitude',
        'distance_meters',
        'people_count',
        'injury_status',
        'injured_count',
        'trapped_status',
        'primary_need',
      ],
      ...incidents.map(
        (incident) => [
          incident.kind.name,
          incident.kind == RescueIncidentKind.sos
              ? 'SOS'
              : incident.checkInStatus?.wireCode ?? '',
          incident.sender,
          incident.peerId,
          incident.message,
          incident.timestamp.toUtc().toIso8601String(),
          incident.latitude?.toStringAsFixed(6) ?? '',
          incident.longitude?.toStringAsFixed(6) ?? '',
          incident.distanceMeters?.round().toString() ?? '',
          incident.triage?.peopleCount?.toString() ?? '',
          incident.triage?.injuryStatus.name ?? '',
          incident.triage?.injuredCount?.toString() ?? '',
          incident.triage?.trappedStatus.name ?? '',
          incident.triage?.primaryNeed.name ?? '',
        ],
      ),
    ];
    return '${rows.map((row) => row.map(_escape).join(',')).join('\r\n')}\r\n';
  }

  static String _escape(String value) {
    if (!value.contains(RegExp(r'[,"\r\n]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }
}

abstract final class RescueOperationalCsv {
  static String build(Iterable<RescueCase> cases) {
    final sorted = cases.toList(growable: false)
      ..sort((first, second) => first.caseHash.compareTo(second.caseHash));
    final rows = <List<String>>[
      [
        'case_hash',
        'state',
        'priority',
        'victim',
        'message',
        'assignee',
        'created_at_utc',
        'updated_at_utc',
        'latitude',
        'longitude',
      ],
      ...sorted.map(
        (rescueCase) => [
          rescueCase.caseHash,
          rescueCase.state.name,
          RescueCaseClusterer.priorityForTriage(rescueCase.triage).name,
          rescueCase.victim,
          rescueCase.message,
          rescueCase.assigneePeerId ?? '',
          rescueCase.createdAt.toUtc().toIso8601String(),
          rescueCase.updatedAt.toUtc().toIso8601String(),
          _validCoordinates(rescueCase.latitude, rescueCase.longitude)
              ? rescueCase.latitude!.toStringAsFixed(6)
              : '',
          _validCoordinates(rescueCase.latitude, rescueCase.longitude)
              ? rescueCase.longitude!.toStringAsFixed(6)
              : '',
        ],
      ),
    ];
    return '${rows.map((row) => row.map(_escape).join(',')).join('\r\n')}\r\n';
  }

  static String _escape(String value) {
    if (!value.contains(RegExp(r'[,"\r\n]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }
}

abstract final class RescueGeoJson {
  static const String schema = 'hearthbit-rescue';
  static const int version = 1;

  static String build({
    required Iterable<RescueCase> cases,
    required Iterable<SweptZone> zones,
  }) {
    final sortedCases = cases.toList(growable: false)
      ..sort((first, second) => first.caseHash.compareTo(second.caseHash));
    final sortedZones = zones.toList(growable: false)
      ..sort((first, second) => first.zoneId.compareTo(second.zoneId));
    final features = <Map<String, Object?>>[
      ...sortedCases.map(_caseFeature),
      ...sortedZones.map(_zoneFeature).whereType<Map<String, Object?>>(),
    ];
    return jsonEncode(<String, Object>{
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  static Map<String, Object?> _caseFeature(RescueCase rescueCase) {
    final triage = rescueCase.triage;
    return <String, Object?>{
      'type': 'Feature',
      'id': 'case:${rescueCase.caseHash}',
      'geometry': _validCoordinates(rescueCase.latitude, rescueCase.longitude)
          ? <String, Object>{
              'type': 'Point',
              'coordinates': <double>[
                rescueCase.longitude!,
                rescueCase.latitude!,
              ],
            }
          : null,
      'properties': <String, Object?>{
        'schema': schema,
        'version': version,
        'featureType': 'rescueCase',
        'caseHash': rescueCase.caseHash,
        'state': rescueCase.state.name,
        'priority': RescueCaseClusterer.priorityForTriage(
          rescueCase.triage,
        ).name,
        'triage': triage == null
            ? null
            : <String, Object?>{
                'peopleCount': triage.peopleCount,
                'injuryStatus': triage.injuryStatus.name,
                'injuredCount': triage.injuredCount,
                'trappedStatus': triage.trappedStatus.name,
                'primaryNeed': triage.primaryNeed.name,
              },
        'victim': rescueCase.victim,
        'message': rescueCase.message,
        'assignee': rescueCase.assigneePeerId,
        'createdAt': rescueCase.createdAt.toUtc().toIso8601String(),
        'updatedAt': rescueCase.updatedAt.toUtc().toIso8601String(),
      },
    };
  }

  static Map<String, Object?>? _zoneFeature(SweptZone zone) {
    final points = zone.points
        .where((point) => _validCoordinates(point.latitude, point.longitude))
        .map((point) => <double>[point.longitude, point.latitude])
        .toList(growable: false);
    if (points.length < 2) return null;
    return <String, Object?>{
      'type': 'Feature',
      'id': 'zone:${zone.zoneId}',
      'geometry': <String, Object>{'type': 'LineString', 'coordinates': points},
      'properties': <String, Object?>{
        'schema': schema,
        'version': version,
        'featureType': 'sweptZone',
        'zoneId': zone.zoneId,
        'teamId': zone.teamId,
        'actor': zone.actorPeerId,
        'callsign': zone.callsign,
        'startedAt': zone.startedAt.toUtc().toIso8601String(),
        'endedAt': zone.endedAt.toUtc().toIso8601String(),
      },
    };
  }
}

bool _validCoordinates(double? latitude, double? longitude) =>
    latitude != null &&
    longitude != null &&
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180;

class RescueExportService {
  RescueExportService._();

  static Future<ShareResult> share({
    required Iterable<RescueIncident> incidents,
    required RenderBox? anchor,
    required String subject,
  }) async {
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    final file = File(
      p.join(directory.path, 'hearthbit-rescue-$timestamp.csv'),
    );
    await file.writeAsString(RescueCsv.build(incidents), flush: true);
    final origin = anchor == null || !anchor.hasSize
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : anchor.localToGlobal(Offset.zero) & anchor.size;
    return SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: subject,
        title: subject,
        sharePositionOrigin: origin,
      ),
    );
  }

  static Future<ShareResult> shareOperational({
    required RescueExportFormat format,
    required Iterable<RescueCase> cases,
    required Iterable<SweptZone> zones,
    required RenderBox? anchor,
    required String subject,
  }) async {
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    final file = File(
      p.join(directory.path, 'hearthbit-rescue-$timestamp.${format.extension}'),
    );
    final content = switch (format) {
      RescueExportFormat.csv => RescueOperationalCsv.build(cases),
      RescueExportFormat.geoJson => RescueGeoJson.build(
        cases: cases,
        zones: zones,
      ),
    };
    await file.writeAsString(content, flush: true);
    final origin = anchor == null || !anchor.hasSize
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : anchor.localToGlobal(Offset.zero) & anchor.size;
    return SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: format.mimeType)],
        subject: subject,
        title: subject,
        sharePositionOrigin: origin,
      ),
    );
  }
}
