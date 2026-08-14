import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import 'secure_storage_config.dart';

typedef DatabaseConfigure = Future<void> Function(sqlcipher.Database database);
typedef DatabaseCreate =
    Future<void> Function(sqlcipher.Database database, int version);
typedef DatabaseUpgrade =
    Future<void> Function(
      sqlcipher.Database database,
      int oldVersion,
      int newVersion,
    );

/// Clave maestra local para las bases sensibles.
///
/// La clave no se sincroniza entre dispositivos. Borrarla después de destruir
/// las bases vuelve irrecuperables las páginas SQLite antiguas que pudieran
/// permanecer en almacenamiento flash.
class SecureDatabaseKeyStore {
  SecureDatabaseKeyStore._();

  static const keyName = 'hearthbit.database.master.v1';
  static const _storage = hearthBitSecureStorage;

  static Future<String>? _cachedKey;

  static Future<String> readOrCreate() {
    return _cachedKey ??= _readOrCreate();
  }

  static Future<String> _readOrCreate() async {
    final existing = await _storage.read(key: keyName);
    if (existing != null && existing.length >= 43) return existing;
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final generated = base64UrlEncode(bytes).replaceAll('=', '');
    await _storage.write(key: keyName, value: generated);
    return generated;
  }

  static Future<void> destroy() async {
    // Esperar una creación en curso evita que una escritura tardía restaure la
    // clave inmediatamente después del panic wipe.
    await _cachedKey;
    _cachedKey = null;
    await _storage.delete(key: keyName);
  }
}

/// Abre bases SQLCipher y migra de forma atómica las bases SQLite legadas.
class SecureDatabase {
  SecureDatabase._();

  static Future<sqlcipher.Database> open({
    required String databasePath,
    required int version,
    required DatabaseCreate onCreate,
    DatabaseConfigure? onConfigure,
    DatabaseUpgrade? onUpgrade,
    sqlcipher.DatabaseFactory? testFactory,
  }) async {
    if (testFactory != null) {
      return testFactory.openDatabase(
        databasePath,
        options: sqlcipher.OpenDatabaseOptions(
          version: version,
          onConfigure: onConfigure,
          onCreate: onCreate,
          onUpgrade: onUpgrade,
        ),
      );
    }

    final password = await SecureDatabaseKeyStore.readOrCreate();
    await _migratePlaintextIfNeeded(databasePath, password);
    return sqlcipher.openDatabase(
      databasePath,
      password: password,
      version: version,
      onConfigure: onConfigure,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    );
  }

  static Future<void> destroy({
    required String databasePath,
    sqlcipher.DatabaseFactory? testFactory,
  }) async {
    if (testFactory != null) {
      await testFactory.deleteDatabase(databasePath);
      return;
    }
    await sqlcipher.deleteDatabase(databasePath);
    await _deleteIfPresent(File('$databasePath-wal'));
    await _deleteIfPresent(File('$databasePath-shm'));
    await _deleteIfPresent(File('$databasePath-journal'));
  }

  static Future<void> _migratePlaintextIfNeeded(
    String databasePath,
    String password,
  ) async {
    final source = File(databasePath);
    final recoveredEncrypted = await _recoverInterruptedMigration(
      databasePath,
      (path) => _verify(path, password),
    );
    if (recoveredEncrypted) return;
    if (!await source.exists()) return;

    Object? encryptedOpenError;
    try {
      final encrypted = await sqlcipher.openDatabase(
        databasePath,
        password: password,
        readOnly: true,
        singleInstance: false,
      );
      try {
        await encrypted.rawQuery('SELECT count(*) FROM sqlite_master');
      } finally {
        await encrypted.close();
      }
      await _cleanupConfirmedEncrypted(databasePath);
      return;
    } catch (error) {
      encryptedOpenError = error;
    }

    final header = await source
        .openRead(0, 16)
        .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    if (ascii.decode(header, allowInvalid: true) != 'SQLite format 3\u0000') {
      throw StateError(
        'Encrypted database could not be opened; original file was preserved: '
        '$encryptedOpenError',
      );
    }

    final temporaryPath = '$databasePath.encrypted.tmp';
    final backupPath = '$databasePath.plaintext.backup';
    await _deleteIfPresent(File(temporaryPath));
    await _deleteSidecars(temporaryPath);

    sqlcipher.Database? plaintext;
    try {
      plaintext = await sqlcipher.openDatabase(
        databasePath,
        singleInstance: false,
      );
      await plaintext.rawQuery('PRAGMA wal_checkpoint(FULL)');
      final userVersionRows = await plaintext.rawQuery('PRAGMA user_version');
      final userVersion =
          (userVersionRows.firstOrNull?['user_version'] as int?) ?? 0;
      await plaintext.execute('ATTACH DATABASE ? AS encrypted KEY ?', [
        temporaryPath,
        password,
      ]);
      try {
        await plaintext.rawQuery("SELECT sqlcipher_export('encrypted')");
        await plaintext.execute('PRAGMA encrypted.user_version = $userVersion');
      } finally {
        await plaintext.execute('DETACH DATABASE encrypted');
      }
      await plaintext.close();
      plaintext = null;

      // El checkpoint ya incorporó el WAL a la base. Estos archivos conservan
      // páginas en claro y no deben sobrevivir al cambio de nombre.
      await _deleteSidecars(databasePath);
      await _deleteIfPresent(File(backupPath));
      await _deleteSidecars(backupPath);
      await source.rename(backupPath);
      await File(temporaryPath).rename(databasePath);
      try {
        await _verify(databasePath, password);
      } catch (_) {
        await _deleteIfPresent(File(databasePath));
        await _deleteSidecars(databasePath);
        await File(backupPath).rename(databasePath);
        rethrow;
      }
      await _cleanupConfirmedEncrypted(databasePath);
    } catch (_) {
      await plaintext?.close();
      await _deleteIfPresent(File(temporaryPath));
      await _deleteSidecars(temporaryPath);
      rethrow;
    }
  }

