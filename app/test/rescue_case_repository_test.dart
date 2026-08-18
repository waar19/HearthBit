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
    expect((await repository.insertSos(rescueCase)).inserted, isTrue);
    expect((await repository.insertSos(rescueCase)).inserted, isFalse);

    final update = RescueCaseUpdate(
      teamId: rescueCase.teamId,
      caseHash: rescueCase.caseHash,
      previousState: RescueCaseState.newCase,
      state: RescueCaseState.assigned,
      actorPeerId: '0011223344556677',
      assigneePeerId: '0011223344556677',
      timestamp: DateTime.utc(2026, 8, 17, 1),
    );
    expect(
      (await repository.applyIncomingUpdate(update)).rescueCase,
      isNotNull,
    );
    expect((await repository.applyIncomingUpdate(update)).rescueCase, isNull);
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
      expect((await repository.insertSos(validOldClosed)).inserted, isTrue);

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

  test(
    'migra v3 poblada al roster activo sin perder casos ni eventos',
    () async {
      final legacy = await _openPopulatedV3(databasePath, activeTeam: '0' * 32);
      await legacy.close();

      final cases = await repository.loadCases(teamId: '0' * 32);
      expect(cases, hasLength(1));
      expect(cases.single.message, 'Ayuda legado');
      expect(cases.single.state, RescueCaseState.assigned);

      final migrated = await databaseFactoryFfi.openDatabase(databasePath);
      final events = await migrated.query('rescue_case_events');
      expect(events, hasLength(1));
      expect(events.single['team_id'], '0' * 32);
      expect(events.single['previous_state'], RescueCaseState.newCase.wireCode);
      expect(await _tableExists(migrated, 'legacy_rescue_cases_v3'), isFalse);
      await migrated.close();
    },
  );

  test('migra v3 sin roster a cuarentena recuperable y no la mezcla', () async {
    final legacy = await _openPopulatedV3(databasePath);
    await legacy.close();

    expect(await repository.loadCases(teamId: '0' * 32), isEmpty);

    final migrated = await databaseFactoryFfi.openDatabase(databasePath);
    expect(await migrated.query('rescue_cases'), isEmpty);
    expect(await migrated.query('rescue_case_events'), isEmpty);
    final legacyCases = await migrated.query('legacy_rescue_cases_v3');
    final legacyEvents = await migrated.query('legacy_rescue_case_events_v3');
    expect(legacyCases.single['message'], 'Ayuda legado');
    expect(legacyEvents.single['state'], RescueCaseState.assigned.wireCode);
    await migrated.close();
  });
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

Future<Database> _openPopulatedV3(
  String databasePath, {
  String? activeTeam,
}) async {
  final database = await databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(
      version: 3,
      onCreate: (database, version) async {
        await RescueDatabaseSchema.createRosterTables(database);
        await database.execute('''
          CREATE TABLE rescue_cases (
            case_hash TEXT PRIMARY KEY,
            victim_peer_id TEXT NOT NULL,
            victim TEXT NOT NULL,
            message TEXT NOT NULL,
            triage TEXT,
            latitude REAL,
            longitude REAL,
            state TEXT NOT NULL,
            assignee_peer_id TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            last_actor_peer_id TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE rescue_case_events (
            event_id TEXT PRIMARY KEY,
            case_hash TEXT NOT NULL,
            state TEXT NOT NULL,
            actor_peer_id TEXT NOT NULL,
            assignee_peer_id TEXT,
            created_at INTEGER NOT NULL,
            applied INTEGER NOT NULL CHECK(applied IN (0, 1)),
            FOREIGN KEY(case_hash) REFERENCES rescue_cases(case_hash)
              ON DELETE CASCADE
          )
        ''');
        await RescueDatabaseSchema.createSweptZoneTables(database);
      },
    ),
  );
  if (activeTeam != null) {
    await database.insert('rescue_teams', {
      'team_id': activeTeam,
      'name': 'Equipo',
      'created_at': 1,
      'leader_peer_id': '0011223344556677',
      'signature': Uint8List(64),
      'active': 1,
    });
  }
  final rescueCase = _case().copyWith(
    state: RescueCaseState.assigned,
    assigneePeerId: '0011223344556677',
    updatedAt: DateTime.utc(2026, 8, 17, 1),
  );
  await database.insert('rescue_cases', {
    'case_hash': rescueCase.caseHash,
    'victim_peer_id': rescueCase.victimPeerId,
    'victim': rescueCase.victim,
    'message': 'Ayuda legado',
    'triage': null,
    'latitude': null,
    'longitude': null,
    'state': rescueCase.state.wireCode,
    'assignee_peer_id': rescueCase.assigneePeerId,
    'created_at': rescueCase.createdAt.millisecondsSinceEpoch,
    'updated_at': rescueCase.updatedAt.millisecondsSinceEpoch,
    'last_actor_peer_id': rescueCase.lastActorPeerId,
  });
  await database.insert('rescue_case_events', {
    'event_id': 'legacy-event',
    'case_hash': rescueCase.caseHash,
    'state': RescueCaseState.assigned.wireCode,
    'actor_peer_id': '0011223344556677',
    'assignee_peer_id': '0011223344556677',
    'created_at': rescueCase.updatedAt.millisecondsSinceEpoch,
    'applied': 1,
  });
  return database;
}

Future<bool> _tableExists(Database database, String name) async {
  final rows = await database.query(
    'sqlite_master',
    columns: ['name'],
    where: "type = 'table' AND name = ?",
    whereArgs: [name],
  );
  return rows.isNotEmpty;
}
