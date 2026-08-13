import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/mesh_models.dart';

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
}
