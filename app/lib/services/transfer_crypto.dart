import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// Criptografía del HearthBit Transfer Protocol.
///
/// Cifrado de contenido de extremo a extremo, independiente del transporte:
/// X25519 efímero + HKDF-SHA256 + XChaCha20-Poly1305 por chunk.
/// Ver `docs/transfer-protocol.md`.
class TransferCrypto {
  static final X25519 _x25519 = X25519();
  static final Xchacha20 _aead = Xchacha20.poly1305Aead();

  static Future<SimpleKeyPair> generateEphemeralKeyPair() =>
      _x25519.newKeyPair();

  static Future<Uint8List> publicKeyBytes(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return Uint8List.fromList(publicKey.bytes);
  }

  static Future<({Uint8List privateKey, Uint8List publicKey})> exportKeyPair(
    SimpleKeyPair keyPair,
  ) async {
    final extracted = await keyPair.extract();
    return (
      privateKey: Uint8List.fromList(extracted.bytes),
      publicKey: Uint8List.fromList(extracted.publicKey.bytes),
    );
  }

  static SimpleKeyPair restoreKeyPair({
    required Uint8List privateKey,
    required Uint8List publicKey,
  }) {
    if (privateKey.length != 32 || publicKey.length != 32) {
      throw const FormatException('Invalid persisted X25519 key material');
    }
    return SimpleKeyPairData(
      privateKey,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  static Future<TransferCipher> deriveCipher({
    required SimpleKeyPair localKeyPair,
    required List<int> remotePublicKey,
    required List<int> transferId,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: SimplePublicKey(
        remotePublicKey,
        type: KeyPairType.x25519,
      ),
    );
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 52);
    final material = await hkdf.deriveKey(
      secretKey: shared,
      nonce: transferId,
      info: 'hearthbit/transfer/v1'.codeUnits,
    );
    final bytes = await material.extractBytes();
    return TransferCipher._(
      SecretKey(bytes.sublist(0, 32)),
      Uint8List.fromList(bytes.sublist(32, 52)),
      Uint8List.fromList(transferId),
    );
  }

  static Future<TransferCipher> deriveSealedCipher({
    required SimpleKeyPair ephemeralKeyPair,
    required List<int> recipientPublicKey,
    required List<int> packageId,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: SimplePublicKey(
        recipientPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    return _deriveSealedCipher(shared: shared, packageId: packageId);
  }

  static Future<TransferCipher> deriveSealedCipherFromSecret({
    required List<int> sharedSecret,
    required List<int> packageId,
  }) {
    if (sharedSecret.length != 32) {
      throw const FormatException('Invalid X25519 shared secret');
    }
    return _deriveSealedCipher(
      shared: SecretKey(sharedSecret),
      packageId: packageId,
    );
  }

  static Future<TransferCipher> _deriveSealedCipher({
    required SecretKey shared,
    required List<int> packageId,
  }) async {
    if (packageId.length != 16) {
      throw const FormatException('Invalid sealed package id');
    }
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 52);
    final material = await hkdf.deriveKey(
      secretKey: shared,
      nonce: packageId,
      info: 'hearthbit/sealed/v1'.codeUnits,
    );
    final bytes = await material.extractBytes();
    return TransferCipher._(
      SecretKey(bytes.sublist(0, 32)),
      Uint8List.fromList(bytes.sublist(32, 52)),
      Uint8List.fromList(packageId),
    );
  }

  /// SHA-256 de un archivo, leyendo por bloques para no cargarlo en memoria.
  static Future<String> hashFile(File file) async {
    final digest = await hashFileBytes(file);
    return digest.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<Uint8List> hashFileBytes(File file) =>
      Isolate.run(() => _hashFilePath(file.path));

  static Future<Uint8List> hashBytes(Uint8List bytes) {
    final transferable = TransferableTypedData.fromList([bytes]);
    return Isolate.run(() {
      final input = transferable.materialize().asUint8List();
      return Uint8List.fromList(crypto.sha256.convert(input).bytes);
    });
  }
}

Future<Uint8List> _hashFilePath(String path) async {
  final output = _DigestSink();
  final input = crypto.sha256.startChunkedConversion(output);
  await for (final block in File(path).openRead()) {
    input.add(block);
  }
  input.close();
  return Uint8List.fromList(output.digest.bytes);
}

class TransferCipher {
  TransferCipher._(this._key, this._noncePrefix, this._transferId);

  final SecretKey _key;
  final Uint8List _noncePrefix;
  final Uint8List _transferId;

  Uint8List _nonce(int chunkIndex) {
    final nonce = Uint8List(24)..setAll(0, _noncePrefix);
    ByteData.sublistView(nonce).setUint32(20, chunkIndex);
    return nonce;
  }

  /// Cifra un chunk; el MAC de 16 bytes queda al final del resultado.
  Future<Uint8List> encryptChunk(int chunkIndex, List<int> plaintext) async {
    final box = await TransferCrypto._aead.encrypt(
      plaintext,
      secretKey: _key,
      nonce: _nonce(chunkIndex),
      aad: _transferId,
    );
    final output = Uint8List(box.cipherText.length + box.mac.bytes.length)
      ..setAll(0, box.cipherText)
      ..setAll(box.cipherText.length, box.mac.bytes);
    return output;
  }

  Future<Uint8List> decryptChunk(int chunkIndex, List<int> payload) async {
    if (payload.length < 16) {
      throw const FormatException('Encrypted chunk too short');
    }
    final cipherText = payload.sublist(0, payload.length - 16);
    final mac = payload.sublist(payload.length - 16);
    final clear = await TransferCrypto._aead.decrypt(
      SecretBox(cipherText, nonce: _nonce(chunkIndex), mac: Mac(mac)),
      secretKey: _key,
      aad: _transferId,
    );
    return Uint8List.fromList(clear);
  }
}

class _DigestSink implements Sink<crypto.Digest> {
  late final crypto.Digest digest;

  @override
  void add(crypto.Digest data) {
    digest = data;
  }

  @override
  void close() {}
}
