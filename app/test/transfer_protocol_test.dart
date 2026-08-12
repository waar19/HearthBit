import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/services/transfer_protocol.dart';

const goldenOfferHex =
    '010101001000112233445566778899aabbccddeeff020008666f746f2e6a7067'
    '03000a696d6167652f6a706567040008000000000010000005002001020304050607'
    '08090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f2006000400010000'
    '07000400000007080020a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7'
    'b8b9babbbcbdbebf0900080000019af232b2000a000811223344556677880b0040'
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

const goldenSignedHex =
    '010101001000112233445566778899aabbccddeeff020008666f746f2e6a7067'
    '03000a696d6167652f6a706567040008000000000010000005002001020304050607'
    '08090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f2006000400010000'
    '07000400000007080020a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7'
    'b8b9babbbcbdbebf0900080000019af232b2000a00081122334455667788';

const goldenChunkHex =
    '011001001000112233445566778899aabbccddeeff0f000400000003100004deadbeef';

Uint8List fromHex(String hex) {
  final cleaned = hex.replaceAll(RegExp(r'\s'), '');
  final bytes = Uint8List(cleaned.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

String toHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

TransferFrame buildGoldenOffer() {
  return TransferFrame(TransferProtocol.typeOffer)
    ..setBytes(TransferProtocol.tagTransferId, [
      for (var i = 0; i < 16; i++) (i * 0x11) & 0xFF,
    ])
    ..setUtf8(TransferProtocol.tagFileName, 'foto.jpg')
    ..setUtf8(TransferProtocol.tagMimeType, 'image/jpeg')
    ..setU64(TransferProtocol.tagFileSize, 1048576)
    ..setBytes(TransferProtocol.tagSha256, [for (var i = 1; i <= 32; i++) i])
    ..setU32(TransferProtocol.tagChunkSize, 65536)
    ..setU32(
      TransferProtocol.tagTransports,
      TransferProtocol.transportBle |
          TransferProtocol.transportLan |
          TransferProtocol.transportNearby,
    )
    ..setBytes(TransferProtocol.tagEphemeralKey, [
      for (var i = 0; i < 32; i++) 0xA0 + i,
    ])
    ..setU64(TransferProtocol.tagExpiresAt, 1765000000000)
    ..setBytes(TransferProtocol.tagSenderPeerId, [
      0x11,
      0x22,
      0x33,
      0x44,
      0x55,
      0x66,
      0x77,
      0x88,
    ])
    ..setBytes(TransferProtocol.tagSignature, List.filled(64, 0xEE));
}

void main() {
  test('la oferta golden coincide byte a byte', () {
    expect(toHex(buildGoldenOffer().encode()), goldenOfferHex);
  });

  test('los bytes firmados excluyen el TLV de firma', () {
    expect(toHex(buildGoldenOffer().signedBytes()), goldenSignedHex);
  });

  test('el chunk golden coincide byte a byte', () {
    final chunk = TransferFrame(TransferProtocol.typeDataChunk)
      ..setBytes(TransferProtocol.tagTransferId, [
        for (var i = 0; i < 16; i++) (i * 0x11) & 0xFF,
      ])
      ..setU32(TransferProtocol.tagChunkIndex, 3)
      ..setBytes(TransferProtocol.tagChunkData, [0xDE, 0xAD, 0xBE, 0xEF]);
    expect(toHex(chunk.encode()), goldenChunkHex);
  });

  test('decodifica la oferta golden con todos los campos', () {
    final frame = TransferFrame.decode(fromHex(goldenOfferHex));
    expect(frame, isNotNull);
    expect(frame!.type, TransferProtocol.typeOffer);
    expect(frame.utf8Value(TransferProtocol.tagFileName), 'foto.jpg');
    expect(frame.utf8Value(TransferProtocol.tagMimeType), 'image/jpeg');
    expect(frame.u64(TransferProtocol.tagFileSize), 1048576);
    expect(frame.u32(TransferProtocol.tagChunkSize), 65536);
    expect(frame.u32(TransferProtocol.tagTransports), 7);
    expect(frame.u64(TransferProtocol.tagExpiresAt), 1765000000000);
    expect(frame.bytes(TransferProtocol.tagSha256), hasLength(32));
    expect(frame.bytes(TransferProtocol.tagSignature), hasLength(64));
  });

  test('rechaza versiones desconocidas y tramas truncadas', () {
    final bad = fromHex(goldenOfferHex);
    bad[0] = 0x02;
    expect(TransferFrame.decode(bad), isNull);
    expect(
      TransferFrame.decode(
        Uint8List.sublistView(fromHex(goldenOfferHex), 0, 10),
      ),
      isNull,
    );
  });

  test('sanea nombres de archivo peligrosos', () {
    expect(sanitizeFileName('../../etc/passwd'), 'passwd');
    expect(sanitizeFileName(r'C:\Users\x\foto.jpg'), 'foto.jpg');
    expect(sanitizeFileName('linda\x00foto.jpg'), 'lindafoto.jpg');
    expect(sanitizeFileName(''), 'archivo');
    expect(sanitizeFileName('a' * 400).length, lessThanOrEqualTo(255));
  });
}
