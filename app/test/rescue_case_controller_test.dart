import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/controllers/rescue_case_controller.dart';
import 'package:hearth_bit/controllers/rescue_roster_controller.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/models/rescue_case_models.dart';
import 'package:hearth_bit/models/rescue_roster_models.dart';
import 'package:hearth_bit/services/rescue_case_repository.dart';

const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _team = '00000000000000000000000000000000';
const _victim = '8899aabbccddeeff';
const _local = '0011223344556677';
const _remoteA = '1111222233334444';
const _remoteB = 'aaaabbbbccccdddd';

class _Mesh extends MeshController {
  final List<MeshMessage> storedMessages = [];
  final List<MeshPeer> livePeers = [];
  final List<({String content, String? channel})> sent = [];
  Future<void> Function()? beforeSendReturns;

  @override
  List<MeshMessage> get messages => List.unmodifiable(storedMessages);

  @override
  List<MeshPeer> get peers => List.unmodifiable(livePeers);

  @override
  Future<String?> sendPublic(String content, {String? channel}) async {
    sent.add((content: content, channel: channel));
    await beforeSendReturns?.call();
    return 'sent-${sent.length}';
  }

  void emit(MeshMessage message) {
    storedMessages.add(message);
    notifyListeners();
  }
}

class _Roster extends RescueRosterController {
  _Roster({required super.mesh, required this.roster});

  RescueTeamRoster? roster;

  @override
  RescueTeamRoster? get activeRoster => roster;

  @override
  List<RescueRosterMember> get members =>
      roster?.members ?? const <RescueRosterMember>[];

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
  Future<List<RescueCase>> loadCases({required String teamId}) async =>
      stored.values.where((item) => item.teamId == teamId).toList();

  @override
  Future<void> discardStaleLocalUpdates() async => staged.clear();

  @override
  Future<RescueCaseWriteResult> insertSos(RescueCase rescueCase) async {
    if (stored.containsKey(rescueCase.caseHash)) {
      return const RescueCaseWriteResult(inserted: false, rescueCase: null);
    }
    stored[rescueCase.caseHash] = rescueCase;
    final pruned = <String>{};
    final teamCases =
        stored.values.where((item) => item.teamId == rescueCase.teamId).toList()
          ..sort((first, second) {
            final updated = second.updatedAt.compareTo(first.updatedAt);
            return updated != 0
                ? updated
                : first.caseHash.compareTo(second.caseHash);
          });
    for (final removed in teamCases.skip(
      RescueCaseRepository.maximumCasesPerTeam,
    )) {
      stored.remove(removed.caseHash);
      pruned.add(removed.caseHash);
    }
    return RescueCaseWriteResult(
      inserted: true,
      rescueCase: pruned.contains(rescueCase.caseHash) ? null : rescueCase,
      prunedCaseHashes: pruned,
    );
  }

  @override
  Future<RescueCaseWriteResult> applyIncomingUpdate(
    RescueCaseUpdate update,
  ) async {
    if (events.contains(update.eventId)) {
      return const RescueCaseWriteResult(inserted: false, rescueCase: null);
    }
    final next = RescueCaseTransition.resolve(stored[update.caseHash]!, update);
    if (next != null) {
      events.add(update.eventId);
      stored[next.caseHash] = next;
    }
    return RescueCaseWriteResult(inserted: next != null, rescueCase: next);
  }

  @override
  Future<bool> stageLocalUpdate(RescueCaseUpdate update) async =>
      staged.add(update.eventId);

