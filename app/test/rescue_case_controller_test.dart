import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/controllers/rescue_case_controller.dart';
import 'package:hearth_bit/controllers/rescue_roster_controller.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/models/rescue_case_models.dart';
import 'package:hearth_bit/models/rescue_roster_models.dart';
import 'package:hearth_bit/services/rescue_case_repository.dart';

const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _victim = '8899aabbccddeeff';
const _local = '0011223344556677';
const _remoteA = '1111222233334444';
const _remoteB = 'aaaabbbbccccdddd';

class _Mesh extends MeshController {
  final List<MeshMessage> storedMessages = [];
  final List<MeshPeer> livePeers = [];
  final List<({String content, String? channel})> sent = [];

  @override
  List<MeshMessage> get messages => List.unmodifiable(storedMessages);

  @override
  List<MeshPeer> get peers => List.unmodifiable(livePeers);

  @override
  Future<String?> sendPublic(String content, {String? channel}) async {
    sent.add((content: content, channel: channel));
    return 'sent-${sent.length}';
  }

  void emit(MeshMessage message) {
    storedMessages.add(message);
    notifyListeners();
  }
}

class _Roster extends RescueRosterController {
  _Roster({required super.mesh, required this.roster});

  final RescueTeamRoster roster;

  @override
  RescueTeamRoster get activeRoster => roster;

  @override
  List<RescueRosterMember> get members => roster.members;

  @override
  RescueRosterMember? verifiedMember({
    required String peerId,
    required Uint8List? signingPublicKey,
  }) {
    if (signingPublicKey == null) return null;
    for (final member in members) {
      if (member.peerId == peerId.toLowerCase() &&
          _sameBytes(member.signingPublicKey, signingPublicKey)) {
        return member;
      }
    }
    return null;
  }

  static bool _sameBytes(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}

class _Repository extends RescueCaseRepository {
  final Map<String, RescueCase> stored = {};
  final Set<String> events = {};
  final Set<String> staged = {};

  @override
  Future<List<RescueCase>> loadCases() async => stored.values.toList();

  @override
  Future<void> discardStaleLocalUpdates() async => staged.clear();

  @override
  Future<bool> insertSos(RescueCase rescueCase) async {
    if (stored.containsKey(rescueCase.caseHash)) return false;
    stored[rescueCase.caseHash] = rescueCase;
    return true;
  }

  @override
  Future<bool> applyIncomingUpdate({
    required RescueCase rescueCase,
    required RescueCaseUpdate update,
  }) async {
    if (!events.add(update.eventId)) return false;
    stored[rescueCase.caseHash] = rescueCase;
    return true;
  }

  @override
  Future<bool> stageLocalUpdate(RescueCaseUpdate update) async =>
      staged.add(update.eventId);

  @override
  Future<void> commitLocalUpdate({
    required RescueCase rescueCase,
    required RescueCaseUpdate update,
  }) async {
    expect(staged.remove(update.eventId), isTrue);
    events.add(update.eventId);
    stored[rescueCase.caseHash] = rescueCase;
  }

  @override
  Future<void> discardLocalUpdate(RescueCaseUpdate update) async {
    staged.remove(update.eventId);
  }

