import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../models/transfer_models.dart';
import '../services/diagnostics_log.dart';
import '../services/at_rest_file_cipher.dart';
import '../services/backup_protection.dart';
import '../services/lan_transport.dart';
import '../services/mesh_platform_service.dart';
import '../services/hbt_package.dart';
import '../services/hbt_share_service.dart';
import '../services/sealed_transfer_package.dart';
import '../services/transfer_crypto.dart';
import '../services/transfer_platform_service.dart';
import '../services/transfer_protocol.dart';
import '../services/transfer_repository.dart';

class PendingSealedImport {
  const PendingSealedImport({
    required this.packagePath,
    required this.metadata,
  });

  final String packagePath;
  final SealedPackageMetadata metadata;
}

/// Orquesta las transferencias de archivos: ofertas firmadas por BLE,
/// negociación de transporte multicanal y cifrado de extremo a extremo con
/// verificación SHA-256.
class TransferController extends ChangeNotifier {
  TransferController(
    this._mesh, {
    TransferPlatformService? platform,
    TransferRepository? repository,
    AtRestFileCipher? fileCipher,
    HbtShareService? shareService,
    this.offerLifetime = defaultOfferLifetime,
  }) : _platform = platform ?? TransferPlatformService(),
       _repository = repository ?? TransferRepository(),
       _fileCipher = fileCipher ?? AtRestFileCipher(),
       _shareService = shareService ?? HbtShareService();

  static const int bleChunkSize = 350;
  static const int bleMaxInlineBytes = 256 * 1024;
  static const int voiceNoteMaxBytes = 64 * 1024;
  static const int defaultChunkSize = 64 * 1024;
  static const int maxFileBytes = 512 * 1024 * 1024;
  static const int maximumTransfersInMemory = 200;
  static const Duration defaultOfferLifetime = Duration(minutes: 10);
  static const Duration priorityHold = Duration(seconds: 20);
  static const bool secureResumeSupported = true;
  static const String voiceNoteMimeType = 'audio/x-hearthbit-voice';
  static const String androidPackageMimeType =
      'application/vnd.android.package-archive';

  static bool isInlineVoiceNote({
    required String mimeType,
    required int bytes,
  }) =>
      mimeType == voiceNoteMimeType && bytes > 0 && bytes <= voiceNoteMaxBytes;

  static bool allowsBleTransfer({
    required String mimeType,
    required int bytes,
  }) =>
      mimeType != androidPackageMimeType &&
      bytes > 0 &&
      bytes <= bleMaxInlineBytes;

  /// Feature flag: Wi-Fi Aware es progresivo y puede desactivarse sin tocar
  /// el resto de transportes. QUIC sobre el data path queda para el futuro.
  static const bool wifiAwareFeatureFlag = true;

  final MeshPlatformService _mesh;
  final TransferPlatformService _platform;
  final TransferRepository _repository;
  final AtRestFileCipher _fileCipher;
  final HbtShareService _shareService;
  final Duration offerLifetime;

  final List<TransferRecord> _transfers = [];
  final Map<String, _TransferSession> _sessions = {};
  final Random _random = Random.secure();

  StreamSubscription<Map<Object?, Object?>>? _meshSubscription;
  StreamSubscription<Map<Object?, Object?>>? _platformSubscription;
  bool nearbySupported = false;
  bool wifiAwareSupported = false;
  bool wifiDirectSupported = false;
  bool multipeerSupported = false;
  DateTime _priorityUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String? lastError;
  PendingSealedImport? pendingSealedImport;

  List<TransferRecord> get transfers => List.unmodifiable(_transfers);

