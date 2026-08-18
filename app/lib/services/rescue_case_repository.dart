import 'package:path/path.dart' as path;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/mesh_models.dart';
import '../models/rescue_case_models.dart';
import 'rescue_database_schema.dart';
import 'secure_database.dart';

DatabaseFactory _defaultDatabaseFactory() => databaseFactory;

class RescueCaseRepository {
  RescueCaseRepository({this.databaseFactory, this.databasePath})
    : assert(databasePath == null || databasePath.isNotEmpty);

  final DatabaseFactory? databaseFactory;
  final String? databasePath;
  Database? _database;

  Future<Database> get _db async {
    final factory = databaseFactory ?? _defaultDatabaseFactory();
    final resolvedPath =
        databasePath ??
        path.join(await factory.getDatabasesPath(), 'hearth_bit_rescue.db');
    return _database ??= await SecureDatabase.open(
      databasePath: resolvedPath,
      version: 3,
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
      },
    );
  }

  Future<List<RescueCase>> loadCases() async {
    final rows = await (await _db).query(
      'rescue_cases',
      orderBy: 'updated_at DESC, case_hash ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<bool> insertSos(RescueCase rescueCase) async {
    _validateCase(rescueCase);
    final database = await _db;
    return database.transaction((transaction) async {
      final existing = await transaction.query(
        'rescue_cases',
        columns: ['case_hash'],
        where: 'case_hash = ?',
        whereArgs: [rescueCase.caseHash],
        limit: 1,
      );
      if (existing.isNotEmpty) return false;
      await transaction.insert('rescue_cases', _toRow(rescueCase));
      return true;
    });
  }

  Future<bool> applyIncomingUpdate({
    required RescueCase rescueCase,
    required RescueCaseUpdate update,
  }) async {
    _validateCase(rescueCase);
    RescueCaseUpdateCodec.encode(update);
    final database = await _db;
    return database.transaction((transaction) async {
      final existing = await transaction.query(
        'rescue_case_events',
        columns: ['event_id'],
        where: 'event_id = ?',
        whereArgs: [update.eventId],
        limit: 1,
      );
      if (existing.isNotEmpty) return false;
      await transaction.insert(
        'rescue_case_events',
        _eventRow(update, applied: true),
      );
      await _upsertCase(transaction, rescueCase);
      return true;
    });
  }

  Future<bool> stageLocalUpdate(RescueCaseUpdate update) async {
    RescueCaseUpdateCodec.encode(update);
    final database = await _db;
    return database.transaction((transaction) async {
      final existing = await transaction.query(
        'rescue_case_events',
        columns: ['event_id'],
        where: 'event_id = ?',
        whereArgs: [update.eventId],
        limit: 1,
      );
      if (existing.isNotEmpty) return false;
      await transaction.insert(
        'rescue_case_events',
        _eventRow(update, applied: false),
      );
      return true;
    });
  }

  Future<void> commitLocalUpdate({
    required RescueCase rescueCase,
    required RescueCaseUpdate update,
  }) async {
    _validateCase(rescueCase);
    RescueCaseUpdateCodec.encode(update);
    final database = await _db;
    await database.transaction((transaction) async {
      final changed = await transaction.update(
        'rescue_case_events',
        {'applied': 1},
        where: 'event_id = ? AND applied = 0',
        whereArgs: [update.eventId],
      );
      if (changed != 1) {
        throw StateError('Staged rescue case update was not found');
      }
      await _upsertCase(transaction, rescueCase);
    });
  }

  Future<void> discardLocalUpdate(RescueCaseUpdate update) async {
    await (await _db).delete(
      'rescue_case_events',
      where: 'event_id = ? AND applied = 0',
      whereArgs: [update.eventId],
    );
  }

  Future<void> discardStaleLocalUpdates() async {
    await (await _db).delete('rescue_case_events', where: 'applied = 0');
  }

  Future<int> eventCount({required String caseHash}) async {
    final result = await (await _db).rawQuery(
      'SELECT COUNT(*) AS count FROM rescue_case_events '
      'WHERE case_hash = ? AND applied = 1',
      [caseHash],
    );
    return (result.single['count']! as num).toInt();
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  static Future<void> _upsertCase(
    DatabaseExecutor database,
    RescueCase rescueCase,
  ) async {
    final updated = await database.update(
      'rescue_cases',
      _toRow(rescueCase),
      where: 'case_hash = ?',
      whereArgs: [rescueCase.caseHash],
    );
    if (updated == 0) {
      await database.insert('rescue_cases', _toRow(rescueCase));
    }
  }

  static Map<String, Object?> _eventRow(
    RescueCaseUpdate update, {
    required bool applied,
  }) => {
    'event_id': update.eventId,
    'case_hash': update.caseHash,
    'state': update.state.wireCode,
    'actor_peer_id': update.actorPeerId,
    'assignee_peer_id': update.assigneePeerId,
    'created_at': update.timestamp.toUtc().millisecondsSinceEpoch,
    'applied': applied ? 1 : 0,
  };

  static Map<String, Object?> _toRow(RescueCase rescueCase) => {
    'case_hash': rescueCase.caseHash,
    'victim_peer_id': rescueCase.victimPeerId,
    'victim': rescueCase.victim,
    'message': rescueCase.message,
    'triage': rescueCase.triage?.encode(),
    'latitude': rescueCase.latitude,
    'longitude': rescueCase.longitude,
    'state': rescueCase.state.wireCode,
    'assignee_peer_id': rescueCase.assigneePeerId,
    'created_at': rescueCase.createdAt.toUtc().millisecondsSinceEpoch,
    'updated_at': rescueCase.updatedAt.toUtc().millisecondsSinceEpoch,
    'last_actor_peer_id': rescueCase.lastActorPeerId,
  };

  static RescueCase _fromRow(Map<String, Object?> row) {
    final state = RescueCaseState.fromWireCode(row['state']! as String);
    if (state == null) throw StateError('Stored rescue case state is invalid');
    final triageValue = row['triage'] as String?;
    final triage = triageValue == null
        ? null
        : SosTriage.tryDecode(triageValue);
    if (triageValue != null && triage == null) {
      throw StateError('Stored rescue case triage is invalid');
    }
    return RescueCase(
      caseHash: row['case_hash']! as String,
      victimPeerId: row['victim_peer_id']! as String,
      victim: row['victim']! as String,
      message: row['message']! as String,
      triage: triage,
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      state: state,
      assigneePeerId: row['assignee_peer_id'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at']! as int,
        isUtc: true,
      ).toLocal(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at']! as int,
        isUtc: true,
      ).toLocal(),
      lastActorPeerId: row['last_actor_peer_id']! as String,
    );
  }

  static void _validateCase(RescueCase rescueCase) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(rescueCase.caseHash) ||
        rescueCase.victimPeerId.isEmpty ||
        rescueCase.victim.isEmpty ||
        rescueCase.message.isEmpty ||
        rescueCase.createdAt.millisecondsSinceEpoch <= 0 ||
        rescueCase.updatedAt.isBefore(rescueCase.createdAt)) {
      throw const FormatException('Invalid rescue case');
    }
  }
}
