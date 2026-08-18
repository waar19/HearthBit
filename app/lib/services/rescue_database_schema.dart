import 'package:sqflite_sqlcipher/sqflite.dart';

abstract final class RescueDatabaseSchema {
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
  }

  static Future<void> createCaseTables(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS rescue_cases (
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
    await database.execute(
      'CREATE INDEX IF NOT EXISTS rescue_cases_priority_idx '
      'ON rescue_cases(state, updated_at)',
    );
    await database.execute('''
      CREATE TABLE IF NOT EXISTS rescue_case_events (
        event_id TEXT PRIMARY KEY,
        case_hash TEXT NOT NULL,
        state TEXT NOT NULL,
        actor_peer_id TEXT NOT NULL,
        assignee_peer_id TEXT,
        created_at INTEGER NOT NULL,
        applied INTEGER NOT NULL CHECK(applied IN (0, 1)),
        FOREIGN KEY(case_hash) REFERENCES rescue_cases(case_hash) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS rescue_case_events_case_idx '
      'ON rescue_case_events(case_hash, created_at)',
    );
  }
}
