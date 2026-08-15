import 'package:path/path.dart' as path;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/mesh_models.dart';
import 'secure_database.dart';

DatabaseFactory _defaultDatabaseFactory() => databaseFactory;

enum PrivateMessageOutboxStatus {
  pending('pending'),
  retrying('retrying'),
  expired('expired');

  const PrivateMessageOutboxStatus(this.wireName);

  final String wireName;

  static PrivateMessageOutboxStatus fromWire(Object? value) {
    return switch (value) {
      'retrying' => PrivateMessageOutboxStatus.retrying,
      'expired' => PrivateMessageOutboxStatus.expired,
      _ => PrivateMessageOutboxStatus.pending,
    };
  }
}

class PendingPrivateMessage {
  const PendingPrivateMessage({
    required this.localId,
    required this.recipientPeerId,
    required this.content,
    required this.createdAt,
    this.attempts = 0,
    this.status = PrivateMessageOutboxStatus.pending,
    this.lastError,
  });

  factory PendingPrivateMessage.fromDatabase(Map<String, Object?> map) {
    return PendingPrivateMessage(
      localId: map['local_id']! as String,
      recipientPeerId: map['recipient_peer_id']! as String,
      content: map['content']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      attempts: map['attempts']! as int,
      status: PrivateMessageOutboxStatus.fromWire(map['status']),
      lastError: map['last_error'] as String?,
    );
  }

  final String localId;
  final String recipientPeerId;
  final String content;
  final DateTime createdAt;
  final int attempts;
  final PrivateMessageOutboxStatus status;
  final String? lastError;

  Map<String, Object?> toDatabase() => {
    'local_id': localId,
    'recipient_peer_id': recipientPeerId,
    'content': content,
    'created_at': createdAt.millisecondsSinceEpoch,
    'attempts': attempts,
    'status': status.wireName,
    'last_error': lastError,
  };

  PendingPrivateMessage copyWith({
    int? attempts,
    PrivateMessageOutboxStatus? status,
    String? lastError,
  }) {
    return PendingPrivateMessage(
      localId: localId,
      recipientPeerId: recipientPeerId,
      content: content,
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
      status: status ?? this.status,
      lastError: lastError,
    );
  }
}

class MessageRepository {
  static const int maximumLoadedMessages = 500;
  static const int maximumStoredMessages = 1000;

  MessageRepository({this.databaseFactory, this.databasePath})
    : assert(databasePath == null || databasePath.isNotEmpty);

  final DatabaseFactory? databaseFactory;
  final String? databasePath;
  Database? _database;

  Future<Database> get _db async {
    final resolvedDatabaseFactory =
        databaseFactory ?? _defaultDatabaseFactory();
    final resolvedDatabasePath = await _resolveDatabasePath(
      resolvedDatabaseFactory,
    );
    return _database ??= await SecureDatabase.open(
      databasePath: resolvedDatabasePath,
      version: 6,
      testFactory: databaseFactory,
      onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
      onCreate: (database, version) async {
        await _createMessagesTable(database);
        await _createKnownPeersTable(database);
        await _createPrivateMessageOutboxTable(database);
        await _createEmergencyDeliveryTables(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createKnownPeersTable(database);
        }
        if (oldVersion < 3) {
          await _createPrivateMessageOutboxTable(database);
        }
        if (oldVersion < 4) {
          await _createEmergencyDeliveryTables(database);
        }
        if (oldVersion < 5) {
          await _addColumnIfMissing(
            database,
            table: 'messages',
            column: 'external',
            definition: 'INTEGER NOT NULL DEFAULT 0',
          );
          await _addColumnIfMissing(
            database,
            table: 'known_peers',
            column: 'hearthbit_verified',
            definition: 'INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 6) {
          await _createEmergencyAttemptHashTable(database);
          await database.rawInsert('''
            INSERT OR IGNORE INTO emergency_attempt_hash
              (local_id, canonical_hash, created_at)
            SELECT local_id, lower(canonical_hash),
              COALESCE(last_attempt_at, created_at)
            FROM emergency_outbox
            WHERE canonical_hash IS NOT NULL
          ''');
        }
      },
    );
  }

  Future<String> _resolveDatabasePath(DatabaseFactory factory) async =>
      databasePath ??
      path.join(await factory.getDatabasesPath(), 'hearth_bit.db');

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
            channel TEXT,
            external INTEGER NOT NULL DEFAULT 0
          )
        ''');
    await database.execute(
      'CREATE INDEX messages_timestamp_idx ON messages(timestamp)',
    );
  }

  static Future<void> _addColumnIfMissing(
    Database database, {
    required String table,
    required String column,
    required String definition,
  }) async {
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    if (columns.any((entry) => entry['name'] == column)) return;
    await database.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  static Future<void> _createKnownPeersTable(Database database) async {
    await database.execute('''
      CREATE TABLE known_peers (
        id TEXT PRIMARY KEY,
        nickname TEXT NOT NULL,
        last_seen INTEGER NOT NULL,
        hearthbit_verified INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await database.execute(
      'CREATE INDEX known_peers_last_seen_idx ON known_peers(last_seen)',
    );
  }

