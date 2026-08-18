import 'dart:async';

import 'package:flutter/material.dart' hide DiagnosticLevel;

import '../controllers/mesh_controller.dart';
import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../services/diagnostics_export_service.dart';
import '../services/diagnostics_log.dart';
import '../services/transport_diagnostics.dart';

class DiagnosticsScreen extends StatefulWidget {
  DiagnosticsScreen({
    required this.controller,
    TransportDiagnostics? transportDiagnostics,
    DiagnosticsExportService? exportService,
    super.key,
  }) : transportDiagnostics =
           transportDiagnostics ?? TransportDiagnostics.instance,
       exportService = exportService ?? DiagnosticsExportService();

  final MeshController controller;
  final TransportDiagnostics transportDiagnostics;
  final DiagnosticsExportService exportService;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool _refreshing = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.controller.refreshPowerStatus();
      await widget.controller.refreshDiagnostics();
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.warning(
        'diagnostics.refresh.failed',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _share(BuildContext anchorContext) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final controller = widget.controller;
    try {
      await controller.refreshDiagnostics();
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.warning(
        'diagnostics.export_refresh.failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.diagnosticsExportRefreshError)),
      );
      setState(() => _exporting = false);
      return;
    }
    if (!mounted) return;
    if (!anchorContext.mounted) {
      setState(() => _exporting = false);
      return;
    }
    DiagnosticsLog.instance.info(
      'diagnostics.snapshot',
      data: {
        'status': controller.status,
        'platform': controller.platformName,
        'nearbyCount': controller.peers.length,
        'presenceCount': controller.genericPresences.length,
        'advertising': controller.meshAdvertising,
        'meshScanActive': controller.meshScanActive,
        'genericScanActive': controller.genericScanActive,
        'batteryLevel': controller.batteryLevel,
        'powerProfile': controller.powerProfile,
        'bleDutyCyclePercent': controller.bleDutyCyclePercent,
        'activeScans': controller.activeBleScans,
        'scanStarts': controller.scanStarts,
        'storeForwardEntries': controller.storeForwardEntries,
        'transportCount': controller.activeTransports.length,
        'operationalCountersLifetime': controller.operationalCountersLifetime,
        ...controller.operationalCounters.toJson(),
      },
    );
    try {
      final anchor = anchorContext.findRenderObject() as RenderBox?;
      await widget.exportService.share(
        anchor: anchor,
        subject: context.l10n.diagnosticsExportSubject,
        operationalCounters: controller.operationalCounters.toJson(),
        operationalCountersLifetime: controller.operationalCountersLifetime,
      );
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.warning(
        'diagnostics.export.failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.diagnosticsExportError)),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.transportDiagnostics,
      ]),
      builder: (context, _) {
        final controller = widget.controller;
        final transportDiagnostics = widget.transportDiagnostics;
        return Scaffold(
          appBar: AppBar(
            title: Text(context.l10n.diagnosticsTitle),
            actions: [
              IconButton(
                tooltip: context.l10n.diagnosticsRefreshTooltip,
                onPressed: _refreshing ? null : _refresh,
                icon: _refreshing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _DiagnosticCard(
                title: context.l10n.diagnosticsMeshSection,
                icon: Icons.hub_outlined,
                rows: [
                  (
                    context.l10n.diagnosticsPlatform,
                    controller.platformName.toUpperCase(),
                  ),
                  (
                    context.l10n.diagnosticsStatus,
                    _statusLabel(context, controller.status),
                  ),
                  (
                    context.l10n.diagnosticsIdentityRotation,
                    controller.lastKeyRotationDiagnostic ?? '—',
                  ),
                  (
                    context.l10n.diagnosticsNearbyDevices,
                    '${controller.peers.length}',
                  ),
                  (
                    context.l10n.diagnosticsAdvertising,
                    _booleanLabel(context, controller.meshAdvertising),
                  ),
                  (
                    context.l10n.diagnosticsMeshScan,
                    _booleanLabel(context, controller.meshScanActive),
                  ),
                  (
                    context.l10n.diagnosticsGenericScan,
                    _booleanLabel(context, controller.genericScanActive),
                  ),
                ],
              ),
              _DiagnosticCard(
                title: context.l10n.diagnosticsEnergySection,
                icon: Icons.battery_saver_outlined,
                rows: [
                  (
                    context.l10n.diagnosticsBattery,
                    '${controller.batteryLevel}%',
                  ),
                  (
                    context.l10n.diagnosticsPowerProfile,
                    controller.powerProfile.wireName,
                  ),
                  (
                    context.l10n.diagnosticsBleDutyCycle,
                    '${controller.bleDutyCyclePercent}%',
                  ),
                  (
                    context.l10n.diagnosticsScanStarts,
                    '${controller.scanStarts}',
                  ),
                  (
                    context.l10n.diagnosticsStoreForward,
                    '${controller.storeForwardEntries}',
                  ),
                ],
              ),
              _DiagnosticCard(
                title: context.l10n.diagnosticsOperationalCountersSection,
                icon: Icons.monitor_heart_outlined,
                rows: [
                  (
                    context.l10n.diagnosticsOpenEmergencyLimitedKnown,
                    '${controller.operationalCounters.openEmergencyRateLimitedKnown}',
                  ),
                  (
                    context.l10n.diagnosticsOpenEmergencyLimitedUnknown,
                    '${controller.operationalCounters.openEmergencyRateLimitedUnknown}',
                  ),
                  (
                    context.l10n.diagnosticsRelaySuppressed,
                    '${controller.operationalCounters.relayDampingSuppressed}',
                  ),
                  (
                    context.l10n.diagnosticsRelayScheduled,
                    '${controller.operationalCounters.relayDampingScheduled}',
                  ),
                  (
                    context.l10n.diagnosticsRelayExpired,
                    '${controller.operationalCounters.relayDampingExpired}',
                  ),
                  (
                    context.l10n.diagnosticsTrustEvictions,
                    '${controller.operationalCounters.trustStoreEvictions}',
                  ),
                  (
                    context.l10n.diagnosticsTrustConflicts,
                    '${controller.operationalCounters.trustConflicts}',
                  ),
                  (
                    context.l10n.diagnosticsOperationalCountersLifetime,
                    controller.operationalCountersLifetime == 'process'
                        ? context.l10n.diagnosticsLifetimeProcess
                        : context.l10n.diagnosticsLifetimeUnknown,
                  ),
                ],
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle(
                        icon: Icons.route_outlined,
                        title: context.l10n.diagnosticsTransportsSection,
                      ),
                      const SizedBox(height: 12),
                      if (controller.activeTransports.isEmpty)
                        Text(context.l10n.diagnosticsNoActiveTransports)
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: controller.activeTransports
                              .map(
                                (transport) =>
                                    Chip(label: Text(transport.toUpperCase())),
                              )
                              .toList(growable: false),
                        ),
                    ],
                  ),
                ),
              ),
              _DiagnosticCard(
                title: context.l10n.diagnosticsTransportOutcomesSection,
                icon: Icons.analytics_outlined,
                rows: [
                  for (final transport in DiagnosticTransport.values)
                    (
                      _transportLabel(context, transport),
                      _transportOutcomeLabel(
                        context,
                        transportDiagnostics.forTransport(transport),
                      ),
                    ),
                ],
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle(
                        icon: Icons.receipt_long_outlined,
                        title: context.l10n.diagnosticsEventsSection,
                      ),
                      const SizedBox(height: 8),
                      ..._eventTiles(context),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (buttonContext) => FilledButton.icon(
                  onPressed: _exporting ? null : () => _share(buttonContext),
                  icon: const Icon(Icons.ios_share),
                  label: Text(context.l10n.diagnosticsExportButton),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _eventTiles(BuildContext context) {
    final entries = DiagnosticsLog.instance.entries.reversed.take(20).toList();
    if (entries.isEmpty) {
      return [Text(context.l10n.diagnosticsNoEvents)];
    }
    return entries
        .map(
          (entry) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(switch (entry.level) {
              DiagnosticLevel.info => Icons.info_outline,
              DiagnosticLevel.warning => Icons.warning_amber_outlined,
              DiagnosticLevel.error => Icons.error_outline,
            }),
            title: Text(entry.event),
            subtitle: Text(
              TimeOfDay.fromDateTime(entry.timestamp.toLocal()).format(context),
            ),
          ),
        )
        .toList(growable: false);
  }

  String _booleanLabel(BuildContext context, bool value) => value
      ? context.l10n.diagnosticsEnabled
      : context.l10n.diagnosticsDisabled;

  String _transportOutcomeLabel(
    BuildContext context,
    TransportOutcomeCounters counters,
  ) => context.l10n.diagnosticsTransportOutcome(
    counters.successes,
    counters.failures,
  );

  String _transportLabel(BuildContext context, DiagnosticTransport transport) {
    return switch (transport) {
      DiagnosticTransport.ble => context.l10n.transportBle,
      DiagnosticTransport.lan => context.l10n.transportLan,
      DiagnosticTransport.wifiDirect => context.l10n.transportWifiDirect,
      DiagnosticTransport.wifiAware => context.l10n.transportWifiAware,
      DiagnosticTransport.multipeer => context.l10n.transportMultipeer,
      DiagnosticTransport.audio => context.l10n.diagnosticsTransportAudio,
      DiagnosticTransport.qr => context.l10n.diagnosticsTransportQr,
      DiagnosticTransport.external => context.l10n.diagnosticsTransportExternal,
    };
  }

  String _statusLabel(BuildContext context, MeshConnectionStatus status) {
    return switch (status) {
      MeshConnectionStatus.active => context.l10n.statusActiveLabel(
        context.l10n.statusBannerYou,
        widget.controller.peers.length,
      ),
      MeshConnectionStatus.degraded => context.l10n.statusDegradedLabel(
        context.l10n.statusBannerYou,
      ),
      MeshConnectionStatus.starting => context.l10n.statusStarting,
      MeshConnectionStatus.error => context.l10n.statusError,
      MeshConnectionStatus.stopped => context.l10n.statusStopped,
    };
  }
}

class _DiagnosticCard extends StatelessWidget {
  const _DiagnosticCard({
    required this.title,
    required this.icon,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(icon: icon, title: title),
            const SizedBox(height: 8),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(label)),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w600),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