  /// Recupera el punto atómico `backup -> temporal -> base` tras un cierre.
  ///
  /// Devuelve true si dejó una base cifrada verificada en [databasePath].
  static Future<bool> _recoverInterruptedMigration(
    String databasePath,
    Future<void> Function(String path) verify,
  ) async {
    final source = File(databasePath);
    final temporaryPath = '$databasePath.encrypted.tmp';
    final backupPath = '$databasePath.plaintext.backup';
    final temporary = File(temporaryPath);
    final backup = File(backupPath);
    if (await source.exists()) return false;

    if (await temporary.exists()) {
      try {
        await verify(temporaryPath);
        await temporary.rename(databasePath);
        await _cleanupConfirmedEncrypted(databasePath);
        return true;
      } catch (_) {
        await _deleteIfPresent(temporary);
        await _deleteSidecars(temporaryPath);
      }
    }

    if (await backup.exists()) {
      await backup.rename(databasePath);
      return false;
    }
    return false;
  }

  @visibleForTesting
  static Future<bool> recoverInterruptedMigrationForTest({
    required String databasePath,
    required Future<void> Function(String path) verify,
  }) => _recoverInterruptedMigration(databasePath, verify);

  @visibleForTesting
  static Future<void> cleanupConfirmedEncryptedForTest(String databasePath) =>
      _cleanupConfirmedEncrypted(databasePath);

  static Future<void> _cleanupConfirmedEncrypted(String databasePath) async {
    final backupPath = '$databasePath.plaintext.backup';
    final temporaryPath = '$databasePath.encrypted.tmp';
    await _deleteIfPresent(File(backupPath));
    await _deleteSidecars(backupPath);
    await _deleteIfPresent(File(temporaryPath));
    await _deleteSidecars(temporaryPath);
    await _deleteSidecars(databasePath);
  }

  static Future<void> _deleteSidecars(String path) async {
    await _deleteIfPresent(File('$path-wal'));
    await _deleteIfPresent(File('$path-shm'));
    await _deleteIfPresent(File('$path-journal'));
  }

  static Future<void> _verify(String databasePath, String password) async {
    final database = await sqlcipher.openDatabase(
      databasePath,
      password: password,
      readOnly: true,
      singleInstance: false,
    );
    try {
      final cipherRows = await database.rawQuery(
        'PRAGMA cipher_integrity_check',
      );
      final cipherResult = cipherRows
          .expand((row) => row.values)
          .map((value) => value.toString().toLowerCase())
          .toList(growable: false);
      if (cipherResult.isNotEmpty && !cipherResult.contains('ok')) {
        throw StateError('SQLCipher integrity verification failed');
      }
      final sqliteRows = await database.rawQuery('PRAGMA integrity_check');
      if (sqliteRows.isEmpty ||
          sqliteRows.first.values.first.toString().toLowerCase() != 'ok') {
        throw StateError('SQLite integrity verification failed');
      }
    } finally {
      await database.close();
    }
  }

  static Future<void> _deleteIfPresent(File file) async {
    if (await file.exists()) await file.delete();
  }
}
