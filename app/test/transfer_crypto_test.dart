import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/models/transfer_models.dart';
import 'package:hearth_bit/services/transfer_crypto.dart';

void main() {
  test('el receptor descifra lo que cifra el emisor', () async {
    final transferId = List<int>.generate(16, (i) => i);
    final sender = await TransferCrypto.generateEphemeralKeyPair();
    final receiver = await TransferCrypto.generateEphemeralKeyPair();

    final senderCipher = await TransferCrypto.deriveCipher(
      localKeyPair: sender,
      remotePublicKey: await TransferCrypto.publicKeyBytes(receiver),
      transferId: transferId,
    );
    final receiverCipher = await TransferCrypto.deriveCipher(
      localKeyPair: receiver,
      remotePublicKey: await TransferCrypto.publicKeyBytes(sender),
      transferId: transferId,
    );

    final plain = List<int>.generate(1000, (i) => (i * 7) & 0xFF);
    final encrypted = await senderCipher.encryptChunk(42, plain);
    expect(encrypted.length, plain.length + 16);
    final decrypted = await receiverCipher.decryptChunk(42, encrypted);
    expect(decrypted, plain);
  });

  test('un chunk manipulado o con índice equivocado es rechazado', () async {
    final transferId = List<int>.generate(16, (i) => 255 - i);
    final sender = await TransferCrypto.generateEphemeralKeyPair();
    final receiver = await TransferCrypto.generateEphemeralKeyPair();
    final senderCipher = await TransferCrypto.deriveCipher(
      localKeyPair: sender,
      remotePublicKey: await TransferCrypto.publicKeyBytes(receiver),
      transferId: transferId,
    );
    final receiverCipher = await TransferCrypto.deriveCipher(
      localKeyPair: receiver,
      remotePublicKey: await TransferCrypto.publicKeyBytes(sender),
      transferId: transferId,
    );

    final encrypted = await senderCipher.encryptChunk(1, [1, 2, 3, 4]);
    final tampered = Uint8List.fromList(encrypted)..[0] ^= 0xFF;
    expect(() => receiverCipher.decryptChunk(1, tampered), throwsA(anything));
    expect(() => receiverCipher.decryptChunk(2, encrypted), throwsA(anything));
  });

  test('el bitmap de chunks rastrea faltantes y reanudación', () {
    final bitmap = ChunkBitmap(20);
    expect(bitmap.isComplete, isFalse);
    expect(bitmap.missing.length, 20);
    for (var i = 0; i < 20; i += 2) {
      bitmap.set(i);
    }
    expect(bitmap.count, 10);
    expect(bitmap.missing.every((i) => i.isOdd), isTrue);

    final restored = ChunkBitmap.fromBytes(20, bitmap.toBytes());
    expect(restored.count, 10);
    for (var i = 1; i < 20; i += 2) {
      restored.set(i);
    }
    expect(restored.isComplete, isTrue);
  });

  test('calcula SHA-256 de archivo fuera del isolate UI', () async {
    final directory = await Directory.systemTemp.createTemp('hb-hash-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}data.bin');
    await file.writeAsBytes(List.generate(1024 * 1024, (i) => i & 0xff));

    expect(
      await TransferCrypto.hashFile(file),
      'fbbab289f7f94b25736c58be46a994c441fd02552cc6022352e3d86d2fab7c83',
    );
  });
}
