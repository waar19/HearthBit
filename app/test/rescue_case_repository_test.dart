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
    );
  });

  tearDown(() async {
    await repository.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
    await temporaryDirectory.delete(recursive: true);
  });

  test('migra v1 a v3 sin borrar el roster', () async {
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

    expect(await repository.loadCases(), isEmpty);

    final migrated = await databaseFactoryFfi.openDatabase(databasePath);
    expect((await migrated.query('rescue_teams')).single['name'], 'Equipo');
    expect(
      (await migrated.rawQuery('PRAGMA user_version')).single['user_version'],
      3,
    );
    await migrated.close();
  });

  test('deduplica SOS por hash y eventos por identidad canónica', () async {
    final rescueCase = _case();
    expect(await repository.insertSos(rescueCase), isTrue);
    expect(await repository.insertSos(rescueCase), isFalse);

    final update = RescueCaseUpdate(
      caseHash: rescueCase.caseHash,
      state: RescueCaseState.assigned,
      actorPeerId: '0011223344556677',
      assigneePeerId: '0011223344556677',
      timestamp: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
    );
    final assigned = rescueCase.copyWith(
      state: RescueCaseState.assigned,
      assigneePeerId: update.assigneePeerId,
      updatedAt: update.timestamp,
      lastActorPeerId: update.actorPeerId,
    );

    expect(
      await repository.applyIncomingUpdate(
        rescueCase: assigned,
        update: update,
      ),
      isTrue,
    );
    expect(
      await repository.applyIncomingUpdate(
        rescueCase: assigned,
        update: update,
      ),
      isFalse,
    );
    expect(await repository.eventCount(caseHash: rescueCase.caseHash), 1);
    expect(
      (await repository.loadCases()).single.state,
      RescueCaseState.assigned,
    );
  });
}

RescueCase _case() => RescueCase(
  caseHash: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  victimPeerId: '8899aabbccddeeff',
  victim: 'Victim',
  message: 'Help',
  state: RescueCaseState.newCase,
  createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
  lastActorPeerId: '8899aabbccddeeff',
);
