import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/services/peer_location_tracker.dart';

MeshMessage _message({
  required String id,
  required String peerId,
  required String content,
  required DateTime timestamp,
  bool isPrivate = false,
  String? channel,
}) => MeshMessage(
  id: id,
  sender: 'Persona',
  content: content,
  senderPeerId: peerId,
  isPrivate: isPrivate,
  isMine: false,
  timestamp: timestamp,
  channel: channel,
);

void main() {
  test('combina SOS, check-ins y HB-LOC por peer en orden temporal', () {
    final tracker = PeerLocationTracker();
    final sosTime = DateTime.fromMillisecondsSinceEpoch(1000);
    final checkInTime = DateTime.fromMillisecondsSinceEpoch(2000);
    final liveTime = DateTime.fromMillisecondsSinceEpoch(3000);

    tracker.replacePersisted([
      _message(
        id: 'sos',
        peerId: 'PEER-A',
        content: 'SOS|Ayuda|4.600000|-74.080000',
        timestamp: sosTime,
        channel: 'sos',
      ),
      _message(
        id: 'checkin',
        peerId: 'peer-a',
        content: EmergencyCheckIn.encode(
          status: CheckInStatus.needsHelp,
          readableMessage: 'Necesito agua',
          timestamp: checkInTime,
          latitude: 4.61,
          longitude: -74.07,
        ),
        timestamp: checkInTime,
        channel: 'checkin',
      ),
    ]);
    tracker.ingestLive(
      _message(
        id: 'live',
        peerId: 'Peer-A',
        content: RadarLocationUpdate.encode(
          latitude: 4.62,
          longitude: -74.06,
          accuracyMeters: 4,
          timestamp: liveTime,
        ),
        timestamp: liveTime,
        isPrivate: true,
      ),
    );

    expect(tracker.trailFor('peer-a'), hasLength(3));
    expect(tracker.latestFor('PEER-A')?.source, PeerLocationSource.live);
    expect(tracker.latestFor('peer-a')?.latitude, 4.62);
  });

  test('notifica cambios, ignora duplicados y limita el trail', () {
    final tracker = PeerLocationTracker(maxTrailLength: 2);
    var notifications = 0;
    tracker.addListener(() => notifications += 1);

    for (var index = 1; index <= 3; index++) {
      final message = _message(
        id: 'live-$index',
        peerId: 'peer',
        content: RadarLocationUpdate.encode(
          latitude: 4 + index / 100,
          longitude: -74,
          accuracyMeters: 5,
          timestamp: DateTime.fromMillisecondsSinceEpoch(index * 1000),
        ),
        timestamp: DateTime.fromMillisecondsSinceEpoch(index * 1000),
        isPrivate: true,
      );
      tracker.ingestLive(message);
      if (index == 3) tracker.ingestLive(message);
    }

    expect(notifications, 3);
    expect(tracker.trailFor('peer'), hasLength(2));
    expect(tracker.trailFor('peer').first.latitude, 4.02);
  });

  test('notifica cuando una recarga elimina ubicaciones anteriores', () {
    final tracker = PeerLocationTracker();
    tracker.ingestPersisted(
      _message(
        id: 'sos',
        peerId: 'peer',
        content: 'SOS|Ayuda|4.600000|-74.080000',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        channel: 'sos',
      ),
    );
    var notifications = 0;
    tracker.addListener(() => notifications += 1);

    tracker.replacePersisted(const []);

    expect(notifications, 1);
    expect(tracker.latestLocations, isEmpty);
  });
}
