import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/secure_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

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

  // Spec Hueco 7: SecureDatabase.destroy debe ser idempotente. Tres sub-cases:
  // (a) dos veces seguidas sobre el mismo path, (b) sobre un path que no
  // existe, (c) sobre un directorio que solo tiene sidecars residuales. Ver
  // docs/superpowers/specs/2026-08-24-panic-wipe-sqlite-cipher-design.md.
  group('destroy is idempotent', () {
    test('dos llamadas seguidas dejan el path y los sidecars limpios',
        () async {
      final idemPath = p.join(directory.path, 'idem.db');
      await File(idemPath).writeAsString('payload');
      await File('$idemPath-wal').writeAsString('wal-payload');
      await File('$idemPath-shm').writeAsString('shm-payload');

      await SecureDatabase.destroy(
        databasePath: idemPath,
        testFactory: databaseFactoryFfi,
      );
      // Segunda llamada: no debe lanzar y debe dejar el path igual de limpio.
      await SecureDatabase.destroy(
        databasePath: idemPath,
        testFactory: databaseFactoryFfi,
      );

      expect(await File(idemPath).exists(), isFalse);
      expect(await File('$idemPath-wal').exists(), isFalse);
      expect(await File('$idemPath-shm').exists(), isFalse);
    });

    test('sobre archivo inexistente no lanza', () async {
      final missingPath = p.join(directory.path, 'nunca-existente.db');

      await SecureDatabase.destroy(
        databasePath: missingPath,
        testFactory: databaseFactoryFfi,
      );
      // Repetir tampoco debe lanzar.
      await SecureDatabase.destroy(
        databasePath: missingPath,
        testFactory: databaseFactoryFfi,
      );

      expect(await File(missingPath).exists(), isFalse);
    });

    test('sobre dir con sidecars limpia cada archivo residual', () async {
      final sidecarPath = p.join(directory.path, 'solo-sidecars.db');
      // No creamos el archivo principal; sólo los sidecars. Reproduce el
      // escenario de un crash previo al cierre que dejó WAL/SHM/journal sueltos.
      await File('$sidecarPath-wal').writeAsString('wal');
      await File('$sidecarPath-shm').writeAsString('shm');
      await File('$sidecarPath-journal').writeAsString('journal');

      await SecureDatabase.destroy(
        databasePath: sidecarPath,
        testFactory: databaseFactoryFfi,
      );
      await SecureDatabase.destroy(
        databasePath: sidecarPath,
        testFactory: databaseFactoryFfi,
      );

      expect(await File('$sidecarPath-wal').exists(), isFalse);
      expect(await File('$sidecarPath-shm').exists(), isFalse);
      expect(await File('$sidecarPath-journal').exists(), isFalse);
    });
  });
}
