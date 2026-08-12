import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/transfer_models.dart';

class TransferRepository {
  Database? _database;

  Future<Database> get _db async {
    return _database ??= await openDatabase(
      path.join(await getDatabasesPath(), 'hearth_bit_transfers.db'),
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE transfers (
            id TEXT PRIMARY KEY,
            peer_id TEXT NOT NULL,
            peer_nickname TEXT NOT NULL,
            direction INTEGER NOT NULL,
            file_name TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            sha256 TEXT NOT NULL,
            chunk_size INTEGER NOT NULL,
            state INTEGER NOT NULL,
            transport INTEGER,
            bytes_done INTEGER NOT NULL,
            file_path TEXT,
            error TEXT,
            bitmap BLOB,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX transfers_updated_idx ON transfers(updated_at)',
        );
      },
    );
  }

  Future<List<TransferRecord>> load() async {
    final rows = await (await _db).query(
      'transfers',
      orderBy: 'updated_at DESC',
      limit: 200,
    );
    return rows.map(TransferRecord.fromDatabase).toList(growable: false);
  }

  Future<Uint8List?> loadBitmap(String id) async {
    final rows = await (await _db).query(
      'transfers',
      columns: ['bitmap'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['bitmap'] as Uint8List?;
  }

  Future<void> save(TransferRecord record, {Uint8List? bitmap}) async {
    record.updatedAt = DateTime.now();
    final values = record.toDatabase();
    if (bitmap != null) values['bitmap'] = bitmap;
    await (await _db).insert(
      'transfers',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    await (await _db).delete('transfers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clear() async {
    await (await _db).delete('transfers');
  }
}
