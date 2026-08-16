import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/controllers/transfer_controller.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/models/transfer_models.dart';
import 'package:hearth_bit/services/mesh_platform_service.dart';
import 'package:hearth_bit/services/hbt_package.dart';
import 'package:hearth_bit/services/transfer_crypto.dart';
import 'package:hearth_bit/services/transfer_platform_service.dart';
import 'package:hearth_bit/services/transfer_protocol.dart';
import 'package:hearth_bit/services/transfer_repository.dart';

class _MeshPlatform extends MeshPlatformService {
  final eventsController = StreamController<Map<Object?, Object?>>.broadcast();
  final sentFrames = <Uint8List>[];
  var failFrameSend = false;
  var verifySignatures = true;

  @override
  Stream<Map<Object?, Object?>> get events => eventsController.stream;

  @override
  Future<void> sendTransferFrame(String peerId, Uint8List frame) async {
    if (failFrameSend) throw StateError('peer unavailable');
    sentFrames.add(Uint8List.fromList(frame));
  }

  @override
  Future<Uint8List> signPayload(Uint8List data) async =>
      Uint8List.fromList(List.filled(64, 7));

  @override
  Future<bool> verifyPeerSignature(
    String peerId,
    Uint8List data,
    Uint8List signature,
  ) async => verifySignatures;
}

class _TransferPlatform extends TransferPlatformService {
  _TransferPlatform({
    this.nearby = false,
    this.wifiAware = false,
    this.wifiDirect = false,
    this.multipeer = false,
  });

  final eventsController = StreamController<Map<Object?, Object?>>.broadcast();
  final bool nearby;
  final bool wifiAware;
  final bool wifiDirect;
  final bool multipeer;
  final nearbyReceives = <String>[];
  final wifiDirectReceives = <String>[];
  final multipeerReceives = <String>[];
  final stopped = <String>[];

  @override
  Stream<Map<Object?, Object?>> get events => eventsController.stream;

  @override
  Future<Map<Object?, Object?>> getTransferCapabilities() async => {
    'nearby': nearby,
    'wifiAware': wifiAware,
    'wifiDirect': wifiDirect,
    'multipeer': multipeer,
  };

  @override
  Future<void> nearbyReceiveFile({
    required String peerId,
    required String transferId,
    required String destinationPath,
  }) async {
    nearbyReceives.add(transferId);
  }

  @override
  Future<void> nearbyStop(String transferId) async {
    stopped.add('nearby:$transferId');
  }

  @override
  Future<void> wifiAwareStop(String transferId) async {
    stopped.add('wifiAware:$transferId');
  }

  @override
  Future<void> wifiDirectReceiveFile({
    required String transferId,
    required String destinationPath,
  }) async {
    wifiDirectReceives.add(transferId);
  }

  @override
  Future<void> multipeerReceiveFile({
    required String transferId,
    required String destinationPath,
  }) async {
    multipeerReceives.add(transferId);
  }

  @override
  Future<void> wifiDirectStop(String transferId) async {
    stopped.add('wifiDirect:$transferId');
  }

  @override
  Future<void> multipeerStop(String transferId) async {
    stopped.add('multipeer:$transferId');
  }
}

class _MemoryTransferRepository extends TransferRepository {
  _MemoryTransferRepository([Iterable<TransferRecord> records = const []])
    : records = {for (final record in records) record.id: record};

  final Map<String, TransferRecord> records;
  final Map<String, Uint8List> bitmaps = {};
  final Map<String, TransferResumeMaterial> materials = {};

  @override
  Future<List<TransferRecord>> load() async => records.values.toList();

  @override
  Future<void> save(
    TransferRecord record, {
    Uint8List? bitmap,
    TransferResumeMaterial? resumeMaterial,
    bool clearResumeMaterial = false,
    bool clearBitmap = false,
  }) async {
    records[record.id] = record;
    if (bitmap != null) bitmaps[record.id] = Uint8List.fromList(bitmap);
    if (resumeMaterial != null) materials[record.id] = resumeMaterial;
    if (clearBitmap) bitmaps.remove(record.id);
    if (clearResumeMaterial) materials.remove(record.id);
  }

  @override
  Future<Uint8List?> loadBitmap(String id) async => bitmaps[id];

  @override
  Future<TransferResumeMaterial?> loadResumeMaterial(String id) async =>
      materials[id];

  @override
  Future<void> delete(String id) async {
    records.remove(id);
    bitmaps.remove(id);
    materials.remove(id);
  }

  @override
  Future<void> clear() async {
    records.clear();
    bitmaps.clear();
    materials.clear();
  }

  @override
  Future<void> destroy() async {
    records.clear();
    bitmaps.clear();
    materials.clear();
  }
}

