import 'package:path/path.dart' as path;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/mesh_models.dart';
import '../models/rescue_case_models.dart';
import 'rescue_database_schema.dart';
import 'secure_database.dart';

DatabaseFactory _defaultDatabaseFactory() => databaseFactory;

class RescueCaseWriteResult {
  const RescueCaseWriteResult({
    required this.inserted,
    required this.rescueCase,
    this.prunedCaseHashes = const <String>{},
  });

  final bool inserted;
  final RescueCase? rescueCase;
  final Set<String> prunedCaseHashes;
}

class RescueCaseRepository {
  RescueCaseRepository({
    this.databaseFactory,
    this.databasePath,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       assert(databasePath == null || databasePath.isNotEmpty);

  static const Duration closedRetention = Duration(days: 30);
  static const Duration maximumRetention = Duration(days: 180);
  static const int maximumCasesPerTeam = 2000;

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

  Future<List<RescueCase>> loadCases({required String teamId}) async {
    final database = await _db;
    await _prune(database, teamId);
    final rows = await database.query(
      'rescue_cases',
      where: 'team_id = ?',
      whereArgs: [teamId],
      orderBy: 'updated_at DESC, case_hash ASC',
      limit: maximumCasesPerTeam,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<RescueCase?> loadCase({
    required String teamId,
    required String caseHash,
  }) async {
    final rows = await (await _db).query(
      'rescue_cases',
      where: 'team_id = ? AND case_hash = ?',
      whereArgs: [teamId, caseHash],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<RescueCaseWriteResult> insertSos(RescueCase rescueCase) async {
    _validateCase(rescueCase);
    final database = await _db;
    return database.transaction((transaction) async {
      final existing = await transaction.query(
        'rescue_cases',
        columns: ['case_hash'],
        where: 'team_id = ? AND case_hash = ?',
        whereArgs: [rescueCase.teamId, rescueCase.caseHash],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return const RescueCaseWriteResult(inserted: false, rescueCase: null);
      }
      await transaction.insert('rescue_cases', _toRow(rescueCase));
      final pruned = await _prune(transaction, rescueCase.teamId);
      return RescueCaseWriteResult(
        inserted: true,
        rescueCase: pruned.contains(rescueCase.caseHash) ? null : rescueCase,
        prunedCaseHashes: pruned,
      );
    });
  }

  Future<RescueCaseWriteResult> applyIncomingUpdate(
    RescueCaseUpdate update,
  ) async {
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
      if (existing.isNotEmpty) {
        return const RescueCaseWriteResult(inserted: false, rescueCase: null);
      }
      final current = await _loadCaseFrom(
        transaction,
        teamId: update.teamId,
        caseHash: update.caseHash,
      );
      if (current == null) {
        return const RescueCaseWriteResult(inserted: false, rescueCase: null);
      }
      final next = RescueCaseTransition.resolve(current, update);
      if (next == null) {
        return const RescueCaseWriteResult(inserted: false, rescueCase: null);
      }
      await transaction.insert(
        'rescue_case_events',
        _eventRow(update, applied: true),
      );
      await _replaceCase(transaction, next);
      final pruned = await _prune(transaction, update.teamId);
      return RescueCaseWriteResult(
        inserted: true,
        rescueCase: pruned.contains(next.caseHash) ? null : next,
        prunedCaseHashes: pruned,
      );
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

  Future<RescueCaseWriteResult> commitLocalUpdate(
    RescueCaseUpdate update,
  ) async {
    RescueCaseUpdateCodec.encode(update);
    final database = await _db;
    return database.transaction((transaction) async {
      final changed = await transaction.update(
        'rescue_case_events',
        {'applied': 1},
        where: 'event_id = ? AND applied = 0',
        whereArgs: [update.eventId],
      );
      if (changed != 1) {
        throw StateError('Staged rescue case update was not found');
      }
      final current = await _loadCaseFrom(
        transaction,
        teamId: update.teamId,
        caseHash: update.caseHash,
      );
      if (current == null) {
        throw StateError('Rescue case was removed before local commit');
      }
      final next = RescueCaseTransition.resolve(current, update);
      if (next != null) await _replaceCase(transaction, next);
      final committed = next ?? current;
      final pruned = await _prune(transaction, update.teamId);
      return RescueCaseWriteResult(
        inserted: next != null,
        rescueCase: pruned.contains(committed.caseHash) ? null : committed,
        prunedCaseHashes: pruned,
      );
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

  Future<int> eventCount({
    required String teamId,
    required String caseHash,
  }) async {
    final result = await (await _db).rawQuery(
      'SELECT COUNT(*) AS count FROM rescue_case_events '
      'WHERE team_id = ? AND case_hash = ? AND applied = 1',
      [teamId, caseHash],
    );
    return (result.single['count']! as num).toInt();
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  static Future<RescueCase?> _loadCaseFrom(
    DatabaseExecutor database, {
    required String teamId,
    required String caseHash,
  }) async {
    final rows = await database.query(
      'rescue_cases',
      where: 'team_id = ? AND case_hash = ?',
      whereArgs: [teamId, caseHash],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  static Future<void> _replaceCase(
    DatabaseExecutor database,
    RescueCase rescueCase,
  ) async {
    _validateCase(rescueCase);
    final updated = await database.update(
      'rescue_cases',
      _toRow(rescueCase),
      where: 'team_id = ? AND case_hash = ?',
      whereArgs: [rescueCase.teamId, rescueCase.caseHash],
    );
    if (updated != 1) throw StateError('Rescue case changed unexpectedly');
  }

  static Map<String, Object?> _eventRow(
    RescueCaseUpdate update, {
    required bool applied,
  }) => {
    'event_id': update.eventId,
    'team_id': update.teamId,
    'case_hash': update.caseHash,
    'previous_state': update.previousState.wireCode,
    'state': update.state.wireCode,
    'actor_peer_id': update.actorPeerId,
    'assignee_peer_id': update.assigneePeerId,
    'created_at': update.timestamp.toUtc().millisecondsSinceEpoch,
    'applied': applied ? 1 : 0,
  };

  static Map<String, Object?> _toRow(RescueCase rescueCase) => {
    'team_id': rescueCase.teamId,
    'case_hash': rescueCase.caseHash,
    'canonical_hash': rescueCase.canonicalHash,
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
      teamId: row['team_id']! as String,
      caseHash: row['case_hash']! as String,
      canonicalHash: row['canonical_hash'] as String?,
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
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(rescueCase.teamId) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(rescueCase.caseHash) ||
        (rescueCase.canonicalHash != null &&
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(rescueCase.canonicalHash!)) ||
        rescueCase.victimPeerId.isEmpty ||
        rescueCase.victim.isEmpty ||
        rescueCase.message.isEmpty ||
        rescueCase.createdAt.millisecondsSinceEpoch <= 0 ||
        rescueCase.updatedAt.isBefore(rescueCase.createdAt)) {
      throw const FormatException('Invalid rescue case');
    }
  }

  Future<Set<String>> _prune(DatabaseExecutor database, String teamId) async {
    final now = _now().toUtc();
    final removed = <String>{};
    final expired = await database.query(
      'rescue_cases',
      columns: ['case_hash'],
      where:
          'team_id = ? AND ('
          '(state = ? AND updated_at < ?) OR updated_at < ?)',
      whereArgs: [
        teamId,
        RescueCaseState.closed.wireCode,
        now.subtract(closedRetention).millisecondsSinceEpoch,
        now.subtract(maximumRetention).millisecondsSinceEpoch,
      ],
    );
    removed.addAll(expired.map((row) => row['case_hash']! as String));
    await database.delete(
      'rescue_cases',
      where:
          'team_id = ? AND ('
          '(state = ? AND updated_at < ?) OR updated_at < ?)',
      whereArgs: [
        teamId,
        RescueCaseState.closed.wireCode,
        now.subtract(closedRetention).millisecondsSinceEpoch,
        now.subtract(maximumRetention).millisecondsSinceEpoch,
      ],
    );
    final overflow = await database.rawQuery(
      'SELECT case_hash FROM rescue_cases WHERE team_id = ? '
      'ORDER BY CASE WHEN state = ? THEN 1 ELSE 0 END ASC, '
      'updated_at DESC, case_hash ASC LIMIT -1 OFFSET ?',
      [teamId, RescueCaseState.closed.wireCode, maximumCasesPerTeam],
    );
    final overflowHashes = overflow
        .map((row) => row['case_hash']! as String)
        .toList(growable: false);
    removed.addAll(overflowHashes);
    for (final caseHash in overflowHashes) {
      await database.delete(
        'rescue_cases',
        where: 'team_id = ? AND case_hash = ?',
        whereArgs: [teamId, caseHash],
      );
    }
    return Set.unmodifiable(removed);
  }
}
