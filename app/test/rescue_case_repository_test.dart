import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hearth_bit/models/rescue_case_models.dart';
import 'package:hearth_bit/services/rescue_case_repository.dart';
import 'package:hearth_bit/services/rescue_database_schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late String databasePath;
  late RescueCaseRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'hearth_bit_rescue_case_test_',
    );
    databasePath = path.join(temporaryDirectory.path, 'rescue.db');
    repository = RescueCaseRepository(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
      now: () => DateTime.utc(2026, 8, 18),
    );
  });

  tearDown(() async {
    await repository.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
    await temporaryDirectory.delete(recursive: true);
  });

  test('migra v1 a v4 sin borrar el roster', () async {
    final legacy = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) =>
            RescueDatabaseSchema.createRosterTables(database),
      ),
    );
    await legacy.insert('rescue_teams', {
      'team_id': '0' * 32,
      'name': 'Equipo',
      'created_at': 1,
      'leader_peer_id': '0' * 16,
      'signature': Uint8List.fromList(List<int>.filled(64, 1)),
      'active': 1,
    });
    await legacy.close();

    expect(await repository.loadCases(teamId: '0' * 32), isEmpty);

    final migrated = await databaseFactoryFfi.openDatabase(databasePath);
    expect((await migrated.query('rescue_teams')).single['name'], 'Equipo');
    expect(
      (await migrated.rawQuery('PRAGMA user_version')).single['user_version'],
      4,
    );
    await migrated.close();
  });

  test('deduplica SOS por hash y eventos por identidad canónica', () async {
    final rescueCase = _case();
    expect(await repository.insertSos(rescueCase), isTrue);
    expect(await repository.insertSos(rescueCase), isFalse);

    final update = RescueCaseUpdate(
      teamId: rescueCase.teamId,
      caseHash: rescueCase.caseHash,
      previousState: RescueCaseState.newCase,
      state: RescueCaseState.assigned,
      actorPeerId: '0011223344556677',
      assigneePeerId: '0011223344556677',
      timestamp: DateTime.utc(2026, 8, 17, 1),
    );
    expect(await repository.applyIncomingUpdate(update), isNotNull);
    expect(await repository.applyIncomingUpdate(update), isNull);
    expect(
      await repository.eventCount(
        teamId: rescueCase.teamId,
        caseHash: rescueCase.caseHash,
      ),
      1,
    );
    expect(
      (await repository.loadCases(teamId: rescueCase.teamId)).single.state,
      RescueCaseState.assigned,
    );
  });

  test(
    'retención elimina cerrados antiguos y acota spam activo por equipo',
    () async {
      final oldClosed = _case().copyWith(
        state: RescueCaseState.closed,
        assigneePeerId: '0011223344556677',
        updatedAt: DateTime.utc(2026, 7, 1),
      );
      final validOldClosed = RescueCase(
        teamId: oldClosed.teamId,
        caseHash: oldClosed.caseHash,
        victimPeerId: oldClosed.victimPeerId,
        victim: oldClosed.victim,
        message: oldClosed.message,
        state: oldClosed.state,
        assigneePeerId: oldClosed.assigneePeerId,
        createdAt: DateTime.utc(2026, 6, 30),
        updatedAt: oldClosed.updatedAt,
        lastActorPeerId: oldClosed.lastActorPeerId,
      );
      expect(await repository.insertSos(validOldClosed), isTrue);

      for (
        var index = 0;
        index <= RescueCaseRepository.maximumCasesPerTeam;
        index++
      ) {
        final createdAt = DateTime.utc(
          2026,
          8,
          17,
        ).add(Duration(milliseconds: index));
        await repository.insertSos(
          RescueCase(
            teamId: '0' * 32,
            caseHash: index.toRadixString(16).padLeft(64, '0'),
            victimPeerId: '8899aabbccddeeff',
            victim: 'Victim',
            message: 'Help',
            state: RescueCaseState.newCase,
            createdAt: createdAt,
            updatedAt: createdAt,
            lastActorPeerId: '8899aabbccddeeff',
          ),
        );
      }

      final retained = await repository.loadCases(teamId: '0' * 32);
      expect(retained, hasLength(RescueCaseRepository.maximumCasesPerTeam));
      expect(
        retained.any((item) => item.state == RescueCaseState.closed),
        isFalse,
      );
    },
  );
}

RescueCase _case() => RescueCase(
  teamId: '0' * 32,
  caseHash: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  victimPeerId: '8899aabbccddeeff',
  victim: 'Victim',
  message: 'Help',
  state: RescueCaseState.newCase,
  createdAt: DateTime.utc(2026, 8, 17),
  updatedAt: DateTime.utc(2026, 8, 17),
  lastActorPeerId: '8899aabbccddeeff',
);