  @override
  Future<void> close() async {}
}

void main() {
  late _Mesh mesh;
  late _Roster roster;
  late _Repository repository;
  late RescueCaseController controller;
  late Uint8List localKey;
  late Uint8List keyA;
  late Uint8List keyB;

  setUp(() async {
    localKey = Uint8List.fromList(List<int>.filled(32, 1));
    keyA = Uint8List.fromList(List<int>.filled(32, 2));
    keyB = Uint8List.fromList(List<int>.filled(32, 3));
    mesh = _Mesh()
      ..peerId = _local
      ..signingPublicKey = localKey;
    roster = _Roster(
      mesh: mesh,
      roster: RescueTeamRoster(
        teamId: '0' * 32,
        name: 'Team',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        leaderPeerId: _local,
        members: [
          _member(_local, localKey, RescueRosterRole.leader),
          _member(_remoteA, keyA, RescueRosterRole.responder),
          _member(_remoteB, keyB, RescueRosterRole.medic),
        ],
        signature: Uint8List.fromList(List<int>.filled(64, 1)),
      ),
    );
    repository = _Repository();
    controller = RescueCaseController(
      mesh: mesh,
      roster: roster,
      repository: repository,
    );
    await controller.initialize();
  });

  tearDown(() {
    controller.dispose();
    roster.dispose();
    mesh.dispose();
  });

  test('deduplica retransmisiones SOS por canonicalHash', () async {
    mesh.emit(_sos('sos-1'));
    mesh.emit(_sos('sos-2'));
    await _pump();

    expect(controller.cases, hasLength(1));
    expect(controller.cases.single.caseHash, _hash);
  });

  test('rechaza actor fuera del roster y clave viva distinta', () async {
    mesh.emit(_sos('sos'));
    mesh.livePeers.add(_peer(_remoteA, keyB));
    mesh.emit(_updateMessage(_remoteA, keyA, 2000));
    mesh.livePeers.add(
      _peer('9999000011112222', Uint8List.fromList(List<int>.filled(32, 9))),
    );
    mesh.emit(
      _updateMessage(
        '9999000011112222',
        Uint8List.fromList(List<int>.filled(32, 9)),
        3000,
      ),
    );
    await _pump();

    expect(controller.cases.single.state, RescueCaseState.newCase);
    expect(repository.events, isEmpty);
  });

  test('resuelve concurrencia y nunca regresa atendido', () async {
    mesh.emit(_sos('sos'));
    mesh.livePeers
      ..add(_peer(_remoteA, keyA))
      ..add(_peer(_remoteB, keyB));
    mesh.emit(_updateMessage(_remoteA, keyA, 2000));
    mesh.emit(_updateMessage(_remoteB, keyB, 2000));
    await _pump();

    expect(controller.cases.single.assigneePeerId, _remoteB);

    mesh.emit(
      _updateMessage(_remoteB, keyB, 3000, state: RescueCaseState.attended),
    );
    mesh.emit(_updateMessage(_remoteA, keyA, 4000));
    await _pump();

    expect(controller.cases.single.state, RescueCaseState.attended);
    expect(controller.cases.single.assigneePeerId, _remoteB);
  });

  test('asignarme persiste y usa el canal MESSAGE firmado normal', () async {
    mesh.emit(_sos('sos'));
    await _pump();

    await controller.assignToMe(_hash);

    expect(controller.cases.single.state, RescueCaseState.assigned);
    expect(controller.cases.single.assigneePeerId, _local);
    expect(mesh.sent.single.channel, RescueCaseController.channel);
    expect(
      RescueCaseUpdateCodec.tryDecode(mesh.sent.single.content),
      isNotNull,
    );
  });
}

RescueRosterMember _member(
  String peerId,
  Uint8List key,
  RescueRosterRole role,
) => RescueRosterMember(
  peerId: peerId,
  callsign: peerId.substring(0, 4),
  role: role,
  signingPublicKey: key,
);

MeshPeer _peer(String peerId, Uint8List key) => MeshPeer(
  id: peerId,
  nickname: peerId.substring(0, 4),
  lastSeen: DateTime.now(),
  secure: true,
  signingPublicKey: key,
);

MeshMessage _sos(String id) => MeshMessage(
  id: id,
  sender: 'Victim',
  content: 'SOS|Help|4.7|-74.1',
  senderPeerId: _victim,
  isPrivate: false,
  isMine: false,
  timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
  channel: 'sos',
  canonicalHash: _hash,
);

MeshMessage _updateMessage(
  String actor,
  Uint8List key,
  int timestamp, {
  RescueCaseState state = RescueCaseState.assigned,
}) {
  final update = RescueCaseUpdate(
    caseHash: _hash,
    state: state,
    actorPeerId: actor,
    assigneePeerId: actor,
    timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
  );
  return MeshMessage(
    id: '$actor-$timestamp-${state.name}-${key.first}',
    sender: actor.substring(0, 4),
    content: RescueCaseUpdateCodec.encode(update),
    senderPeerId: actor,
    isPrivate: false,
    isMine: false,
    timestamp: update.timestamp,
    channel: RescueCaseController.channel,
  );
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
