import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hearth_bit/models/swept_zone_models.dart';
import 'package:hearth_bit/services/rescue_database_schema.dart';
import 'package:hearth_bit/services/swept_zone_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late String databasePath;
  late SweptZoneRepository repository;
  final now = DateTime.utc(2026, 8, 18, 12);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'hearth_bit_swept_zone_test_',
    );
    databasePath = path.join(temporaryDirectory.path, 'rescue.db');
    repository = SweptZoneRepository(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
      now: () => now,
    );
  });

  tearDown(() async {
    await repository.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
    await temporaryDirectory.delete(recursive: true);
  });

  test('migra v2 a v3 y conserva las tablas operativas', () async {
    final legacy = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (database, version) async {
          await RescueDatabaseSchema.createRosterTables(database);
          await RescueDatabaseSchema.createCaseTables(database);
        },
      ),
    );
    await legacy.close();

    expect(await repository.loadZones(teamId: 'f' * 32), isEmpty);

    final migrated = await databaseFactoryFfi.openDatabase(databasePath);
    final tables = await migrated.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    expect(tables.map((row) => row['name']), contains('rescue_cases'));
    expect(tables.map((row) => row['name']), contains('swept_zones'));
    expect(
      (await migrated.rawQuery('PRAGMA user_version')).single['user_version'],
      3,
    );
    await migrated.close();
  });

  test('deduplica y limita retención a 30 días y 200 zonas', () async {
    final recent = _zone(1, now.subtract(const Duration(hours: 1)));
    expect(await repository.insert(recent), isTrue);
    expect(await repository.insert(recent), isFalse);

    final expired = _zone(2, now.subtract(const Duration(days: 31)));
    expect(await repository.insert(expired), isTrue);
    expect(
      (await repository.loadZones(
        teamId: recent.teamId,
      )).map((zone) => zone.zoneId),
      isNot(contains(expired.zoneId)),
    );

    for (var index = 3; index < 204; index++) {
      await repository.insert(
        _zone(index, now.subtract(Duration(minutes: index))),
      );
    }
    expect(await repository.count(teamId: recent.teamId), 200);
  });
}

SweptZone _zone(int seed, DateTime endedAt) {
  final startedAt = endedAt.subtract(const Duration(minutes: 1));
  return SweptZone(
    version: SweptZoneCodec.version,
    zoneId: seed.toRadixString(16).padLeft(32, '0'),
    teamId: 'f' * 32,
    actorPeerId: '0011223344556677',
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
