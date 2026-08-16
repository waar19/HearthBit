import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum HbtPackageKind { exchange, sealed }

class HbtPackageHeader {
  const HbtPackageHeader({
    required this.kind,
    required this.transferId,
    required this.payloadOffset,
    required this.payloadLength,
  });

  final HbtPackageKind kind;
  final Uint8List transferId;
  final int payloadOffset;
  final int payloadLength;
}

/// Formatos de archivo transportables por share sheet.
///
/// HBTX conserva el contenedor cifrado de una sesión OFFER/ACCEPT. HBTS se
/// implementa sobre una cabecera propia en `sealed_transfer_package.dart`.
abstract final class HbtPackageProtocol {
  static const String mimeType = 'application/x-hearthbit';
  static const String extension = '.hbt';
  static const int version = 1;
  static const int exchangeHeaderLength = 4 + 1 + 16 + 8;
  static const int maximumPackageBytes = 700 * 1024 * 1024;
  static final Uint8List _exchangeMagic = Uint8List.fromList(
    ascii.encode('HBTX'),
  );
  static final Uint8List _sealedMagic = Uint8List.fromList(
    ascii.encode('HBTS'),
  );

  static Future<File> writeExchange({
    required File container,
    required Uint8List transferId,
    required File destination,
  }) async {
    if (transferId.length != 16) {
      throw const FormatException('HBTX transferId must be 16 bytes');
    }
    final length = await container.length();
    if (length <= 0 || length + exchangeHeaderLength > maximumPackageBytes) {
      throw const FormatException('HBTX payload size is invalid');
    }
    final header = Uint8List(exchangeHeaderLength);
    header.setRange(0, 4, _exchangeMagic);
    header[4] = version;
    header.setRange(5, 21, transferId);
    ByteData.sublistView(header).setUint64(21, length);
    final sink = destination.openWrite();
    try {
      sink.add(header);
      await sink.addStream(container.openRead());
      await sink.flush();
    } finally {
      await sink.close();
    }
    return destination;
  }

  static Future<HbtPackageHeader> inspect(File package) async {
    final total = await package.length();
    if (total < 5 || total > maximumPackageBytes) {
      throw const FormatException('Invalid HBT package size');
    }
    final prefix = await package
        .openRead(0, exchangeHeaderLength)
        .fold(
          BytesBuilder(copy: false),
          (builder, chunk) => builder..add(chunk),
        );
    final bytes = prefix.toBytes();
    if (bytes.length < 5 || bytes[4] != version) {
      throw const FormatException('Unsupported HBT package version');
    }
    if (_startsWith(bytes, _exchangeMagic)) {
      if (bytes.length != exchangeHeaderLength) {
        throw const FormatException('Truncated HBTX header');
      }
      final payloadLength = ByteData.sublistView(bytes).getUint64(21);
      if (payloadLength <= 0 || payloadLength + exchangeHeaderLength != total) {
        throw const FormatException('Invalid HBTX payload length');
      }
      return HbtPackageHeader(
        kind: HbtPackageKind.exchange,
        transferId: Uint8List.fromList(bytes.sublist(5, 21)),
        payloadOffset: exchangeHeaderLength,
        payloadLength: payloadLength,
      );
    }
    if (_startsWith(bytes, _sealedMagic)) {
      return HbtPackageHeader(
        kind: HbtPackageKind.sealed,
        transferId: Uint8List(0),
        payloadOffset: 0,
        payloadLength: total,
      );
    }
    throw const FormatException('Unknown HBT package magic');
  }

  static Future<File> extractExchange({
    required File package,
    required HbtPackageHeader header,
    required File destination,
  }) async {
    if (header.kind != HbtPackageKind.exchange) {
      throw const FormatException('Expected HBTX package');
    }
    final sink = destination.openWrite();
    try {
      await sink.addStream(
        package.openRead(
          header.payloadOffset,
          header.payloadOffset + header.payloadLength,
        ),
      );
      await sink.flush();
    } finally {
      await sink.close();
    }
    return destination;
  }

  static bool _startsWith(Uint8List value, Uint8List prefix) {
    if (value.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (value[i] != prefix[i]) return false;
    }
    return true;
  }
}
