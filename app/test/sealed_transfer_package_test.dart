import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/sealed_transfer_package.dart';
import 'package:hearth_bit/services/transfer_crypto.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sealed-hbt-test-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('HBTS cifra para el destinatario y conserva firma y hash', () async {
    final source = File('${directory.path}/rescue.txt');
    await source.writeAsString('critical rescue coordinates');
    final recipient = await X25519().newKeyPair();
    final recipientPublic = await recipient.extractPublicKey();
    final ephemeral = await TransferCrypto.generateEphemeralKeyPair();
    final ephemeralPublic = await TransferCrypto.publicKeyBytes(ephemeral);
    final packageId = Uint8List.fromList(List.generate(16, (i) => i + 1));
    final encryptCipher = await TransferCrypto.deriveSealedCipher(
      ephemeralKeyPair: ephemeral,
      recipientPublicKey: recipientPublic.bytes,
      packageId: packageId,
    );
    final package = File('${directory.path}/rescue.hbt');

    await SealedTransferPackage.create(
      source: source,
      destination: package,
      packageId: packageId,
      senderPeerId: '0011223344556677',
      recipientPeerId: '8899aabbccddeeff',
      ephemeralPublicKey: ephemeralPublic,
      fileName: '../rescue.txt',
      mimeType: 'text/plain',
      chunkSize: 8,
      sha256: await TransferCrypto.hashFileBytes(source),
      cipher: encryptCipher,
      sign: (data) async {
        final digest = await TransferCrypto.hashBytes(data);
        return Uint8List.fromList([...digest, ...digest]);
      },
    );
    final metadata = await SealedTransferPackage.inspect(package);
    final expectedSignatureDigest = await TransferCrypto.hashBytes(
      metadata.signedHeader,
    );
    expect(
      metadata.signature,
      Uint8List.fromList([
        ...expectedSignatureDigest,
        ...expectedSignatureDigest,
      ]),
    );

    final shared = await X25519().sharedSecretKey(
      keyPair: recipient,
      remotePublicKey: SimplePublicKey(
        metadata.ephemeralPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    final decryptCipher = await TransferCrypto.deriveSealedCipherFromSecret(
      sharedSecret: await shared.extractBytes(),
      packageId: metadata.packageId,
    );
    final opened = File('${directory.path}/opened.txt');
    await SealedTransferPackage.decrypt(
      package: package,
      metadata: metadata,
      destination: opened,
      cipher: decryptCipher,
    );

    expect(metadata.fileName, 'rescue.txt');
    expect(await opened.readAsString(), 'critical rescue coordinates');
    expect(await TransferCrypto.hashFileBytes(opened), metadata.sha256);
  });

  test('HBTS rechaza alteración del ciphertext', () async {
    final source = File('${directory.path}/source.bin');
    await source.writeAsBytes(List.generate(32, (i) => i));
    final recipient = await X25519().newKeyPair();
    final recipientPublic = await recipient.extractPublicKey();
    final ephemeral = await TransferCrypto.generateEphemeralKeyPair();
    final packageId = Uint8List(16);
    final cipher = await TransferCrypto.deriveSealedCipher(
      ephemeralKeyPair: ephemeral,
      recipientPublicKey: recipientPublic.bytes,
      packageId: packageId,
    );
    final package = File('${directory.path}/tampered.hbt');
    await SealedTransferPackage.create(
      source: source,
      destination: package,
      packageId: packageId,
      senderPeerId: '0011223344556677',
      recipientPeerId: '8899aabbccddeeff',
      ephemeralPublicKey: await TransferCrypto.publicKeyBytes(ephemeral),
      fileName: 'source.bin',
      mimeType: 'application/octet-stream',
      chunkSize: 16,
      sha256: await TransferCrypto.hashFileBytes(source),
      cipher: cipher,
      sign: (_) async => Uint8List(64),
    );
    final metadata = await SealedTransferPackage.inspect(package);
    final bytes = await package.readAsBytes();
    bytes[bytes.length - 1] ^= 1;
    await package.writeAsBytes(bytes);
    final shared = await X25519().sharedSecretKey(
      keyPair: recipient,
      remotePublicKey: SimplePublicKey(
        metadata.ephemeralPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    final decryptCipher = await TransferCrypto.deriveSealedCipherFromSecret(
      sharedSecret: await shared.extractBytes(),
      packageId: packageId,
    );

    expect(
      () => SealedTransferPackage.decrypt(
        package: package,
        metadata: metadata,
        destination: File('${directory.path}/bad.bin'),
        cipher: decryptCipher,
      ),
      throwsA(anything),
    );
  });
}
