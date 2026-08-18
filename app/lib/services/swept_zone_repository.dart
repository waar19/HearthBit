import 'package:path/path.dart' as path;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/swept_zone_models.dart';
import 'rescue_database_schema.dart';
import 'secure_database.dart';

DatabaseFactory _defaultDatabaseFactory() => databaseFactory;

class SweptZoneRepository {
  SweptZoneRepository({
    this.databaseFactory,
    this.databasePath,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       assert(databasePath == null || databasePath.isNotEmpty);

  static const Duration retention = Duration(days: 30);
  static const int maximumRetainedZones = 200;

  final DatabaseFactory? databaseFactory;
  final String? databasePath;
  final DateTime Function() _now;
  Database? _database;

  Future<Database> get _db async {
    final factory = databaseFactory ?? _defaultDatabaseFactory();
    final resolvedPath =
        databasePath ??
        path.join(await factory.getDatabasesPath(), 'hearth_bit_rescue.db');
    return _database ??= await SecureDatabase.open(
      databasePath: resolvedPath,
      version: RescueDatabaseSchema.version,
      testFactory: databaseFactory,
      onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
      onCreate: (database, version) async {
        await RescueDatabaseSchema.createRosterTables(database);
        await RescueDatabaseSchema.createCaseTables(database);
        await RescueDatabaseSchema.createSweptZoneTables(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await RescueDatabaseSchema.createCaseTables(database);
        }
        if (oldVersion < 3) {
          await RescueDatabaseSchema.createSweptZoneTables(database);
        }
        if (oldVersion < 4) {
          await RescueDatabaseSchema.migrateToV4(database);
        }
      },
    );
  }

  Future<List<SweptZone>> loadZones({required String teamId}) async {
    final database = await _db;
    await _prune(database);
    final rows = await database.query(
      'swept_zones',
      where: 'team_id = ?',
      whereArgs: [teamId],
      orderBy: 'ended_at DESC, zone_id ASC',
      limit: maximumRetainedZones,
    );
    final zones = <SweptZone>[];
    for (final row in rows) {
      final zone = SweptZoneCodec.tryDecode(row['payload']! as String);
      if (zone != null &&
          zone.zoneId == row['zone_id'] &&
          zone.teamId == row['team_id'] &&
          zone.actorPeerId == row['actor_peer_id']) {
        zones.add(zone);
      }
    }
    return List.unmodifiable(zones);
  }

  Future<bool> insert(SweptZone zone) async {
    final payload = SweptZoneCodec.encode(zone);
    final database = await _db;
    return database.transaction((transaction) async {
      final duplicate = await transaction.query(
        'swept_zones',
        columns: ['zone_id'],
        where: 'zone_id = ?',
        whereArgs: [zone.zoneId],
        limit: 1,
      );
      if (duplicate.isNotEmpty) return false;
      await transaction.insert('swept_zones', {
        'zone_id': zone.zoneId,
        'version': zone.version,
        'team_id': zone.teamId,
        'actor_peer_id': zone.actorPeerId,
        'callsign': zone.callsign,
        'started_at': zone.startedAt.toUtc().millisecondsSinceEpoch,
        'ended_at': zone.endedAt.toUtc().millisecondsSinceEpoch,
        'payload': payload,
        'received_at': _now().toUtc().millisecondsSinceEpoch,
      });
      await _prune(transaction);
      return true;
    });
  }

  Future<int> count({required String teamId}) async {
    final rows = await (await _db).rawQuery(
      'SELECT COUNT(*) AS count FROM swept_zones WHERE team_id = ?',
      [teamId],
    );
    return (rows.single['count']! as num).toInt();
  }

  Future<void> _prune(DatabaseExecutor database) async {
    final cutoff = _now().toUtc().subtract(retention).millisecondsSinceEpoch;
    await database.delete(
      'swept_zones',
      where: 'ended_at < ?',
      whereArgs: [cutoff],
    );
    await database.rawDelete(
      'DELETE FROM swept_zones WHERE zone_id IN ('
      'SELECT zone_id FROM swept_zones '
      'ORDER BY ended_at DESC, received_at DESC, zone_id ASC '
      'LIMIT -1 OFFSET ?)',
      [maximumRetainedZones],
    );
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }
}
