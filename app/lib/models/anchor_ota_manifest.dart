import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class AnchorOtaManifest {
  const AnchorOtaManifest({
    required this.version,
    required this.imageSize,
    required this.sha256Digest,
    required this.chunkSize,
  });

  static const int encodedLength = 110;
  static const int minimumChunkSize = 64;
  static const int maximumChunkSize = 480;

  final int version;
  final int imageSize;
  final Uint8List sha256Digest;
  final int chunkSize;

  int get chunkCount => (imageSize + chunkSize - 1) ~/ chunkSize;

  factory AnchorOtaManifest.parse(Uint8List bytes) {
    if (bytes.length != encodedLength) {
      throw const FormatException('anchor_ota_manifest_length');
    }
    if (bytes[0] != 0x42 ||
        bytes[1] != 0x4f ||
        bytes[2] != 0x54 ||
        bytes[3] != 0x41) {
      throw const FormatException('anchor_ota_manifest_magic');
    }
    final data = ByteData.sublistView(bytes);
    final version = data.getUint32(4, Endian.big);
    final imageSize = data.getUint32(8, Endian.big);
    final chunkSize = data.getUint16(44, Endian.big);
    if (version == 0 || imageSize == 0) {
      throw const FormatException('anchor_ota_manifest_values');
    }
    if (chunkSize < minimumChunkSize || chunkSize > maximumChunkSize) {
      throw const FormatException('anchor_ota_manifest_chunk');
    }
    return AnchorOtaManifest(
      version: version,
      imageSize: imageSize,
      sha256Digest: Uint8List.fromList(bytes.sublist(12, 44)),
      chunkSize: chunkSize,
    );
  }
}

class AnchorOtaBundle {
  const AnchorOtaBundle({
    required this.manifest,
    required this.manifestBytes,
    required this.imageBytes,
  });

  static const String manifestAsset = 'assets/firmware/bitle.bin.bota';
  static const String imageAsset = 'assets/firmware/bitle.bin';

  final AnchorOtaManifest manifest;
  final Uint8List manifestBytes;
  final Uint8List imageBytes;

  static Future<AnchorOtaBundle> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final manifestData = await assets.load(manifestAsset);
    final imageData = await assets.load(imageAsset);
    final manifestBytes = manifestData.buffer.asUint8List(
      manifestData.offsetInBytes,
      manifestData.lengthInBytes,
    );
    final imageBytes = imageData.buffer.asUint8List(
      imageData.offsetInBytes,
      imageData.lengthInBytes,
    );
    final manifest = AnchorOtaManifest.parse(manifestBytes);
    if (imageBytes.length != manifest.imageSize) {
      throw const FormatException('anchor_ota_image_size');
    }
    final digest = sha256.convert(imageBytes).bytes;
    if (!_constantTimeEquals(digest, manifest.sha256Digest)) {
      throw const FormatException('anchor_ota_image_digest');
    }
    return AnchorOtaBundle(
      manifest: manifest,
      manifestBytes: Uint8List.fromList(manifestBytes),
      imageBytes: Uint8List.fromList(imageBytes),
    );
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
