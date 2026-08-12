import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../controllers/transfer_controller.dart';
import '../services/fountain_code.dart';
import '../services/mesh_platform_service.dart';
import '../services/optical_protocol.dart';
import '../services/transfer_protocol.dart';

/// Receptor óptico: escanea la secuencia de QR y reconstruye el archivo con
/// el decodificador fountain. No necesita canal de retorno; si hay sesión de
/// malla con el emisor, envía una confirmación BLE al terminar.
class OpticalReceiveScreen extends StatefulWidget {
  const OpticalReceiveScreen({required this.transfers, super.key});

  final TransferController transfers;

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
  String? _error;
  bool _finishing = false;

  void _onDetect(BarcodeCapture capture) {
    if (_savedPath != null || _finishing) return;
    for (final barcode in capture.barcodes) {
      final content = barcode.rawValue;
      if (content == null) continue;
      final symbol = OpticalProtocol.decode(content);
      if (symbol is OpticalHeader) {
        _onHeader(symbol);
      } else if (symbol is OpticalDataSymbol) {
        _onData(symbol);
      }
    }
  }

  void _onHeader(OpticalHeader header) {
    if (_header != null && _sameId(_header!.transferId, header.transferId)) {
      return;
    }
    // Cabecera nueva: el emisor reinició la sesión (o es otra transferencia).
    setState(() {
      _header = header;
      _decoder = FountainDecoder(
        chunkCount: header.chunkCount,
        chunkSize: header.chunkSize,
        seed: header.seed,
      );
      _error = null;
    });
  }

  void _onData(OpticalDataSymbol symbol) {
    final header = _header;
    final decoder = _decoder;
    if (header == null || decoder == null) return;
    if (!_sameId(header.transferId, symbol.transferId)) return;
    final progressed = decoder.addSymbol(symbol.symbolIndex, symbol.payload);
    if (progressed) setState(() {});
    if (decoder.isComplete) {
      _finishing = true;
      unawaited(_finish(header, decoder));
    }
  }

  Future<void> _finish(OpticalHeader header, FountainDecoder decoder) async {
    await _scanner.stop();
    try {
      final data = decoder.assemble(header.fileSize);
      final digest = Uint8List.fromList(sha256.convert(data).bytes);
      if (!_sameId(digest, header.sha256)) {
        throw StateError('La verificación SHA-256 falló; reinicia el envío');
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
      await widget.transfers.registerOpticalReceived(
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
        _error = error.toString();
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
      appBar: AppBar(title: const Text('Recibir por QR')),
      body: SafeArea(
        child: _savedPath != null
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
                        '${header?.fileName ?? "Archivo"} verificado y guardado',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(_savedPath!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('LISTO'),
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
                          const Text(
                            'Apunta la cámara al QR del emisor. La cabecera '
                            'se repite cada pocos frames.',
                            textAlign: TextAlign.center,
                          )
                        else ...[
                          Text(
                            '${header.fileName} · '
                            '${decoder?.decodedCount ?? 0} de '
                            '${header.chunkCount} chunks · '
                            '${decoder?.symbolsReceived ?? 0} símbolos',
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
