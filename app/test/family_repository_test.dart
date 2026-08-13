import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hearth_bit/services/family_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late String databasePath;
  late FamilyRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'hearth_bit_family_test_',
    );
    databasePath = path.join(temporaryDirectory.path, 'family.db');
    repository = FamilyRepository(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
    );
  });

  tearDown(() async {
    await repository.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
    await temporaryDirectory.delete(recursive: true);
  });

  test('crea, renombra y elimina grupos y miembros verificados', () async {
    final group = await repository.createGroup('Familia');
    await repository.renameGroup(group.id, 'Casa');
    final member = await repository.addMember(
      groupId: group.id,
      peerId: '0011223344556677',
      nickname: 'Ana',
      signingPublicKey: Uint8List.fromList(List.generate(32, (index) => index)),
      fingerprint: '00:11:22:33:44:55',
    );

    expect((await repository.listGroups()).single.name, 'Casa');
    expect((await repository.listMembers()).single.nickname, 'Ana');

    await repository.deleteMember(member.id);
    expect(await repository.listMembers(), isEmpty);
    await repository.deleteGroup(group.id);
    expect(await repository.listGroups(), isEmpty);
  });

  test('mantiene unicidad de clave y peer dentro del grupo', () async {
    final group = await repository.createGroup('Familia');
    final key = Uint8List(32);
    await repository.addMember(
      groupId: group.id,
      peerId: '0011223344556677',
      nickname: 'Ana',
      signingPublicKey: key,
      fingerprint: '00:00:00:00:00:00',
    );

    expect(
      () => repository.addMember(
        groupId: group.id,
        peerId: '0011223344556677',
        nickname: 'Otra',
        signingPublicKey: Uint8List.fromList(List.filled(32, 1)),
        fingerprint: '11:11:11:11:11:11',
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('migra v1 sin borrar grupos ni miembros', () async {
    await repository.close();
    final oldDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
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
        },
      ),
    );
    final groupId = await oldDatabase.insert('family_groups', {
      'name': 'Existente',
      'created_at': 1000,
      'updated_at': 1000,
    });
    await oldDatabase.insert('family_members', {
      'group_id': groupId,
      'peer_id': '0011223344556677',
      'nickname': 'Ana',
      'signing_public_key': Uint8List(32),
      'fingerprint': '00:00:00:00:00:00',
      'verified_at': 1000,
    });
    await oldDatabase.close();

    repository = FamilyRepository(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    await repository.bindOwnerSigningKey(Uint8List(32));

    expect((await repository.listGroups()).single.name, 'Existente');
    expect((await repository.listMembers()).single.nickname, 'Ana');
    expect(await repository.readOwnerSigningKey(), Uint8List(32));
  });
}
