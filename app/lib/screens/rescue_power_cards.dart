import 'dart:io';

import 'package:flutter/material.dart';

import '../controllers/mesh_controller.dart';
import '../l10n/l10n.dart';

/// Tarjeta del modo rescate: reenvía el SOS con GPS fresco periódicamente
/// para que los rescatistas puedan seguir la posición de la persona.
class RescueModeCard extends StatelessWidget {
  const RescueModeCard({required this.controller, super.key});

  final MeshController controller;

  @override
  Widget build(BuildContext context) {
    final minutes = MeshController.rescueInterval.inMinutes;
    final l10n = context.l10n;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.my_location),
            title: Text(
              l10n.rescueModeTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              controller.rescueMode
                  ? '${l10n.rescueModeActive(minutes)}'
                        '${controller.lastRescuePing != null ? " ${l10n.rescueModeLastPing(_hourLabel(controller.lastRescuePing!))}" : ""}'
                  : l10n.rescueModeInactive(minutes),
            ),
            value: controller.rescueMode,
            onChanged: controller.canSend
                ? (value) => controller.setRescueMode(value)
                : null,
          ),
          if (controller.rescueMode && !controller.backgroundLocationGranted)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.rescueModeNoBackgroundLocation,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: controller.ensureAlwaysLocation,
                    child: Text(l10n.actionAllow),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _hourLabel(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// Lista de verificación de energía: qué desactivar o conceder para que la
/// malla y el GPS sobrevivan en segundo plano sin agotar la batería.
class PowerSavingCard extends StatelessWidget {
  const PowerSavingCard({required this.controller, super.key});

  final MeshController controller;

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.battery_saver),
              title: Text(
                l10n.powerCardTitle,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(l10n.powerCardSubtitle),
            ),
            if (isAndroid)
              _StatusRow(
                ok: controller.ignoringBatteryOptimizations,
                label: l10n.powerBatteryOptimization,
                actionLabel: l10n.actionDisable,
                onAction: controller.requestDisableBatteryOptimizations,
              ),
            _StatusRow(
              ok: controller.backgroundLocationGranted,
              label: isAndroid
                  ? l10n.powerLocationAndroid
                  : l10n.powerLocationIos,
              actionLabel: l10n.actionAllow,
              onAction: controller.ensureAlwaysLocation,
            ),
            if (controller.lowPowerMode)
              _StatusRow(
                ok: false,
                label: isAndroid ? l10n.powerSaverAndroid : l10n.powerSaverIos,
              ),
            ExpansionTile(
              leading: const Icon(Icons.tips_and_updates_outlined),
              title: Text(l10n.powerTipsTitle),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                for (final tip in _tips(l10n, isAndroid))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• $tip',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<String> _tips(AppLocalizations l10n, bool isAndroid) => [
    l10n.powerTipBrightness,
    l10n.powerTipMobileData,
    l10n.powerTipCloseApps,
    if (isAndroid) ...[
      l10n.powerTipAndroidRecents,
      l10n.powerTipAndroidVendor,
      l10n.powerTipAndroidSync,
    ] else ...[
      l10n.powerTipIosForceClose,
      l10n.powerTipIosBackgroundRefresh,
      l10n.powerTipIosLowPower,
    ],
    l10n.powerTipShareBattery,
  ];
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.ok,
    required this.label,
    this.actionLabel,
    this.onAction,
  });

  final bool ok;
  final String label;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            color: ok ? scheme.primary : scheme.error,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          if (!ok && onAction != null)
            TextButton(
              onPressed: () => onAction!(),
              child: Text(actionLabel ?? context.l10n.actionAdjust),
            ),
        ],
      ),
    );
  }
}
