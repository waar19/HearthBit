import 'dart:async';

import 'package:flutter/material.dart' hide DiagnosticLevel;

import '../controllers/mesh_controller.dart';
import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../services/diagnostics_export_service.dart';
import '../services/diagnostics_log.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({required this.controller, super.key});

  final MeshController controller;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final _export = DiagnosticsExportService();
  bool _refreshing = false;

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
    final controller = widget.controller;
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
      },
    );
    try {
      final anchor = anchorContext.findRenderObject() as RenderBox?;
      await _export.share(
        anchor: anchor,
        subject: context.l10n.diagnosticsExportSubject,
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
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
                  onPressed: () => _share(buttonContext),
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
