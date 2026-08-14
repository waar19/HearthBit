import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/models/transfer_models.dart';
import 'package:hearth_bit/services/transfer_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'restaura bitmap y sesión de resume tras reiniciar repositorio',
    () async {
      final directory = await Directory.systemTemp.createTemp('hb-repo-test-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}transfers.db';
      final record = TransferRecord(
        id: '00112233445566778899aabbccddeeff',
        peerId: 'peer',
        peerNickname: 'Peer',
        direction: TransferDirection.incoming,
        fileName: 'partial.bin',
        mimeType: 'application/octet-stream',
        fileSize: 400,
        sha256Hex: '00' * 32,
        chunkSize: 100,
        state: TransferState.transferring,
        filePath: 'partial.bin.part',
      );
      final bitmap = Uint8List.fromList([0x05]);
      final material = TransferResumeMaterial(
        localPrivateKey: Uint8List.fromList(List.filled(32, 1)),
        localPublicKey: Uint8List.fromList(List.filled(32, 2)),
        remotePublicKey: Uint8List.fromList(List.filled(32, 3)),
        offeredTransports: 3,
      );
      var repository = TransferRepository(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      await repository.save(record, bitmap: bitmap, resumeMaterial: material);
      await repository.close();

      repository = TransferRepository(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(repository.close);
      final restored = await repository.loadResumeMaterial(record.id);

      expect(await repository.loadBitmap(record.id), bitmap);
      expect(restored, isNotNull);
      expect(restored!.localPrivateKey, material.localPrivateKey);
      expect(restored.localPublicKey, material.localPublicKey);
      expect(restored.remotePublicKey, material.remotePublicKey);
      expect(restored.offeredTransports, 3);
    },
  );
}
