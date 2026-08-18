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
    final interruption = controller.meshInterruptionReason;
    final (color, accent, icon, label) = switch ((interruption, status)) {
      (MeshInterruptionReason.permissionsRevoked, _) => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.no_accounts_outlined,
        context.l10n.statusMeshPermissionsRevoked,
      ),
      (MeshInterruptionReason.batteryRestricted, _) => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.battery_alert_outlined,
        context.l10n.statusMeshBatteryRestricted,
      ),
      (MeshInterruptionReason.unavailable, _) => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.portable_wifi_off_outlined,
        context.l10n.statusMeshSuspended,
      ),
      (null, MeshConnectionStatus.active) => (
        scheme.surfaceContainerHigh,
        scheme.primary,
        Icons.bluetooth_connected,
        context.l10n.statusActiveLabel(
          displayNickname,
          controller.peers.length,
        ),
      ),
      (null, MeshConnectionStatus.degraded) => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.bluetooth_searching,
        context.l10n.statusDegradedLabel(displayNickname),
      ),
      (null, MeshConnectionStatus.starting) => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.bluetooth_searching,
        context.l10n.statusStarting,
      ),
      (null, MeshConnectionStatus.error) => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.bluetooth_disabled,
        context.l10n.statusError,
      ),
      (null, MeshConnectionStatus.stopped) => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.bluetooth_disabled,
        context.l10n.statusStopped,
      ),
    };
    final (action, actionLabel) = switch ((interruption, status)) {
      (MeshInterruptionReason.batteryRestricted, _) => (
        controller.requestDisableBatteryOptimizations,
        context.l10n.actionAdjust,
      ),
      (MeshInterruptionReason.permissionsRevoked, _) => (
        controller.start,
        context.l10n.actionRetry,
      ),
      (MeshInterruptionReason.unavailable, _) => (
        controller.start,
        context.l10n.actionRestart,
      ),
      (null, MeshConnectionStatus.active) => (
        controller.stop,
        context.l10n.actionStop,
      ),
      (null, MeshConnectionStatus.degraded) => (
        controller.start,
        context.l10n.actionRestart,
      ),
      (null, MeshConnectionStatus.starting) => (null, null),
      (null, MeshConnectionStatus.error) ||
      (null, MeshConnectionStatus.stopped) => (
        controller.start,
        context.l10n.actionActivate,
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
            if (action == null)
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              FilledButton.tonal(
                onPressed: action,
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}
