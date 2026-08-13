import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../models/family_models.dart';

typedef FamilyPayloadSigner = Future<Uint8List> Function(Uint8List payload);

class FamilyQrCodec {
  FamilyQrCodec({Ed25519? algorithm}) : _algorithm = algorithm ?? Ed25519();

  static const String prefix = 'HBFG1:';
  static const int version = 1;
  static const int identityType = 0x46;
  static const int peerIdBytes = 8;
  static const int publicKeyBytes = 32;
  static const int signatureBytes = 64;
  static const int maximumNicknameBytes = 31;

  final Ed25519 _algorithm;

  Future<String> encode({
    required String peerId,
    required String nickname,
    required Uint8List signingPublicKey,
    required FamilyPayloadSigner sign,
  }) async {
    final canonical = canonicalPayload(
      peerId: peerId,
      nickname: nickname,
      signingPublicKey: signingPublicKey,
    );
    final signature = await sign(canonical);
    if (signature.length != signatureBytes) {
      throw const FormatException('Invalid Ed25519 signature length');
    }
    return '$prefix${base64Url.encode([...canonical, ...signature]).replaceAll('=', '')}';
  }

  Future<FamilyQrIdentity> decodeAndVerify(String encoded) async {
    if (!encoded.startsWith(prefix)) {
      throw const FormatException('Invalid family QR type');
    }
    final bytes = _decodeBase64(encoded.substring(prefix.length));
    if (bytes.length < 2 + peerIdBytes + 1 + publicKeyBytes + signatureBytes) {
      throw const FormatException('Truncated family QR');
    }
    final signatureOffset = bytes.length - signatureBytes;
    final canonical = Uint8List.sublistView(bytes, 0, signatureOffset);
    final signature = Uint8List.sublistView(bytes, signatureOffset);
    if (canonical[0] != version) {
      throw const FormatException('Unsupported family QR version');
    }
    if (canonical[1] != identityType) {
      throw const FormatException('Invalid family QR payload type');
    }
    final nicknameLength = canonical[2 + peerIdBytes];
    final expectedCanonicalLength =
        2 + peerIdBytes + 1 + nicknameLength + publicKeyBytes;
    if (nicknameLength == 0 ||
        nicknameLength > maximumNicknameBytes ||
        canonical.length != expectedCanonicalLength) {
      throw const FormatException('Invalid family QR nickname length');
    }
    final peerBytes = Uint8List.sublistView(canonical, 2, 2 + peerIdBytes);
    final nicknameStart = 2 + peerIdBytes + 1;
    final keyStart = nicknameStart + nicknameLength;
    final nickname = utf8.decode(
      Uint8List.sublistView(canonical, nicknameStart, keyStart),
      allowMalformed: false,
    );
    if (nickname.trim().isEmpty || nickname != nickname.trim()) {
      throw const FormatException('Invalid family QR nickname');
    }
    final signingPublicKey = Uint8List.sublistView(canonical, keyStart);
    final verified = await _algorithm.verify(
      canonical,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(signingPublicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!verified) {
      throw const FormatException('Invalid family QR signature');
    }
    final peerId = _hex(peerBytes);
    if (!RegExp(r'^[0-9a-f]{16}$').hasMatch(peerId)) {
      throw const FormatException('Invalid family QR peerId');
    }
    return FamilyQrIdentity(
      peerId: peerId,
      nickname: nickname,
      signingPublicKey: Uint8List.fromList(signingPublicKey),
      fingerprint: fingerprint(signingPublicKey),
    );
  }

  static Uint8List canonicalPayload({
    required String peerId,
    required String nickname,
    required Uint8List signingPublicKey,
  }) {
    final normalizedPeerId = peerId.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{16}$').hasMatch(normalizedPeerId)) {
      throw const FormatException('Invalid peerId');
    }
    if (signingPublicKey.length != publicKeyBytes) {
      throw const FormatException('Invalid Ed25519 public key length');
    }
    final cleanNickname = nickname.trim();
    final nicknameBytes = utf8.encode(cleanNickname);
    if (cleanNickname.isEmpty || nicknameBytes.length > maximumNicknameBytes) {
      throw const FormatException('Invalid nickname length');
    }
    return Uint8List.fromList([
      version,
      identityType,
      ..._unhex(normalizedPeerId),
      nicknameBytes.length,
      ...nicknameBytes,
      ...signingPublicKey,
    ]);
  }

  static String fingerprint(List<int> signingPublicKey) {
    if (signingPublicKey.length != publicKeyBytes) {
      throw const FormatException('Invalid Ed25519 public key length');
    }
    final short = sha256.convert(signingPublicKey).bytes.take(6);
    return short
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
  }

  static Uint8List _decodeBase64(String value) {
    if (value.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw const FormatException('Invalid family QR encoding');
    }
    final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
    try {
      return base64Url.decode(padded);
    } on FormatException {
      throw const FormatException('Invalid family QR encoding');
    }
  }

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _unhex(String value) => Uint8List.fromList([
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ]);
}
