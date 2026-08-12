// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:hearth_bit/services/transfer_protocol.dart';

String hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final offer = TransferFrame(TransferProtocol.typeOffer)
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

  final chunk = TransferFrame(TransferProtocol.typeDataChunk)
    ..setBytes(TransferProtocol.tagTransferId, [
      for (var i = 0; i < 16; i++) (i * 0x11) & 0xFF,
    ])
    ..setU32(TransferProtocol.tagChunkIndex, 3)
    ..setBytes(TransferProtocol.tagChunkData, [0xDE, 0xAD, 0xBE, 0xEF]);

  print('OFFER=${hex(offer.encode())}');
  print('SIGNED=${hex(offer.signedBytes())}');
  print('CHUNK=${hex(chunk.encode())}');
}
