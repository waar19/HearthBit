import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../l10n/l10n.dart';
import '../services/fountain_code.dart';
import '../services/mesh_platform_service.dart';
import '../services/optical_protocol.dart';
import '../services/transfer_protocol.dart';

/// Emisor óptico: muestra una secuencia de QR con símbolos fountain.
///
/// El receptor puede engancharse en cualquier momento (la cabecera se repite
/// cada pocos frames) y no necesita canal de retorno. Si ambos teléfonos
/// además comparten sesión de malla, el receptor confirma la recepción por
/// BLE y el emisor se detiene automáticamente.
class OpticalSendScreen extends StatefulWidget {
  const OpticalSendScreen({
    required this.filePath,
    required this.fileName,
    this.senderPeerId = '',
    super.key,
  });

  final String filePath;
  final String fileName;
  final String senderPeerId;

  @override
  State<OpticalSendScreen> createState() => _OpticalSendScreenState();
}

enum _Density {
  compact(200),
  medium(420),
  high(650);

  const _Density(this.chunkSize);

  final int chunkSize;

  String label(AppLocalizations l10n) => switch (this) {
    _Density.compact => l10n.densityCompact,
    _Density.medium => l10n.densityMedium,
    _Density.high => l10n.densityHigh,
  };
}

class _OpticalSendScreenState extends State<OpticalSendScreen> {
  static const int _headerEvery = 8;

  final MeshPlatformService _mesh = MeshPlatformService();
  StreamSubscription<Map<Object?, Object?>>? _meshSubscription;

  Uint8List? _fileBytes;
  Uint8List _sha256 = Uint8List(32);
  Uint8List _transferId = Uint8List(16);
  int _seed = 0;

