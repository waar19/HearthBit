import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../models/transfer_models.dart';
import 'transfer_crypto.dart';

/// Transporte LAN/hotspot: TCP directo entre los dos teléfonos.
///
/// La señalización (IP, puerto y token) viaja por BLE dentro de Noise, y el
/// contenido va cifrado chunk a chunk con XChaCha20-Poly1305, así que no se
/// depende de TLS ni de certificados: la LAN solo ve bytes opacos.
///
/// Protocolo del socket (big-endian):
/// 1. receptor → emisor: token (16 bytes) + [u32 largoBitmap][bitmap]
/// 2. emisor → receptor: por cada chunk faltante [u32 índice][u32 largo][cifrado]
/// 3. emisor → receptor: índice terminador 0xFFFFFFFF
/// 4. receptor → emisor: 0x01 si el archivo quedó completo y verificado
class LanSender {
  LanSender({
    required this.transferId,
    required this.sourceFile,
    required this.chunkSize,
    required this.cipher,
    required this.token,
    this.onProgress,
    this.throttle,
  });

  final String transferId;
  final File sourceFile;
  final int chunkSize;
  final TransferCipher cipher;
  final Uint8List token;
  final void Function(int bytesSent)? onProgress;
  final Future<void> Function()? throttle;

  ServerSocket? _server;

  /// Abre el servidor y devuelve `ip:puerto` alcanzables en la LAN.
  Future<String> listen() async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    unawaited(_acceptLoop(server));
    final ip = await _localIpv4();
    return '$ip:${server.port}';
  }

  final Completer<bool> done = Completer<bool>();

  Future<void> close() async {
    await _server?.close();
    _server = null;
  }

  Future<void> _acceptLoop(ServerSocket server) async {
    try {
      final socket = await server.first.timeout(const Duration(seconds: 30));
      await _serve(socket);
    } catch (error) {
      if (!done.isCompleted) done.completeError(error);
    } finally {
      await close();
    }
  }

  Future<void> _serve(Socket socket) async {
    socket.setOption(SocketOption.tcpNoDelay, true);
    final reader = _SocketReader(socket);
    final received = await reader.read(16);
    if (!_constantTimeEquals(received, token)) {
      socket.destroy();
      throw const SocketException('Invalid LAN token');
    }
    final bitmapLength = ByteData.sublistView(
      await reader.read(4),
    ).getUint32(0);
    if (bitmapLength > 1 << 20) {
      socket.destroy();
      throw const SocketException('LAN bitmap too large');
    }
    final fileSize = await sourceFile.length();
    final chunkCount = (fileSize + chunkSize - 1) ~/ chunkSize;
    final bitmap = ChunkBitmap.fromBytes(
      chunkCount,
      await reader.read(bitmapLength),
    );

    final raf = await sourceFile.open();
    var sent = 0;
    try {
      for (final index in bitmap.missing) {
        await raf.setPosition(index * chunkSize);
        final plain = await raf.read(
          index == chunkCount - 1 ? fileSize - index * chunkSize : chunkSize,
        );
        final encrypted = await cipher.encryptChunk(index, plain);
        final header = Uint8List(8);
        ByteData.sublistView(header)
          ..setUint32(0, index)
          ..setUint32(4, encrypted.length);
        socket.add(header);
        socket.add(encrypted);
        sent += plain.length;
        onProgress?.call(sent);
        if (throttle != null) await throttle!();
      }
      final terminator = Uint8List(4)
        ..buffer.asByteData().setUint32(0, 0xFFFFFFFF);
      socket.add(terminator);
      await socket.flush();
      final ack = await reader.read(1).timeout(const Duration(seconds: 60));
      if (!done.isCompleted) done.complete(ack[0] == 0x01);
    } finally {
      await raf.close();
      socket.destroy();
    }
  }
}

class LanReceiver {
  LanReceiver({
    required this.transferId,
    required this.destinationFile,
    required this.fileSize,
    required this.chunkSize,
    required this.cipher,
    required this.token,
    required this.bitmap,
    this.onProgress,
  });

