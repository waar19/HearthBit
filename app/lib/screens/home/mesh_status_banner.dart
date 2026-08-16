import 'package:flutter/material.dart';

import '../../controllers/mesh_controller.dart';
import '../../l10n/l10n.dart';
import '../../models/mesh_models.dart';

class MeshStatusBanner extends StatelessWidget {
  const MeshStatusBanner({required this.controller, super.key});

  final MeshController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = controller.status;
    final displayNickname =
        controller.nickname.trim().isEmpty ||
            isDefaultMeshNickname(controller.nickname)
        ? context.l10n.statusBannerYou
        : controller.nickname;
    final (color, accent, icon, label) = switch (status) {
      MeshConnectionStatus.active => (
        scheme.surfaceContainerHigh,
        scheme.primary,
        Icons.bluetooth_connected,
        context.l10n.statusActiveLabel(
          displayNickname,
          controller.peers.length,
        ),
      ),
      MeshConnectionStatus.degraded => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.bluetooth_searching,
        context.l10n.statusDegradedLabel(displayNickname),
      ),
      MeshConnectionStatus.starting => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.bluetooth_searching,
        context.l10n.statusStarting,
      ),
      MeshConnectionStatus.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.bluetooth_disabled,
        context.l10n.statusError,
      ),
      MeshConnectionStatus.stopped => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.bluetooth_disabled,
        context.l10n.statusStopped,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: accent),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
            if (status == MeshConnectionStatus.starting)
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (status == MeshConnectionStatus.active)
              FilledButton.tonal(
                onPressed: controller.stop,
                child: Text(context.l10n.actionStop),
              )
            else if (status == MeshConnectionStatus.degraded)
              FilledButton.tonal(
                onPressed: controller.start,
                child: Text(context.l10n.actionRestart),
              )
            else
              FilledButton.tonal(
                onPressed: controller.start,
                child: Text(context.l10n.actionActivate),
              ),
          ],
        ),
      ),
    );
  }
}
