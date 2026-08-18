import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/rescue_roster_models.dart';
import 'rescue_database_schema.dart';
import 'rescue_roster_codec.dart';
import 'secure_database.dart';

DatabaseFactory _defaultDatabaseFactory() => databaseFactory;

class RescueRosterRepository {
  RescueRosterRepository({this.databaseFactory, this.databasePath})
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

  Future<RescueTeamRoster?> loadActiveRoster() async {
    final database = await _db;
    final teams = await database.query(
      'rescue_teams',
      where: 'active = 1',
      limit: 1,
    );
    if (teams.isEmpty) return null;
    final team = teams.single;
    final memberRows = await database.query(
      'rescue_members',
      where: 'team_id = ?',
      whereArgs: [team['team_id']],
      orderBy: 'position ASC',
      limit: RescueRosterCodec.maximumMembers + 1,
    );
    if (memberRows.isEmpty ||
        memberRows.length > RescueRosterCodec.maximumMembers) {
      throw StateError('Stored rescue roster member count is invalid');
    }
    final members = memberRows
        .map((row) {
          final role = RescueRosterRole.fromWireCode(row['role']! as int);
          if (role == null) {
            throw StateError('Stored rescue roster role is invalid');
          }
          return RescueRosterMember(
            peerId: row['peer_id']! as String,
            callsign: row['callsign']! as String,
            role: role,
            signingPublicKey: Uint8List.fromList(
              row['signing_public_key']! as List<int>,
            ),
          );
        })
        .toList(growable: false);
    final roster = RescueTeamRoster(
      teamId: team['team_id']! as String,
      name: team['name']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        team['created_at']! as int,
      ),
      leaderPeerId: team['leader_peer_id']! as String,
      members: members,
      signature: Uint8List.fromList(team['signature']! as List<int>),
    );
    RescueRosterCodec.canonicalPayload(roster);
    if (roster.signature.length != RescueRosterCodec.signatureBytes) {
      throw StateError('Stored rescue roster signature is invalid');
    }
    return roster;
  }

  Future<void> saveActiveRoster(RescueTeamRoster roster) async {
    RescueRosterCodec.canonicalPayload(roster);
    if (roster.signature.length != RescueRosterCodec.signatureBytes) {
      throw const FormatException('Invalid rescue roster signature');
    }
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete('rescue_teams');
      await transaction.insert('rescue_teams', {
        'team_id': roster.teamId,
        'name': roster.name,
        'created_at': roster.createdAt.millisecondsSinceEpoch,
        'leader_peer_id': roster.leaderPeerId,
        'signature': roster.signature,
        'active': 1,
      });
      for (var position = 0; position < roster.members.length; position++) {
        final member = roster.members[position];
        await transaction.insert('rescue_members', {
          'team_id': roster.teamId,
          'position': position,
          'peer_id': member.peerId,
          'callsign': member.callsign,
          'role': member.role.wireCode,
          'signing_public_key': member.signingPublicKey,
        });
      }
    });
  }

  Future<void> clear() async {
    await (await _db).delete('rescue_teams');
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }
}
