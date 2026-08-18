import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hearth_bit/models/transfer_models.dart';
import 'package:hearth_bit/services/transfer_repository.dart';
import 'package:hearth_bit/services/transfer_retention.dart';

TransferRecord _record({
  required String id,
  required TransferState state,
  required String filePath,
  required DateTime updatedAt,
}) {
  return TransferRecord(
    id: id,
    peerId: 'peer',
    peerNickname: 'Peer',
    direction: TransferDirection.incoming,
    fileName: '$id.bin',
    mimeType: 'application/octet-stream',
    fileSize: 10,
    sha256Hex: '00' * 32,
    chunkSize: 10,
    state: state,
    filePath: filePath,
    createdAt: updatedAt,
    updatedAt: updatedAt,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('política conserva activos y limita el historial a 500', () {
    final now = DateTime.utc(2026, 8, 18);
    final records = [
      _record(
        id: 'active',
        state: TransferState.transferring,
        filePath: 'active',
        updatedAt: now.subtract(const Duration(days: 90)),
      ),
      for (var index = 0; index < 502; index++)
        _record(
          id: 'history-$index',
          state: TransferState.completed,
          filePath: 'history-$index',
          updatedAt: now.subtract(Duration(minutes: index)),
        ),
    ];

    final plan = planTransferRetention(
      records: records,
      files: const [],
      recordIdByManagedPath: const {},
      now: now,
    );

    expect(plan.recordIds, hasLength(2));
    expect(plan.recordIds, containsAll(['history-500', 'history-501']));
    expect(plan.recordIds, isNot(contains('active')));
  });

  test(
    'purga DB y archivos administrados sin borrar una ruta externa',
    () async {
      final temporary = await Directory.systemTemp.createTemp('hb-retention-');
      addTearDown(() => temporary.delete(recursive: true));
      final managed = Directory(p.join(temporary.path, 'hearthbit_transfers'));
      await managed.create();
      final managedFile = File(p.join(managed.path, 'old.bin'));
      final activeFile = File(p.join(managed.path, 'active.bin'));
      final externalFile = File(p.join(temporary.path, 'user-original.bin'));
      await managedFile.writeAsBytes(List.filled(10, 1));
      await activeFile.writeAsBytes(List.filled(10, 2));
      await externalFile.writeAsBytes(List.filled(10, 3));

      final databasePath = p.join(temporary.path, 'transfers.db');
      final repository = TransferRepository(
        databaseFactory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      addTearDown(repository.close);
      final now = DateTime.utc(2026, 8, 18);
      final old = now.subtract(const Duration(days: 31));
      for (final record in [
        _record(
          id: 'managed-old',
          state: TransferState.completed,
          filePath: managedFile.path,
          updatedAt: old,
        ),
        _record(
          id: 'external-old',
          state: TransferState.failed,
          filePath: externalFile.path,
          updatedAt: old,
        ),
        _record(
          id: 'active',
          state: TransferState.transferring,
          filePath: activeFile.path,
          updatedAt: old,
        ),
      ]) {
        await repository.save(record);
      }
      final database = await databaseFactoryFfi.openDatabase(databasePath);
      await database.update('transfers', {
        'updated_at': old.millisecondsSinceEpoch,
      });

      final service = TransferRetentionService(
        repository: repository,
        managedDirectories: () async => [managed],
        clock: () => now,
      );
      final plan = await service.purge();

      expect(plan.recordIds, containsAll(['managed-old', 'external-old']));
      expect(await managedFile.exists(), isFalse);
      expect(await externalFile.exists(), isTrue);
      expect(await activeFile.exists(), isTrue);
      expect(
        (await repository.loadAllForRetention()).map((record) => record.id),
        ['active'],
      );
    },
  );

  test('cuota elimina primero el archivo no activo más antiguo', () async {
    final temporary = await Directory.systemTemp.createTemp('hb-quota-');
    addTearDown(() => temporary.delete(recursive: true));
    final managed = Directory(p.join(temporary.path, 'cache'));
    await managed.create();
    final active = File(p.join(managed.path, 'active.bin'));
    final oldest = File(p.join(managed.path, 'oldest.bin'));
    final newest = File(p.join(managed.path, 'newest.bin'));
    await active.writeAsBytes(List.filled(10, 1));
    await oldest.writeAsBytes(List.filled(10, 2));
    await newest.writeAsBytes(List.filled(10, 3));
    final now = DateTime.utc(2026, 8, 18);
    await active.setLastModified(now.subtract(const Duration(days: 3)));
    await oldest.setLastModified(now.subtract(const Duration(days: 2)));
    await newest.setLastModified(now.subtract(const Duration(days: 1)));

    final repository = TransferRepository(
      databaseFactory: databaseFactoryFfi,
      databasePath: p.join(temporary.path, 'transfers.db'),
    );
    addTearDown(repository.close);
    await repository.save(
      _record(
        id: 'active',
        state: TransferState.transferring,
        filePath: active.path,
        updatedAt: now,
      ),
    );
    await repository.save(
      _record(
        id: 'oldest',
        state: TransferState.completed,
        filePath: oldest.path,
        updatedAt: now,
      ),
    );
    await repository.save(
      _record(
        id: 'newest',
        state: TransferState.completed,
        filePath: newest.path,
        updatedAt: now,
      ),
    );

    final service = TransferRetentionService(
      repository: repository,
      managedDirectories: () async => [managed],
      clock: () => now,
      maximumManagedBytes: 20,
    );
    await service.purge();

    expect(await active.exists(), isTrue);
    expect(await oldest.exists(), isFalse);
    expect(await newest.exists(), isTrue);
    expect(
      (await repository.loadAllForRetention()).map((record) => record.id),
      containsAll(['active', 'newest']),
    );
  });

  test('guardia canónica rechaza archivos fuera de las raíces', () async {
    final temporary = await Directory.systemTemp.createTemp('hb-guard-');
    addTearDown(() => temporary.delete(recursive: true));
    final managed = Directory(p.join(temporary.path, 'managed'));
    await managed.create();
    final external = File(p.join(temporary.path, 'original.txt'));
    await external.writeAsString('do not delete');

    expect(
      await TransferRetentionService.isManagedPath(
        external.path,
        roots: [managed],
      ),
      isFalse,
    );
    expect(
      await TransferRetentionService.deleteManagedFile(
        external.path,
        roots: [managed],
      ),
      isFalse,
    );
    expect(await external.exists(), isTrue);
  });
}
