import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/secure_database.dart';

void main() {
  late Directory directory;
  late String databasePath;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hearthbit-db-test-');
    databasePath = '${directory.path}${Platform.pathSeparator}messages.db';
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('limpia respaldos en claro y sidecars de forma idempotente', () async {
    for (final suffix in [
      '.plaintext.backup',
      '.plaintext.backup-wal',
      '.plaintext.backup-shm',
      '-wal',
      '-shm',
      '-journal',
      '.encrypted.tmp',
      '.encrypted.tmp-wal',
    ]) {
      await File('$databasePath$suffix').writeAsString('residuo');
    }

    await SecureDatabase.cleanupConfirmedEncryptedForTest(databasePath);
    await SecureDatabase.cleanupConfirmedEncryptedForTest(databasePath);

    expect(
      directory.listSync().whereType<File>(),
      isEmpty,
      reason: 'ninguna página o copia en claro debe permanecer',
    );
  });

  test(
    'reanuda el cambio atómico promoviendo el temporal verificado',
    () async {
      final backup = File('$databasePath.plaintext.backup');
      final temporary = File('$databasePath.encrypted.tmp');
      await backup.writeAsString('sqlite-en-claro');
      await temporary.writeAsString('sqlcipher-valido');
      await File('$databasePath-wal').writeAsString('wal-en-claro');

      final recovered = await SecureDatabase.recoverInterruptedMigrationForTest(
        databasePath: databasePath,
        verify: (path) async {
          expect(await File(path).readAsString(), 'sqlcipher-valido');
        },
      );

      expect(recovered, isTrue);
      expect(await File(databasePath).readAsString(), 'sqlcipher-valido');
      expect(await backup.exists(), isFalse);
      expect(await temporary.exists(), isFalse);
      expect(await File('$databasePath-wal').exists(), isFalse);
    },
  );

  test(
    'restaura el respaldo si el temporal interrumpido no verifica',
    () async {
      final backup = File('$databasePath.plaintext.backup');
      final temporary = File('$databasePath.encrypted.tmp');
      await backup.writeAsString('sqlite-recuperable');
      await temporary.writeAsString('cifrado-truncado');

      final recovered = await SecureDatabase.recoverInterruptedMigrationForTest(
        databasePath: databasePath,
        verify: (_) async => throw const FormatException('truncado'),
      );

      expect(recovered, isFalse);
      expect(await File(databasePath).readAsString(), 'sqlite-recuperable');
      expect(await backup.exists(), isFalse);
      expect(await temporary.exists(), isFalse);
    },
  );
}