  final String transferId;
  final File destinationFile;
  final int fileSize;
  final int chunkSize;
  final TransferCipher cipher;
  final Uint8List token;
  final ChunkBitmap bitmap;
  final void Function(int bytesReceived, ChunkBitmap bitmap)? onProgress;

  /// Se conecta al emisor, descarga los chunks faltantes y devuelve `true`
  /// si el bitmap quedó completo.
  Future<bool> receive(String endpoint) async {
    final separator = endpoint.lastIndexOf(':');
    final host = endpoint.substring(0, separator);
    final port = int.parse(endpoint.substring(separator + 1));
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 15),
    );
    socket.setOption(SocketOption.tcpNoDelay, true);
    final reader = _SocketReader(socket);
    try {
      socket.add(token);
      final bitmapBytes = bitmap.toBytes();
      final header = Uint8List(4)
        ..buffer.asByteData().setUint32(0, bitmapBytes.length);
      socket.add(header);
      socket.add(bitmapBytes);
      await socket.flush();

      final raf = await destinationFile.open(mode: FileMode.writeOnlyAppend);
      try {
        if (await raf.length() < fileSize) {
          await raf.truncate(fileSize);
        }
        var receivedBytes = bitmap.count * chunkSize;
        while (true) {
          final indexBytes = await reader
              .read(4)
              .timeout(const Duration(seconds: 60));
          final index = ByteData.sublistView(indexBytes).getUint32(0);
          if (index == 0xFFFFFFFF) break;
          final length = ByteData.sublistView(
            await reader.read(4),
          ).getUint32(0);
          if (index >= bitmap.length || length > chunkSize + 64) {
            throw const SocketException('LAN chunk out of range');
          }
          final encrypted = await reader.read(length);
          final plain = await cipher.decryptChunk(index, encrypted);
          await raf.setPosition(index * chunkSize);
          await raf.writeFrom(plain);
          bitmap.set(index);
          receivedBytes += plain.length;
          onProgress?.call(receivedBytes, bitmap);
        }
        await raf.flush();
      } finally {
        await raf.close();
      }
      final complete = bitmap.isComplete;
      socket.add([complete ? 0x01 : 0x00]);
      await socket.flush();
      return complete;
    } finally {
      socket.destroy();
    }
  }
}

Future<String> _localIpv4() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (!address.isLoopback) return address.address;
    }
  }
  throw const SocketException('No IPv4 address on the local network');
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

/// Lector con búfer sobre un [Socket] para leer cantidades exactas de bytes.
class _SocketReader {
  _SocketReader(Socket socket) {
    _subscription = socket.listen(
      (data) {
        _buffer.add(data);
        _bufferedBytes += data.length;
        _tryComplete();
      },
      onDone: () {
        _closed = true;
        _tryComplete();
      },
      onError: (Object error) {
        _closed = true;
        _pendingError = error;
        _tryComplete();
      },
    );
  }

  final List<List<int>> _buffer = [];
  int _bufferedBytes = 0;
  bool _closed = false;
  Object? _pendingError;
  Completer<Uint8List>? _pending;
  int _pendingLength = 0;
  late final StreamSubscription<List<int>> _subscription;

  Future<Uint8List> read(int length) {
    assert(_pending == null, 'lectura concurrente');
    final completer = Completer<Uint8List>();
    _pending = completer;
    _pendingLength = length;
    _tryComplete();
    return completer.future;
  }

  void _tryComplete() {
    final pending = _pending;
    if (pending == null) return;
    if (_bufferedBytes >= _pendingLength) {
      final output = Uint8List(_pendingLength);
      var offset = 0;
      while (offset < _pendingLength) {
        final head = _buffer.first;
        final take = (_pendingLength - offset).clamp(0, head.length);
        output.setRange(offset, offset + take, head);
        offset += take;
        if (take == head.length) {
          _buffer.removeAt(0);
        } else {
          _buffer[0] = head.sublist(take);
        }
      }
      _bufferedBytes -= _pendingLength;
      _pending = null;
      pending.complete(output);
    } else if (_closed) {
      _pending = null;
      _subscription.cancel();
      pending.completeError(
        _pendingError ?? const SocketException('LAN connection closed'),
      );
    }
  }
}
