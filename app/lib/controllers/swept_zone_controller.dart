import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/mesh_models.dart';
import '../models/rescue_roster_models.dart';
import '../models/swept_zone_models.dart';
import '../services/swept_zone_repository.dart';
import 'mesh_controller.dart';
import 'rescue_roster_controller.dart';

class SweptZoneController extends ChangeNotifier {
  SweptZoneController({
    required this.mesh,
    required this.roster,
    SweptZoneRepository? repository,
    Random? secureRandom,
    DateTime Function()? now,
  }) : _repository = repository ?? SweptZoneRepository(),
       _random = secureRandom ?? Random.secure(),
       _now = now ?? DateTime.now;

  static const String channel = 'rescue-zone';
  static const double maximumAcceptedAccuracyMeters = 50;
  static const double minimumPointDistanceMeters = 5;
  static const Duration maximumFutureSkew = Duration(minutes: 5);

  final MeshController mesh;
  final RescueRosterController roster;
  final SweptZoneRepository _repository;
  final Random _random;
  final DateTime Function() _now;
  final Map<String, SweptZone> _zonesById = {};
  final Set<String> _processedMessageIds = {};
  final List<SweptZonePoint> _draftPoints = [];

  bool _disposed = false;
  bool _processing = false;
  bool _processingRequested = false;
  String? _loadedTeamId;
  DateTime? _recordingStartedAt;

  bool loading = true;
  bool publishing = false;
  String? lastError;

  bool get isRecording => _recordingStartedAt != null;
  List<SweptZonePoint> get draftPoints => List.unmodifiable(_draftPoints);

  List<SweptZone> get zones {
    final result = _zonesById.values.toList(growable: false)
      ..sort((first, second) {
        final timeOrder = second.endedAt.compareTo(first.endedAt);
        return timeOrder != 0
            ? timeOrder
            : first.zoneId.compareTo(second.zoneId);
      });
    return List.unmodifiable(result);
  }

  RescueRosterMember? get localMember => roster.verifiedMember(
    peerId: mesh.peerId,
    signingPublicKey: mesh.signingPublicKey,
  );

