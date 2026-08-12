import 'dart:convert';
import 'dart:typed_data';

/// Framing de los símbolos ópticos HearthBit (HBQ v1).
///
/// Cada QR contiene un símbolo en base64: o bien la cabecera (metadatos y
/// parámetros del código fountain, repetida periódicamente para que el
/// receptor pueda engancharse en cualquier momento) o bien un símbolo de
/// datos (índice + payload XOR). El `transferId` de 16 bytes coincide con el
/// formato HBT para poder confirmar por el backchannel BLE.
class OpticalProtocol {
  static const int version = 1;
  static const List<int> magic = [0x48, 0x42, 0x51, version]; // "HBQ" + v1
  static const int typeHeader = 0x00;
  static const int typeData = 0x01;
  static const int transferIdLength = 16;
  static const int sha256Length = 32;

  static String encodeHeader(OpticalHeader header) {
    final builder = BytesBuilder(copy: false)
      ..add(magic)
      ..addByte(typeHeader)
      ..add(header.transferId)
      ..add(_u32(header.seed))
      ..add(_u64(header.fileSize))
      ..add(_u16(header.chunkSize))
      ..add(_u32(header.chunkCount))
      ..add(header.sha256);
    final name = utf8.encode(header.fileName);
    builder
      ..addByte(name.length)
      ..add(name);
    final peer = ascii.encode(header.senderPeerId);
    builder
      ..addByte(peer.length)
      ..add(peer);
    return base64Encode(builder.takeBytes());
  }

  static String encodeData({
    required Uint8List transferId,
    required int symbolIndex,
    required Uint8List payload,
  }) {
    final builder = BytesBuilder(copy: false)
      ..add(magic)
      ..addByte(typeData)
      ..add(transferId)
      ..add(_u32(symbolIndex))
      ..add(payload);
    return base64Encode(builder.takeBytes());
  }

  /// Devuelve [OpticalHeader], [OpticalDataSymbol] o null si el contenido no
  /// es un símbolo HBQ válido.
  static Object? decode(String content) {
    Uint8List bytes;
    try {
      bytes = base64Decode(content);
    } on FormatException {
      return null;
    }
    if (bytes.length < magic.length + 1 + transferIdLength) return null;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return null;
    }
    final type = bytes[magic.length];
    var offset = magic.length + 1;
    final transferId = Uint8List.sublistView(
      bytes,
      offset,
      offset + transferIdLength,
    );
    offset += transferIdLength;
    switch (type) {
      case typeHeader:
        return _decodeHeader(bytes, offset, transferId);
      case typeData:
        if (bytes.length < offset + 4 + 1) return null;
        final view = ByteData.sublistView(bytes);
        final symbolIndex = view.getUint32(offset);
        offset += 4;
        return OpticalDataSymbol(
          transferId: Uint8List.fromList(transferId),
          symbolIndex: symbolIndex,
          payload: Uint8List.fromList(Uint8List.sublistView(bytes, offset)),
        );
      default:
        return null;
    }
  }

  static OpticalHeader? _decodeHeader(
    Uint8List bytes,
    int offset,
    Uint8List transferId,
  ) {
    // seed(4) + fileSize(8) + chunkSize(2) + chunkCount(4) + sha(32) + len(1)
    if (bytes.length < offset + 4 + 8 + 2 + 4 + sha256Length + 2) return null;
    final view = ByteData.sublistView(bytes);
    final seed = view.getUint32(offset);
    offset += 4;
    final fileSize = _readU64(view, offset);
    offset += 8;
    final chunkSize = view.getUint16(offset);
    offset += 2;
    final chunkCount = view.getUint32(offset);
    offset += 4;
    final sha256 = Uint8List.fromList(
      Uint8List.sublistView(bytes, offset, offset + sha256Length),
    );
    offset += sha256Length;
    final nameLength = bytes[offset];
    offset += 1;
    if (bytes.length < offset + nameLength + 1) return null;
    final fileName = utf8.decode(
      Uint8List.sublistView(bytes, offset, offset + nameLength),
      allowMalformed: true,
    );
    offset += nameLength;
    final peerLength = bytes[offset];
    offset += 1;
    if (bytes.length < offset + peerLength) return null;
    final senderPeerId = ascii.decode(
      Uint8List.sublistView(bytes, offset, offset + peerLength),
      allowInvalid: true,
    );
    if (chunkSize == 0 || chunkCount == 0 || fileSize <= 0) return null;
    return OpticalHeader(
      transferId: Uint8List.fromList(transferId),
      seed: seed,
      fileSize: fileSize,
      chunkSize: chunkSize,
      chunkCount: chunkCount,
      sha256: sha256,
      fileName: fileName,
      senderPeerId: senderPeerId,
    );
  }

  static Uint8List _u16(int value) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, value);

  static Uint8List _u32(int value) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, value);

  static Uint8List _u64(int value) {
    final bytes = Uint8List(8);
    final view = ByteData.sublistView(bytes);
    view.setUint32(0, value ~/ 0x100000000);
    view.setUint32(4, value & 0xffffffff);
    return bytes;
  }

  static int _readU64(ByteData view, int offset) =>
      view.getUint32(offset) * 0x100000000 + view.getUint32(offset + 4);
}

class OpticalHeader {
  OpticalHeader({
    required this.transferId,
    required this.seed,
    required this.fileSize,
    required this.chunkSize,
    required this.chunkCount,
    required this.sha256,
    required this.fileName,
    this.senderPeerId = '',
  });

  final Uint8List transferId;
  final int seed;
  final int fileSize;
  final int chunkSize;
  final int chunkCount;
  final Uint8List sha256;
  final String fileName;

  /// Peer ID de malla del emisor (hex); vacío si no ofrece backchannel BLE.
  final String senderPeerId;
}

class OpticalDataSymbol {
  OpticalDataSymbol({
    required this.transferId,
    required this.symbolIndex,
    required this.payload,
  });

  final Uint8List transferId;
  final int symbolIndex;
  final Uint8List payload;
}
