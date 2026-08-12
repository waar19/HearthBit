import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/mesh_models.dart';

class MessageRepository {
  Database? _database;

  Future<Database> get _db async {
    return _database ??= await openDatabase(
      path.join(await getDatabasesPath(), 'hearth_bit.db'),
      version: 2,
      onCreate: (database, version) async {
        await _createMessagesTable(database);
        await _createKnownPeersTable(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createKnownPeersTable(database);
        }
      },
    );
  }

  static Future<void> _createMessagesTable(Database database) async {
    await database.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            sender TEXT NOT NULL,
            content TEXT NOT NULL,
            sender_peer_id TEXT NOT NULL,
            is_private INTEGER NOT NULL,
            is_mine INTEGER NOT NULL,
            timestamp INTEGER NOT NULL,
            channel TEXT
          )
        ''');
    await database.execute(
      'CREATE INDEX messages_timestamp_idx ON messages(timestamp)',
    );
  }

  static Future<void> _createKnownPeersTable(Database database) async {
    await database.execute('''
      CREATE TABLE known_peers (
        id TEXT PRIMARY KEY,
        nickname TEXT NOT NULL,
        last_seen INTEGER NOT NULL
      )
    ''');
    await database.execute(
      'CREATE INDEX known_peers_last_seen_idx ON known_peers(last_seen)',
    );
  }

  Future<List<MeshMessage>> load() async {
    final rows = await (await _db).query(
      'messages',
      orderBy: 'timestamp ASC',
      limit: 500,
    );
    return rows.map(MeshMessage.fromDatabase).toList(growable: false);
  }

  Future<void> save(MeshMessage message) async {
    await (await _db).insert(
      'messages',
      message.toDatabase(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<MeshPeer>> loadKnownPeers() async {
    final rows = await (await _db).query(
      'known_peers',
      orderBy: 'last_seen DESC',
    );
    return rows.map(MeshPeer.fromDatabase).toList(growable: false);
  }

  Future<void> saveKnownPeers(Iterable<MeshPeer> peers) async {
    final database = await _db;
    final batch = database.batch();
    for (final peer in peers) {
      batch.insert(
        'known_peers',
        peer.toDatabase(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> clear() async {
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete('messages');
      await transaction.delete('known_peers');
    });
  }
}
