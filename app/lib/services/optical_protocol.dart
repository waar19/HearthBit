import 'dart:convert';
import 'dart:typed_data';

/// Framing de los símbolos ópticos HearthBit (HBQ v1/v2).
///
/// Cada QR contiene un símbolo en base64: o bien la cabecera (metadatos y
/// parámetros del código fountain, repetida periódicamente para que el
/// receptor pueda engancharse en cualquier momento) o bien un símbolo de
/// datos (índice + payload XOR). El `transferId` de 16 bytes coincide con el
/// formato HBT para poder confirmar por el backchannel BLE.
class OpticalProtocol {
  static const int legacyVersion = 1;
  static const int version = 2;
  static const List<int> magicPrefix = [0x48, 0x42, 0x51]; // "HBQ"
  static const List<int> magic = [...magicPrefix, version];
  static const int typeHeader = 0x00;
  static const int typeData = 0x01;
  static const int transferIdLength = 16;
  static const int sha256Length = 32;
  static const int signatureLength = 64;
  static const int maximumEncodedFrameLength = 32 * 1024;
  static const int maximumFileSize = 64 * 1024 * 1024;
  static const int maximumChunkSize = 4096;
  static const int maximumChunkCount = 262144;

  static String encodeHeader(OpticalHeader header) {
    final signature = header.signature;
    if (signature == null) return encodeLegacyHeader(header);
    if (signature.length != signatureLength) {
      throw ArgumentError.value(signature.length, 'signature');
    }
    return base64Encode(
      Uint8List.fromList([...signingPayload(header), ...signature]),
    );
  }

  static String encodeLegacyHeader(OpticalHeader header) {
    return base64Encode(_headerBytes(header, protocolVersion: legacyVersion));
  }

  /// Bytes canónicos que firma Ed25519 en HBQ v2.
  static Uint8List signingPayload(OpticalHeader header) =>
      _headerBytes(header, protocolVersion: version);

  static Uint8List _headerBytes(
    OpticalHeader header, {
    required int protocolVersion,
  }) {
    if (!_isCoherentHeader(header)) {
      throw ArgumentError('Incoherent or oversized optical header');
    }
    final builder = BytesBuilder(copy: false)
      ..add([...magicPrefix, protocolVersion])
      ..addByte(typeHeader)
      ..add(header.transferId)
      ..add(_u32(header.seed))
      ..add(_u64(header.fileSize))
      ..add(_u16(header.chunkSize))
      ..add(_u32(header.chunkCount))
      ..add(header.sha256);
    final name = utf8.encode(header.fileName);
    if (name.isEmpty || name.length > 255) {
      throw ArgumentError.value(header.fileName, 'fileName');
    }
    builder
      ..addByte(name.length)
      ..add(name);
    final peer = ascii.encode(header.senderPeerId);
    if (peer.length > 128) {
      throw ArgumentError.value(header.senderPeerId, 'senderPeerId');
    }
    builder
      ..addByte(peer.length)
      ..add(peer);
    return builder.takeBytes();
  }

  static String encodeData({
    required Uint8List transferId,
    required int symbolIndex,
    required Uint8List payload,
  }) {
    if (transferId.length != transferIdLength ||
        symbolIndex < 0 ||
        symbolIndex > 0xffffffff ||
        payload.isEmpty ||
        payload.length > maximumChunkSize) {
      throw ArgumentError('Invalid optical data symbol');
    }
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
    if (content.isEmpty || content.length > maximumEncodedFrameLength) {
      return null;
    }
    Uint8List bytes;
    try {
      bytes = base64Decode(content);
    } on FormatException {
      return null;
    }
    if (bytes.length < magic.length + 1 + transferIdLength) return null;
    for (var i = 0; i < magicPrefix.length; i++) {
      if (bytes[i] != magicPrefix[i]) return null;
    }
    final protocolVersion = bytes[magicPrefix.length];
    if (protocolVersion != legacyVersion && protocolVersion != version) {
      return null;
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
        return _decodeHeader(
          bytes,
          offset,
          transferId,
          protocolVersion: protocolVersion,
        );
      case typeData:
        if (protocolVersion != version && protocolVersion != legacyVersion) {
          return null;
        }
        if (bytes.length < offset + 4 + 1) return null;
        final view = ByteData.sublistView(bytes);
        final symbolIndex = view.getUint32(offset);
        offset += 4;
        final payloadLength = bytes.length - offset;
        if (payloadLength <= 0 || payloadLength > maximumChunkSize) return null;
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
    Uint8List transferId, {
    required int protocolVersion,
  }) {
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
    String fileName;
    try {
      fileName = utf8.decode(
        Uint8List.sublistView(bytes, offset, offset + nameLength),
      );
    } on FormatException {
      return null;
    }
    offset += nameLength;
    final peerLength = bytes[offset];
    offset += 1;
    if (bytes.length < offset + peerLength) return null;
    String senderPeerId;
    try {
      senderPeerId = ascii.decode(
        Uint8List.sublistView(bytes, offset, offset + peerLength),
      );
    } on FormatException {
      return null;
    }
    offset += peerLength;
    Uint8List? signature;
    if (protocolVersion == version) {
      if (bytes.length != offset + signatureLength) return null;
      signature = Uint8List.fromList(
        Uint8List.sublistView(bytes, offset, offset + signatureLength),
      );
    } else if (bytes.length != offset) {
      return null;
    }
    final header = OpticalHeader(
      transferId: Uint8List.fromList(transferId),
      seed: seed,
      fileSize: fileSize,
      chunkSize: chunkSize,
      chunkCount: chunkCount,
      sha256: sha256,
      fileName: fileName,
      senderPeerId: senderPeerId,
      protocolVersion: protocolVersion,
      signature: signature,
    );
    return _isCoherentHeader(header) ? header : null;
  }

  static bool _isCoherentHeader(OpticalHeader header) {
    final fileNameBytes = utf8.encode(header.fileName);
    final senderPeerId = header.senderPeerId;
    if (header.transferId.length != transferIdLength ||
        header.sha256.length != sha256Length ||
        fileNameBytes.isEmpty ||
        fileNameBytes.length > 255 ||
        (senderPeerId.isNotEmpty &&
            !RegExp(r'^[0-9a-fA-F]{8,128}$').hasMatch(senderPeerId)) ||
        header.fileSize <= 0 ||
        header.fileSize > maximumFileSize ||
        header.chunkSize <= 0 ||
        header.chunkSize > maximumChunkSize ||
        header.chunkCount <= 0 ||
        header.chunkCount > maximumChunkCount) {
      return false;
    }
    final expectedChunks =
        (header.fileSize + header.chunkSize - 1) ~/ header.chunkSize;
    return expectedChunks == header.chunkCount;
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
    this.protocolVersion = OpticalProtocol.legacyVersion,
    this.signature,
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
  final int protocolVersion;
  final Uint8List? signature;

  bool get isLegacy => protocolVersion == OpticalProtocol.legacyVersion;
  bool get isSigned => signature?.length == OpticalProtocol.signatureLength;
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
