import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/mesh_controller.dart';
import '../controllers/lan_gateway_controller.dart';
import '../l10n/l10n.dart';
import '../models/mesh_models.dart';

class MeshHealthCard extends StatelessWidget {
  const MeshHealthCard({required this.controller, this.lanGateway, super.key});

  final MeshController controller;
  final LanGatewayController? lanGateway;

  @override
  Widget build(BuildContext context) {
    final peers = controller.peers;
    final relays = peers
        .where(
          (peer) =>
              peer.role == MeshNodeRole.phoneRelay ||
              peer.role == MeshNodeRole.infraRelay,
        )
        .length;
    final anchors = peers
        .where((peer) => peer.role == MeshNodeRole.infraDataAnchor)
        .length;
    final trunks = peers.where((peer) => peer.hasLongRangeTrunk).length;
    final signals = controller.genericPresences.length;
    final summary = [
      context.l10n.meshHealthDirect(peers.length),
      context.l10n.meshHealthRelays(relays),
      context.l10n.meshHealthAnchors(anchors),
      context.l10n.meshHealthTrunks(trunks),
      context.l10n.meshHealthSignals(signals),
      if (lanGateway case final lan?)
        lan.status.connected
            ? context.l10n.lanGatewayConnected
            : lan.enabled
            ? context.l10n.lanGatewaySearching
            : context.l10n.lanGatewayDisabled,
    ].join(', ');

    return Semantics(
      container: true,
      label: '${context.l10n.meshHealthTitle}. $summary',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 340 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.2;
              final rings = ExcludeSemantics(
                child: SizedBox.square(
                  dimension: 112,
                  child: CustomPaint(
                    painter: _MeshRingsPainter(
                      peerRatio: (peers.length / 8).clamp(0, 1),
                      relayRatio: (relays / 4).clamp(0, 1),
                      anchorReady: anchors > 0,
                      colors: Theme.of(context).colorScheme,
                    ),
                    child: Center(
                      child: Text(
                        '${peers.length}',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              );
              final details = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.meshHealthTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(context.l10n.meshHealthDirect(peers.length)),
                  Text(context.l10n.meshHealthRelays(relays)),
                  if (trunks > 0) Text(context.l10n.meshHealthTrunks(trunks)),
                  Text(context.l10n.meshHealthSignals(signals)),
                  if (lanGateway case final lan?) ...[
                    const SizedBox(height: 6),
                    Text(
                      lan.status.connected
                          ? context.l10n.lanGatewayConnected
                          : lan.enabled
                          ? context.l10n.lanGatewaySearching
                          : context.l10n.lanGatewayDisabled,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: lan.status.connected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                    if (lan.status.error case final error?)
                      Text(
                        error,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    TextButton.icon(
                      onPressed: lan.enabled
                          ? lan.disable
                          : () => _configureLan(context, lan),
                      icon: Icon(
                        lan.enabled ? Icons.lan_outlined : Icons.add_link,
                      ),
                      label: Text(
                        lan.enabled
                            ? context.l10n.lanGatewayDisable
                            : context.l10n.lanGatewayConfigure,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    anchors > 0
                        ? context.l10n.meshHealthAnchorReady
                        : context.l10n.meshHealthNoAnchor,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              );
              if (stacked) {
                return Column(
                  children: [
                    rings,
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: details),
                  ],
                );
              }
              return Row(
                children: [
                  rings,
                  const SizedBox(width: 16),
                  Expanded(child: details),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _configureLan(
    BuildContext context,
    LanGatewayController lan,
  ) async {
    final keyController = TextEditingController();
    String? error;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.lanGatewayConfigure),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.lanGatewayPrivacy),
                const SizedBox(height: 12),
                TextField(
                  controller: keyController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: context.l10n.lanGatewayPsk,
                    errorText: error,
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () {
                      keyController.text = lan.generatePairingKey();
                      setDialogState(() => error = null);
                    },
                    child: Text(context.l10n.lanGatewayGeneratePsk),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await lan.enable(keyController.text);
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } on FormatException {
                  setDialogState(
                    () => error = context.l10n.lanGatewayInvalidPsk,
                  );
                }
              },
              child: Text(context.l10n.gatewayEnableAction),
            ),
          ],
        ),
      ),
    );
    keyController.dispose();
    if (accepted == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.lanGatewaySearching)));
    }
  }
}

class _MeshRingsPainter extends CustomPainter {
  const _MeshRingsPainter({
    required this.peerRatio,
    required this.relayRatio,
    required this.anchorReady,
    required this.colors,
  });

  final double peerRatio;
  final double relayRatio;
  final bool anchorReady;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final background = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = colors.surfaceContainerHighest;
    final foreground = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 7;
    for (final radius in [48.0, 36.0, 24.0]) {
      canvas.drawCircle(center, radius, background);
    }
    foreground.color = colors.primary;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 48),
      -math.pi / 2,
      math.pi * 2 * peerRatio,
      false,
      foreground,
    );
    foreground.color = colors.secondary;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 36),
      -math.pi / 2,
      math.pi * 2 * relayRatio,
      false,
      foreground,
    );
    if (anchorReady) {
      foreground.color = colors.tertiary;
      canvas.drawCircle(center, 24, foreground);
    }
  }

  @override
  bool shouldRepaint(covariant _MeshRingsPainter oldDelegate) =>
      peerRatio != oldDelegate.peerRatio ||
      relayRatio != oldDelegate.relayRatio ||
      anchorReady != oldDelegate.anchorReady ||
      colors != oldDelegate.colors;
}
