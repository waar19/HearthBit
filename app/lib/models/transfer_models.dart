import 'dart:typed_data';

enum TransferDirection { outgoing, incoming }

enum TransferState {
  /// Oferta enviada (saliente) o recibida sin responder (entrante).
  offered,
  connecting,
  transferring,
  completed,
  rejected,
  cancelled,
  failed,
}

enum TransferTransport {
  ble,
  lan,
  nearby,
  wifiAware,
  optical,
  wifiDirect,
  multipeer,
  external,
}

class TransferRecord {
  TransferRecord({
    required this.id,
    required this.peerId,
    required this.peerNickname,
    required this.direction,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.sha256Hex,
    required this.chunkSize,
    required this.state,
    this.transport,
    this.bytesDone = 0,
    this.filePath,
    this.error,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  factory TransferRecord.fromDatabase(Map<String, Object?> map) {
    return TransferRecord(
      id: map['id']! as String,
      peerId: map['peer_id']! as String,
      peerNickname: map['peer_nickname']! as String,
      direction: TransferDirection.values[map['direction']! as int],
      fileName: map['file_name']! as String,
      mimeType: map['mime_type']! as String,
      fileSize: map['file_size']! as int,
      sha256Hex: map['sha256']! as String,
      chunkSize: map['chunk_size']! as int,
      state: TransferState.values[map['state']! as int],
      transport: map['transport'] == null
          ? null
          : TransferTransport.values[map['transport']! as int],
      bytesDone: map['bytes_done'] as int? ?? 0,
      filePath: map['file_path'] as String?,
      error: map['error'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at']! as int),
    );
  }

  final String id;
  final String peerId;
  final String peerNickname;
  final TransferDirection direction;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String sha256Hex;
  final int chunkSize;
  TransferState state;
  TransferTransport? transport;
  int bytesDone;
  String? filePath;
  String? error;
  final DateTime createdAt;
  DateTime updatedAt;

  int get chunkCount =>
      fileSize == 0 ? 0 : (fileSize + chunkSize - 1) ~/ chunkSize;

  bool get isActive =>
      state == TransferState.offered ||
      state == TransferState.connecting ||
      state == TransferState.transferring;

  double get progress =>
      fileSize == 0 ? 0 : (bytesDone / fileSize).clamp(0.0, 1.0).toDouble();

  Map<String, Object?> toDatabase() => {
    'id': id,
    'peer_id': peerId,
    'peer_nickname': peerNickname,
    'direction': direction.index,
    'file_name': fileName,
    'mime_type': mimeType,
    'file_size': fileSize,
    'sha256': sha256Hex,
    'chunk_size': chunkSize,
    'state': state.index,
    'transport': transport?.index,
    'bytes_done': bytesDone,
    'file_path': filePath,
    'error': error,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };
}

/// Bitmap de chunks recibidos: un bit por chunk, LSB primero en cada byte.
class ChunkBitmap {
  ChunkBitmap(this.length) : _bits = Uint8List((length + 7) ~/ 8);

  ChunkBitmap.fromBytes(this.length, Uint8List bytes)
    : _bits = Uint8List((length + 7) ~/ 8) {
    for (var i = 0; i < _bits.length && i < bytes.length; i++) {
      _bits[i] = bytes[i];
    }
  }

  final int length;
  final Uint8List _bits;

  bool operator [](int index) => (_bits[index >> 3] >> (index & 7)) & 1 == 1;

  void set(int index) {
    _bits[index >> 3] |= 1 << (index & 7);
  }

  int get count {
    var total = 0;
    for (var i = 0; i < length; i++) {
      if (this[i]) total += 1;
    }
    return total;
  }

  bool get isComplete => count == length;

  Iterable<int> get missing sync* {
    for (var i = 0; i < length; i++) {
      if (!this[i]) yield i;
    }
  }

  Uint8List toBytes() => Uint8List.fromList(_bits);
}