MeshPeer _peer({bool supportsTransfers = true}) => MeshPeer(
  id: 'peer-12345678',
  nickname: 'Rescuer',
  lastSeen: DateTime.now(),
  secure: true,
  supportsTransfers: supportsTransfers,
);

Future<TransferFrame> _offerFrame({
  required int transports,
  String mimeType = 'application/octet-stream',
  int fileSize = 1024,
}) async {
  final keyPair = await TransferCrypto.generateEphemeralKeyPair();
  return TransferFrame(TransferProtocol.typeOffer)
    ..setBytes(
      TransferProtocol.tagTransferId,
      Uint8List.fromList(List.generate(16, (index) => index + 1)),
    )
    ..setUtf8(TransferProtocol.tagFileName, 'rescue.bin')
    ..setUtf8(TransferProtocol.tagMimeType, mimeType)
    ..setU64(TransferProtocol.tagFileSize, fileSize)
    ..setBytes(TransferProtocol.tagSha256, Uint8List(32))
    ..setU32(TransferProtocol.tagChunkSize, 350)
    ..setU32(TransferProtocol.tagTransports, transports)
    ..setBytes(
      TransferProtocol.tagEphemeralKey,
      await TransferCrypto.publicKeyBytes(keyPair),
    )
    ..setU64(
      TransferProtocol.tagExpiresAt,
      DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
    )
    ..setBytes(
      TransferProtocol.tagSignature,
      Uint8List.fromList(List.filled(64, 9)),
    );
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late _MeshPlatform mesh;
  late _TransferPlatform platform;
  late _MemoryTransferRepository repository;
  late TransferController controller;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'hearthbit-transfer-test-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => temporaryDirectory.path,
        );
    mesh = _MeshPlatform();
    platform = _TransferPlatform(wifiAware: true);
    repository = _MemoryTransferRepository();
    controller = TransferController(
      mesh,
      platform: platform,
      repository: repository,
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await mesh.eventsController.close();
    await platform.eventsController.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('offers a file with the supported transport flags', () async {
    final file = File('${temporaryDirectory.path}/report.txt');
    await file.writeAsString('safe status report');

    final id = await controller.sendFile(
      peer: _peer(),
      filePath: file.path,
      fileName: '../report.txt',
    );

    expect(controller.transfers, hasLength(1));
    final record = controller.transfers.single;
    expect(record.id, id);
    expect(record.fileName, 'report.txt');
    expect(record.state, TransferState.offered);
    expect(record.chunkSize, TransferController.bleChunkSize);

    final frame = TransferFrame.decode(mesh.sentFrames.single)!;
    final transports = frame.u32(TransferProtocol.tagTransports)!;
    expect(transports & TransferProtocol.transportLan, isNonZero);
    expect(transports & TransferProtocol.transportBle, isNonZero);
    expect(transports & TransferProtocol.transportNearby, isZero);
    expect(transports & TransferProtocol.transportWifiAware, isNonZero);
    expect(transports & TransferProtocol.transportWifiDirect, isZero);
    expect(transports & TransferProtocol.transportMultipeer, isZero);
    expect(transports & TransferProtocol.transportExternal, isNonZero);
  });

  test('rejects unsupported peers and empty files', () async {
    final file = File('${temporaryDirectory.path}/empty.bin');
    await file.create();

    expect(
      () => controller.sendFile(
        peer: _peer(supportsTransfers: false),
        filePath: file.path,
        fileName: 'empty.bin',
      ),
      throwsStateError,
    );
    expect(
      () => controller.sendFile(
        peer: _peer(),
        filePath: file.path,
        fileName: 'empty.bin',
      ),
      throwsStateError,
    );
  });

  test('accepts an incoming offer and prefers LAN', () async {
    final offer = await _offerFrame(
      transports:
          TransferProtocol.transportLan |
          TransferProtocol.transportNearby |
          TransferProtocol.transportBle,
    );
    mesh.eventsController.add({
      'type': 'transferFrame',
      'peerId': _peer().id,
      'frame': offer.encode(),
    });
    await pumpEventQueue();

    final record = controller.transfers.single;
    await controller.acceptOffer(record.id);

    expect(record.state, TransferState.connecting);
    expect(record.transport, TransferTransport.lan);
    expect(
      TransferFrame.decode(mesh.sentFrames.last)!.type,
      TransferProtocol.typeAccept,
    );
  });

  test('uses Nearby when it is the only offered available transport', () async {
    controller.dispose();
    await platform.eventsController.close();
    platform = _TransferPlatform(nearby: true);
    controller = TransferController(
      mesh,
      platform: platform,
      repository: repository,
    );
    await controller.initialize();
    final offer = await _offerFrame(
      transports: TransferProtocol.transportNearby,
    );
    mesh.eventsController.add({
      'type': 'transferFrame',
      'peerId': _peer().id,
      'frame': offer.encode(),
    });
    await pumpEventQueue();

    final record = controller.transfers.single;
    await controller.acceptOffer(record.id);

    expect(record.transport, TransferTransport.nearby);
    expect(platform.nearbyReceives, [record.id]);
  });

  test('selects Wi-Fi Direct and Multipeer when each is available', () async {
    controller.dispose();
    await platform.eventsController.close();
    platform = _TransferPlatform(wifiDirect: true, multipeer: true);
    controller = TransferController(
      mesh,
      platform: platform,
      repository: repository,
    );
    await controller.initialize();
    final directOffer = await _offerFrame(
      transports:
          TransferProtocol.transportWifiDirect |
          TransferProtocol.transportMultipeer,
    );
    mesh.eventsController.add({
      'type': 'transferFrame',
      'peerId': _peer().id,
      'frame': directOffer.encode(),
    });
    await pumpEventQueue();

    final record = controller.transfers.single;
    await controller.acceptOffer(record.id);

    expect(record.transport, TransferTransport.wifiDirect);
    expect(platform.wifiDirectReceives, [record.id]);

    platform.eventsController.add({
      'type': 'wifiDirectError',
      'transferId': record.id,
      'message': 'direct failed',
    });
    await _waitUntil(() => record.transport == TransferTransport.multipeer);
    expect(platform.multipeerReceives, [record.id]);
  });

  test('imports HBTX only after matching an accepted session', () async {
    final transferId = Uint8List.fromList(List.generate(16, (index) => index));
    final senderKey = await TransferCrypto.generateEphemeralKeyPair();
    final plaintext = Uint8List.fromList('share-sheet payload'.codeUnits);
    final digest = await TransferCrypto.hashBytes(plaintext);
    final offer = TransferFrame(TransferProtocol.typeOffer)
      ..setBytes(TransferProtocol.tagTransferId, transferId)
      ..setUtf8(TransferProtocol.tagFileName, 'share.txt')
      ..setUtf8(TransferProtocol.tagMimeType, 'text/plain')
      ..setU64(TransferProtocol.tagFileSize, plaintext.length)
      ..setBytes(TransferProtocol.tagSha256, digest)
      ..setU32(TransferProtocol.tagChunkSize, TransferController.bleChunkSize)
      ..setU32(
        TransferProtocol.tagTransports,
        TransferProtocol.transportExternal,
      )
      ..setBytes(
        TransferProtocol.tagEphemeralKey,
        await TransferCrypto.publicKeyBytes(senderKey),
      )
      ..setU64(
        TransferProtocol.tagExpiresAt,
        DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      )
      ..setBytes(TransferProtocol.tagSignature, Uint8List(64));
    mesh.eventsController.add({
      'type': 'transferFrame',
      'peerId': _peer().id,
      'frame': offer.encode(),
    });
    await pumpEventQueue();
    final record = controller.transfers.single;
    await controller.acceptOffer(
      record.id,
      preferredTransport: TransferTransport.external,
    );
    final accept = TransferFrame.decode(mesh.sentFrames.last)!;
    final senderCipher = await TransferCrypto.deriveCipher(
      localKeyPair: senderKey,
      remotePublicKey: accept.bytes(TransferProtocol.tagEphemeralKey)!,
      transferId: transferId,
    );
    final encrypted = await senderCipher.encryptChunk(0, plaintext);
    final container = File('${temporaryDirectory.path}/session.enc');
    final header = Uint8List(8);
    ByteData.sublistView(header)
      ..setUint32(0, 0)
      ..setUint32(4, encrypted.length);
    await container.writeAsBytes([...header, ...encrypted]);
    final package = File('${temporaryDirectory.path}/session.hbt');
    await HbtPackageProtocol.writeExchange(
      container: container,
      transferId: transferId,
      destination: package,
    );

    await controller.importHbtPackage(package.path);

    expect(record.state, TransferState.completed);
    expect(await File(record.filePath!).readAsString(), 'share-sheet payload');
  });

  test('prefers BLE and auto-accepts small incoming voice notes', () async {
    final offer = await _offerFrame(
      transports: TransferProtocol.transportLan | TransferProtocol.transportBle,
      mimeType: TransferController.voiceNoteMimeType,
      fileSize: 512,
    );
    mesh.eventsController.add({
      'type': 'transferFrame',
      'peerId': _peer().id,
      'frame': offer.encode(),
    });
    await _waitUntil(
      () =>
          controller.transfers.isNotEmpty &&
          controller.transfers.single.state == TransferState.connecting,
    );

    expect(controller.transfers.single.transport, TransferTransport.ble);
    expect(controller.transfers.single.state, TransferState.connecting);
  });

  test(
    'reject and cancel finish locally even when the peer disappears',
    () async {
      final file = File('${temporaryDirectory.path}/cancel.txt');
      await file.writeAsString('cancel me');
      final rejectId = await controller.sendFile(
        peer: _peer(),
        filePath: file.path,
        fileName: 'cancel.txt',
      );
      await controller.rejectOffer(rejectId, reason: 'not needed');
      expect(controller.transfers.first.state, TransferState.rejected);

      final cancelId = await controller.sendFile(
        peer: _peer(),
        filePath: file.path,
        fileName: 'cancel.txt',
      );
      mesh.failFrameSend = true;
      await controller.cancel(cancelId);
      expect(controller.transfers.first.state, TransferState.cancelled);
    },
  );

  test('expires outgoing offers using the configured lifetime', () async {
    controller.dispose();
    controller = TransferController(
      mesh,
      platform: platform,
      repository: repository,
      offerLifetime: const Duration(milliseconds: 10),
    );
    await controller.initialize();
    final file = File('${temporaryDirectory.path}/expiring.txt');
    await file.writeAsString('short lived');

    await controller.sendFile(
      peer: _peer(),
      filePath: file.path,
      fileName: 'expiring.txt',
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(controller.transfers.first.state, TransferState.failed);
    expect(controller.transfers.first.error, isNotEmpty);
  });

  test('marks interrupted persisted transfers as failed on startup', () async {
    final interrupted = TransferRecord(
      id: 'interrupted',
      peerId: 'peer',
      peerNickname: 'Peer',
      direction: TransferDirection.incoming,
      fileName: 'partial.bin',
      mimeType: 'application/octet-stream',
      fileSize: 100,
      sha256Hex: '00',
      chunkSize: 50,
      state: TransferState.transferring,
    );
    controller.dispose();
    repository = _MemoryTransferRepository([interrupted]);
    controller = TransferController(
      mesh,
      platform: platform,
      repository: repository,
    );

    await controller.initialize();

    expect(controller.transfers.single.state, TransferState.failed);
    expect(controller.transfers.single.error, isNotEmpty);
  });

  test('restaura sesión cifrada y solicita solo chunks faltantes', () async {
    final partial = File('${temporaryDirectory.path}/resume.part');
    await partial.writeAsBytes(Uint8List(400));
    const id = '00112233445566778899aabbccddeeff';
    final interrupted = TransferRecord(
      id: id,
      peerId: _peer().id,
      peerNickname: 'Rescuer',
      direction: TransferDirection.incoming,
      fileName: 'partial.bin',
      mimeType: 'application/octet-stream',
      fileSize: 400,
      sha256Hex: '00' * 32,
      chunkSize: 100,
      state: TransferState.transferring,
      transport: TransferTransport.ble,
      filePath: partial.path,
    );
    final local = await TransferCrypto.generateEphemeralKeyPair();
    final remote = await TransferCrypto.generateEphemeralKeyPair();
    final exported = await TransferCrypto.exportKeyPair(local);
    final bitmap = ChunkBitmap(4)
      ..set(0)
      ..set(2);

    controller.dispose();
    repository = _MemoryTransferRepository([interrupted])
      ..bitmaps[id] = bitmap.toBytes()
      ..materials[id] = TransferResumeMaterial(
        localPrivateKey: exported.privateKey,
        localPublicKey: exported.publicKey,
        remotePublicKey: await TransferCrypto.publicKeyBytes(remote),
        offeredTransports: TransferProtocol.transportBle,
      );
    mesh.sentFrames.clear();
    controller = TransferController(
      mesh,
      platform: platform,
      repository: repository,
    );

    await controller.initialize();

    expect(controller.transfers.single.state, TransferState.connecting);
    expect(controller.transfers.single.bytesDone, 200);
    final resume = TransferFrame.decode(mesh.sentFrames.single)!;
    expect(resume.type, TransferProtocol.typeResumeRequest);
    expect(resume.bytes(TransferProtocol.tagChunkBitmap), bitmap.toBytes());
    expect(
      resume.u8(TransferProtocol.tagTransport),
      TransferProtocol.transportIdBle,
    );
  });

  test('enforces BLE and voice-note size policy', () {
    expect(
      TransferController.allowsBleTransfer(
        mimeType: 'text/plain',
        bytes: TransferController.bleMaxInlineBytes,
      ),
      isTrue,
    );
    expect(
      TransferController.allowsBleTransfer(
        mimeType: 'text/plain',
        bytes: TransferController.bleMaxInlineBytes + 1,
      ),
      isFalse,
    );
    expect(
      TransferController.allowsBleTransfer(
        mimeType: TransferController.androidPackageMimeType,
        bytes: 100,
      ),
      isFalse,
    );
    expect(
      TransferController.isInlineVoiceNote(
        mimeType: TransferController.voiceNoteMimeType,
        bytes: TransferController.voiceNoteMaxBytes,
      ),
      isTrue,
    );
  });
}
