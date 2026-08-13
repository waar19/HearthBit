import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/services/family_qr_codec.dart';

void main() {
  test('codifica y verifica una identidad familiar Ed25519', () async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final codec = FamilyQrCodec(algorithm: algorithm);

    final encoded = await codec.encode(
      peerId: '0011223344556677',
      nickname: 'Ana',
      signingPublicKey: Uint8List.fromList(publicKey.bytes),
      sign: (payload) async => Uint8List.fromList(
        (await algorithm.sign(payload, keyPair: keyPair)).bytes,
      ),
    );
    final decoded = await codec.decodeAndVerify(encoded);

    expect(decoded.peerId, '0011223344556677');
    expect(decoded.nickname, 'Ana');
    expect(decoded.signingPublicKey, publicKey.bytes);
    expect(
      decoded.fingerprint,
      matches(RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$')),
    );
  });

  test('rechaza una firma modificada', () async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final codec = FamilyQrCodec(algorithm: algorithm);
    final encoded = await codec.encode(
      peerId: '0011223344556677',
      nickname: 'Ana',
      signingPublicKey: Uint8List.fromList(publicKey.bytes),
      sign: (payload) async => Uint8List.fromList(
        (await algorithm.sign(payload, keyPair: keyPair)).bytes,
      ),
    );
    final suffix = encoded.substring(FamilyQrCodec.prefix.length);
    final mutationIndex = suffix.length - 10;
    final replacement = suffix[mutationIndex] == 'A' ? 'B' : 'A';
    final tampered =
        '${FamilyQrCodec.prefix}${suffix.substring(0, mutationIndex)}'
        '$replacement${suffix.substring(mutationIndex + 1)}';

    expect(
      () => codec.decodeAndVerify(tampered),
      throwsA(isA<FormatException>()),
    );
  });

  test('rechaza peerId y longitudes no canónicas', () {
    expect(
      () => FamilyQrCodec.canonicalPayload(
        peerId: 'peer-visible',
        nickname: 'Ana',
        signingPublicKey: Uint8List(32),
      ),
      throwsFormatException,
    );
    expect(
      () => FamilyQrCodec.canonicalPayload(
        peerId: '0011223344556677',
        nickname: 'A' * 32,
        signingPublicKey: Uint8List(32),
      ),
      throwsFormatException,
    );
  });
}
