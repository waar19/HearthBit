import 'package:sqflite_sqlcipher/sqflite.dart';

abstract final class RescueDatabaseSchema {
  static const int version = 4;

  static Future<void> createRosterTables(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS rescue_teams (
        team_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        leader_peer_id TEXT NOT NULL,
        signature BLOB NOT NULL,
        active INTEGER NOT NULL CHECK(active IN (0, 1))
      )
    ''');
    await database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS rescue_one_active_team_idx '
      'ON rescue_teams(active) WHERE active = 1',
    );
    await database.execute('''
      CREATE TABLE IF NOT EXISTS rescue_members (
        team_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        peer_id TEXT NOT NULL,
        callsign TEXT NOT NULL,
        role INTEGER NOT NULL,
        signing_public_key BLOB NOT NULL,
        PRIMARY KEY(team_id, peer_id),
        UNIQUE(team_id, signing_public_key),
        UNIQUE(team_id, position),
        FOREIGN KEY(team_id) REFERENCES rescue_teams(team_id) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS rescue_members_peer_idx '
      'ON rescue_members(peer_id)',
    );
    await database.execute('''
      CREATE TABLE IF NOT EXISTS rescue_roster_versions (
        team_id TEXT PRIMARY KEY,
        max_created_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> createCaseTables(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS rescue_cases (
        team_id TEXT NOT NULL,
        case_hash TEXT NOT NULL,
        canonical_hash TEXT,
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
        last_actor_peer_id TEXT NOT NULL,
        PRIMARY KEY(team_id, case_hash)
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS rescue_cases_priority_idx '
      'ON rescue_cases(team_id, state, updated_at)',
    );
    await database.execute('''
      CREATE TABLE IF NOT EXISTS rescue_case_events (
        event_id TEXT PRIMARY KEY,
        team_id TEXT NOT NULL,
        case_hash TEXT NOT NULL,
        previous_state TEXT NOT NULL,
        state TEXT NOT NULL,
        actor_peer_id TEXT NOT NULL,
        assignee_peer_id TEXT,
        created_at INTEGER NOT NULL,
        applied INTEGER NOT NULL CHECK(applied IN (0, 1)),
        FOREIGN KEY(team_id, case_hash)
          REFERENCES rescue_cases(team_id, case_hash) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS rescue_case_events_case_idx '
      'ON rescue_case_events(team_id, case_hash, created_at)',
    );
  }

  static Future<void> createSweptZoneTables(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS swept_zones (
        zone_id TEXT PRIMARY KEY,
        version INTEGER NOT NULL,
        team_id TEXT NOT NULL,
        actor_peer_id TEXT NOT NULL,
        callsign TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        ended_at INTEGER NOT NULL,
        payload TEXT NOT NULL,
        received_at INTEGER NOT NULL
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS swept_zones_team_time_idx '
      'ON swept_zones(team_id, ended_at DESC)',
    );
  }

  /// La apertura de sqflite ejecuta `onUpgrade` en una transacción.
  ///
  /// Los casos v3 no tenían equipo. Si existe un roster activo, se atribuyen a
  /// ese equipo. De lo contrario, las tablas se conservan con prefijo
  /// `legacy_` para recuperación explícita y nunca se mezclan automáticamente.
  static Future<void> migrateToV4(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS rescue_roster_versions (
        team_id TEXT PRIMARY KEY,
        max_created_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      INSERT INTO rescue_roster_versions(team_id, max_created_at)
      SELECT team_id, MAX(created_at) FROM rescue_teams GROUP BY team_id
      ON CONFLICT(team_id) DO UPDATE SET max_created_at =
        MAX(max_created_at, excluded.max_created_at)
    ''');
    final caseColumns = await database.rawQuery(
      'PRAGMA table_info(rescue_cases)',
    );
    final alreadyScoped = caseColumns.any(
      (column) => column['name'] == 'team_id',
    );
    if (caseColumns.isEmpty || alreadyScoped) {
      await createCaseTables(database);
      return;
    }
    await database.execute(
      'ALTER TABLE rescue_case_events RENAME TO legacy_rescue_case_events_v3',
    );
    await database.execute(
      'ALTER TABLE rescue_cases RENAME TO legacy_rescue_cases_v3',
    );
    await database.execute('DROP INDEX IF EXISTS rescue_cases_priority_idx');
    await database.execute('DROP INDEX IF EXISTS rescue_case_events_case_idx');
    await createCaseTables(database);
    final activeTeams = await database.query(
      'rescue_teams',
      columns: ['team_id'],
      where: 'active = 1',
      limit: 1,
    );
    if (activeTeams.isEmpty) return;
    final teamId = activeTeams.single['team_id']! as String;
    await database.rawInsert(
      '''
      INSERT INTO rescue_cases(
        team_id, case_hash, canonical_hash, victim_peer_id, victim, message,
        triage, latitude, longitude, state, assignee_peer_id, created_at,
        updated_at, last_actor_peer_id
      )
      SELECT ?, case_hash, NULL, victim_peer_id, victim, message, triage,
        latitude, longitude, state, assignee_peer_id, created_at, updated_at,
        last_actor_peer_id
      FROM legacy_rescue_cases_v3
      ''',
      [teamId],
    );
    await database.rawInsert(
      '''
      INSERT INTO rescue_case_events(
        event_id, team_id, case_hash, previous_state, state, actor_peer_id,
        assignee_peer_id, created_at, applied
      )
      SELECT event_id, ?, case_hash,
        CASE state
          WHEN 'A' THEN 'N'
          WHEN 'E' THEN 'A'
          WHEN 'T' THEN 'E'
          WHEN 'C' THEN 'T'
          ELSE 'N'
        END,
        state, actor_peer_id, assignee_peer_id, created_at, applied
      FROM legacy_rescue_case_events_v3
      ''',
      [teamId],
    );
    await database.execute('DROP TABLE legacy_rescue_case_events_v3');
    await database.execute('DROP TABLE legacy_rescue_cases_v3');
  }
}
