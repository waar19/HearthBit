import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/family_models.dart';

DatabaseFactory _defaultDatabaseFactory() => databaseFactory;

class FamilyRepository {
  FamilyRepository({this.databaseFactory, this.databasePath})
    : assert(databasePath == null || databasePath.isNotEmpty);

  final DatabaseFactory? databaseFactory;
  final String? databasePath;
  Database? _database;

  Future<Database> get _db async {
    final factory = databaseFactory ?? _defaultDatabaseFactory();
    final resolvedPath =
        databasePath ??
        path.join(await factory.getDatabasesPath(), 'hearth_bit_family.db');
    return _database ??= await factory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (database, version) async {
          await _createFamilyTables(database);
          await _createMetadataTable(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createMetadataTable(database);
        },
      ),
    );
  }

  static Future<void> _createFamilyTables(Database database) async {
    await database.execute('''
      CREATE TABLE family_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE family_members (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL,
        peer_id TEXT NOT NULL,
        nickname TEXT NOT NULL,
        signing_public_key BLOB NOT NULL,
        fingerprint TEXT NOT NULL,
        verified_at INTEGER NOT NULL,
        FOREIGN KEY(group_id) REFERENCES family_groups(id) ON DELETE CASCADE,
        UNIQUE(group_id, peer_id),
        UNIQUE(group_id, signing_public_key)
      )
    ''');
    await database.execute(
      'CREATE INDEX family_members_peer_idx ON family_members(peer_id)',
    );
    await database.execute(
      'CREATE INDEX family_members_key_idx ON family_members(signing_public_key)',
    );
  }

  static Future<void> _createMetadataTable(Database database) =>
      database.execute('''
        CREATE TABLE IF NOT EXISTS family_metadata (
          key TEXT PRIMARY KEY,
          value BLOB NOT NULL
        )
      ''');

  Future<List<FamilyGroup>> listGroups() async {
    final rows = await (await _db).query(
      'family_groups',
      orderBy: 'updated_at DESC, id DESC',
    );
    return rows.map(FamilyGroup.fromDatabase).toList(growable: false);
  }

  Future<FamilyGroup> createGroup(String name) async {
    final cleanName = _validateName(name);
    final now = DateTime.now().millisecondsSinceEpoch;
    final database = await _db;
    final id = await database.insert('family_groups', {
      'name': cleanName,
      'created_at': now,
      'updated_at': now,
    });
    return FamilyGroup(
      id: id,
      name: cleanName,
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  Future<void> renameGroup(int groupId, String name) async {
    final cleanName = _validateName(name);
    final updated = await (await _db).update(
      'family_groups',
      {'name': cleanName, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [groupId],
    );
    if (updated != 1) throw StateError('Family group not found');
  }

  Future<void> deleteGroup(int groupId) async {
    await (await _db).delete(
      'family_groups',
      where: 'id = ?',
      whereArgs: [groupId],
    );
  }

  Future<List<FamilyMember>> listMembers({int? groupId}) async {
    final rows = await (await _db).query(
      'family_members',
      where: groupId == null ? null : 'group_id = ?',
      whereArgs: groupId == null ? null : [groupId],
      orderBy: 'nickname COLLATE NOCASE ASC, verified_at DESC',
    );
    return rows.map(FamilyMember.fromDatabase).toList(growable: false);
  }

  Future<FamilyMember> addMember({
    required int groupId,
    required String peerId,
    required String nickname,
    required Uint8List signingPublicKey,
    required String fingerprint,
    DateTime? verifiedAt,
  }) async {
    final normalizedPeerId = peerId.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{16}$').hasMatch(normalizedPeerId)) {
      throw const FormatException('Invalid peerId');
    }
    if (signingPublicKey.length != 32) {
      throw const FormatException('Invalid signing public key');
    }
    final cleanNickname = nickname.trim();
    if (cleanNickname.isEmpty) throw const FormatException('Invalid nickname');
    final verified = verifiedAt ?? DateTime.now();
    final database = await _db;
    final id = await database.insert('family_members', {
      'group_id': groupId,
      'peer_id': normalizedPeerId,
      'nickname': cleanNickname,
      'signing_public_key': signingPublicKey,
      'fingerprint': fingerprint,
      'verified_at': verified.millisecondsSinceEpoch,
    });
    return FamilyMember(
      id: id,
      groupId: groupId,
      peerId: normalizedPeerId,
      nickname: cleanNickname,
      signingPublicKey: Uint8List.fromList(signingPublicKey),
      fingerprint: fingerprint,
      verifiedAt: verified,
    );
  }

  Future<void> deleteMember(int memberId) async {
    await (await _db).delete(
      'family_members',
      where: 'id = ?',
      whereArgs: [memberId],
    );
  }

  Future<Uint8List?> readOwnerSigningKey() async {
    final rows = await (await _db).query(
      'family_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['owner_signing_key'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Uint8List.fromList(rows.single['value']! as List<int>);
  }

  Future<void> bindOwnerSigningKey(Uint8List signingPublicKey) async {
    if (signingPublicKey.length != 32) {
      throw const FormatException('Invalid signing public key');
    }
    await (await _db).insert('family_metadata', {
      'key': 'owner_signing_key',
      'value': signingPublicKey,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearTrust() async {
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete('family_groups');
      await transaction.delete('family_metadata');
    });
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  static String _validateName(String value) {
    final clean = value.trim();
    if (clean.isEmpty || clean.length > 80) {
      throw const FormatException('Invalid family group name');
    }
    return clean;
  }
}
