import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import 'diagnostics_log.dart';

typedef DiagnosticsShareInvoker =
    Future<ShareResult> Function(ShareParams params);

class DiagnosticsExportService {
  DiagnosticsExportService({
    DiagnosticsLog? log,
    DiagnosticsShareInvoker? share,
  }) : _log = log ?? DiagnosticsLog.instance,
       _share = share ?? SharePlus.instance.share;

  final DiagnosticsLog _log;
  final DiagnosticsShareInvoker _share;

  Future<ShareResult> share({
    required RenderBox? anchor,
    required String subject,
  }) async {
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
