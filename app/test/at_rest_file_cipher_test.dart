import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/services/at_rest_file_cipher.dart';

void main() {
  test('cifra por chunks y solo materializa claro bajo demanda', () async {
    final directory = await Directory.systemTemp.createTemp('hbit-rest-test');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/voice.m4a');
    final clear = List<int>.generate(1024 * 1024 + 33, (index) => index % 251);
    await source.writeAsBytes(clear);
    final cipher = AtRestFileCipher(
      testingKey: SecretKey(List<int>.generate(32, (index) => index)),
      temporaryDirectory: () async => directory,
    );

    final encrypted = await cipher.encrypt(source);

    expect(await source.exists(), isFalse);
    expect(AtRestFileCipher.isEncryptedPath(encrypted.path), isTrue);
    expect(await encrypted.readAsBytes(), isNot(equals(clear)));

    final restored = await cipher.decryptToTemporary(encrypted);
    expect(await restored.readAsBytes(), clear);
    await restored.delete();
  });

  test('rechaza ciphertext alterado', () async {
    final directory = await Directory.systemTemp.createTemp('hbit-rest-tamper');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/file.bin');
    await source.writeAsBytes(List<int>.generate(1024, (index) => index % 255));
    final cipher = AtRestFileCipher(
      testingKey: SecretKey(List<int>.filled(32, 7)),
      temporaryDirectory: () async => directory,
    );
    final encrypted = await cipher.encrypt(source);
    final bytes = await encrypted.readAsBytes();
    bytes[bytes.length - 1] ^= 0xFF;
    await encrypted.writeAsBytes(bytes);

    await expectLater(
      cipher.decryptToTemporary(encrypted),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