  @override
  Future<RescueCaseWriteResult> commitLocalUpdate(
    RescueCaseUpdate update,
  ) async {
    expect(staged.remove(update.eventId), isTrue);
    events.add(update.eventId);
    final next = RescueCaseTransition.resolve(stored[update.caseHash]!, update);
    if (next != null) stored[next.caseHash] = next;
    return RescueCaseWriteResult(
      inserted: next != null,
      rescueCase: next ?? stored[update.caseHash]!,
    );
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

  setUpAll(sqfliteFfiInit);

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
        teamId: _team,
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

  test(
    'identidad estable ignora canonical mutable y separa remitentes',
    () async {
      final first = RescueCaseController.stableCaseHash(
        senderPeerId: _victim,
        messageId: 'interop-id',
      );
      final retry = RescueCaseController.stableCaseHash(
        senderPeerId: _victim,
        messageId: 'interop-id',
      );
      final other = RescueCaseController.stableCaseHash(
        senderPeerId: _remoteA,
        messageId: 'interop-id',
      );
      final anotherMessage = RescueCaseController.stableCaseHash(
        senderPeerId: _victim,
        messageId: 'other-id',
      );
      expect(first, retry);
      expect(first, isNot(other));
      expect(first, isNot(anotherMessage));

      mesh.emit(_sos('interop-id', canonicalHash: _hash));
      await _pump();

      expect(controller.cases, hasLength(1));
      expect(controller.cases.single.caseHash, first);
      expect(controller.cases.single.canonicalHash, _hash);
    },
  );

  test('autoriza por roster aunque el peer ya no esté visible', () async {
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

    expect(controller.cases.single.state, RescueCaseState.assigned);
    expect(controller.cases.single.assigneePeerId, _remoteA);
    expect(repository.events, hasLength(1));
  });

  test('resuelve concurrencia y nunca regresa atendido', () async {
    mesh.emit(_sos('sos'));
    mesh.livePeers
      ..add(_peer(_remoteA, keyA))
      ..add(_peer(_remoteB, keyB));
    mesh.emit(_updateMessage(_remoteA, keyA, 2000));
    mesh.emit(_updateMessage(_remoteB, keyB, 2000));
    await _pump();

    expect(controller.cases.single.assigneePeerId, _remoteA);

    mesh.emit(
      _updateMessage(
        _remoteA,
        keyA,
        3000,
        previousState: RescueCaseState.assigned,
        state: RescueCaseState.enRoute,
      ),
    );
    mesh.emit(
      _updateMessage(
        _remoteA,
        keyA,
        3500,
        previousState: RescueCaseState.enRoute,
        state: RescueCaseState.attended,
      ),
    );
    mesh.emit(_updateMessage(_remoteA, keyA, 4000));
    await _pump();

    expect(controller.cases.single.state, RescueCaseState.attended);
    expect(controller.cases.single.assigneePeerId, _remoteA);
  });

  test('asignación menor 31 segundos después no roba el caso', () async {
    mesh.emit(_sos('sos'));
    mesh.emit(_updateMessage(_remoteB, keyB, 2000));
    mesh.emit(_updateMessage(_remoteA, keyA, 33001));
    await _pump();

    expect(controller.cases.single.state, RescueCaseState.assigned);
    expect(controller.cases.single.assigneePeerId, _remoteB);
    expect(repository.events, hasLength(1));
  });

  test('rechaza timestamp payload distinto al paquete firmado', () async {
    mesh.emit(_sos('sos'));
    mesh.emit(
      _updateMessage(
        _remoteA,
        keyA,
        2000,
        packetTimestamp: DateTime.fromMillisecondsSinceEpoch(4000, isUtc: true),
      ),
    );
    await _pump();

    expect(controller.cases.single.state, RescueCaseState.newCase);
    expect(repository.events, isEmpty);
  });

  test('asignarme persiste y usa el canal MESSAGE firmado normal', () async {
    mesh.emit(_sos('sos'));
    await _pump();

    await controller.assignToMe(controller.cases.single.caseHash);

    expect(controller.cases.single.state, RescueCaseState.assigned);
    expect(controller.cases.single.assigneePeerId, _local);
    expect(mesh.sent.single.channel, RescueCaseController.channel);
    expect(
      RescueCaseUpdateCodec.tryDecode(mesh.sent.single.content),
      isNotNull,
    );
  });

  test('rechaza saltos, avance ajeno y cierre ajeno', () async {
    mesh.emit(_sos('sos'));
    mesh.emit(_updateMessage(_remoteA, keyA, 2000));
    await _pump();

    mesh.emit(
      _updateMessage(
        _remoteA,
        keyA,
        3000,
        previousState: RescueCaseState.enRoute,
        state: RescueCaseState.attended,
      ),
    );
    mesh.emit(
      _updateMessage(
        _remoteB,
        keyB,
        3100,
        previousState: RescueCaseState.assigned,
        state: RescueCaseState.enRoute,
        assignee: _remoteA,
      ),
    );
    await _pump();
    expect(controller.cases.single.state, RescueCaseState.assigned);

    mesh.emit(
      _updateMessage(
        _remoteA,
        keyA,
        4000,
        previousState: RescueCaseState.assigned,
        state: RescueCaseState.enRoute,
      ),
    );
    mesh.emit(
      _updateMessage(
        _remoteA,
        keyA,
        5000,
        previousState: RescueCaseState.enRoute,
        state: RescueCaseState.attended,
      ),
    );
    await _pump();
    mesh.emit(
      _updateMessage(
        _remoteB,
        keyB,
        6000,
        previousState: RescueCaseState.attended,
        state: RescueCaseState.closed,
        assignee: _remoteA,
      ),
    );
    await _pump();
    expect(controller.cases.single.state, RescueCaseState.attended);
  });

  test('ignora updates privados, externos y de otro canal', () async {
    mesh.emit(_sos('sos'));
    mesh.emit(_updateMessage(_remoteA, keyA, 2000, isPrivate: true));
    mesh.emit(_updateMessage(_remoteA, keyA, 2100, external: true));
    mesh.emit(_updateMessage(_remoteA, keyA, 2200, channel: 'other'));
    await _pump();

    expect(controller.cases.single.state, RescueCaseState.newCase);
    expect(repository.events, isEmpty);
  });

  test('rechaza updates anteriores al caso o demasiado futuros', () async {
    mesh.emit(_sos('sos'));
    mesh.emit(_updateMessage(_remoteA, keyA, 500));
    mesh.emit(
      _updateMessage(
        _remoteA,
        keyA,
        DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 6))
            .millisecondsSinceEpoch,
      ),
    );
    await _pump();

    expect(controller.cases.single.state, RescueCaseState.newCase);
  });

  test('commit local no pisa un avance remoto intercalado', () async {
    mesh.emit(_sos('sos'));
    await _pump();
    final caseHash = controller.cases.single.caseHash;
    mesh.beforeSendReturns = () async {
      final current = repository.stored[caseHash]!;
      repository.stored[caseHash] = current.copyWith(
        state: RescueCaseState.enRoute,
        assigneePeerId: _remoteA,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(3000),
        lastActorPeerId: _remoteA,
      );
    };

    await controller.assignToMe(caseHash);

    expect(controller.cases.single.state, RescueCaseState.enRoute);
    expect(controller.cases.single.assigneePeerId, _remoteA);
  });

  test(
    'cambiar de equipo oculta casos y carga solo el equipo activo',
    () async {
      mesh.emit(_sos('sos'));
      await _pump();
      expect(controller.cases, hasLength(1));

      roster.roster = RescueTeamRoster(
        teamId: 'f' * 32,
        name: 'Other',
        createdAt: DateTime.fromMillisecondsSinceEpoch(2),
        leaderPeerId: _local,
        members: [_member(_local, localKey, RescueRosterRole.leader)],
        signature: Uint8List.fromList(List<int>.filled(64, 2)),
      );
      roster.notifyListeners();
      await _pump();

      expect(controller.cases, isEmpty);
    },
  );

  test('reprocesa SOS cuando el roster termina de inicializar', () async {
    final active = roster.roster;
    roster.roster = null;
    roster.loading = true;
    roster.notifyListeners();
    await _pump();
    mesh.emit(_sos('late-roster'));
    await _pump();
    expect(controller.cases, isEmpty);

    roster.roster = active;
    roster.loading = false;
    roster.notifyListeners();
    await _pump();

    expect(controller.cases, hasLength(1));
  });

  test('reprocesa update que llegó antes de su SOS', () async {
    mesh.emit(_updateMessage(_remoteA, keyA, 2000));
    await _pump();
    expect(controller.cases, isEmpty);

    mesh.emit(_sos('sos'));
    await _pump();

    expect(controller.cases.single.state, RescueCaseState.assigned);
  });

  test(
    'reprocesa update recibido sin roster cuando después se activa',
    () async {
      final active = roster.roster;
      roster.roster = null;
      roster.loading = false;
      roster.notifyListeners();
      mesh.emit(_updateMessage(_remoteA, keyA, 2000));
      await _pump();

      roster.roster = active;
      roster.notifyListeners();
      mesh.emit(_sos('sos'));
      await _pump();

      expect(controller.cases.single.state, RescueCaseState.assigned);
    },
  );

  test('update de A recibido bajo B se procesa al volver a A', () async {
    final rosterA = roster.roster!;
    mesh.emit(_sos('sos'));
    await _pump();
    roster.roster = _rosterForTeam(
      teamId: 'f' * 32,
      localKey: localKey,
      remoteKey: keyA,
    );
    roster.notifyListeners();
    await _pump();

    mesh.emit(_updateMessage(_remoteA, keyA, 2000));
    await _pump();
    expect(controller.cases, isEmpty);

    roster.roster = rosterA;
    roster.notifyListeners();
    await _pump();
    expect(controller.cases.single.state, RescueCaseState.assigned);
  });

  test('controller y repositorio retienen los mismos 2000 casos', () async {
    for (
      var index = 0;
      index <= RescueCaseRepository.maximumCasesPerTeam;
      index++
    ) {
      mesh.storedMessages.add(_sos('capacity-$index'));
    }
    mesh.notifyListeners();
    await _pump(10);

    expect(
      controller.cases,
      hasLength(RescueCaseRepository.maximumCasesPerTeam),
    );
    expect(
      repository.stored,
      hasLength(RescueCaseRepository.maximumCasesPerTeam),
    );
    expect(
      controller.cases.map((item) => item.caseHash).toSet(),
      repository.stored.keys.toSet(),
    );
  });

  test('base de datos y controller conservan los mismos 2000 hashes', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'hearth_bit_case_controller_retention_',
    );
    final databasePath = path.join(temporaryDirectory.path, 'rescue.db');
    final realMesh = _Mesh()
      ..peerId = _local
      ..signingPublicKey = localKey;
    final realRoster = _Roster(mesh: realMesh, roster: roster.roster);
    final realRepository = RescueCaseRepository(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
      now: () => DateTime.fromMillisecondsSinceEpoch(10000, isUtc: true),
    );
    final realController = RescueCaseController(
      mesh: realMesh,
      roster: realRoster,
      repository: realRepository,
      now: () => DateTime.fromMillisecondsSinceEpoch(10000, isUtc: true),
    );
    await realController.initialize();
    for (
      var index = 0;
      index <= RescueCaseRepository.maximumCasesPerTeam;
      index++
    ) {
      realMesh.storedMessages.add(_sos('db-capacity-$index'));
    }
    realMesh.notifyListeners();
    for (
      var attempt = 0;
      attempt < 3000 &&
          realController.cases.length <
              RescueCaseRepository.maximumCasesPerTeam;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await _pump(10);

    final persisted = await realRepository.loadCases(teamId: _team);
    expect(
      realController.cases,
      hasLength(RescueCaseRepository.maximumCasesPerTeam),
    );
    expect(persisted, hasLength(RescueCaseRepository.maximumCasesPerTeam));
    expect(
      realController.cases.map((item) => item.caseHash).toSet(),
      persisted.map((item) => item.caseHash).toSet(),
    );

    await realRepository.close();
    realController.dispose();
    realRoster.dispose();
    realMesh.dispose();
    await databaseFactoryFfi.deleteDatabase(databasePath);
    await temporaryDirectory.delete(recursive: true);
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

MeshMessage _sos(String id, {String canonicalHash = _hash}) => MeshMessage(
  id: id,
  sender: 'Victim',
  content: 'SOS|Help|4.7|-74.1',
  senderPeerId: _victim,
  isPrivate: false,
  isMine: false,
  timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
  channel: 'sos',
  canonicalHash: canonicalHash,
);

MeshMessage _updateMessage(
  String actor,
  Uint8List key,
  int timestamp, {
  RescueCaseState previousState = RescueCaseState.newCase,
  RescueCaseState state = RescueCaseState.assigned,
  String? assignee,
  bool isPrivate = false,
  bool external = false,
  String channel = RescueCaseController.channel,
  DateTime? packetTimestamp,
}) {
  final update = RescueCaseUpdate(
    teamId: _team,
    caseHash: RescueCaseController.stableCaseHash(
      senderPeerId: _victim,
      messageId: 'sos',
    ),
    previousState: previousState,
    state: state,
    actorPeerId: actor,
    assigneePeerId: assignee ?? actor,
    timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
  );
  return MeshMessage(
    id: '$actor-$timestamp-${state.name}-${key.first}',
    sender: actor.substring(0, 4),
    content: RescueCaseUpdateCodec.encode(update),
    senderPeerId: actor,
    isPrivate: isPrivate,
    isMine: false,
    timestamp: packetTimestamp ?? update.timestamp,
    channel: channel,
    external: external,
  );
}

RescueTeamRoster _rosterForTeam({
  required String teamId,
  required Uint8List localKey,
  required Uint8List remoteKey,
}) => RescueTeamRoster(
  teamId: teamId,
  name: 'Other',
  createdAt: DateTime.fromMillisecondsSinceEpoch(2),
  leaderPeerId: _local,
  members: [
    _member(_local, localKey, RescueRosterRole.leader),
    _member(_remoteA, remoteKey, RescueRosterRole.responder),
  ],
  signature: Uint8List(64),
);

Future<void> _pump([int turns = 3]) async {
  for (var index = 0; index < turns; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
