import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/transfer_models.dart';
import 'secure_database.dart';

DatabaseFactory _defaultDatabaseFactory() => databaseFactory;

class TransferRepository {
  TransferRepository({this.databaseFactory, this.databasePath})
    : assert(databasePath == null || databasePath.isNotEmpty);

  final DatabaseFactory? databaseFactory;
  final String? databasePath;
  Database? _database;

  Future<Database> get _db async {
    final factory = databaseFactory ?? _defaultDatabaseFactory();
    return _database ??= await SecureDatabase.open(
      databasePath: await _resolveDatabasePath(factory),
      version: 2,
      testFactory: databaseFactory,
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
            session_private BLOB,
            session_public BLOB,
            remote_ephemeral BLOB,
            offered_transports INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX transfers_updated_idx ON transfers(updated_at)',
        );
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
            'ALTER TABLE transfers ADD COLUMN session_private BLOB',
          );
          await database.execute(
            'ALTER TABLE transfers ADD COLUMN session_public BLOB',
          );
          await database.execute(
            'ALTER TABLE transfers ADD COLUMN remote_ephemeral BLOB',
          );
          await database.execute(
            'ALTER TABLE transfers ADD COLUMN offered_transports INTEGER',
          );
        }
      },
    );
  }

  Future<String> _resolveDatabasePath(DatabaseFactory factory) async =>
      databasePath ??
      path.join(await factory.getDatabasesPath(), 'hearth_bit_transfers.db');

  Future<List<TransferRecord>> load() async {
    final rows = await (await _db).query(
      'transfers',
      orderBy: 'updated_at DESC',
      limit: 200,
    );
    return rows.map(TransferRecord.fromDatabase).toList(growable: false);
  }

  Future<List<TransferRecord>> loadAllForRetention() async {
    final rows = await (await _db).query(
      'transfers',
      orderBy: 'updated_at DESC',
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

  Future<TransferResumeMaterial?> loadResumeMaterial(String id) async {
    final rows = await (await _db).query(
      'transfers',
      columns: [
        'session_private',
        'session_public',
        'remote_ephemeral',
        'offered_transports',
      ],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TransferResumeMaterial.tryParse(rows.first);
  }

  Future<void> save(
    TransferRecord record, {
    Uint8List? bitmap,
    TransferResumeMaterial? resumeMaterial,
    bool clearResumeMaterial = false,
    bool clearBitmap = false,
  }) async {
    record.updatedAt = DateTime.now();
    final values = record.toDatabase();
    if (bitmap != null) values['bitmap'] = bitmap;
    if (clearBitmap) values['bitmap'] = null;
    if (resumeMaterial != null) values.addAll(resumeMaterial.toDatabase());
    if (clearResumeMaterial) {
      values.addAll(const {
        'session_private': null,
        'session_public': null,
        'remote_ephemeral': null,
        'offered_transports': null,
      });
    }
    final database = await _db;
    await database.transaction((transaction) async {
      final updated = await transaction.update(
        'transfers',
        values,
        where: 'id = ?',
        whereArgs: [record.id],
      );
      if (updated == 0) {
        await transaction.insert('transfers', values);
      }
    });
  }

  Future<void> delete(String id) async {
    await (await _db).delete('transfers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMany(Iterable<String> ids) async {
    final values = ids.toList(growable: false);
    if (values.isEmpty) return;
    final database = await _db;
    await database.transaction((transaction) async {
      for (final id in values) {
        await transaction.delete('transfers', where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  Future<void> clear() async {
    await (await _db).delete('transfers');
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  Future<void> destroy() async {
    final factory = databaseFactory ?? _defaultDatabaseFactory();
    final resolvedPath = await _resolveDatabasePath(factory);
    await close();
    await SecureDatabase.destroy(
      databasePath: resolvedPath,
      testFactory: databaseFactory,
    );
  }
}

class TransferResumeMaterial {
  const TransferResumeMaterial({
    required this.localPrivateKey,
    required this.localPublicKey,
    required this.remotePublicKey,
    required this.offeredTransports,
  });

  final Uint8List localPrivateKey;
  final Uint8List localPublicKey;
  final Uint8List remotePublicKey;
  final int offeredTransports;

  static TransferResumeMaterial? tryParse(Map<String, Object?> row) {
    final privateKey = row['session_private'];
    final publicKey = row['session_public'];
    final remoteKey = row['remote_ephemeral'];
    final transports = row['offered_transports'];
    if (privateKey is! Uint8List ||
        privateKey.length != 32 ||
        publicKey is! Uint8List ||
        publicKey.length != 32 ||
        remoteKey is! Uint8List ||
        remoteKey.length != 32 ||
        transports is! int ||
        transports < 0) {
      return null;
    }
    return TransferResumeMaterial(
      localPrivateKey: Uint8List.fromList(privateKey),
      localPublicKey: Uint8List.fromList(publicKey),
      remotePublicKey: Uint8List.fromList(remoteKey),
      offeredTransports: transports,
    );
  }

  Map<String, Object?> toDatabase() => {
    'session_private': localPrivateKey,
    'session_public': localPublicKey,
    'remote_ephemeral': remotePublicKey,
    'offered_transports': offeredTransports,
  };
}