  Future<void> initialize() async {
    mesh.addListener(_handleMeshChanged);
    roster.addListener(_handleRosterChanged);
    try {
      await _reloadForActiveTeam();
      await _processMessages();
    } catch (error) {
      lastError = error.toString();
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  void startRecording() {
    final activeRoster = roster.activeRoster;
    final member = localMember;
    if (activeRoster == null || member == null) {
      throw StateError('A verified active rescue roster is required');
    }
    _draftPoints.clear();
    _recordingStartedAt = _now().toUtc();
    lastError = null;
    notifyListeners();
  }

  bool addRecordedPoint({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime recordedAt,
  }) {
    final startedAt = _recordingStartedAt;
    if (startedAt == null ||
        _draftPoints.length >= SweptZoneCodec.maximumPoints ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        !accuracyMeters.isFinite ||
        accuracyMeters < 0 ||
        accuracyMeters > maximumAcceptedAccuracyMeters ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return false;
    }
    final timestamp = recordedAt.toUtc();
    if (timestamp.isBefore(startedAt)) return false;
    final previous = _draftPoints.lastOrNull;
    if (previous != null) {
      if (timestamp.isBefore(previous.recordedAt) ||
          _distanceMeters(
                previous.latitude,
                previous.longitude,
                latitude,
                longitude,
              ) <
              minimumPointDistanceMeters) {
        return false;
      }
    }
    _draftPoints.add(
      SweptZonePoint(
        latitude: latitude,
        longitude: longitude,
        recordedAt: timestamp,
      ),
    );
    notifyListeners();
    return true;
  }

  void cancelRecording() {
    _recordingStartedAt = null;
    _draftPoints.clear();
    lastError = null;
    notifyListeners();
  }

  Future<SweptZone> finishAndPublish() async {
    final activeRoster = roster.activeRoster;
    final member = localMember;
    final startedAt = _recordingStartedAt;
    if (activeRoster == null || member == null || startedAt == null) {
      throw StateError('No authorized swept-zone recording is active');
    }
    if (_draftPoints.length < SweptZoneCodec.minimumPoints) {
      throw StateError('At least two valid route points are required');
    }
    final points = List<SweptZonePoint>.unmodifiable(_draftPoints);
    final endedAt = points.last.recordedAt;
    final zone = SweptZone(
      version: SweptZoneCodec.version,
      zoneId: _randomHex(16),
      teamId: activeRoster.teamId,
      actorPeerId: member.peerId,
      callsign: member.callsign,
      startedAt: startedAt,
      endedAt: endedAt,
      points: points,
    );
    SweptZoneCodec.encode(zone);
    publishing = true;
    lastError = null;
    notifyListeners();
    try {
      final messageId = await mesh.sendPublic(
        SweptZoneCodec.encode(zone),
        channel: channel,
      );
      if (messageId == null || messageId.isEmpty) {
        throw StateError('Swept zone was not transmitted');
      }
      await _repository.insert(zone);
      _zonesById[zone.zoneId] = zone;
      _recordingStartedAt = null;
      _draftPoints.clear();
      return zone;
    } catch (error) {
      lastError = error.toString();
      rethrow;
    } finally {
      publishing = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _handleMeshChanged() {
    unawaited(_processMessages());
  }

  void _handleRosterChanged() {
    unawaited(_reloadForActiveTeam());
  }

  Future<void> _reloadForActiveTeam() async {
    final teamId = roster.activeRoster?.teamId;
    if (teamId == _loadedTeamId) return;
    _loadedTeamId = teamId;
    _zonesById.clear();
    if (teamId != null) {
      for (final zone in await _repository.loadZones(teamId: teamId)) {
        _zonesById[zone.zoneId] = zone;
      }
    }
    if (!_disposed) notifyListeners();
    await _processMessages();
  }

  Future<void> _processMessages() async {
    if (_processing) {
      _processingRequested = true;
      return;
    }
    _processing = true;
    try {
      do {
        _processingRequested = false;
        final messages = mesh.messages.toList(growable: false)
          ..sort((first, second) {
            final timeOrder = first.timestamp.compareTo(second.timestamp);
            return timeOrder != 0 ? timeOrder : first.id.compareTo(second.id);
          });
        for (final message in messages) {
          if (_processedMessageIds.contains(message.id) ||
              message.isPrivate ||
              message.channel != channel ||
              !message.content.startsWith(SweptZoneCodec.marker)) {
            continue;
          }
          if (!message.isMine) {
            final zone = SweptZoneCodec.tryDecode(message.content);
            if (zone != null) await _ingestIncoming(message, zone);
          }
          _processedMessageIds.add(message.id);
        }
      } while (_processingRequested);
      lastError = null;
    } catch (error) {
      lastError = error.toString();
    } finally {
      _processing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _ingestIncoming(MeshMessage message, SweptZone zone) async {
    final activeRoster = roster.activeRoster;
    final sender = message.senderPeerId.trim().toLowerCase();
    if (activeRoster == null ||
        zone.teamId != activeRoster.teamId ||
        zone.actorPeerId != sender ||
        zone.endedAt.isAfter(_now().toUtc().add(maximumFutureSkew)) ||
        zone.endedAt.isBefore(
          _now().toUtc().subtract(SweptZoneRepository.retention),
        )) {
      return;
    }
    final member = _memberByPeerId(sender);
    if (member == null || member.callsign != zone.callsign) return;

    // Native MESSAGE verification is pinned to this active roster. Looking up
    // the persisted roster by peer ID keeps authorization valid after a sender
    // moves out of radio visibility without weakening the native signature.
    final inserted = await _repository.insert(zone);
    if (inserted) _zonesById[zone.zoneId] = zone;
  }

  RescueRosterMember? _memberByPeerId(String peerId) {
    for (final member in roster.members) {
      if (member.peerId == peerId) return member;
    }
    return null;
  }

  String _randomHex(int byteCount) => List<int>.generate(
    byteCount,
    (_) => _random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static double _distanceMeters(
    double firstLatitude,
    double firstLongitude,
    double secondLatitude,
    double secondLongitude,
  ) {
    const earthRadius = 6371000.0;
    final firstLatitudeRadians = firstLatitude * pi / 180;
    final secondLatitudeRadians = secondLatitude * pi / 180;
    final latitudeDelta = (secondLatitude - firstLatitude) * pi / 180;
    final longitudeDelta = (secondLongitude - firstLongitude) * pi / 180;
    final haversine =
        sin(latitudeDelta / 2) * sin(latitudeDelta / 2) +
        cos(firstLatitudeRadians) *
            cos(secondLatitudeRadians) *
            sin(longitudeDelta / 2) *
            sin(longitudeDelta / 2);
    return earthRadius * 2 * atan2(sqrt(haversine), sqrt(1 - haversine));
  }

  @override
  void dispose() {
    _disposed = true;
    mesh.removeListener(_handleMeshChanged);
    roster.removeListener(_handleRosterChanged);
    unawaited(_repository.close());
    super.dispose();
  }
}
