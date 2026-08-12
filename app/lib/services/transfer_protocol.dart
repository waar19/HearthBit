import 'dart:convert';
import 'dart:typed_data';

/// Codec del HearthBit Transfer Protocol (HBT) v1.
///
/// Formato: `[versión u8][tipo u8][TLV...]` con TLV `[tag u8][len u16][valor]`
/// en big-endian y tags codificados en orden ascendente para que los vectores
/// golden sean idénticos en Dart, Kotlin y Swift.
/// Ver `docs/transfer-protocol.md`.
class TransferProtocol {
  static const int version = 0x01;

  // Tipos de trama.
  static const int typeOffer = 0x01;
  static const int typeAccept = 0x02;
  static const int typeReject = 0x03;
  static const int typeTransportHint = 0x04;
  static const int typeProgress = 0x05;
  static const int typeComplete = 0x06;
  static const int typeCancel = 0x07;
  static const int typeResumeRequest = 0x08;
  static const int typeDataChunk = 0x10;
  static const int typeDataAck = 0x11;

  // Tags TLV.
  static const int tagTransferId = 0x01;
  static const int tagFileName = 0x02;
  static const int tagMimeType = 0x03;
  static const int tagFileSize = 0x04;
  static const int tagSha256 = 0x05;
  static const int tagChunkSize = 0x06;
  static const int tagTransports = 0x07;
  static const int tagEphemeralKey = 0x08;
  static const int tagExpiresAt = 0x09;
  static const int tagSenderPeerId = 0x0A;
  static const int tagSignature = 0x0B;
  static const int tagTransport = 0x0C;
  static const int tagEndpoint = 0x0D;
  static const int tagToken = 0x0E;
  static const int tagChunkIndex = 0x0F;
  static const int tagChunkData = 0x10;
  static const int tagChunkBitmap = 0x11;
  static const int tagReason = 0x12;
  static const int tagReceivedCount = 0x14;

  // Máscara TRANSPORTS.
  static const int transportBle = 1;
  static const int transportLan = 2;
  static const int transportNearby = 4;
  static const int transportWifiAware = 8;
  static const int transportOptical = 16;

  // Valores del tag TRANSPORT.
  static const int transportIdBle = 0;
  static const int transportIdLan = 1;
  static const int transportIdNearby = 2;
  static const int transportIdWifiAware = 3;
  static const int transportIdOptical = 4;
}

/// Trama HBT genérica: tipo + campos TLV indexados por tag.
class TransferFrame {
  TransferFrame(this.type, [Map<int, Uint8List>? tags])
    : tags = tags ?? <int, Uint8List>{};

  final int type;
  final Map<int, Uint8List> tags;

  static TransferFrame? decode(Uint8List input) {
    if (input.length < 2 || input[0] != TransferProtocol.version) return null;
    final frame = TransferFrame(input[1]);
    var offset = 2;
    while (offset + 3 <= input.length) {
      final tag = input[offset];
      final length = (input[offset + 1] << 8) | input[offset + 2];
      offset += 3;
      if (offset + length > input.length) return null;
      frame.tags[tag] = Uint8List.sublistView(input, offset, offset + length);
      offset += length;
    }
    return offset == input.length ? frame : null;
  }

  Uint8List encode() {
    final builder = BytesBuilder(copy: false)
      ..addByte(TransferProtocol.version)
      ..addByte(type);
    final orderedTags = tags.keys.toList()..sort();
    for (final tag in orderedTags) {
      final value = tags[tag]!;
      if (value.length > 0xFFFF) {
        throw ArgumentError('TLV $tag excede 65535 bytes');
      }
      builder
        ..addByte(tag)
        ..addByte(value.length >> 8)
        ..addByte(value.length & 0xFF)
        ..add(value);
    }
    return builder.toBytes();
  }

  /// Bytes que cubre la firma Ed25519: la trama sin el TLV SIGNATURE.
  Uint8List signedBytes() {
    final unsigned = TransferFrame(
      type,
      Map.of(tags)..remove(TransferProtocol.tagSignature),
    );
    return unsigned.encode();
  }

  // Helpers de acceso tipado.
  Uint8List? bytes(int tag) => tags[tag];

  String? utf8Value(int tag) {
    final value = tags[tag];
    return value == null ? null : utf8.decode(value);
  }

  int? u8(int tag) {
    final value = tags[tag];
    return (value == null || value.length != 1) ? null : value[0];
  }

  int? u32(int tag) {
    final value = tags[tag];
    if (value == null || value.length != 4) return null;
    return ByteData.sublistView(value).getUint32(0);
  }

  int? u64(int tag) {
    final value = tags[tag];
    if (value == null || value.length != 8) return null;
    return ByteData.sublistView(value).getUint64(0);
  }

  // Helpers de escritura.
  void setBytes(int tag, List<int> value) {
    tags[tag] = Uint8List.fromList(value);
  }

  void setUtf8(int tag, String value) {
    tags[tag] = Uint8List.fromList(utf8.encode(value));
  }

  void setU8(int tag, int value) {
    tags[tag] = Uint8List.fromList([value & 0xFF]);
  }

  void setU32(int tag, int value) {
    tags[tag] = Uint8List(4)..buffer.asByteData().setUint32(0, value);
  }

  void setU64(int tag, int value) {
    tags[tag] = Uint8List(8)..buffer.asByteData().setUint64(0, value);
  }
}

/// Sanea nombres de archivo recibidos: sin rutas, sin caracteres de control,
/// máximo 255 bytes UTF-8 y nunca vacío.
String sanitizeFileName(String raw) {
  final withoutPath = raw.split(RegExp(r'[/\\]')).last;
  final cleaned = withoutPath
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
      .replaceAll('..', '_')
      .trim();
  if (cleaned.isEmpty || cleaned == '.') return 'archivo';
  var bytes = utf8.encode(cleaned);
  if (bytes.length <= 255) return cleaned;
  var cut = cleaned.length;
  while (cut > 0 && utf8.encode(cleaned.substring(0, cut)).length > 255) {
    cut -= 1;
  }
  return cleaned.substring(0, cut);
}
