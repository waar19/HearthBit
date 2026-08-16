import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import 'diagnostics_log.dart';
import 'transport_diagnostics.dart';

typedef DiagnosticsShareInvoker =
    Future<ShareResult> Function(ShareParams params);

class DiagnosticsExportService {
  DiagnosticsExportService({
    DiagnosticsLog? log,
    TransportDiagnostics? transportDiagnostics,
    DiagnosticsShareInvoker? share,
  }) : _log = log ?? DiagnosticsLog.instance,
       _transportDiagnostics =
           transportDiagnostics ?? TransportDiagnostics.instance,
       _share = share ?? SharePlus.instance.share;

  final DiagnosticsLog _log;
  final TransportDiagnostics _transportDiagnostics;
  final DiagnosticsShareInvoker _share;

  Future<ShareResult> share({
    required RenderBox? anchor,
    required String subject,
  }) async {
    _log.info(
      'diagnostics.transport.outcomes',
      data: _transportDiagnostics.exportData(),
    );
    final file = await _log.createExportFile();
    final origin = anchor == null || !anchor.hasSize
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : anchor.localToGlobal(Offset.zero) & anchor.size;
    return _share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: subject,
        title: subject,
        sharePositionOrigin: origin,
      ),
    );
  }
}
