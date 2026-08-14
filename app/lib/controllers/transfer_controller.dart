import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../models/transfer_models.dart';
import '../services/lan_transport.dart';
import '../services/mesh_platform_service.dart';
import '../services/transfer_crypto.dart';
import '../services/transfer_platform_service.dart';
import '../services/transfer_protocol.dart';
import '../services/transfer_repository.dart';

/// Orquesta las transferencias de archivos: ofertas firmadas por BLE,
/// negociación de transporte (LAN > Nearby > BLE) y cifrado de extremo a
/// extremo con verificación SHA-256.
class TransferController extends ChangeNotifier {
  TransferController(
    this._mesh, {
    TransferPlatformService? platform,
    TransferRepository? repository,
  }) : _platform = platform ?? TransferPlatformService(),
       _repository = repository ?? TransferRepository();

  static const int bleChunkSize = 350;
  static const int bleMaxInlineBytes = 256 * 1024;
  static const int voiceNoteMaxBytes = 64 * 1024;
  static const int defaultChunkSize = 64 * 1024;
  static const int maxFileBytes = 512 * 1024 * 1024;
  static const int maximumTransfersInMemory = 200;
  static const Duration offerLifetime = Duration(minutes: 10);
  static const Duration priorityHold = Duration(seconds: 20);
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

  final List<TransferRecord> _transfers = [];
  final Map<String, _TransferSession> _sessions = {};
  final Random _random = Random.secure();

  StreamSubscription<Map<Object?, Object?>>? _meshSubscription;
  StreamSubscription<Map<Object?, Object?>>? _platformSubscription;
  bool nearbySupported = false;
  bool wifiAwareSupported = false;
  DateTime _priorityUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String? lastError;

  List<TransferRecord> get transfers => List.unmodifiable(_transfers);

