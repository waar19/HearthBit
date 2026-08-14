import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/mesh_models.dart';

DatabaseFactory _defaultDatabaseFactory() => databaseFactory;

enum PrivateMessageOutboxStatus {
  pending('pending'),
  retrying('retrying');

  const PrivateMessageOutboxStatus(this.wireName);

  final String wireName;

  static PrivateMessageOutboxStatus fromWire(Object? value) {
    return switch (value) {
      'retrying' => PrivateMessageOutboxStatus.retrying,
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
    final resolvedDatabasePath =
        databasePath ??
        path.join(
          await resolvedDatabaseFactory.getDatabasesPath(),
          'hearth_bit.db',
        );
    return _database ??= await resolvedDatabaseFactory.openDatabase(
      resolvedDatabasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (database, version) async {
          await _createMessagesTable(database);
          await _createKnownPeersTable(database);
          await _createPrivateMessageOutboxTable(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createKnownPeersTable(database);
          }
          if (oldVersion < 3) {
            await _createPrivateMessageOutboxTable(database);
          }
        },
      ),
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

  Future<void> insertPendingPrivateMessage(
    PendingPrivateMessage message,
  ) async {
    await (await _db).insert(
      'private_message_outbox',
      message.toDatabase(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
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

  Future<void> clear() async {
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete('messages');
      await transaction.delete('known_peers');
      await transaction.delete('private_message_outbox');
    });
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }
}
