import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/services/message_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late String databasePath;
  late MessageRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'hearth_bit_outbox_test_',
    );
    databasePath = path.join(temporaryDirectory.path, 'messages.db');
    repository = MessageRepository(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
    );
  });

  tearDown(() async {
    await repository.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
    await temporaryDirectory.delete(recursive: true);
  });

  test('inserta, lista, actualiza y elimina mensajes pendientes', () async {
    final pending = PendingPrivateMessage(
      localId: 'local-1',
      recipientPeerId: 'peer-1',
      content: 'Necesito ayuda',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1234),
    );

    await repository.insertPendingPrivateMessage(pending);
    var stored = (await repository.listPendingPrivateMessages()).single;

    expect(stored.localId, 'local-1');
    expect(stored.recipientPeerId, 'peer-1');
    expect(stored.content, 'Necesito ayuda');
    expect(stored.attempts, 0);
    expect(stored.status, PrivateMessageOutboxStatus.pending);

    stored = stored.copyWith(
      attempts: 1,
      status: PrivateMessageOutboxStatus.retrying,
      lastError: 'sin sesión',
    );
    await repository.updatePendingPrivateMessage(stored);
    final updated = (await repository.listPendingPrivateMessages()).single;

    expect(updated.attempts, 1);
    expect(updated.status, PrivateMessageOutboxStatus.retrying);
    expect(updated.lastError, 'sin sesión');

    await repository.deletePendingPrivateMessage(updated.localId);
    expect(await repository.listPendingPrivateMessages(), isEmpty);
  });

  test('persiste el origen externo y la verificación HearthBit', () async {
    await repository.save(
      MeshMessage(
        id: 'external-sos',
        sender: 'BitChat',
        content: 'SOS|Ayuda||',
        senderPeerId: 'external-peer',
        isPrivate: false,
        isMine: false,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1234),
        channel: 'sos',
        external: true,
        canonicalHash:
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      ),
    );
    await repository.saveKnownPeers([
      MeshPeer(
        id: 'hearthbit-peer',
        nickname: 'HearthBit',
        lastSeen: DateTime.now(),
        secure: true,
        hearthbitVerified: true,
      ),
    ]);

    final restoredMessage = (await repository.load()).single;
    expect(restoredMessage.external, isTrue);
    expect(
      restoredMessage.canonicalHash,
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    );
    expect(
      (await repository.loadKnownPeers()).single.hearthbitVerified,
      isTrue,
    );
  });

  test('vence privados tras 20 intentos o 7 días y limita el outbox', () async {
    final now = DateTime.utc(2026, 8, 14);
    await repository.insertPendingPrivateMessage(
      PendingPrivateMessage(
        localId: 'too-many-attempts',
        recipientPeerId: 'peer-a',
        content: 'A',
        createdAt: now,
        attempts: 20,
      ),
    );
    await repository.insertPendingPrivateMessage(
      PendingPrivateMessage(
        localId: 'too-old',
        recipientPeerId: 'peer-b',
        content: 'B',
        createdAt: now.subtract(const Duration(days: 8)),
      ),
    );
    await repository.expirePrivateMessageOutbox(now);

    final expired = await repository.listPendingPrivateMessages();
    expect(
      expired.map((message) => message.status),
      everyElement(PrivateMessageOutboxStatus.expired),
    );

    for (var index = 0; index < 205; index++) {
      await repository.insertPendingPrivateMessage(
        PendingPrivateMessage(
          localId: 'bounded-$index',
          recipientPeerId: 'peer',
          content: '$index',
          createdAt: now.add(Duration(milliseconds: index)),
        ),
      );
    }
    expect(await repository.listPendingPrivateMessages(), hasLength(200));
  });

  test('migra una base v2 sin perder mensajes existentes', () async {
    await repository.close();
    final oldDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 2,
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
          await database.execute('''
            CREATE TABLE known_peers (
              id TEXT PRIMARY KEY,
              nickname TEXT NOT NULL,
              last_seen INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    await oldDatabase.insert('messages', {
      'id': 'existing',
      'sender': 'Ana',
      'content': 'Antes de migrar',
      'sender_peer_id': 'peer-old',
      'is_private': 1,
      'is_mine': 0,
      'timestamp': 1000,
      'channel': null,
    });
    await oldDatabase.close();

    repository = MessageRepository(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    await repository.insertPendingPrivateMessage(
      PendingPrivateMessage(
        localId: 'after-migration',
        recipientPeerId: 'peer-new',
        content: 'Después',
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
      ),
    );

    expect((await repository.load()).single.content, 'Antes de migrar');
    expect(
      (await repository.listPendingPrivateMessages()).single.content,
      'Después',
    );
  });

  test('persiste estados, ACK únicos y expiración de emergencias', () async {
    final createdAt = DateTime.utc(2026, 8, 14, 1);
    var delivery = EmergencyDelivery(
      localId: 'emergency-1',
      kind: EmergencyDeliveryKind.sos,
      content: 'SOS|Ayuda||',
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(hours: 24)),
      nextAttemptAt: createdAt,
      state: EmergencyDeliveryState.pending,
    );
    await repository.insertEmergencyDelivery(delivery);
    delivery = delivery.copyWith(
      state: EmergencyDeliveryState.relayed,
      attempts: 1,
      lastAttemptAt: createdAt,
      nextAttemptAt: createdAt.add(const Duration(seconds: 15)),
      canonicalHash: 'a' * 64,
    );
    await repository.updateEmergencyDelivery(delivery);
    delivery = delivery.copyWith(
      attempts: 2,
      canonicalHash: 'b' * 64,
      nextAttemptAt: createdAt.add(const Duration(seconds: 45)),
    );
    await repository.updateEmergencyDelivery(delivery);

    await repository.recordEmergencyAcknowledgement(
      canonicalHash: 'a' * 64,
      peerId: 'peer-a',
      acknowledgedAt: createdAt.add(const Duration(seconds: 2)),
    );
    await repository.recordEmergencyAcknowledgement(
      canonicalHash: 'b' * 64,
      peerId: 'peer-b',
      acknowledgedAt: createdAt.add(const Duration(seconds: 4)),
    );

    final acknowledged = (await repository.loadEmergencyDeliveries()).single;
    expect(acknowledged.state, EmergencyDeliveryState.acknowledged);
    expect(acknowledged.confirmationCount, 2);

    await repository.insertEmergencyDelivery(
      EmergencyDelivery(
        localId: 'emergency-expired',
        kind: EmergencyDeliveryKind.checkIn,
        content: 'Estoy bien\n[HB-CHECKIN|OK|1|||1]',
        createdAt: createdAt,
        expiresAt: createdAt.add(const Duration(minutes: 1)),
        nextAttemptAt: createdAt,
        state: EmergencyDeliveryState.pending,
      ),
    );
    await repository.expireEmergencyDeliveries(
      createdAt.add(const Duration(minutes: 2)),
    );
    final expired = (await repository.loadEmergencyDeliveries()).firstWhere(
      (item) => item.localId == 'emergency-expired',
    );
    expect(expired.state, EmergencyDeliveryState.expired);
  });

  test('carga los 500 más recientes y conserva 1000 en disco', () async {
    await repository.load();
    final database = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final batch = database.batch();
    for (var index = 0; index < 1005; index++) {
      batch.insert(
        'messages',
        MeshMessage(
          id: 'message-$index',
          sender: 'Peer',
          content: 'Mensaje $index',
          senderPeerId: 'peer',
          isPrivate: false,
          isMine: false,
          timestamp: DateTime.fromMillisecondsSinceEpoch(index),
        ).toDatabase(),
      );
    }
    await batch.commit(noResult: true);
    await database.close();

    final loaded = await repository.load();
    expect(loaded, hasLength(MessageRepository.maximumLoadedMessages));
    expect(loaded.first.id, 'message-505');
    expect(loaded.last.id, 'message-1004');
    expect(
      loaded.map((message) => message.timestamp.millisecondsSinceEpoch),
      orderedEquals(
        loaded
            .map((message) => message.timestamp.millisecondsSinceEpoch)
            .toList()
          ..sort(),
      ),
    );

    await repository.save(
      MeshMessage(
        id: 'message-1005',
        sender: 'Peer',
        content: 'Mensaje 1005',
        senderPeerId: 'peer',
        isPrivate: false,
        isMine: false,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1005),
      ),
    );
    final prunedDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final countRows = await prunedDatabase.rawQuery(
      'SELECT COUNT(*) AS total FROM messages',
    );
    final count = (countRows.single['total'] as num).toInt();
    await prunedDatabase.close();

    expect(count, MessageRepository.maximumStoredMessages);
    final afterPrune = await repository.load();
    expect(afterPrune.first.id, 'message-506');
    expect(afterPrune.last.id, 'message-1005');
  });
}