  Future<void> initialize() async {
    _transfers
      ..clear()
      ..addAll(await _repository.load());
    _trimTransfersInMemory();
    // Las transferencias que quedaron a medias en una sesión anterior no
    // tienen ya sesión criptográfica en memoria: se marcan como fallidas.
    for (final record in _transfers) {
      if (record.isActive) {
        record.state = TransferState.failed;
        record.error = currentL10n.terrInterrupted;
        await _repository.save(record);
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
    if (nearbySupported) transports |= TransferProtocol.transportNearby;
    if (wifiAwareSupported) transports |= TransferProtocol.transportWifiAware;
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
    final session = _TransferSession(keyPair: keyPair);
    session.expiryTimer = Timer(offerLifetime, () {
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

  Future<void> acceptOffer(String transferId) async {
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
    record.transport = _chooseTransport(record, session);
    if (record.transport == null) {
      _fail(record, currentL10n.terrNoTransport);
      return;
    }
    await _repository.save(record);
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
    }
    _armConnectTimeout(record, session);
  }

  Future<void> rejectOffer(String transferId, {String? reason}) async {
    final record = _find(transferId);
    if (record == null) return;
    final frame = TransferFrame(TransferProtocol.typeReject)
      ..setBytes(TransferProtocol.tagTransferId, _fromHex(transferId));
    if (reason != null) frame.setUtf8(TransferProtocol.tagReason, reason);
    await _sendFrame(record.peerId, frame, record);
    record.state = TransferState.rejected;
    await _finishSession(record);
  }

  Future<void> cancel(String transferId) async {
    final record = _find(transferId);
    if (record == null || !record.isActive) return;
    final frame = TransferFrame(TransferProtocol.typeCancel)
      ..setBytes(TransferProtocol.tagTransferId, _fromHex(transferId));
    try {
      await _sendFrame(record.peerId, frame, record);
    } catch (_) {
      // El peer puede haber desaparecido; se cancela localmente igual.
    }
    record.state = TransferState.cancelled;
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
      filePath: filePath,
    );
    _transfers.insert(0, record);
    _trimTransfersInMemory();
    await _repository.save(record);
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
    await _repository.clear();
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
        ephemeral == null ||
        fileSize == null ||
        chunkSize == null ||
        sha256 == null ||
        fileName == null) {
      return;
    }
    if (fileSize <= 0 || fileSize > maxFileBytes) return;
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
      peerNickname: peerId.substring(0, 8),
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
    session.cipher = await TransferCrypto.deriveCipher(
      localKeyPair: session.keyPair!,
      remotePublicKey: ephemeral,
      transferId: _fromHex(transferId),
    );
    record.state = TransferState.connecting;
    record.transport = _transportFromId(transport);
    await _repository.save(record);
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
      case TransferTransport.ble:
        await _startBleSend(record, session);
        break;
      case TransferTransport.optical:
      case null:
        _fail(record, currentL10n.terrUnsupportedTransport);
        break;
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
    final transferId = event['transferId'] as String?;
    if (transferId == null) return;
    final record = _find(transferId);
    if (record == null) return;
    switch (event['type']) {
      case 'nearbyProgress':
      case 'wifiAwareProgress':
        final bytes = event['bytes'] as int? ?? 0;
        record.state = TransferState.transferring;
        // El contenedor cifrado añade 24 bytes por chunk; se aproxima.
        record.bytesDone = min(bytes, record.fileSize);
        notifyListeners();
        break;
      case 'nearbyDone':
      case 'wifiAwareDone':
        unawaited(_finishContainerTransfer(record));
        break;
      case 'nearbyError':
      case 'wifiAwareError':
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
    } catch (_) {
      // El receptor pedirá otro transporte si su conexión falló.
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

  Future<void> _startBleSend(
    TransferRecord record,
    _TransferSession session,
  ) async {
    record.state = TransferState.transferring;
    notifyListeners();
    final file = File(record.filePath!);
    final raf = await file.open();
    var acked = 0;
    try {
      for (var index = 0; index < record.chunkCount; index++) {
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

  /// Cierre común de Nearby y Wi-Fi Aware: ambos entregan el contenedor
  /// cifrado completo como un único archivo.
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
      } catch (_) {}
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
    } catch (_) {
      // Aunque el peer no reciba el COMPLETE, el archivo local es válido.
    }
    await _finishSession(record);
  }

  // ---------------------------------------------------------------------
  // Utilidades internas
  // ---------------------------------------------------------------------

  Future<void> _sendFrame(
    String peerId,
    TransferFrame frame,
    TransferRecord record,
  ) async {
    try {
      await _mesh.sendTransferFrame(peerId, frame.encode());
    } catch (error) {
      if (record.isActive) {
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
    // Persistencia periódica para poder reanudar: cada 64 chunks.
    if (bitmap.count % 64 == 0 || bitmap.isComplete) {
      unawaited(_repository.save(record, bitmap: bitmap.toBytes()));
    }
  }

  void _fail(TransferRecord record, String message) {
    if (record.state == TransferState.completed) return;
    record.state = TransferState.failed;
    record.error = message;
    lastError = message;
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
    await _platform.nearbyStop(record.id);
    await _platform.wifiAwareStop(record.id);
    _trimTransfersInMemory();
    await _repository.save(record);
    notifyListeners();
  }

  Future<Directory> _transfersDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(p.join(documents.path, 'hearthbit_transfers'));
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
  };

  TransferTransport? _transportFromId(int id) => switch (id) {
    TransferProtocol.transportIdBle => TransferTransport.ble,
    TransferProtocol.transportIdLan => TransferTransport.lan,
    TransferProtocol.transportIdNearby => TransferTransport.nearby,
    TransferProtocol.transportIdWifiAware => TransferTransport.wifiAware,
    TransferProtocol.transportIdOptical => TransferTransport.optical,
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
  final Set<TransferTransport> triedTransports = {};
  final StreamController<int> ackController = StreamController.broadcast();
}
