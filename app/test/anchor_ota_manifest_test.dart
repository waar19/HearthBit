import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/models/anchor_ota_manifest.dart';

void main() {
  Uint8List manifestFor(
    Uint8List image, {
    int version = 8,
    int chunkSize = 384,
  }) {
    final bytes = Uint8List(AnchorOtaManifest.encodedLength);
    bytes.setRange(0, 4, 'BOTA'.codeUnits);
    final data = ByteData.sublistView(bytes);
    data.setUint32(4, version, Endian.big);
    data.setUint32(8, image.length, Endian.big);
    bytes.setRange(12, 44, sha256.convert(image).bytes);
    data.setUint16(44, chunkSize, Endian.big);
    return bytes;
  }

  test('parses a valid signed-manifest envelope', () {
    final image = Uint8List.fromList(
      List<int>.generate(1000, (index) => index),
    );
    final manifest = AnchorOtaManifest.parse(manifestFor(image));

    expect(manifest.version, 8);
    expect(manifest.imageSize, 1000);
    expect(manifest.chunkSize, 384);
    expect(manifest.chunkCount, 3);
    expect(manifest.sha256Digest, sha256.convert(image).bytes);
  });

  test('rejects malformed manifest fields', () {
    final image = Uint8List.fromList([1, 2, 3]);
    final valid = manifestFor(image);

    expect(
      () => AnchorOtaManifest.parse(Uint8List(109)),
      throwsFormatException,
    );
    expect(
      () => AnchorOtaManifest.parse(Uint8List.fromList(valid)..[0] = 0),
      throwsFormatException,
    );
    expect(
      () => AnchorOtaManifest.parse(manifestFor(image, version: 0)),
      throwsFormatException,
    );
    expect(
      () => AnchorOtaManifest.parse(manifestFor(image, chunkSize: 481)),
      throwsFormatException,
    );
  });

  test('bundle rejects an image that does not match the manifest', () async {
    final expected = Uint8List.fromList([1, 2, 3, 4]);
    final actual = Uint8List.fromList([1, 2, 3, 5]);
    final bundle = _MemoryAssetBundle({
      AnchorOtaBundle.manifestAsset: manifestFor(expected),
      AnchorOtaBundle.imageAsset: actual,
    });

    await expectLater(
      AnchorOtaBundle.load(bundle: bundle),
      throwsFormatException,
    );
  });
}

class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.assets);

  final Map<String, Uint8List> assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = assets[key];
    if (bytes == null) throw StateError('Missing asset $key');
    return ByteData.sublistView(bytes);
  }
}
