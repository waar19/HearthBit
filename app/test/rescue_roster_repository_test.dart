import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hearth_bit/models/rescue_roster_models.dart';
import 'package:hearth_bit/services/rescue_roster_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late String databasePath;
  late RescueRosterRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'hearth_bit_rescue_roster_test_',
    );
    databasePath = path.join(temporaryDirectory.path, 'rescue.db');
    repository = RescueRosterRepository(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
    );
  });

  tearDown(() async {
    await repository.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
    await temporaryDirectory.delete(recursive: true);
  });

  test('guarda y reemplaza atómicamente el roster activo cifrado', () async {
    await repository.saveActiveRoster(_roster('Equipo Uno', 1));
    expect((await repository.loadActiveRoster())?.name, 'Equipo Uno');

    await repository.saveActiveRoster(_roster('Equipo Dos', 2));
    final active = await repository.loadActiveRoster();
    expect(active?.name, 'Equipo Dos');
    expect(active?.members.single.callsign, 'Líder 2');

    await repository.clear();
    expect(await repository.loadActiveRoster(), isNull);
  });

  test(
    'rechaza replay del mismo equipo tras remover, limpiar y reiniciar',
    () async {
      final original = _sameTeamRoster(createdAt: 1000, includeResponder: true);
      final removed = _sameTeamRoster(createdAt: 2000, includeResponder: false);
      await repository.saveActiveRoster(original);
      await repository.saveActiveRoster(removed);

      await expectLater(
        repository.saveActiveRoster(original),
        throwsStateError,
      );
      await repository.clear();
      await repository.close();
      repository = RescueRosterRepository(
        databaseFactory: databaseFactoryFfi,
        databasePath: databasePath,
      );

      await expectLater(repository.saveActiveRoster(removed), throwsStateError);
      expect(await repository.loadActiveRoster(), isNull);
    },
  );
}

RescueTeamRoster _roster(String name, int seed) {
  final peerId = seed.toRadixString(16).padLeft(16, '0');
  return RescueTeamRoster(
    teamId: seed.toRadixString(16).padLeft(32, '0'),
    name: name,
    createdAt: DateTime.fromMillisecondsSinceEpoch(seed * 1000),
    leaderPeerId: peerId,
    members: [
      RescueRosterMember(
        peerId: peerId,
        callsign: 'Líder $seed',
        role: RescueRosterRole.leader,
        signingPublicKey: Uint8List.fromList(
          List.generate(32, (index) => index + seed),
        ),
      ),
    ],
    signature: Uint8List.fromList(List.filled(64, seed)),
  );
}

RescueTeamRoster _sameTeamRoster({
  required int createdAt,
  required bool includeResponder,
}) {
  final leader = RescueRosterMember(
    peerId: '0011223344556677',
    callsign: 'Líder',
    role: RescueRosterRole.leader,
    signingPublicKey: Uint8List.fromList(List<int>.filled(32, 1)),
  );
  return RescueTeamRoster(
    teamId: '0' * 32,
    name: 'Equipo',
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
    leaderPeerId: leader.peerId,
    members: [
      leader,
      if (includeResponder)
        RescueRosterMember(
          peerId: '8899aabbccddeeff',
          callsign: 'Bravo',
          role: RescueRosterRole.responder,
          signingPublicKey: Uint8List.fromList(List<int>.filled(32, 2)),
        ),
    ],
    signature: Uint8List.fromList(List<int>.filled(64, createdAt ~/ 1000)),
  );
}
