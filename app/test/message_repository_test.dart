import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
}