  static Future<void> _createPrivateMessageOutboxTable(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS private_message_outbox (
        local_id TEXT PRIMARY KEY,
        recipient_peer_id TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        last_error TEXT
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS private_message_outbox_recipient_idx '
      'ON private_message_outbox(recipient_peer_id, status, created_at)',
    );
  }

  static Future<void> _createEmergencyDeliveryTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS emergency_outbox (
        local_id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        next_attempt_at INTEGER NOT NULL,
        state TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_attempt_at INTEGER,
        canonical_hash TEXT UNIQUE,
        last_error TEXT
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS emergency_outbox_due_idx '
      'ON emergency_outbox(state, next_attempt_at, expires_at)',
    );
    await _createEmergencyAttemptHashTable(database);
    await database.execute('''
      CREATE TABLE IF NOT EXISTS emergency_ack (
        local_id TEXT NOT NULL,
        peer_id TEXT NOT NULL,
        acknowledged_at INTEGER NOT NULL,
        PRIMARY KEY(local_id, peer_id),
        FOREIGN KEY(local_id) REFERENCES emergency_outbox(local_id)
          ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _createEmergencyAttemptHashTable(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS emergency_attempt_hash (
        local_id TEXT NOT NULL,
        canonical_hash TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(local_id) REFERENCES emergency_outbox(local_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS emergency_attempt_hash_local_idx '
      'ON emergency_attempt_hash(local_id, created_at DESC)',
    );
  }

  static Future<void> _storeEmergencyAttemptHash(
    DatabaseExecutor transaction,
    EmergencyDelivery delivery,
  ) async {
    final canonicalHash = delivery.canonicalHash?.toLowerCase();
    if (canonicalHash == null || canonicalHash.isEmpty) return;
    await transaction.insert('emergency_attempt_hash', {
      'local_id': delivery.localId,
      'canonical_hash': canonicalHash,
      'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await transaction.rawDelete(
      'DELETE FROM emergency_attempt_hash '
      'WHERE local_id = ? AND canonical_hash NOT IN ('
      'SELECT canonical_hash FROM emergency_attempt_hash '
      'WHERE local_id = ? ORDER BY created_at DESC, rowid DESC LIMIT 64'
      ')',
      [delivery.localId, delivery.localId],
    );
  }

  Future<List<MeshMessage>> load() async {
    final rows = await (await _db).query(
      'messages',
      orderBy: 'timestamp DESC, id DESC',
      limit: maximumLoadedMessages,
    );
    return rows
        .map(MeshMessage.fromDatabase)
        .toList(growable: false)
        .reversed
        .toList(growable: false);
  }

  Future<void> save(MeshMessage message) async {
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.insert(
        'messages',
        message.toDatabase(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await transaction.rawDelete(
        'DELETE FROM messages WHERE id NOT IN ('
        'SELECT id FROM messages '
        'ORDER BY timestamp DESC, id DESC LIMIT ?'
        ')',
        [maximumStoredMessages],
      );
    });
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
    await database.transaction((transaction) async {
      final batch = transaction.batch();
      for (final peer in peers) {
        batch.insert(
          'known_peers',
          peer.toDatabase(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      await transaction.rawDelete(
        'DELETE FROM known_peers WHERE last_seen < ? OR id NOT IN ('
        'SELECT id FROM known_peers ORDER BY last_seen DESC LIMIT 1000'
        ')',
        [
          DateTime.now()
              .subtract(const Duration(days: 30))
              .millisecondsSinceEpoch,
        ],
      );
    });
  }

  Future<void> insertPendingPrivateMessage(
    PendingPrivateMessage message,
  ) async {
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.insert(
        'private_message_outbox',
        message.toDatabase(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await transaction.rawDelete(
        'DELETE FROM private_message_outbox WHERE local_id NOT IN ('
        'SELECT local_id FROM private_message_outbox '
        'ORDER BY created_at DESC, local_id DESC LIMIT 200'
        ')',
      );
    });
  }

  Future<void> expirePrivateMessageOutbox(DateTime now) async {
    await (await _db).update(
      'private_message_outbox',
      {'status': PrivateMessageOutboxStatus.expired.wireName},
      where: 'status != ? AND (created_at <= ? OR attempts >= 20)',
      whereArgs: [
        PrivateMessageOutboxStatus.expired.wireName,
        now.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
      ],
    );
  }

  Future<List<PendingPrivateMessage>> listPendingPrivateMessages() async {
    final rows = await (await _db).query(
      'private_message_outbox',
      orderBy: 'created_at ASC, local_id ASC',
    );
    return rows.map(PendingPrivateMessage.fromDatabase).toList(growable: false);
  }

  Future<void> updatePendingPrivateMessage(
    PendingPrivateMessage message,
  ) async {
    await (await _db).update(
      'private_message_outbox',
      message.toDatabase(),
      where: 'local_id = ?',
      whereArgs: [message.localId],
    );
  }

  Future<void> deletePendingPrivateMessage(String localId) async {
    await (await _db).delete(
      'private_message_outbox',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> insertEmergencyDelivery(EmergencyDelivery delivery) async {
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.insert(
        'emergency_outbox',
        delivery.toDatabase(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await _storeEmergencyAttemptHash(transaction, delivery);
      await transaction.rawDelete(
        'DELETE FROM emergency_outbox WHERE local_id NOT IN ('
        'SELECT local_id FROM emergency_outbox '
        'ORDER BY created_at DESC LIMIT 200'
        ')',
      );
    });
  }

  Future<void> updateEmergencyDelivery(EmergencyDelivery delivery) async {
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.update(
        'emergency_outbox',
        delivery.toDatabase(),
        where: 'local_id = ?',
        whereArgs: [delivery.localId],
      );
      await _storeEmergencyAttemptHash(transaction, delivery);
    });
  }

  Future<List<EmergencyDelivery>> loadEmergencyDeliveries() async {
    final database = await _db;
    final rows = await database.query(
      'emergency_outbox',
      orderBy: 'created_at DESC',
      limit: 200,
    );
    if (rows.isEmpty) return const [];
    final acknowledgements = await database.query('emergency_ack');
    final peersByDelivery = <String, Set<String>>{};
    for (final acknowledgement in acknowledgements) {
      final localId = acknowledgement['local_id']! as String;
      peersByDelivery
          .putIfAbsent(localId, () => <String>{})
          .add(acknowledgement['peer_id']! as String);
    }
    return rows
        .map(
          (row) => EmergencyDelivery.fromDatabase(
            row,
            acknowledgedBy: peersByDelivery[row['local_id']] ?? const {},
          ),
        )
        .toList(growable: false);
  }

  Future<String?> recordEmergencyAcknowledgement({
    required String canonicalHash,
    required String peerId,
    required DateTime acknowledgedAt,
  }) async {
    final database = await _db;
    return database.transaction((transaction) async {
      final rows = await transaction.query(
        'emergency_attempt_hash',
        columns: ['local_id'],
        where: 'canonical_hash = ?',
        whereArgs: [canonicalHash.toLowerCase()],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final localId = rows.single['local_id']! as String;
      await transaction.insert('emergency_ack', {
        'local_id': localId,
        'peer_id': peerId.toLowerCase(),
        'acknowledged_at': acknowledgedAt.toUtc().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await transaction.update(
        'emergency_outbox',
        {'state': EmergencyDeliveryState.acknowledged.wireName},
        where: 'local_id = ?',
        whereArgs: [localId],
      );
      return localId;
    });
  }

  Future<void> expireEmergencyDeliveries(DateTime now) async {
    await (await _db).update(
      'emergency_outbox',
      {'state': EmergencyDeliveryState.expired.wireName},
      where: 'expires_at <= ? AND state IN (?, ?)',
      whereArgs: [
        now.toUtc().millisecondsSinceEpoch,
        EmergencyDeliveryState.pending.wireName,
        EmergencyDeliveryState.relayed.wireName,
      ],
    );
  }

  Future<void> clear() async {
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete('messages');
      await transaction.delete('known_peers');
      await transaction.delete('private_message_outbox');
      await transaction.delete('emergency_outbox');
    });
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
