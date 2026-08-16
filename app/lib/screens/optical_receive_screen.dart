import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../controllers/mesh_controller.dart';
import '../controllers/transfer_controller.dart';
import '../l10n/l10n.dart';
import '../services/fountain_code.dart';
import '../services/mesh_platform_service.dart';
import '../services/optical_protocol.dart';
import '../services/transfer_crypto.dart';
import '../services/transfer_protocol.dart';

/// Receptor óptico: escanea la secuencia de QR y reconstruye el archivo con
/// el decodificador fountain. No necesita canal de retorno; si hay sesión de
/// malla con el emisor, envía una confirmación BLE al terminar.
class OpticalReceiveScreen extends StatefulWidget {
  const OpticalReceiveScreen({required this.mesh, this.transfers, super.key});

  final TransferController? transfers;
  final MeshController mesh;

  @override
  State<OpticalReceiveScreen> createState() => _OpticalReceiveScreenState();
}

class _OpticalReceiveScreenState extends State<OpticalReceiveScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.unrestricted,
    formats: const [BarcodeFormat.qrCode],
  );

  OpticalHeader? _header;
  FountainDecoder? _decoder;
  String? _savedPath;
  String? _emergencyReceived;
  String? _error;
  bool _finishing = false;
  bool _processingEmergency = false;
  bool _approvingHeader = false;
  bool _decoding = false;
  final List<(int, Uint8List)> _pendingSymbols = [];
  _OpticalTrust? _trust;

  void _onDetect(BarcodeCapture capture) {
    if (_savedPath != null ||
        _emergencyReceived != null ||
        _finishing ||
        _processingEmergency) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final content = barcode.rawValue;
      if (content == null) continue;
      final symbol = OpticalProtocol.decode(content);
      if (symbol is OpticalHeader && widget.transfers != null) {
        unawaited(_onHeader(symbol));
      } else if (symbol is OpticalDataSymbol && widget.transfers != null) {
        _onData(symbol);
      } else if (symbol is OpticalEmergencyBundle) {
        unawaited(_onEmergency(symbol));
      }
    }
  }

  Future<void> _onEmergency(OpticalEmergencyBundle bundle) async {
    if (_processingEmergency) return;
    _processingEmergency = true;
    await _scanner.stop();
    if (!mounted) return;
    final accepted =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            icon: Icon(
              Icons.crisis_alert,
              color: Theme.of(dialogContext).colorScheme.error,
            ),
            title: Text(context.l10n.sosQrRelayTitle),
            content: SelectableText(bundle.fallbackText),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.l10n.actionReject),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(context.l10n.sosQrRelayAction),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted) return;
    if (!accepted) {
      _processingEmergency = false;
      await _scanner.start();
      return;
    }
    try {
      await MeshPlatformService().injectEmergencyQrFrames(
        announcementFrame: bundle.announcementFrame,
        messageFrame: bundle.messageFrame,
      );
      if (!mounted) return;
      setState(() {
        _emergencyReceived = bundle.fallbackText;
        _processingEmergency = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = context.l10n.sosQrInvalid;
        _processingEmergency = false;
      });
      await _scanner.start();
    }
  }

  Future<void> _onHeader(OpticalHeader header) async {
    if (_approvingHeader ||
        (_header != null && _sameId(_header!.transferId, header.transferId))) {
      return;
    }
    _approvingHeader = true;
    final knownPeer =
        header.senderPeerId.isNotEmpty &&
        (widget.mesh.peerById(header.senderPeerId) != null ||
            widget.mesh.knownPeerById(header.senderPeerId) != null);
    var trust = _OpticalTrust.unverified;
    if (knownPeer && header.isSigned) {
      var verified = false;
      try {
        verified = await MeshPlatformService().verifyPeerSignature(
          header.senderPeerId,
          OpticalProtocol.signingPayload(header),
          header.signature!,
        );
      } catch (_) {
        verified = false;
      }
      if (!verified) {
        if (mounted) {
          setState(() {
            _error = context.l10n.opticalSignatureInvalid;
            _approvingHeader = false;
          });
        }
        return;
      }
      trust = _OpticalTrust.verified;
    } else {
      if (!mounted) return;
      await _scanner.stop();
      final accepted = await _confirmUnverified(header);
      if (!mounted) return;
      if (!accepted) {
        setState(() => _approvingHeader = false);
        await _scanner.start();
        return;
      }
      trust = header.isLegacy ? _OpticalTrust.legacy : _OpticalTrust.unverified;
      await _scanner.start();
    }
    final decoder = await FountainDecoder.createInIsolate(
      chunkCount: header.chunkCount,
      chunkSize: header.chunkSize,
      seed: header.seed,
    );
    if (!mounted) return;
    // Cabecera nueva: el emisor reinició la sesión (o es otra transferencia).
    setState(() {
      _header = header;
      _trust = trust;
      _decoder = decoder;
      _error = null;
      _approvingHeader = false;
      _pendingSymbols.clear();
    });
  }

  Future<bool> _confirmUnverified(OpticalHeader header) async {
    final fingerprintSource = header.senderPeerId.isNotEmpty
        ? utf8.encode(header.senderPeerId)
        : header.signature ?? OpticalProtocol.signingPayload(header);
    final fingerprint = sha256
        .convert(fingerprintSource)
        .bytes
        .take(12)
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join()
        .replaceAllMapped(RegExp(r'.{4}'), (match) => '${match.group(0)} ')
        .trim();
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.l10n.opticalUnverifiedTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.opticalUnverifiedBody),
                  if (header.isLegacy) ...[
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.opticalLegacyWarning,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SelectableText(context.l10n.opticalFingerprint(fingerprint)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.l10n.actionReject),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(context.l10n.opticalAcceptUnverified),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _onData(OpticalDataSymbol symbol) {
    final header = _header;
    if (header == null || _decoder == null) return;
    if (!_sameId(header.transferId, symbol.transferId)) return;
    if (_pendingSymbols.length < 256) {
      _pendingSymbols.add((
        symbol.symbolIndex,
        Uint8List.fromList(symbol.payload),
      ));
    }
    unawaited(_drainSymbols());
  }

  Future<void> _drainSymbols() async {
    if (_decoding || _finishing) return;
    _decoding = true;
    try {
      while (_pendingSymbols.isNotEmpty && !_finishing) {
        final header = _header;
        final decoder = _decoder;
        if (header == null || decoder == null) return;
        final take = _pendingSymbols.length.clamp(0, 32);
        final batch = _pendingSymbols.sublist(0, take);
        _pendingSymbols.removeRange(0, take);
        final updated = await FountainDecoder.addSymbolsInIsolate(
          decoder,
          batch,
        );
        if (!mounted || !identical(decoder, _decoder)) return;
        _decoder = updated;
        setState(() {});
        if (updated.isComplete) {
          _finishing = true;
          await _finish(header, updated);
        }
      }
    } finally {
      _decoding = false;
    }
  }

  Future<void> _finish(OpticalHeader header, FountainDecoder decoder) async {
    await _scanner.stop();
    try {
      final data = await decoder.assembleInIsolate(header.fileSize);
      final digest = await TransferCrypto.hashBytes(data);
      if (!_sameId(digest, header.sha256)) {
        throw StateError(currentL10n.opticalShaFailed);
      }
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(
        p.join(documents.path, 'hearthbit_transfers'),
      );
      await directory.create(recursive: true);
      final safeName = sanitizeFileName(header.fileName);
      final path = p.join(
        directory.path,
        '${_hex(header.transferId)}_$safeName',
      );
      await File(path).writeAsBytes(data, flush: true);
      await widget.transfers!.registerOpticalReceived(
        transferIdHex: _hex(header.transferId),
        fileName: safeName,
        fileSize: header.fileSize,
        sha256Hex: _hex(header.sha256),
        chunkSize: header.chunkSize,
        filePath: path,
        peerId: header.senderPeerId,
      );
      await _confirmViaMesh(header);
      if (!mounted) return;
      setState(() => _savedPath = path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is StateError ? error.message : error.toString();
        _finishing = false;
        _header = null;
        _decoder = null;
      });
      await _scanner.start();
    }
  }

  /// Backchannel opcional: solo funciona si existe sesión Noise con el
  /// emisor; si no, el fallo se ignora y el emisor sigue en modo rateless.
  Future<void> _confirmViaMesh(OpticalHeader header) async {
    if (header.senderPeerId.isEmpty) return;
    try {
      final frame = TransferFrame(TransferProtocol.typeComplete)
        ..setBytes(TransferProtocol.tagTransferId, header.transferId);
      await MeshPlatformService().sendTransferFrame(
        header.senderPeerId,
        frame.encode(),
      );
    } catch (_) {}
  }

  bool _sameId(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final header = _header;
    final decoder = _decoder;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.receiveByQr)),
      body: SafeArea(
        child: _emergencyReceived != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.crisis_alert,
                        size: 72,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.sosQrRelayed,
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        _emergencyReceived!,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(context.l10n.actionDone),
                      ),
                    ],
                  ),
                ),
              )
            : _savedPath != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 72,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.opticalSavedTitle(
                          header?.fileName ?? context.l10n.genericFile,
                        ),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      if (_trust != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _trust == _OpticalTrust.verified
                              ? context.l10n.opticalVerifiedSource
                              : context.l10n.opticalUnverifiedTitle,
                          style: TextStyle(
                            color: _trust == _OpticalTrust.verified
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(_savedPath!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(context.l10n.actionDone),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: MobileScanner(
                      controller: _scanner,
                      onDetect: _onDetect,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (_error != null)
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          )
                        else if (header == null)
                          Text(
                            context.l10n.opticalScanHint,
                            textAlign: TextAlign.center,
                          )
                        else ...[
                          Text(
                            context.l10n.opticalReceiveStats(
                              header.fileName,
                              decoder?.decodedCount ?? 0,
                              header.chunkCount,
                              decoder?.symbolsReceived ?? 0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: header.chunkCount == 0
                                ? 0
                                : (decoder?.decodedCount ?? 0) /
                                      header.chunkCount,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

enum _OpticalTrust { verified, unverified, legacy }