  FountainEncoder? _encoder;
  String? _headerContent;
  Timer? _timer;
  int _frameCounter = 0;
  int _symbolIndex = 0;
  double _fps = 8;
  _Density _density = _Density.medium;
  String? _currentQr;
  bool _confirmed = false;
  String? _error;
  int _encoderGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
    _meshSubscription = _mesh.events.listen(_handleMeshEvent, onError: (_) {});
  }

  Future<void> _prepare() async {
    try {
      final bytes = await File(widget.filePath).readAsBytes();
      if (bytes.isEmpty) {
        setState(() => _error = currentL10n.opticalFileEmpty);
        return;
      }
      final random = Random.secure();
      setState(() {
        _fileBytes = bytes;
        _sha256 = Uint8List.fromList(sha256.convert(bytes).bytes);
        _transferId = Uint8List.fromList(
          List.generate(16, (_) => random.nextInt(256)),
        );
        _seed = random.nextInt(0xffffffff);
      });
      await _rebuildEncoder();
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  /// Cambiar la densidad altera el tamaño de chunk, así que se reinicia la
  /// sesión con un nuevo transferId: el receptor se resincroniza al ver la
  /// nueva cabecera.
  Future<void> _rebuildEncoder() async {
    final bytes = _fileBytes;
    if (bytes == null) return;
    final generation = ++_encoderGeneration;
    final random = Random.secure();
    _transferId = Uint8List.fromList(
      List.generate(16, (_) => random.nextInt(256)),
    );
    _seed = random.nextInt(0xffffffff);
    _encoder = FountainEncoder(
      data: bytes,
      chunkSize: _density.chunkSize,
      seed: _seed,
    );
    final unsignedHeader = OpticalHeader(
      transferId: _transferId,
      seed: _seed,
      fileSize: bytes.length,
      chunkSize: _density.chunkSize,
      chunkCount: _encoder!.chunkCount,
      sha256: _sha256,
      fileName: widget.fileName,
      senderPeerId: widget.senderPeerId,
      protocolVersion: OpticalProtocol.version,
    );
    Uint8List signature;
    try {
      signature = await _mesh.signPayload(
        OpticalProtocol.signingPayload(unsignedHeader),
      );
    } catch (error) {
      if (mounted && generation == _encoderGeneration) {
        setState(() => _error = error.toString());
      }
      return;
    }
    if (!mounted || generation != _encoderGeneration) return;
    _headerContent = OpticalProtocol.encodeHeader(
      OpticalHeader(
        transferId: unsignedHeader.transferId,
        seed: unsignedHeader.seed,
        fileSize: unsignedHeader.fileSize,
        chunkSize: unsignedHeader.chunkSize,
        chunkCount: unsignedHeader.chunkCount,
        sha256: unsignedHeader.sha256,
        fileName: unsignedHeader.fileName,
        senderPeerId: unsignedHeader.senderPeerId,
        protocolVersion: OpticalProtocol.version,
        signature: signature,
      ),
    );
    _frameCounter = 0;
    _symbolIndex = 0;
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_confirmed) return;
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / _fps).round()),
      (_) => _nextFrame(),
    );
  }

  void _nextFrame() {
    final encoder = _encoder;
    if (encoder == null || _confirmed) return;
    String content;
    if (_frameCounter % _headerEvery == 0) {
      content = _headerContent!;
    } else {
      content = OpticalProtocol.encodeData(
        transferId: _transferId,
        symbolIndex: _symbolIndex,
        payload: encoder.encodeSymbol(_symbolIndex),
      );
      _symbolIndex += 1;
    }
    _frameCounter += 1;
    setState(() => _currentQr = content);
  }

  void _handleMeshEvent(Map<Object?, Object?> event) {
    if (event['type'] != 'transferFrame') return;
    final bytes = event['frame'] as Uint8List?;
    if (bytes == null) return;
    final frame = TransferFrame.decode(bytes);
    if (frame == null || frame.type != TransferProtocol.typeComplete) return;
    final id = frame.bytes(TransferProtocol.tagTransferId);
    if (id == null || id.length != _transferId.length) return;
    for (var i = 0; i < id.length; i++) {
      if (id[i] != _transferId[i]) return;
    }
    _timer?.cancel();
    setState(() => _confirmed = true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _meshSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final encoder = _encoder;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.sendByQr)),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(_error!))
            : encoder == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      context.l10n.opticalSendStats(
                        widget.fileName,
                        encoder.chunkCount,
                        _symbolIndex + 1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _confirmed
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 72,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  context.l10n.opticalConfirmed,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            )
                          : _currentQr == null
                          ? const CircularProgressIndicator()
                          : Padding(
                              padding: const EdgeInsets.all(16),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: ColoredBox(
                                  color: Colors.white,
                                  child: CustomPaint(
                                    painter: QrFramePainter(_currentQr!),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  if (!_confirmed)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text(context.l10n.opticalSpeedLabel),
                              Expanded(
                                child: Slider(
                                  value: _fps,
                                  min: 2,
                                  max: 15,
                                  divisions: 13,
                                  label: context.l10n.opticalFps(_fps.round()),
                                  onChanged: (value) {
                                    setState(() => _fps = value);
                                    _restartTimer();
                                  },
                                ),
                              ),
                            ],
                          ),
                          SegmentedButton<_Density>(
                            segments: _Density.values
                                .map(
                                  (density) => ButtonSegment(
                                    value: density,
                                    label: Text(density.label(context.l10n)),
                                  ),
                                )
                                .toList(),
                            selected: {_density},
                            onSelectionChanged: (selection) {
                              setState(() => _density = selection.first);
                              unawaited(_rebuildEncoder());
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              context.l10n.opticalSendHint,
                              style: const TextStyle(fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Pinta un QR generado con el paquete `qr` (sin dependencias de imagen).
class QrFramePainter extends CustomPainter {
  QrFramePainter(this.data) {
    final code = QrCode(
      payload: QrPayload.fromString(data),
      errorCorrectLevel: QrErrorCorrectLevel.low,
    );
    _image = QrImage(code);
  }

  final String data;
  late final QrImage _image;

  @override
  void paint(Canvas canvas, Size size) {
    final paintDark = Paint()..color = const Color(0xFF000000);
    final modules = _image.moduleCount;
    final cell = size.shortestSide / (modules + 2); // margen de 1 módulo
    final offset = cell;
    for (var row = 0; row < modules; row++) {
      for (var col = 0; col < modules; col++) {
        if (_image.isDark(row, col)) {
          canvas.drawRect(
            Rect.fromLTWH(
              offset + col * cell,
              offset + row * cell,
              cell + 0.5,
              cell + 0.5,
            ),
            paintDark,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant QrFramePainter oldDelegate) =>
      oldDelegate.data != data;
}
