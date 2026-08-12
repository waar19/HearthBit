import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/mesh_models.dart';

class MessageRepository {
  Database? _database;

  Future<Database> get _db async {
    return _database ??= await openDatabase(
      path.join(await getDatabasesPath(), 'emergency_com.db'),
      version: 1,
      onCreate: (database, version) async {
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
      },
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

  Future<void> clear() async {
    await (await _db).delete('messages');
  }
}
