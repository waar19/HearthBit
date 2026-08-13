import 'package:flutter/foundation.dart';

import '../models/mesh_models.dart';

enum PeerLocationSource { sos, checkIn, live }

@immutable
class PeerLocation {
  const PeerLocation({
    required this.peerId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.source,
    this.accuracyMeters,
  });

  final String peerId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final PeerLocationSource source;
  final double? accuracyMeters;
}

class PeerLocationTracker extends ChangeNotifier {
  PeerLocationTracker({this.maxTrailLength = 100});

  final int maxTrailLength;
  final Map<String, List<PeerLocation>> _trails = {};

  Iterable<PeerLocation> get latestLocations => _trails.values
      .where((trail) => trail.isNotEmpty)
      .map((trail) => trail.last);

  PeerLocation? latestFor(String peerId) {
    final trail = _trails[_normalizePeerId(peerId)];
    return trail == null || trail.isEmpty ? null : trail.last;
  }

  List<PeerLocation> trailFor(String peerId) =>
      List.unmodifiable(_trails[_normalizePeerId(peerId)] ?? const []);

  void replacePersisted(Iterable<MeshMessage> messages) {
    final hadLocations = _trails.isNotEmpty;
    _trails.clear();
    var changed = false;
    for (final message in messages) {
      changed = _addPersisted(message, notify: false) || changed;
    }
    if (hadLocations || changed) notifyListeners();
  }

  void ingestPersisted(MeshMessage message) {
    if (_addPersisted(message, notify: false)) notifyListeners();
  }

  void ingestLive(MeshMessage message) {
    final update = message.radarLocation;
    if (update == null) return;
    final changed = _add(
      PeerLocation(
        peerId: message.senderPeerId,
        latitude: update.latitude,
        longitude: update.longitude,
        timestamp: update.timestamp,
        source: PeerLocationSource.live,
        accuracyMeters: update.accuracyMeters,
      ),
    );
    if (changed) notifyListeners();
  }

  void clear() {
    if (_trails.isEmpty) return;
    _trails.clear();
    notifyListeners();
  }

  bool _addPersisted(MeshMessage message, {required bool notify}) {
    PeerLocation? location;
    final checkIn = message.checkIn;
    if (checkIn?.latitude != null && checkIn?.longitude != null) {
      location = PeerLocation(
        peerId: checkIn!.peerId,
        latitude: checkIn.latitude!,
        longitude: checkIn.longitude!,
        timestamp: checkIn.timestamp,
        source: PeerLocationSource.checkIn,
      );
    } else if (message.isSos &&
        message.sosLatitude != null &&
        message.sosLongitude != null) {
      location = PeerLocation(
        peerId: message.senderPeerId,
        latitude: message.sosLatitude!,
        longitude: message.sosLongitude!,
        timestamp: message.timestamp,
        source: PeerLocationSource.sos,
      );
    }
    if (location == null) return false;
    final changed = _add(location);
    if (changed && notify) notifyListeners();
    return changed;
  }

  bool _add(PeerLocation location) {
    if (!_validCoordinates(location.latitude, location.longitude) ||
        location.timestamp.millisecondsSinceEpoch <= 0 ||
        maxTrailLength <= 0) {
      return false;
    }
    final key = _normalizePeerId(location.peerId);
    if (key.isEmpty) return false;
    final normalized = PeerLocation(
      peerId: location.peerId,
      latitude: location.latitude,
      longitude: location.longitude,
      timestamp: location.timestamp,
      source: location.source,
      accuracyMeters: location.accuracyMeters,
    );
    final trail = _trails.putIfAbsent(key, () => []);
    final duplicate = trail.any(
      (point) =>
          point.timestamp == normalized.timestamp &&
          point.latitude == normalized.latitude &&
          point.longitude == normalized.longitude &&
          point.source == normalized.source,
    );
    if (duplicate) return false;
    trail.add(normalized);
    trail.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (trail.length > maxTrailLength) {
      trail.removeRange(0, trail.length - maxTrailLength);
    }
    return true;
  }

  static String _normalizePeerId(String peerId) => peerId.trim().toLowerCase();

  static bool _validCoordinates(double latitude, double longitude) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}