  Future<void> initialize() async {
    _transfers
      ..clear()
      ..addAll(await _repository.load());
    _trimTransfersInMemory();
    final resumableIncoming = <TransferRecord>[];
    for (final record in _transfers) {
      if (!record.isActive) continue;
      final material = await _repository.loadResumeMaterial(record.id);
      final bitmapBytes = await _repository.loadBitmap(record.id);
      final filePath = record.filePath;
      final canRestore =
          material != null &&
          filePath != null &&
          await File(filePath).exists() &&
          (record.direction == TransferDirection.outgoing ||
              bitmapBytes != null);
      if (!canRestore) {
        record.state = TransferState.failed;
        record.error = currentL10n.terrInterrupted;
        await _repository.save(
          record,
          clearResumeMaterial: true,
          clearBitmap: true,
        );
        continue;
      }
      try {
        final restoredMaterial = material;
        final keyPair = TransferCrypto.restoreKeyPair(
          privateKey: restoredMaterial.localPrivateKey,
          publicKey: restoredMaterial.localPublicKey,
        );
        final cipher = await TransferCrypto.deriveCipher(
          localKeyPair: keyPair,
          remotePublicKey: restoredMaterial.remotePublicKey,
          transferId: _fromHex(record.id),
        );
        final restoredBitmap = ChunkBitmap.fromBytes(
          record.chunkCount,
          bitmapBytes ?? Uint8List((record.chunkCount + 7) ~/ 8),
        );
        _sessions[record.id] =
            _TransferSession(
                keyPair: keyPair,
                remoteEphemeral: restoredMaterial.remotePublicKey,
                offeredTransports: restoredMaterial.offeredTransports,
              )
              ..cipher = cipher
              ..bitmap = restoredBitmap;
        record
          ..state = TransferState.connecting
          ..bytesDone = min(
            restoredBitmap.count * record.chunkSize,
            record.fileSize,
          )
          ..error = null;
        if (record.direction == TransferDirection.incoming) {
          resumableIncoming.add(record);
        }
      } catch (_) {
        record.state = TransferState.failed;
        record.error = currentL10n.terrInterrupted;
        await _repository.save(
          record,
          clearResumeMaterial: true,
          clearBitmap: true,
        );
      }
    }
    _meshSubscription = _mesh.events.listen(_handleMeshEvent);
    _platformSubscription = _platform.events.listen(
      _handlePlatformEvent,
      // En iOS el canal existe pero no emite; ignorar errores de plugin.
      onError: (Object _) {},
    );
    final capabilities = await _platform.getTransferCapabilities();
    nearbySupported = capabilities['nearby'] as bool? ?? false;
    wifiAwareSupported =
        wifiAwareFeatureFlag && (capabilities['wifiAware'] as bool? ?? false);
    wifiDirectSupported = capabilities['wifiDirect'] as bool? ?? false;
    multipeerSupported = capabilities['multipeer'] as bool? ?? false;
    final initialImport = await _platform.consumeInitialHbtImport();
    if (initialImport != null) {
      unawaited(importHbtPackage(initialImport));
    }
    for (final record in resumableIncoming) {
      await _requestResume(record);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Salida: ofrecer un archivo
  // ---------------------------------------------------------------------

  Future<String> sendFile({
    required MeshPeer peer,
    required String filePath,
    required String fileName,
    String? mimeType,
  }) async {
    if (!peer.supportsTransfers) {
      throw StateError(currentL10n.terrPeerDoesNotSupportTransfers);
    }
    final file = File(filePath);
    final fileSize = await file.length();
    if (fileSize == 0 || fileSize > maxFileBytes) {
      throw StateError(currentL10n.terrFileSize);
    }
    final transferId = _randomBytes(16);
    final idHex = _hex(transferId);
    final keyPair = await TransferCrypto.generateEphemeralKeyPair();
    final sha256Hex = await TransferCrypto.hashFile(file);
    final resolvedMimeType = mimeType ?? _guessMime(fileName);
    final allowsBle = allowsBleTransfer(
      mimeType: resolvedMimeType,
      bytes: fileSize,
    );
    final chunkSize = allowsBle ? bleChunkSize : defaultChunkSize;

    var transports = TransferProtocol.transportLan;
    transports |= TransferProtocol.transportExternal;
    if (nearbySupported) transports |= TransferProtocol.transportNearby;
    if (wifiAwareSupported) transports |= TransferProtocol.transportWifiAware;
    if (wifiDirectSupported) {
      transports |= TransferProtocol.transportWifiDirect;
    }
    if (multipeerSupported) {
      transports |= TransferProtocol.transportMultipeer;
    }
    if (allowsBle) {
      transports |= TransferProtocol.transportBle;
    }

    final record = TransferRecord(
      id: idHex,
      peerId: peer.id,
      peerNickname: peer.nickname,
      direction: TransferDirection.outgoing,
      fileName: sanitizeFileName(fileName),
      mimeType: resolvedMimeType,
      fileSize: fileSize,
      sha256Hex: sha256Hex,
      chunkSize: chunkSize,
      state: TransferState.offered,
      filePath: filePath,
    );
    final session = _TransferSession(
      keyPair: keyPair,
      offeredTransports: transports,
    );
    session.expiryTimer = Timer(offerLifetime, () {
      DiagnosticsLog.instance.warning(
        'transfer.offer.expired',
        data: {'direction': record.direction},
      );
      _fail(
        record,
        peer.supportsTransfers
            ? currentL10n.terrOfferExpired
            : currentL10n.terrOfferExpiredNoHbt,
      );
    });
    _sessions[idHex] = session;
    _transfers.insert(0, record);
    _trimTransfersInMemory();
    await _repository.save(record);
    DiagnosticsLog.instance.info(
      'transfer.offer.sent',
      data: {
        'bytes': fileSize,
        'bleAllowed': allowsBle,
        'nearbyAvailable': nearbySupported,
        'wifiAwareAvailable': wifiAwareSupported,
        'wifiDirectAvailable': wifiDirectSupported,
        'multipeerAvailable': multipeerSupported,
      },
    );
    notifyListeners();

    final frame = TransferFrame(TransferProtocol.typeOffer)
      ..setBytes(TransferProtocol.tagTransferId, transferId)
      ..setUtf8(TransferProtocol.tagFileName, record.fileName)
      ..setUtf8(TransferProtocol.tagMimeType, record.mimeType)
      ..setU64(TransferProtocol.tagFileSize, fileSize)
      ..setBytes(TransferProtocol.tagSha256, _fromHex(sha256Hex))
      ..setU32(TransferProtocol.tagChunkSize, chunkSize)
      ..setU32(TransferProtocol.tagTransports, transports)
      ..setBytes(
        TransferProtocol.tagEphemeralKey,
        await TransferCrypto.publicKeyBytes(keyPair),
      )
      ..setU64(
        TransferProtocol.tagExpiresAt,
        DateTime.now().add(offerLifetime).millisecondsSinceEpoch,
      );
    final signature = await _mesh.signPayload(frame.signedBytes());
    frame.setBytes(TransferProtocol.tagSignature, signature);
    await _sendFrame(record.peerId, frame, record);
    return idHex;
  }

  // ---------------------------------------------------------------------
  // Entrada: aceptar o rechazar ofertas
  // ---------------------------------------------------------------------

  bool canAcceptExternal(String transferId) {
    final record = _find(transferId);
    final session = _sessions[transferId];
    return record?.direction == TransferDirection.incoming &&
        record?.state == TransferState.offered &&
        session != null &&
        session.offeredTransports & TransferProtocol.transportExternal != 0;
  }

  bool canShareExternal(String transferId) {
    final record = _find(transferId);
    final session = _sessions[transferId];
    return record?.direction == TransferDirection.outgoing &&
        record?.transport == TransferTransport.external &&
        session?.externalPackagePath != null;
  }

  Future<void> acceptOffer(
    String transferId, {
    TransferTransport? preferredTransport,
  }) async {
    final record = _find(transferId);
    final session = _sessions[transferId];
    if (record == null ||
        session == null ||
        record.direction != TransferDirection.incoming) {
      return;
    }
    final keyPair = await TransferCrypto.generateEphemeralKeyPair();
    session.keyPair = keyPair;
    session.cipher = await TransferCrypto.deriveCipher(
      localKeyPair: keyPair,
      remotePublicKey: session.remoteEphemeral!,
      transferId: _fromHex(transferId),
    );
    session.bitmap = ChunkBitmap(record.chunkCount);
    record.filePath = await _incomingPath(record, partial: true);
    record.state = TransferState.connecting;
    record.transport =
        preferredTransport == TransferTransport.external &&
            session.offeredTransports & TransferProtocol.transportExternal != 0
        ? TransferTransport.external
        : _chooseTransport(record, session);
    if (record.transport == null) {
      DiagnosticsLog.instance.warning('transfer.accept.no_transport');
      _fail(record, currentL10n.terrNoTransport);
      return;
    }
    DiagnosticsLog.instance.info(
      'transfer.offer.accepted',
      data: {'transport': record.transport!},
    );
    await _saveResumeState(record, session, bitmap: session.bitmap);
    notifyListeners();

    final frame = TransferFrame(TransferProtocol.typeAccept)
      ..setBytes(TransferProtocol.tagTransferId, _fromHex(transferId))
      ..setBytes(
        TransferProtocol.tagEphemeralKey,
        await TransferCrypto.publicKeyBytes(keyPair),
      )
      ..setU8(TransferProtocol.tagTransport, _transportId(record.transport!));
    await _sendFrame(record.peerId, frame, record);

    if (record.transport == TransferTransport.nearby) {
      await _startNearbyReceive(record, session);
    } else if (record.transport == TransferTransport.wifiAware) {
      await _startWifiAwareReceive(record, session);
    } else if (record.transport == TransferTransport.wifiDirect) {
      await _startWifiDirectReceive(record, session);
    } else if (record.transport == TransferTransport.multipeer) {
      await _startMultipeerReceive(record, session);
    }
    if (record.transport != TransferTransport.external) {
      _armConnectTimeout(record, session);
    }
  }

  Future<void> rejectOffer(String transferId, {String? reason}) async {
    final record = _find(transferId);
    if (record == null) return;
    final frame = TransferFrame(TransferProtocol.typeReject)
      ..setBytes(TransferProtocol.tagTransferId, _fromHex(transferId));
    if (reason != null) frame.setUtf8(TransferProtocol.tagReason, reason);
    await _sendFrame(record.peerId, frame, record);
    record.state = TransferState.rejected;
    DiagnosticsLog.instance.info('transfer.offer.rejected');
    await _finishSession(record);
  }

  Future<void> cancel(String transferId) async {
    final record = _find(transferId);
    if (record == null || !record.isActive) return;
    final frame = TransferFrame(TransferProtocol.typeCancel)
      ..setBytes(TransferProtocol.tagTransferId, _fromHex(transferId));
    try {
      await _sendFrame(record.peerId, frame, record);
    } catch (error, stackTrace) {
      // El peer puede haber desaparecido; se cancela localmente igual.
      DiagnosticsLog.instance.warning(
        'transfer.cancel.remote_unreachable',
        error: error,
        stackTrace: stackTrace,
      );
    }
    record.state = TransferState.cancelled;
    DiagnosticsLog.instance.info('transfer.cancelled');
    await _finishSession(record);
  }

  Future<void> remove(String transferId) async {
    final record = _find(transferId);
    if (record == null) return;
    if (record.isActive) await cancel(transferId);
    _transfers.removeWhere((item) => item.id == transferId);
    await _repository.delete(transferId);
    notifyListeners();
  }

  /// Registra un archivo recibido por el modo óptico (QR) para que aparezca
  /// en la lista de transferencias con su verificación ya hecha.
  Future<void> registerOpticalReceived({
    required String transferIdHex,
    required String fileName,
    required int fileSize,
    required String sha256Hex,
    required int chunkSize,
    required String filePath,
    String peerId = '',
  }) async {
    final protected = await _fileCipher.encrypt(File(filePath));
    final record = TransferRecord(
      id: transferIdHex,
      peerId: peerId,
      peerNickname: peerId.isEmpty
          ? currentL10n.transportOptical
          : peerId.substring(0, 8),
      direction: TransferDirection.incoming,
      fileName: fileName,
      mimeType: _guessMime(fileName),
      fileSize: fileSize,
      sha256Hex: sha256Hex,
      chunkSize: chunkSize,
      state: TransferState.completed,
      transport: TransferTransport.optical,
      bytesDone: fileSize,
      filePath: protected.path,
    );
    _transfers.insert(0, record);
    _trimTransfersInMemory();
    await _repository.save(record);
    notifyListeners();
  }

  Future<void> shareExternalPackage(String transferId, {Rect? origin}) async {
    final record = _find(transferId);
    final packagePath = _sessions[transferId]?.externalPackagePath;
    if (record == null || packagePath == null) {
      throw StateError('HBTX package is not ready');
    }
    await _shareService.share(
      path: packagePath,
      fileName: '${p.basenameWithoutExtension(record.fileName)}.hbt',
      origin: origin,
    );
  }

  Future<void> shareSealedFile({
    required MeshPeer peer,
    required String filePath,
    required String fileName,
    String? mimeType,
    Rect? origin,
  }) async {
    if (!peer.hearthbitVerified) {
      throw StateError('Sealed transfer requires a verified HearthBit contact');
    }
    final source = File(filePath);
    final fileSize = await source.length();
    if (fileSize <= 0 || fileSize > maxFileBytes) {
      throw StateError(currentL10n.terrFileSize);
    }
    final recipient = await _mesh.getSealedTransferRecipient(peer.id);
    final packageId = _randomBytes(16);
    final keyPair = await TransferCrypto.generateEphemeralKeyPair();
    final ephemeralPublic = await TransferCrypto.publicKeyBytes(keyPair);
    final cipher = await TransferCrypto.deriveSealedCipher(
      ephemeralKeyPair: keyPair,
      recipientPublicKey: recipient.noisePublicKey,
      packageId: packageId,
    );
    final temporary = await getTemporaryDirectory();
    final package = File(
      p.join(temporary.path, 'sealed-${_hex(packageId)}.hbt'),
    );
    final sha256 = await TransferCrypto.hashFileBytes(source);
    final safeName = sanitizeFileName(fileName);
    await SealedTransferPackage.create(
      source: source,
      destination: package,
      packageId: packageId,
      senderPeerId: recipient.senderPeerId,
      recipientPeerId: recipient.recipientPeerId,
      ephemeralPublicKey: ephemeralPublic,
      fileName: safeName,
      mimeType: mimeType ?? _guessMime(safeName),
      chunkSize: defaultChunkSize,
      sha256: sha256,
      cipher: cipher,
      sign: _mesh.signPayload,
    );
    try {
      await _shareService.share(
        path: package.path,
        fileName: '${p.basenameWithoutExtension(safeName)}.hbt',
        origin: origin,
      );
      final record = TransferRecord(
        id: _hex(packageId),
        peerId: peer.id,
        peerNickname: peer.nickname,
        direction: TransferDirection.outgoing,
        fileName: safeName,
        mimeType: mimeType ?? _guessMime(safeName),
        fileSize: fileSize,
        sha256Hex: _hex(sha256),
        chunkSize: defaultChunkSize,
        state: TransferState.completed,
        transport: TransferTransport.external,
        bytesDone: fileSize,
        filePath: filePath,
      );
      _transfers.insert(0, record);
      _trimTransfersInMemory();
      await _repository.save(record);
      notifyListeners();
    } finally {
      if (await package.exists()) await package.delete();
    }
  }

  Future<void> importHbtPackage(String path) async {
    final package = File(path);
    try {
      final header = await HbtPackageProtocol.inspect(package);
      if (header.kind == HbtPackageKind.sealed) {
        await _importSealedPackage(package);
        return;
      }
      final transferId = _hex(header.transferId);
      final record = _find(transferId);
      final session = _sessions[transferId];
      if (record == null ||
          session == null ||
          record.direction != TransferDirection.incoming ||
          record.transport != TransferTransport.external ||
          session.cipher == null) {
        throw const FormatException('HBTX package has no accepted session');
      }
      final containerPath = await _incomingPath(
        record,
        partial: true,
        suffix: '.enc',
      );
      await HbtPackageProtocol.extractExchange(
        package: package,
        header: header,
        destination: File(containerPath),
      );
      session.containerPath = containerPath;
      record.state = TransferState.transferring;
      notifyListeners();
      await _finishContainerTransfer(record);
    } catch (error) {
      lastError = '${currentL10n.terrTransport}: $error';
      notifyListeners();
    } finally {
      if (await package.exists()) {
        await package.delete();
      }
    }
  }

  Future<void> _importSealedPackage(File package) async {
    final metadata = await SealedTransferPackage.inspect(package);
    final validSignature = await _mesh.verifyPeerSignature(
      metadata.senderPeerId,
      metadata.signedHeader,
      metadata.signature,
    );
    if (!validSignature) {
      throw const FormatException('Unknown sender or invalid HBTS signature');
    }
    if (_find(_hex(metadata.packageId)) != null) {
      throw const FormatException('Sealed package was already imported');
    }
    final directory = await _transfersDirectory();
    final retained = File(
      p.join(directory.path, 'pending-${_hex(metadata.packageId)}.hbt'),
    );
    await package.copy(retained.path);
    final previous = pendingSealedImport;
    pendingSealedImport = PendingSealedImport(
      packagePath: retained.path,
      metadata: metadata,
    );
    if (previous != null) {
      final old = File(previous.packagePath);
      if (await old.exists()) await old.delete();
    }
    notifyListeners();
  }

  Future<void> acceptPendingSealedImport() async {
    final pending = pendingSealedImport;
    if (pending == null) return;
    pendingSealedImport = null;
    final metadata = pending.metadata;
    final package = File(pending.packagePath);
    File? partial;
    try {
      final sharedSecret = await _mesh.deriveSealedOpenSecret(
        metadata.ephemeralPublicKey,
        metadata.recipientPeerId,
      );
      final cipher = await TransferCrypto.deriveSealedCipherFromSecret(
        sharedSecret: sharedSecret,
        packageId: metadata.packageId,
      );
      final record = TransferRecord(
        id: _hex(metadata.packageId),
        peerId: metadata.senderPeerId,
        peerNickname: metadata.senderPeerId.substring(0, 8),
        direction: TransferDirection.incoming,
        fileName: metadata.fileName,
        mimeType: metadata.mimeType,
        fileSize: metadata.fileSize,
        sha256Hex: _hex(metadata.sha256),
        chunkSize: metadata.chunkSize,
        state: TransferState.transferring,
        transport: TransferTransport.external,
      );
      partial = File(await _incomingPath(record, partial: true));
      await SealedTransferPackage.decrypt(
        package: package,
        metadata: metadata,
        destination: partial,
        cipher: cipher,
      );
      final digest = await TransferCrypto.hashFile(partial);
      if (digest != record.sha256Hex) {
        throw const FormatException('Sealed plaintext SHA-256 mismatch');
      }
      final finalPath = await _incomingPath(record, partial: false);
      await partial.rename(finalPath);
      record
        ..filePath = finalPath
        ..bytesDone = record.fileSize
        ..state = TransferState.completed;
      await _protectCompletedFile(record);
      _transfers.insert(0, record);
      _trimTransfersInMemory();
      await _repository.save(record);
    } catch (error) {
      if (partial != null && await partial.exists()) await partial.delete();
      lastError = '${currentL10n.terrTransport}: $error';
    } finally {
      if (await package.exists()) await package.delete();
      notifyListeners();
    }
  }

  Future<void> rejectPendingSealedImport() async {
    final pending = pendingSealedImport;
    pendingSealedImport = null;
    if (pending != null) {
      final package = File(pending.packagePath);
      if (await package.exists()) await package.delete();
    }
    notifyListeners();
  }

  /// Borrado de emergencia: cancela todo y elimina metadatos y archivos.
  Future<void> wipe() async {
    for (final record in List.of(_transfers)) {
      if (record.isActive) {
        await cancel(record.id);
      }
    }
    _transfers.clear();
    await _repository.destroy();
    final directory = await _transfersDirectory();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Eventos de la malla (tramas HBT) y del canal nativo
  // ---------------------------------------------------------------------

  void _handleMeshEvent(Map<Object?, Object?> event) {
    switch (event['type']) {
      case 'transferFrame':
        final peerId = event['peerId'] as String?;
        final bytes = event['frame'] as Uint8List?;
        if (peerId == null || bytes == null) return;
        final frame = TransferFrame.decode(bytes);
        if (frame == null) return;
        unawaited(_handleFrame(peerId, frame));
        break;
      case 'message':
        final message = event['message'];
        if (message is Map<Object?, Object?> && message['channel'] == 'sos') {
          // Prioridad SOS: cualquier SOS en la malla frena los transportes
          // de datos durante unos segundos.
          _priorityUntil = DateTime.now().add(priorityHold);
        }
        break;
      default:
        break;
    }
  }

  Future<void> _handleFrame(String peerId, TransferFrame frame) async {
    final idBytes = frame.bytes(TransferProtocol.tagTransferId);
    if (idBytes == null || idBytes.length != 16) return;
    final transferId = _hex(idBytes);
    switch (frame.type) {
      case TransferProtocol.typeOffer:
        await _handleOffer(peerId, transferId, frame);
        break;
      case TransferProtocol.typeAccept:
        await _handleAccept(peerId, transferId, frame);
        break;
      case TransferProtocol.typeReject:
        final record = _find(transferId);
        if (record != null && record.peerId == peerId) {
          record.state = TransferState.rejected;
          await _finishSession(record);
        }
        break;
      case TransferProtocol.typeCancel:
        final record = _find(transferId);
        if (record != null && record.peerId == peerId) {
          record.state = TransferState.cancelled;
          await _finishSession(record);
        }
        break;
      case TransferProtocol.typeTransportHint:
        await _handleTransportHint(peerId, transferId, frame);
        break;
      case TransferProtocol.typeProgress:
        final record = _find(transferId);
        final received = frame.u32(TransferProtocol.tagReceivedCount);
        if (record != null && received != null) {
          record.bytesDone = min(record.fileSize, received * record.chunkSize);
          notifyListeners();
        }
        break;
      case TransferProtocol.typeComplete:
        final record = _find(transferId);
        if (record != null &&
            record.peerId == peerId &&
            record.direction == TransferDirection.outgoing) {
          record.bytesDone = record.fileSize;
          record.state = TransferState.completed;
          await _finishSession(record);
        }
        break;
      case TransferProtocol.typeDataChunk:
        await _handleDataChunk(peerId, transferId, frame);
        break;
      case TransferProtocol.typeDataAck:
        _sessions[transferId]?.ackController.add(
          frame.u32(TransferProtocol.tagReceivedCount) ?? 0,
        );
        break;
      case TransferProtocol.typeResumeRequest:
        await _handleResumeRequest(peerId, transferId, frame);
        break;
      default:
        break;
    }
  }

  Future<void> _handleOffer(
    String peerId,
    String transferId,
    TransferFrame frame,
  ) async {
    if (_find(transferId) != null) return;
    final signature = frame.bytes(TransferProtocol.tagSignature);
    final ephemeral = frame.bytes(TransferProtocol.tagEphemeralKey);
    final fileSize = frame.u64(TransferProtocol.tagFileSize);
    final chunkSize = frame.u32(TransferProtocol.tagChunkSize);
    final sha256 = frame.bytes(TransferProtocol.tagSha256);
    final expiresAt = frame.u64(TransferProtocol.tagExpiresAt);
    final fileName = frame.utf8Value(TransferProtocol.tagFileName);
    if (signature == null ||
        signature.length != 64 ||
        ephemeral == null ||
        ephemeral.length != 32 ||
        fileSize == null ||
        chunkSize == null ||
        sha256 == null ||
        sha256.length != 32 ||
        fileName == null) {
      return;
    }
    if (fileSize <= 0 ||
        fileSize > maxFileBytes ||
        chunkSize <= 0 ||
        chunkSize > defaultChunkSize ||
        utf8.encode(fileName).length > 255) {
      return;
    }
    if (expiresAt != null &&
        DateTime.now().millisecondsSinceEpoch > expiresAt) {
      return;
    }
    final verified = await _mesh.verifyPeerSignature(
      peerId,
      frame.signedBytes(),
      signature,
    );
    if (!verified) {
      lastError = currentL10n.terrInvalidSignature;
      notifyListeners();
      return;
    }
    final record = TransferRecord(
      id: transferId,
      peerId: peerId,
      peerNickname: peerId.substring(0, min(8, peerId.length)),
      direction: TransferDirection.incoming,
      fileName: sanitizeFileName(fileName),
      mimeType:
          frame.utf8Value(TransferProtocol.tagMimeType) ??
          'application/octet-stream',
      fileSize: fileSize,
      sha256Hex: _hex(sha256),
      chunkSize: chunkSize,
      state: TransferState.offered,
    );
    _sessions[transferId] = _TransferSession(
      remoteEphemeral: Uint8List.fromList(ephemeral),
      offeredTransports: frame.u32(TransferProtocol.tagTransports) ?? 0,
    );
    _transfers.insert(0, record);
    _trimTransfersInMemory();
    await _repository.save(record);
    notifyListeners();
    if (isInlineVoiceNote(mimeType: record.mimeType, bytes: record.fileSize)) {
      await acceptOffer(record.id);
    }
  }

  Future<void> _handleAccept(
    String peerId,
    String transferId,
    TransferFrame frame,
  ) async {
    final record = _find(transferId);
    final session = _sessions[transferId];
    if (record == null ||
        session == null ||
        record.peerId != peerId ||
        record.direction != TransferDirection.outgoing) {
      return;
    }
    final ephemeral = frame.bytes(TransferProtocol.tagEphemeralKey);
    final transport = frame.u8(TransferProtocol.tagTransport);
    if (ephemeral == null || transport == null) return;
    session.expiryTimer?.cancel();
    session.remoteEphemeral = Uint8List.fromList(ephemeral);
    session.cipher = await TransferCrypto.deriveCipher(
      localKeyPair: session.keyPair!,
      remotePublicKey: ephemeral,
      transferId: _fromHex(transferId),
    );
    record.state = TransferState.connecting;
    record.transport = _transportFromId(transport);
    session.bitmap ??= ChunkBitmap(record.chunkCount);
    await _saveResumeState(record, session, bitmap: session.bitmap);
    notifyListeners();

    switch (record.transport) {
      case TransferTransport.lan:
        await _startLanSend(record, session);
        break;
      case TransferTransport.nearby:
        await _startNearbySend(record, session);
        break;
      case TransferTransport.wifiAware:
        await _startWifiAwareSend(record, session);
        break;
      case TransferTransport.wifiDirect:
        await _startWifiDirectSend(record, session);
        break;
      case TransferTransport.multipeer:
        await _startMultipeerSend(record, session);
        break;
      case TransferTransport.external:
        await _prepareExternalSend(record, session);
        break;
      case TransferTransport.ble:
        await _startBleSend(record, session);
        break;
      case TransferTransport.optical:
      case null:
        _fail(record, currentL10n.terrUnsupportedTransport);
        break;
    }
  }

  Future<void> resume(String transferId) async {
    final record = _find(transferId);
    if (record == null ||
        record.direction != TransferDirection.incoming ||
        !_sessions.containsKey(transferId)) {
      return;
    }
    await _requestResume(record);
  }

  Future<void> _requestResume(TransferRecord record) async {
    final session = _sessions[record.id];
    final bitmap = session?.bitmap;
    if (session == null || bitmap == null || session.cipher == null) return;
    final offered = session.offeredTransports;
    TransferTransport? transport;
    if (record.transport == TransferTransport.lan &&
        offered & TransferProtocol.transportLan != 0) {
      transport = TransferTransport.lan;
    } else if (record.transport == TransferTransport.nearby &&
        offered & TransferProtocol.transportNearby != 0 &&
        nearbySupported) {
      transport = TransferTransport.nearby;
    } else if (record.transport == TransferTransport.wifiAware &&
        offered & TransferProtocol.transportWifiAware != 0 &&
        wifiAwareSupported) {
      transport = TransferTransport.wifiAware;
    } else if (record.transport == TransferTransport.wifiDirect &&
        offered & TransferProtocol.transportWifiDirect != 0 &&
        wifiDirectSupported) {
      transport = TransferTransport.wifiDirect;
    } else if (record.transport == TransferTransport.multipeer &&
        offered & TransferProtocol.transportMultipeer != 0 &&
        multipeerSupported) {
      transport = TransferTransport.multipeer;
    } else if (record.transport == TransferTransport.external &&
        offered & TransferProtocol.transportExternal != 0) {
      transport = TransferTransport.external;
    } else if (record.transport == TransferTransport.ble &&
        offered & TransferProtocol.transportBle != 0) {
      transport = TransferTransport.ble;
    } else if (offered & TransferProtocol.transportLan != 0) {
      transport = TransferTransport.lan;
    } else if (offered & TransferProtocol.transportNearby != 0 &&
        nearbySupported) {
      transport = TransferTransport.nearby;
    } else if (offered & TransferProtocol.transportWifiAware != 0 &&
        wifiAwareSupported) {
      transport = TransferTransport.wifiAware;
    } else if (offered & TransferProtocol.transportWifiDirect != 0 &&
        wifiDirectSupported) {
      transport = TransferTransport.wifiDirect;
    } else if (offered & TransferProtocol.transportMultipeer != 0 &&
        multipeerSupported) {
      transport = TransferTransport.multipeer;
    } else if (offered & TransferProtocol.transportBle != 0 &&
        allowsBleTransfer(mimeType: record.mimeType, bytes: record.fileSize)) {
      transport = TransferTransport.ble;
    }
    if (transport == null) {
      _fail(record, currentL10n.terrNoTransport);
      return;
    }
    record
      ..transport = transport
      ..state = TransferState.connecting
      ..error = null;
    await _saveResumeState(record, session, bitmap: bitmap);
    final frame = TransferFrame(TransferProtocol.typeResumeRequest)
      ..setBytes(TransferProtocol.tagTransferId, _fromHex(record.id))
      ..setBytes(TransferProtocol.tagChunkBitmap, bitmap.toBytes())
      ..setU8(TransferProtocol.tagTransport, _transportId(transport));
    try {
      await _sendFrame(
        record.peerId,
        frame,
        record,
        failTransferOnError: false,
      );
      if (transport != TransferTransport.external) {
        _armConnectTimeout(record, session);
      }
    } catch (error) {
      lastError = currentL10n.terrNoMeshSession('$error');
    }
  }

  Future<void> _handleResumeRequest(
    String peerId,
    String transferId,
    TransferFrame frame,
  ) async {
    final record = _find(transferId);
    final session = _sessions[transferId];
    final bitmapBytes = frame.bytes(TransferProtocol.tagChunkBitmap);
    final transportId = frame.u8(TransferProtocol.tagTransport);
    if (record == null ||
        session == null ||
        record.peerId != peerId ||
        record.direction != TransferDirection.outgoing ||
        session.cipher == null ||
        bitmapBytes == null ||
        bitmapBytes.length != (record.chunkCount + 7) ~/ 8 ||
        transportId == null) {
      return;
    }
    final transport = _transportFromId(transportId);
    final allowed =
        (transport == TransferTransport.lan &&
            session.offeredTransports & TransferProtocol.transportLan != 0) ||
        (transport == TransferTransport.nearby &&
            nearbySupported &&
            session.offeredTransports & TransferProtocol.transportNearby !=
                0) ||
        (transport == TransferTransport.wifiAware &&
            wifiAwareSupported &&
            session.offeredTransports & TransferProtocol.transportWifiAware !=
                0) ||
        (transport == TransferTransport.wifiDirect &&
            wifiDirectSupported &&
            session.offeredTransports & TransferProtocol.transportWifiDirect !=
                0) ||
        (transport == TransferTransport.multipeer &&
            multipeerSupported &&
            session.offeredTransports & TransferProtocol.transportMultipeer !=
                0) ||
        (transport == TransferTransport.external &&
            session.offeredTransports & TransferProtocol.transportExternal !=
                0) ||
        (transport == TransferTransport.ble &&
            session.offeredTransports & TransferProtocol.transportBle != 0);
    if (!allowed) return;
    final remoteBitmap = ChunkBitmap.fromBytes(record.chunkCount, bitmapBytes);
    record
      ..transport = transport
      ..state = TransferState.connecting
      ..error = null;
    await _saveResumeState(record, session);
    if (transport == TransferTransport.lan) {
      await _startLanSend(record, session);
    } else if (transport == TransferTransport.nearby) {
      await _startNearbySend(record, session);
    } else if (transport == TransferTransport.wifiAware) {
      await _startWifiAwareSend(record, session);
    } else if (transport == TransferTransport.wifiDirect) {
      await _startWifiDirectSend(record, session);
    } else if (transport == TransferTransport.multipeer) {
      await _startMultipeerSend(record, session);
    } else if (transport == TransferTransport.external) {
      await _prepareExternalSend(record, session);
    } else if (transport == TransferTransport.ble) {
      await _startBleSend(record, session, remoteBitmap: remoteBitmap);
    }
  }

  Future<void> _handleTransportHint(
    String peerId,
    String transferId,
    TransferFrame frame,
  ) async {
    final record = _find(transferId);
    final session = _sessions[transferId];
    if (record == null ||
        session == null ||
        record.peerId != peerId ||
        record.direction != TransferDirection.incoming) {
      return;
    }
    final endpoint = frame.utf8Value(TransferProtocol.tagEndpoint);
    final token = frame.bytes(TransferProtocol.tagToken);
    if (endpoint == null || token == null) return;
    session.connectTimer?.cancel();
    record.state = TransferState.transferring;
    notifyListeners();

    final receiver = LanReceiver(
      transferId: transferId,
      destinationFile: File(record.filePath!),
      fileSize: record.fileSize,
      chunkSize: record.chunkSize,
      cipher: session.cipher!,
      token: Uint8List.fromList(token),
      bitmap: session.bitmap!,
      onProgress: (bytes, bitmap) {
        record.bytesDone = min(bytes, record.fileSize);
        _persistProgress(record, bitmap);
        notifyListeners();
      },
    );
    try {
      final complete = await receiver.receive(endpoint);
      if (complete) {
        await _completeIncoming(record);
      } else {
        _fail(record, currentL10n.terrLanIncomplete);
      }
    } catch (error) {
      await _receiverFallback(
        record,
        session,
        currentL10n.terrLanFailed('$error'),
      );
    }
  }

  Future<void> _handleDataChunk(
    String peerId,
    String transferId,
    TransferFrame frame,
  ) async {
    final record = _find(transferId);
    final session = _sessions[transferId];
    if (record == null ||
        session == null ||
        record.peerId != peerId ||
        record.direction != TransferDirection.incoming ||
        session.cipher == null) {
      return;
    }
    final index = frame.u32(TransferProtocol.tagChunkIndex);
    final data = frame.bytes(TransferProtocol.tagChunkData);
    if (index == null || data == null || index >= record.chunkCount) return;
    session.connectTimer?.cancel();
    if (record.state != TransferState.transferring) {
      record.state = TransferState.transferring;
    }
    try {
      final plain = await session.cipher!.decryptChunk(index, data);
      final raf = await File(
        record.filePath!,
      ).open(mode: FileMode.writeOnlyAppend);
      try {
        if (await raf.length() < record.fileSize) {
          await raf.truncate(record.fileSize);
        }
        await raf.setPosition(index * record.chunkSize);
        await raf.writeFrom(plain);
      } finally {
        await raf.close();
      }
      session.bitmap!.set(index);
      record.bytesDone = min(
        session.bitmap!.count * record.chunkSize,
        record.fileSize,
      );
      final received = session.bitmap!.count;
      if (received % 8 == 0 || session.bitmap!.isComplete) {
        final ack = TransferFrame(TransferProtocol.typeDataAck)
          ..setBytes(TransferProtocol.tagTransferId, _fromHex(transferId))
          ..setU32(TransferProtocol.tagReceivedCount, received);
        await _sendFrame(peerId, ack, record);
      }
      _persistProgress(record, session.bitmap!);
      notifyListeners();
      if (session.bitmap!.isComplete) {
        await _completeIncoming(record);
      }
    } catch (error) {
      _fail(record, currentL10n.terrBleChunk('$error'));
    }
  }

  void _handlePlatformEvent(Map<Object?, Object?> event) {
    if (event['type'] == 'hbtImport') {
      final path = event['path'] as String?;
      if (path != null) unawaited(importHbtPackage(path));
      return;
    }
    final transferId = event['transferId'] as String?;
    if (transferId == null) return;
    final record = _find(transferId);
    if (record == null) return;
    switch (event['type']) {
      case 'nearbyProgress':
      case 'wifiAwareProgress':
      case 'wifiDirectProgress':
      case 'multipeerProgress':
        final bytes = event['bytes'] as int? ?? 0;
        record.state = TransferState.transferring;
        // El contenedor cifrado añade 24 bytes por chunk; se aproxima.
        record.bytesDone = min(bytes, record.fileSize);
        notifyListeners();
        break;
      case 'nearbyDone':
      case 'wifiAwareDone':
      case 'wifiDirectDone':
      case 'multipeerDone':
        unawaited(_finishContainerTransfer(record));
        break;
      case 'nearbyError':
      case 'wifiAwareError':
      case 'wifiDirectError':
      case 'multipeerError':
        DiagnosticsLog.instance.warning(
          'transfer.transport.failed',
          data: {'transportEvent': event['type'] as String? ?? 'unknown'},
        );
        final message =
            event['message'] as String? ?? currentL10n.terrTransport;
        final session = _sessions[transferId];
        if (record.direction == TransferDirection.incoming && session != null) {
          unawaited(_receiverFallback(record, session, message));
        } else {
          _fail(record, message);
        }
        break;
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------
  // Transportes del lado emisor
  // ---------------------------------------------------------------------

  Future<void> _startLanSend(
    TransferRecord record,
    _TransferSession session,
  ) async {
    final token = _randomBytes(16);
    final sender = LanSender(
      transferId: record.id,
      sourceFile: File(record.filePath!),
      chunkSize: record.chunkSize,
      cipher: session.cipher!,
      token: token,
      onProgress: (bytes) {
        record.state = TransferState.transferring;
        record.bytesDone = min(bytes, record.fileSize);
        notifyListeners();
      },
      throttle: _throttle,
    );
    session.lanSender = sender;
    try {
      final endpoint = await sender.listen();
      final hint = TransferFrame(TransferProtocol.typeTransportHint)
        ..setBytes(TransferProtocol.tagTransferId, _fromHex(record.id))
        ..setU8(TransferProtocol.tagTransport, TransferProtocol.transportIdLan)
        ..setUtf8(TransferProtocol.tagEndpoint, endpoint)
        ..setBytes(TransferProtocol.tagToken, token);
      await _sendFrame(record.peerId, hint, record);
      final delivered = await sender.done.future;
      if (delivered) {
        record.bytesDone = record.fileSize;
        record.state = TransferState.completed;
        await _finishSession(record);
      }
      // Si no llegó completo, el receptor decide el fallback y este lado
      // recibirá un nuevo ACCEPT o un CANCEL.
    } catch (error, stackTrace) {
      // El receptor pedirá otro transporte si su conexión falló.
      DiagnosticsLog.instance.warning(
        'transfer.lan.sender_failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _startNearbySend(
    TransferRecord record,
    _TransferSession session,
  ) async {
    try {
      final container = await _encryptContainer(record, session);
      session.containerPath = container.path;
      await _platform.nearbySendFile(
        peerId: record.peerId,
        transferId: record.id,
        filePath: container.path,
      );
    } catch (error) {
      _fail(record, currentL10n.terrNearbyStart('$error'));
    }
  }

  Future<void> _startWifiAwareSend(
    TransferRecord record,
    _TransferSession session,
  ) async {
    try {
      final container = await _encryptContainer(record, session);
      session.containerPath = container.path;
      await _platform.wifiAwareSendFile(
        transferId: record.id,
        filePath: container.path,
      );
    } catch (error) {
      _fail(record, currentL10n.terrWifiAwareStart('$error'));
    }
  }

  Future<void> _startWifiDirectSend(
    TransferRecord record,
    _TransferSession session,
  ) async {
    try {
      final container = await _encryptContainer(record, session);
      session.containerPath = container.path;
      await _platform.wifiDirectSendFile(
        transferId: record.id,
        filePath: container.path,
      );
    } catch (error) {
      _fail(record, '${currentL10n.terrTransport}: $error');
    }
  }

  Future<void> _startMultipeerSend(
    TransferRecord record,
    _TransferSession session,
  ) async {
    try {
      final container = await _encryptContainer(record, session);
      session.containerPath = container.path;
      await _platform.multipeerSendFile(
        transferId: record.id,
        filePath: container.path,
      );
    } catch (error) {
      _fail(record, '${currentL10n.terrTransport}: $error');
    }
  }

  Future<void> _prepareExternalSend(
    TransferRecord record,
    _TransferSession session,
  ) async {
    try {
      final container = await _encryptContainer(record, session);
      session.containerPath = container.path;
      final temporary = await getTemporaryDirectory();
      final package = File(p.join(temporary.path, 'hbt-${record.id}.hbt'));
      await HbtPackageProtocol.writeExchange(
        container: container,
        transferId: _fromHex(record.id),
        destination: package,
      );
      session.externalPackagePath = package.path;
      record.state = TransferState.connecting;
      notifyListeners();
    } catch (error) {
      _fail(record, '${currentL10n.terrTransport}: $error');
    }
  }

  Future<void> _startBleSend(
    TransferRecord record,
    _TransferSession session, {
    ChunkBitmap? remoteBitmap,
  }) async {
    record.state = TransferState.transferring;
    notifyListeners();
    final file = File(record.filePath!);
    final raf = await file.open();
    var acked = 0;
    try {
      for (var index = 0; index < record.chunkCount; index++) {
        if (remoteBitmap?[index] ?? false) {
          record.bytesDone = min(
            remoteBitmap!.count * record.chunkSize,
            record.fileSize,
          );
          continue;
        }
        await raf.setPosition(index * record.chunkSize);
        final remaining = record.fileSize - index * record.chunkSize;
        final plain = await raf.read(min(record.chunkSize, remaining));
        final encrypted = await session.cipher!.encryptChunk(index, plain);
        final frame = TransferFrame(TransferProtocol.typeDataChunk)
          ..setBytes(TransferProtocol.tagTransferId, _fromHex(record.id))
          ..setU32(TransferProtocol.tagChunkIndex, index)
          ..setBytes(TransferProtocol.tagChunkData, encrypted);
        await _sendFrame(record.peerId, frame, record);
        record.bytesDone = min((index + 1) * record.chunkSize, record.fileSize);
        notifyListeners();
        final windowEnd = index + 1;
        if (windowEnd % 8 == 0 && windowEnd < record.chunkCount) {
          acked = await _awaitAck(
            session,
            minimum: windowEnd - 7,
            current: acked,
          );
        }
        await _throttle();
        if (!record.isActive) return;
      }
      // El COMPLETE del receptor confirma la verificación SHA-256.
    } catch (error) {
      _fail(record, currentL10n.terrBleInterrupted('$error'));
    } finally {
      await raf.close();
    }
  }

  Future<int> _awaitAck(
    _TransferSession session, {
    required int minimum,
    required int current,
  }) async {
    if (current >= minimum) return current;
    try {
      return await session.ackController.stream
          .firstWhere((count) => count >= minimum)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw StateError(currentL10n.terrReceiverSilent);
    }
  }

  // ---------------------------------------------------------------------
  // Transportes del lado receptor
  // ---------------------------------------------------------------------

  Future<void> _startNearbyReceive(
    TransferRecord record,
    _TransferSession session,
  ) async {
    final container = await _incomingPath(
      record,
      partial: true,
      suffix: '.enc',
    );
    session.containerPath = container;
    try {
      await _platform.nearbyReceiveFile(
        peerId: record.peerId,
        transferId: record.id,
        destinationPath: container,
      );
    } catch (error) {
      await _receiverFallback(
        record,
        session,
        currentL10n.terrNearbyUnavailable('$error'),
      );
    }
  }

  Future<void> _startWifiAwareReceive(
    TransferRecord record,
    _TransferSession session,
  ) async {
    final container = await _incomingPath(
      record,
      partial: true,
      suffix: '.enc',
    );
    session.containerPath = container;
    try {
      await _platform.wifiAwareReceiveFile(
        transferId: record.id,
        destinationPath: container,
      );
    } catch (error) {
      await _receiverFallback(
        record,
        session,
        currentL10n.terrWifiAwareUnavailable('$error'),
      );
    }
  }

  Future<void> _startWifiDirectReceive(
    TransferRecord record,
    _TransferSession session,
  ) async {
    final container = await _incomingPath(
      record,
      partial: true,
      suffix: '.enc',
    );
    session.containerPath = container;
    try {
      await _platform.wifiDirectReceiveFile(
        transferId: record.id,
        destinationPath: container,
      );
    } catch (error) {
      await _receiverFallback(
        record,
        session,
        '${currentL10n.terrTransport}: $error',
      );
    }
  }

  Future<void> _startMultipeerReceive(
    TransferRecord record,
    _TransferSession session,
  ) async {
    final container = await _incomingPath(
      record,
      partial: true,
      suffix: '.enc',
    );
    session.containerPath = container;
    try {
      await _platform.multipeerReceiveFile(
        transferId: record.id,
        destinationPath: container,
      );
    } catch (error) {
      await _receiverFallback(
        record,
        session,
        '${currentL10n.terrTransport}: $error',
      );
    }
  }

  /// Cierre común de transportes que entregan el contenedor cifrado completo.
  Future<void> _finishContainerTransfer(TransferRecord record) async {
    final session = _sessions[record.id];
    if (record.direction == TransferDirection.outgoing) {
      record.bytesDone = record.fileSize;
      // El COMPLETE del receptor confirma la verificación.
      return;
    }
    if (session?.containerPath == null) return;
    try {
      await _decryptContainer(File(session!.containerPath!), record, session);
      if (session.bitmap!.isComplete) {
        await _completeIncoming(record);
      } else {
        _fail(record, currentL10n.terrContainerIncomplete);
      }
    } catch (error) {
      _fail(record, currentL10n.terrContainerDecrypt('$error'));
    }
  }

  /// Si un transporte falla en el receptor, intenta el siguiente disponible
  /// reenviando un ACCEPT; si no quedan, cancela.
  Future<void> _receiverFallback(
    TransferRecord record,
    _TransferSession session,
    String reason,
  ) async {
    final tried = session.triedTransports..add(record.transport!);
    final next = _chooseTransport(record, session, excluding: tried);
    if (next == null) {
      _fail(record, reason);
      final frame = TransferFrame(TransferProtocol.typeCancel)
        ..setBytes(TransferProtocol.tagTransferId, _fromHex(record.id))
        ..setUtf8(TransferProtocol.tagReason, reason);
      try {
        await _sendFrame(record.peerId, frame, record);
      } catch (error, stackTrace) {
        DiagnosticsLog.instance.warning(
          'transfer.fallback.cancel_not_delivered',
          error: error,
          stackTrace: stackTrace,
        );
      }
      return;
    }
    record.transport = next;
    record.state = TransferState.connecting;
    notifyListeners();
    final frame = TransferFrame(TransferProtocol.typeAccept)
      ..setBytes(TransferProtocol.tagTransferId, _fromHex(record.id))
      ..setBytes(
        TransferProtocol.tagEphemeralKey,
        await TransferCrypto.publicKeyBytes(session.keyPair!),
      )
      ..setU8(TransferProtocol.tagTransport, _transportId(next));
    await _sendFrame(record.peerId, frame, record);
    if (next == TransferTransport.nearby) {
      await _startNearbyReceive(record, session);
    } else if (next == TransferTransport.wifiAware) {
      await _startWifiAwareReceive(record, session);
    } else if (next == TransferTransport.wifiDirect) {
      await _startWifiDirectReceive(record, session);
    } else if (next == TransferTransport.multipeer) {
      await _startMultipeerReceive(record, session);
    }
    _armConnectTimeout(record, session);
  }

  Future<void> _completeIncoming(TransferRecord record) async {
    final partial = File(record.filePath!);
    final digest = await TransferCrypto.hashFile(partial);
    if (digest != record.sha256Hex) {
      await partial.delete();
      _fail(record, currentL10n.terrShaMismatch);
      return;
    }
    final finalPath = await _incomingPath(record, partial: false);
    await partial.rename(finalPath);
    record.filePath = finalPath;
    record.bytesDone = record.fileSize;
    record.state = TransferState.completed;
    final frame = TransferFrame(TransferProtocol.typeComplete)
      ..setBytes(TransferProtocol.tagTransferId, _fromHex(record.id));
    try {
      await _sendFrame(record.peerId, frame, record);
    } catch (error, stackTrace) {
      // Aunque el peer no reciba el COMPLETE, el archivo local es válido.
      DiagnosticsLog.instance.warning(
        'transfer.complete.not_acknowledged',
        error: error,
        stackTrace: stackTrace,
      );
    }
    await _finishSession(record);
  }

  // ---------------------------------------------------------------------
  // Utilidades internas
  // ---------------------------------------------------------------------

  Future<void> _sendFrame(
    String peerId,
    TransferFrame frame,
    TransferRecord record, {
    bool failTransferOnError = true,
  }) async {
    try {
      await _mesh.sendTransferFrame(peerId, frame.encode());
    } catch (error) {
      if (failTransferOnError && record.isActive) {
        _fail(record, currentL10n.terrNoMeshSession('$error'));
      }
      rethrow;
    }
  }

  TransferTransport? _chooseTransport(
    TransferRecord record,
    _TransferSession session, {
    Set<TransferTransport> excluding = const {},
  }) {
    final offered = session.offeredTransports;
    final bleAvailable =
        offered & TransferProtocol.transportBle != 0 &&
        record.fileSize <= bleMaxInlineBytes;
    final preferBle = isInlineVoiceNote(
      mimeType: record.mimeType,
      bytes: record.fileSize,
    );
    final candidates = <TransferTransport>[
      if (preferBle && bleAvailable) TransferTransport.ble,
      if (offered & TransferProtocol.transportLan != 0) TransferTransport.lan,
      if (offered & TransferProtocol.transportNearby != 0 && nearbySupported)
        TransferTransport.nearby,
      if (offered & TransferProtocol.transportWifiAware != 0 &&
          wifiAwareSupported)
        TransferTransport.wifiAware,
      if (offered & TransferProtocol.transportWifiDirect != 0 &&
          wifiDirectSupported)
        TransferTransport.wifiDirect,
      if (offered & TransferProtocol.transportMultipeer != 0 &&
          multipeerSupported)
        TransferTransport.multipeer,
      if (!preferBle && bleAvailable) TransferTransport.ble,
    ];
    for (final candidate in candidates) {
      if (!excluding.contains(candidate)) return candidate;
    }
    return null;
  }

  void _armConnectTimeout(TransferRecord record, _TransferSession session) {
    session.connectTimer?.cancel();
    session.connectTimer = Timer(const Duration(seconds: 45), () {
      if (record.state == TransferState.connecting) {
        unawaited(
          _receiverFallback(record, session, currentL10n.terrTransportTimeout),
        );
      }
    });
  }

  Future<File> _encryptContainer(
    TransferRecord record,
    _TransferSession session,
  ) async {
    final path = await _incomingPath(record, partial: true, suffix: '.enc');
    final container = File(path);
    final sink = container.openWrite();
    final raf = await File(record.filePath!).open();
    try {
      for (var index = 0; index < record.chunkCount; index++) {
        await raf.setPosition(index * record.chunkSize);
        final remaining = record.fileSize - index * record.chunkSize;
        final plain = await raf.read(min(record.chunkSize, remaining));
        final encrypted = await session.cipher!.encryptChunk(index, plain);
        final header = Uint8List(8);
        ByteData.sublistView(header)
          ..setUint32(0, index)
          ..setUint32(4, encrypted.length);
        sink.add(header);
        sink.add(encrypted);
      }
      await sink.flush();
    } finally {
      await sink.close();
      await raf.close();
    }
    return container;
  }

  Future<void> _decryptContainer(
    File container,
    TransferRecord record,
    _TransferSession session,
  ) async {
    final bytes = await container.readAsBytes();
    final raf = await File(
      record.filePath!,
    ).open(mode: FileMode.writeOnlyAppend);
    try {
      if (await raf.length() < record.fileSize) {
        await raf.truncate(record.fileSize);
      }
      var offset = 0;
      while (offset + 8 <= bytes.length) {
        final view = ByteData.sublistView(bytes, offset, offset + 8);
        final index = view.getUint32(0);
        final length = view.getUint32(4);
        offset += 8;
        if (offset + length > bytes.length || index >= record.chunkCount) {
          break;
        }
        final plain = await session.cipher!.decryptChunk(
          index,
          Uint8List.sublistView(bytes, offset, offset + length),
        );
        await raf.setPosition(index * record.chunkSize);
        await raf.writeFrom(plain);
        session.bitmap!.set(index);
        offset += length;
      }
    } finally {
      await raf.close();
    }
    record.bytesDone = min(
      session.bitmap!.count * record.chunkSize,
      record.fileSize,
    );
    await container.delete();
  }

  Future<void> _throttle() async {
    if (DateTime.now().isBefore(_priorityUntil)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  void _persistProgress(TransferRecord record, ChunkBitmap bitmap) {
    // Acota la repetición tras un cierre sin escribir por cada paquete BLE.
    if (bitmap.count % 8 == 0 || bitmap.isComplete) {
      unawaited(_repository.save(record, bitmap: bitmap.toBytes()));
    }
  }

  Future<void> _saveResumeState(
    TransferRecord record,
    _TransferSession session, {
    ChunkBitmap? bitmap,
  }) async {
    final keyPair = session.keyPair;
    final remote = session.remoteEphemeral;
    if (keyPair == null || remote == null || remote.length != 32) {
      throw StateError('Transfer session cannot be persisted safely');
    }
    final local = await TransferCrypto.exportKeyPair(keyPair);
    await _repository.save(
      record,
      bitmap: bitmap?.toBytes(),
      resumeMaterial: TransferResumeMaterial(
        localPrivateKey: local.privateKey,
        localPublicKey: local.publicKey,
        remotePublicKey: Uint8List.fromList(remote),
        offeredTransports: session.offeredTransports,
      ),
    );
  }

  void _fail(TransferRecord record, String message) {
    if (record.state == TransferState.completed) return;
    record.state = TransferState.failed;
    record.error = message;
    lastError = message;
    DiagnosticsLog.instance.warning(
      'transfer.failed',
      data: {
        'direction': record.direction,
        if (record.transport != null) 'transport': record.transport!,
        'state': record.state,
      },
    );
    unawaited(_finishSession(record));
  }

  Future<void> _finishSession(TransferRecord record) async {
    final session = _sessions.remove(record.id);
    session?.expiryTimer?.cancel();
    session?.connectTimer?.cancel();
    await session?.lanSender?.close();
    await session?.ackController.close();
    if (session?.containerPath != null) {
      final container = File(session!.containerPath!);
      if (await container.exists()) await container.delete();
    }
    if (session?.externalPackagePath != null) {
      final package = File(session!.externalPackagePath!);
      if (await package.exists()) await package.delete();
    }
    await _platform.nearbyStop(record.id);
    await _platform.wifiAwareStop(record.id);
    await _platform.wifiDirectStop(record.id);
    await _platform.multipeerStop(record.id);
    await _protectCompletedFile(record);
    _trimTransfersInMemory();
    await _repository.save(
      record,
      clearResumeMaterial: true,
      clearBitmap: true,
    );
    notifyListeners();
  }

  Future<void> _protectCompletedFile(TransferRecord record) async {
    if (record.state != TransferState.completed || record.filePath == null) {
      return;
    }
    final source = File(record.filePath!);
    if (!await source.exists() ||
        AtRestFileCipher.isEncryptedPath(source.path)) {
      return;
    }
    var shouldProtect = record.direction == TransferDirection.incoming;
    if (!shouldProtect) {
      final temporary = await getTemporaryDirectory();
      final name = p.basename(source.path);
      shouldProtect =
          p.isWithin(temporary.path, source.path) &&
          (name.startsWith('hearthbit_voice_') || name.startsWith('hb_'));
    }
    if (!shouldProtect) return;
    record.filePath = (await _fileCipher.encrypt(source)).path;
  }

  Future<Directory> _transfersDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'hearthbit_transfers'));
    await directory.create(recursive: true);
    await BackupProtection.exclude(directory.path);
    return directory;
  }

  Future<String> _incomingPath(
    TransferRecord record, {
    required bool partial,
    String suffix = '',
  }) async {
    final directory = await _transfersDirectory();
    await directory.create(recursive: true);
    final name = partial
        ? '${record.id}$suffix.part'
        : '${record.id}_${record.fileName}';
    return p.join(directory.path, name);
  }

  void _trimTransfersInMemory() {
    while (_transfers.length > maximumTransfersInMemory) {
      final removable = _transfers.lastIndexWhere(
        (record) => !record.isActive && !_sessions.containsKey(record.id),
      );
      if (removable < 0) return;
      _transfers.removeAt(removable);
    }
  }

  TransferRecord? _find(String transferId) {
    for (final record in _transfers) {
      if (record.id == transferId) return record;
    }
    return null;
  }

  Uint8List _randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

  String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Uint8List _fromHex(String hex) {
    final output = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < output.length; i++) {
      output[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return output;
  }

  int _transportId(TransferTransport transport) => switch (transport) {
    TransferTransport.ble => TransferProtocol.transportIdBle,
    TransferTransport.lan => TransferProtocol.transportIdLan,
    TransferTransport.nearby => TransferProtocol.transportIdNearby,
    TransferTransport.wifiAware => TransferProtocol.transportIdWifiAware,
    TransferTransport.optical => TransferProtocol.transportIdOptical,
    TransferTransport.wifiDirect => TransferProtocol.transportIdWifiDirect,
    TransferTransport.multipeer => TransferProtocol.transportIdMultipeer,
    TransferTransport.external => TransferProtocol.transportIdExternal,
  };

  TransferTransport? _transportFromId(int id) => switch (id) {
    TransferProtocol.transportIdBle => TransferTransport.ble,
    TransferProtocol.transportIdLan => TransferTransport.lan,
    TransferProtocol.transportIdNearby => TransferTransport.nearby,
    TransferProtocol.transportIdWifiAware => TransferTransport.wifiAware,
    TransferProtocol.transportIdOptical => TransferTransport.optical,
    TransferProtocol.transportIdWifiDirect => TransferTransport.wifiDirect,
    TransferProtocol.transportIdMultipeer => TransferTransport.multipeer,
    TransferProtocol.transportIdExternal => TransferTransport.external,
    _ => null,
  };

  String _guessMime(String fileName) {
    final extension = p.extension(fileName).toLowerCase();
    return switch (extension) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.mp4' => 'video/mp4',
      '.mp3' => 'audio/mpeg',
      '.m4a' => 'audio/mp4',
      '.pdf' => 'application/pdf',
      '.txt' => 'text/plain',
      '.zip' => 'application/zip',
      '.apk' => androidPackageMimeType,
      _ => 'application/octet-stream',
    };
  }

  @override
  void dispose() {
    _meshSubscription?.cancel();
    _platformSubscription?.cancel();
    for (final session in _sessions.values) {
      session.expiryTimer?.cancel();
      session.connectTimer?.cancel();
      unawaited(session.lanSender?.close());
      unawaited(session.ackController.close());
    }
    _sessions.clear();
    unawaited(_repository.close());
    super.dispose();
  }
}

class _TransferSession {
  _TransferSession({
    this.keyPair,
    this.remoteEphemeral,
    this.offeredTransports = 0,
  });

  SimpleKeyPair? keyPair;
  Uint8List? remoteEphemeral;
  int offeredTransports;
  TransferCipher? cipher;
  ChunkBitmap? bitmap;
  LanSender? lanSender;
  Timer? expiryTimer;
  Timer? connectTimer;
  String? containerPath;
  String? externalPackagePath;
  final Set<TransferTransport> triedTransports = {};
  final StreamController<int> ackController = StreamController.broadcast();
}
