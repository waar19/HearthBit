import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/controllers/rescue_roster_controller.dart';
import 'package:hearth_bit/controllers/swept_zone_controller.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/models/rescue_roster_models.dart';
import 'package:hearth_bit/models/swept_zone_models.dart';
import 'package:hearth_bit/services/swept_zone_repository.dart';

const _team = 'ffeeddccbbaa99887766554433221100';
const _actor = '0011223344556677';

class _Mesh extends MeshController {
  final List<MeshMessage> storedMessages = [];

  @override
  List<MeshMessage> get messages => List.unmodifiable(storedMessages);

  void emit(MeshMessage message) {
    storedMessages.add(message);
    notifyListeners();
  }
}

class _Roster extends RescueRosterController {
  _Roster({required super.mesh});

  RescueTeamRoster? current;

  @override
  RescueTeamRoster? get activeRoster => current;

  @override
  List<RescueRosterMember> get members =>
      current?.members ?? const <RescueRosterMember>[];

  void activate(RescueTeamRoster? roster) {
    current = roster;
    notifyListeners();
  }
}

class _Repository extends SweptZoneRepository {
  final Map<String, SweptZone> stored = {};

  @override
  Future<List<SweptZone>> loadZones({required String teamId}) async =>
      stored.values.where((zone) => zone.teamId == teamId).toList();

  @override
  Future<bool> insert(SweptZone zone) async {
    if (stored.containsKey(zone.zoneId)) return false;
    stored[zone.zoneId] = zone;
    return true;
  }

  @override
  Future<void> close() async {}
}

void main() {
  test(
    'filtra precisión, distancia y solo registra con roster verificado',
    () async {
      final mesh = _Mesh()
        ..peerId = _actor
        ..signingPublicKey = Uint8List(32);
      final roster = _Roster(mesh: mesh)..activate(_roster());
      final controller = SweptZoneController(
        mesh: mesh,
        roster: roster,
        repository: _Repository(),
        now: () => DateTime.utc(2026, 8, 18, 12),
      );
      await controller.initialize();
      controller.startRecording();

      expect(
        controller.addRecordedPoint(
          latitude: 4.7,
          longitude: -74.1,
          accuracyMeters: 80,
          recordedAt: DateTime.utc(2026, 8, 18, 12),
        ),
        isFalse,
      );
      expect(
        controller.addRecordedPoint(
          latitude: 4.7,
          longitude: -74.1,
          accuracyMeters: 5,
          recordedAt: DateTime.utc(2026, 8, 18, 12),
        ),
        isTrue,
      );
      expect(
        controller.addRecordedPoint(
          latitude: 4.700001,
          longitude: -74.100001,
          accuracyMeters: 5,
          recordedAt: DateTime.utc(2026, 8, 18, 12, 0, 1),
        ),
        isFalse,
      );
      expect(
        controller.addRecordedPoint(
          latitude: 4.7001,
          longitude: -74.1001,
          accuracyMeters: 5,
          recordedAt: DateTime.utc(2026, 8, 18, 12, 0, 2),
        ),
        isTrue,
      );
      expect(controller.draftPoints, hasLength(2));

      controller.cancelRecording();
      controller.dispose();
      roster.dispose();
      mesh.dispose();
    },
  );

  test('rechaza actor distinto, ausencia de roster y duplicados', () async {
    final mesh = _Mesh();
    final roster = _Roster(mesh: mesh);
    final repository = _Repository();
    final now = DateTime.utc(2026, 8, 18, 12);
    final controller = SweptZoneController(
      mesh: mesh,
      roster: roster,
      repository: repository,
      now: () => now,
    );
    await controller.initialize();

    final zone = _zone(now);
    mesh.emit(_message('without-roster', zone, sender: _actor));
    await _settle();
    expect(controller.zones, isEmpty);

    roster.activate(_roster());
    mesh.emit(_message('wrong-actor', zone, sender: '8899aabbccddeeff'));
    await _settle();
    expect(controller.zones, isEmpty);

    mesh.emit(_message('accepted', zone, sender: _actor));
    await _settle();
    expect(controller.zones, hasLength(1));

    mesh.emit(_message('duplicate', zone, sender: _actor));
    await _settle();
    expect(controller.zones, hasLength(1));
    expect(repository.stored, hasLength(1));

    controller.dispose();
    roster.dispose();
    mesh.dispose();
  });
}

Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

MeshMessage _message(String id, SweptZone zone, {required String sender}) =>
    MeshMessage(
      id: id,
      sender: 'Águila',
      content: SweptZoneCodec.encode(zone),
      senderPeerId: sender,
      isPrivate: false,
      isMine: false,
      timestamp: zone.endedAt,
      channel: SweptZoneController.channel,
    );

RescueTeamRoster _roster() => RescueTeamRoster(
  teamId: _team,
  name: 'Equipo',
  createdAt: DateTime.utc(2026),
  leaderPeerId: _actor,
  members: [
    RescueRosterMember(
      peerId: _actor,
      callsign: 'Águila',
      role: RescueRosterRole.leader,
      signingPublicKey: Uint8List(32),
    ),
  ],
  signature: Uint8List(64),
);

SweptZone _zone(DateTime now) {
  final startedAt = now.subtract(const Duration(minutes: 2));
  final endedAt = now.subtract(const Duration(minutes: 1));
  return SweptZone(
    version: SweptZoneCodec.version,
    zoneId: '0123456789abcdef0123456789abcdef',
    teamId: _team,
    actorPeerId: _actor,
    callsign: 'Águila',
    startedAt: startedAt,
    endedAt: endedAt,
    points: [
      SweptZonePoint(latitude: 4.7, longitude: -74.1, recordedAt: startedAt),
      SweptZonePoint(
        latitude: 4.7001,
        longitude: -74.1001,
        recordedAt: endedAt,
      ),
    ],
  );
}
