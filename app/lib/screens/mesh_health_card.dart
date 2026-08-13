import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/mesh_controller.dart';
import '../l10n/l10n.dart';
import '../models/mesh_models.dart';

class MeshHealthCard extends StatelessWidget {
  const MeshHealthCard({required this.controller, super.key});

  final MeshController controller;

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
                  Text(context.l10n.meshHealthTrunks(trunks)),
                  Text(context.l10n.meshHealthSignals(signals)),
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
