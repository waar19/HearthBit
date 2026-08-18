import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import 'secure_storage_config.dart';
import 'transfer_storage.dart';

class AtRestFileCipher {
  AtRestFileCipher({
    FlutterSecureStorage? storage,
    SecretKey? testingKey,
    Future<Directory> Function()? temporaryDirectory,
  }) : _storage = storage ?? hearthBitSecureStorage,
       _providedTestingKey = testingKey,
       _temporaryDirectory =
           temporaryDirectory ?? TransferStorage.cacheDirectory;

  static const _keyName = 'hearthbit.files.at_rest.v1';
  static const _magic = 'HBRST001';
  static const _chunkSize = 1024 * 1024;
  static const _noncePrefixBytes = 20;
  static final _algorithm = Xchacha20.poly1305Aead();

  final FlutterSecureStorage _storage;
  final SecretKey? _providedTestingKey;
  final Future<Directory> Function() _temporaryDirectory;

  static bool isEncryptedPath(String path) => path.endsWith('.hbe');

  Future<File> encrypt(File source) async {
    if (isEncryptedPath(source.path)) return source;
    final key = await _loadOrCreateKey();
    final random = Random.secure();
    final noncePrefix = Uint8List.fromList(
      List.generate(_noncePrefixBytes, (_) => random.nextInt(256)),
    );
    final output = File('${source.path}.hbe.tmp');
    final sink = output.openWrite();
    final input = await source.open();
    try {
      sink.add(ascii.encode(_magic));
      sink.add(noncePrefix);
      sink.add(_uint64(await source.length()));
      sink.add(_uint32(_chunkSize));
      var index = 0;
      while (true) {
        final clear = await input.read(_chunkSize);
        if (clear.isEmpty) break;
        final box = await _algorithm.encrypt(
          clear,
          secretKey: key,
          nonce: _nonce(noncePrefix, index),
          aad: _uint32(index),
        );
        final payload = Uint8List(box.cipherText.length + box.mac.bytes.length)
          ..setAll(0, box.cipherText)
          ..setAll(box.cipherText.length, box.mac.bytes);
        sink
          ..add(_uint32(payload.length))
          ..add(payload);
        index += 1;
      }
      await sink.flush();
      await sink.close();
      await input.close();
      final encrypted = File('${source.path}.hbe');
      if (await encrypted.exists()) await encrypted.delete();
      await output.rename(encrypted.path);
      await source.delete();
      return encrypted;
    } catch (_) {
      await input.close();
      await sink.close();
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  Future<File> decryptToTemporary(File source) async {
    if (!isEncryptedPath(source.path)) return source;
    final key = await _loadKey();
    final input = await source.open();
    final header = await input.read(40);
    if (header.length != 40 ||
        ascii.decode(header.sublist(0, 8), allowInvalid: true) != _magic) {
      await input.close();
      throw const FormatException('Invalid encrypted HearthBit file');
    }
    final noncePrefix = Uint8List.fromList(header.sublist(8, 28));
    final originalLength = ByteData.sublistView(
      Uint8List.fromList(header.sublist(28, 36)),
    ).getUint64(0);
    final chunkSize = ByteData.sublistView(
      Uint8List.fromList(header.sublist(36, 40)),
    ).getUint32(0);
    if (chunkSize != _chunkSize) {
      await input.close();
      throw const FormatException('Unsupported encrypted file chunk size');
    }
    final temporary = await _temporaryDirectory();
    final originalName = p.basenameWithoutExtension(source.path);
    final output = File(
      p.join(
        temporary.path,
        'hearthbit_plain_${DateTime.now().microsecondsSinceEpoch}_$originalName',
      ),
    );
    final sink = output.openWrite();
    var written = 0;
    var index = 0;
    try {
      while (written < originalLength) {
        final lengthBytes = await input.read(4);
        if (lengthBytes.length != 4) {
          throw const FormatException('Truncated encrypted HearthBit file');
        }
        final payloadLength = ByteData.sublistView(
          Uint8List.fromList(lengthBytes),
        ).getUint32(0);
        if (payloadLength < 16 || payloadLength > _chunkSize + 16) {
          throw const FormatException('Invalid encrypted file chunk');
        }
        final payload = await input.read(payloadLength);
        if (payload.length != payloadLength) {
          throw const FormatException('Truncated encrypted file chunk');
        }
        final clear = await _algorithm.decrypt(
          SecretBox(
            payload.sublist(0, payload.length - 16),
            nonce: _nonce(noncePrefix, index),
            mac: Mac(payload.sublist(payload.length - 16)),
          ),
          secretKey: key,
          aad: _uint32(index),
        );
        sink.add(clear);
        written += clear.length;
        index += 1;
      }
      if (written != originalLength) {
        throw const FormatException('Encrypted file length mismatch');
      }
      await sink.flush();
      await sink.close();
      await input.close();
      return output;
    } catch (_) {
      await input.close();
      await sink.close();
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  Future<SecretKey> _loadOrCreateKey() async {
    if (_providedTestingKey != null) return _providedTestingKey;
    final existing = await _storage.read(key: _keyName);
    if (existing != null) return SecretKey(base64Decode(existing));
    final bytes = Uint8List.fromList(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    await _storage.write(key: _keyName, value: base64Encode(bytes));
    return SecretKey(bytes);
  }

  Future<SecretKey> _loadKey() async {
    if (_providedTestingKey != null) return _providedTestingKey;
    final value = await _storage.read(key: _keyName);
    if (value == null) throw StateError('Encrypted file key is unavailable');
    return SecretKey(base64Decode(value));
  }

  static Future<void> destroyKey({
    FlutterSecureStorage storage = hearthBitSecureStorage,
  }) => storage.delete(key: _keyName);

  static Uint8List _nonce(Uint8List prefix, int index) => Uint8List(24)
    ..setAll(0, prefix)
    ..setAll(20, _uint32(index));

  static Uint8List _uint32(int value) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, value);

  static Uint8List _uint64(int value) =>
      Uint8List(8)..buffer.asByteData().setUint64(0, value);
}
