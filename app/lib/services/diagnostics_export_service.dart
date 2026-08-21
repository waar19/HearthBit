import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../models/mesh_models.dart';
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
    Map<String, int> operationalCounters = const {},
    String operationalCountersLifetime = 'unknown',
    SosOperationalMetrics sosMetrics = const SosOperationalMetrics(),
  }) async {
    _log.info(
      'diagnostics.transport.outcomes',
      data: _transportDiagnostics.exportData(),
    );
    includeOperationalCounters(
      operationalCounters,
      lifetime: operationalCountersLifetime,
    );
    includeSosMetrics(sosMetrics);
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

  void includeOperationalCounters(
    Map<String, int> counters, {
    String lifetime = 'unknown',
  }) {
    _log.info(
      'diagnostics.operational_counters',
      data: {
        ...counters,
        'operationalCountersLifetime': lifetime == 'process'
            ? 'process'
            : 'unknown',
      },
    );
  }

  void includeSosMetrics(SosOperationalMetrics metrics) {
    _log.info(
      'diagnostics.sos_metrics',
      data: {
        ...metrics.toJson(),
        'firstRelayObserved': 'unavailable',
        'relayStateMeaning': 'local_native_tx',
        'hopCount': 'unavailable',
        'hopCountReason': 'ttl_reset_and_unsigned',
      },
    );
  }
}
