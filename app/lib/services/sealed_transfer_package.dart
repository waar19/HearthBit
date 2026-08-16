import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'hbt_package.dart';
import 'transfer_crypto.dart';
import 'transfer_protocol.dart';

class SealedPackageMetadata {
  const SealedPackageMetadata({
    required this.packageId,
    required this.senderPeerId,
    required this.recipientPeerId,
    required this.ephemeralPublicKey,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.chunkSize,
    required this.sha256,
    required this.signedHeader,
    required this.signature,
    required this.payloadOffset,
  });

  final Uint8List packageId;
  final String senderPeerId;
  final String recipientPeerId;
  final Uint8List ephemeralPublicKey;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final int chunkSize;
  final Uint8List sha256;
  final Uint8List signedHeader;
  final Uint8List signature;
  final int payloadOffset;
}

abstract final class SealedTransferPackage {
  static const int version = 1;
  static const int signatureLength = 64;
  static const int maximumMetadataBytes = 4096;
  static final Uint8List _magic = Uint8List.fromList(ascii.encode('HBTS'));

  static Future<File> create({
    required File source,
    required File destination,
    required Uint8List packageId,
    required String senderPeerId,
    required String recipientPeerId,
    required Uint8List ephemeralPublicKey,
    required String fileName,
    required String mimeType,
    required int chunkSize,
    required Uint8List sha256,
    required TransferCipher cipher,
    required Future<Uint8List> Function(Uint8List data) sign,
  }) async {
    final fileSize = await source.length();
    if (fileSize <= 0 ||
        fileSize > 512 * 1024 * 1024 ||
        packageId.length != 16 ||
        ephemeralPublicKey.length != 32 ||
        sha256.length != 32 ||
        chunkSize <= 0 ||
        chunkSize > 64 * 1024) {
      throw const FormatException('Invalid sealed package metadata');
    }
    final sender = _peerIdBytes(senderPeerId);
    final recipient = _peerIdBytes(recipientPeerId);
    final safeName = sanitizeFileName(fileName);
    final nameBytes = utf8.encode(safeName);
    final mimeBytes = utf8.encode(mimeType);
    if (nameBytes.length > 255 || mimeBytes.isEmpty || mimeBytes.length > 255) {
      throw const FormatException('Invalid sealed package text metadata');
    }
    final builder = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(version)
      ..add(packageId)
      ..add(sender)
      ..add(recipient)
      ..add(ephemeralPublicKey);
    final numeric = Uint8List(12);
    ByteData.sublistView(numeric)
      ..setUint64(0, fileSize)
      ..setUint32(8, chunkSize);
    builder
      ..add(numeric)
      ..add(sha256)
      ..add(_u16(nameBytes.length))
      ..add(nameBytes)
      ..add(_u16(mimeBytes.length))
      ..add(mimeBytes);
    final signedHeader = builder.toBytes();
    final signature = await sign(signedHeader);
    if (signature.length != signatureLength) {
      throw const FormatException('Invalid sealed package signature');
    }
    final sink = destination.openWrite();
    final sourceFile = await source.open();
    try {
      sink
        ..add(signedHeader)
        ..add(signature);
      final chunks = (fileSize + chunkSize - 1) ~/ chunkSize;
      for (var index = 0; index < chunks; index++) {
        await sourceFile.setPosition(index * chunkSize);
        final clear = await sourceFile.read(
          min(chunkSize, fileSize - index * chunkSize),
        );
        final encrypted = await cipher.encryptChunk(index, clear);
        final frameHeader = Uint8List(8);
        ByteData.sublistView(frameHeader)
          ..setUint32(0, index)
          ..setUint32(4, encrypted.length);
        sink
          ..add(frameHeader)
          ..add(encrypted);
      }
      await sink.flush();
    } finally {
      await sourceFile.close();
      await sink.close();
    }
    if (await destination.length() > HbtPackageProtocol.maximumPackageBytes) {
      await destination.delete();
      throw const FormatException('Sealed package exceeds maximum size');
    }
    return destination;
  }

  static Future<SealedPackageMetadata> inspect(File package) async {
    final total = await package.length();
    if (total <= signatureLength ||
        total > HbtPackageProtocol.maximumPackageBytes) {
      throw const FormatException('Invalid sealed package size');
    }
    final file = await package.open();
    try {
      final fixed = await file.read(115);
      if (fixed.length != 115 ||
          !_startsWith(fixed, _magic) ||
          fixed[4] != version) {
        throw const FormatException('Invalid sealed package header');
      }
      final packageId = Uint8List.fromList(fixed.sublist(5, 21));
      final sender = _hex(fixed.sublist(21, 29));
      final recipient = _hex(fixed.sublist(29, 37));
      final ephemeral = Uint8List.fromList(fixed.sublist(37, 69));
      final data = ByteData.sublistView(Uint8List.fromList(fixed));
      final fileSize = data.getUint64(69);
      final chunkSize = data.getUint32(77);
      final sha256 = Uint8List.fromList(fixed.sublist(81, 113));
      final nameLength = (fixed[113] << 8) | fixed[114];
      if (nameLength <= 0 || nameLength > 255) {
        throw const FormatException('Invalid sealed file name');
      }
      final nameBytes = await file.read(nameLength);
      final mimeLengthBytes = await file.read(2);
      if (nameBytes.length != nameLength || mimeLengthBytes.length != 2) {
        throw const FormatException('Truncated sealed metadata');
      }
      final mimeLength = (mimeLengthBytes[0] << 8) | mimeLengthBytes[1];
      if (mimeLength <= 0 || mimeLength > 255) {
        throw const FormatException('Invalid sealed MIME type');
      }
      final mimeBytes = await file.read(mimeLength);
      final signature = await file.read(signatureLength);
      if (mimeBytes.length != mimeLength ||
          signature.length != signatureLength) {
        throw const FormatException('Truncated sealed signature');
      }
      final signedHeader = Uint8List.fromList([
        ...fixed,
        ...nameBytes,
        ...mimeLengthBytes,
        ...mimeBytes,
      ]);
      if (signedHeader.length > maximumMetadataBytes ||
          fileSize <= 0 ||
          fileSize > 512 * 1024 * 1024 ||
          chunkSize <= 0 ||
          chunkSize > 64 * 1024) {
        throw const FormatException('Invalid sealed limits');
      }
      return SealedPackageMetadata(
        packageId: packageId,
        senderPeerId: sender,
        recipientPeerId: recipient,
        ephemeralPublicKey: ephemeral,
        fileName: sanitizeFileName(utf8.decode(nameBytes)),
        mimeType: utf8.decode(mimeBytes),
        fileSize: fileSize,
        chunkSize: chunkSize,
        sha256: sha256,
        signedHeader: signedHeader,
        signature: Uint8List.fromList(signature),
        payloadOffset: signedHeader.length + signatureLength,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid sealed package');
    } finally {
      await file.close();
    }
  }

  static Future<void> decrypt({
    required File package,
    required SealedPackageMetadata metadata,
    required File destination,
    required TransferCipher cipher,
  }) async {
    final input = await package.open();
    final output = await destination.open(mode: FileMode.writeOnly);
    try {
      await input.setPosition(metadata.payloadOffset);
      var expectedIndex = 0;
      var clearBytes = 0;
      while (clearBytes < metadata.fileSize) {
        final header = await input.read(8);
        if (header.length != 8) {
          throw const FormatException('Truncated sealed chunk header');
        }
        final view = ByteData.sublistView(Uint8List.fromList(header));
        final index = view.getUint32(0);
        final length = view.getUint32(4);
        if (index != expectedIndex ||
            length < 16 ||
            length > metadata.chunkSize + 16) {
          throw const FormatException('Invalid sealed chunk');
        }
        final encrypted = await input.read(length);
        if (encrypted.length != length) {
          throw const FormatException('Truncated sealed chunk');
        }
        final clear = await cipher.decryptChunk(index, encrypted);
        if (clearBytes + clear.length > metadata.fileSize) {
          throw const FormatException('Sealed plaintext exceeds declared size');
        }
        await output.writeFrom(clear);
        clearBytes += clear.length;
        expectedIndex += 1;
      }
      if (await input.position() != await input.length()) {
        throw const FormatException('Trailing sealed package data');
      }
    } finally {
      await input.close();
      await output.close();
    }
  }

  static Uint8List _peerIdBytes(String value) {
    if (!RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(value)) {
      throw const FormatException('Invalid sealed peer id');
    }
    return Uint8List.fromList(
      List.generate(
        8,
        (index) =>
            int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
      ),
    );
  }

  static Uint8List _u16(int value) =>
      Uint8List.fromList([value >> 8, value & 0xff]);

  static bool _startsWith(List<int> value, List<int> prefix) {
    for (var i = 0; i < prefix.length; i++) {
      if (value[i] != prefix[i]) return false;
    }
    return true;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
