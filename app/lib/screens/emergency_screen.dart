import 'package:flutter/material.dart';

import '../controllers/mesh_controller.dart';
import '../controllers/emergency_gateway_controller.dart';
import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../services/app_preferences.dart';
import 'emergency_gateway_card.dart';
import 'map_screen.dart';
import 'radar_screen.dart';
import 'rescue_power_cards.dart';

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({
    required this.controller,
    required this.preferences,
    required this.gateway,
    super.key,
  });

  final MeshController controller;
  final AppPreferences preferences;
  final EmergencyGatewayController gateway;

  @override
  Widget build(BuildContext context) {
    final sosMessages = controller.messages
        .where((message) => message.isSos)
        .toList(growable: false)
        .reversed;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          context.l10n.emergencyHeadline,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(context.l10n.emergencyInstructions, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        Center(
          child: _HoldSosButton(
            enabled: !controller.activatingEmergency,
            active: controller.rescueMode,
            onActivated: () => controller.activateEmergency(),
          ),
        ),
        const SizedBox(height: 16),
        if (controller.rescueMode)
          FilledButton.tonalIcon(
            onPressed: () => controller.setRescueMode(false),
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(context.l10n.emergencyStopRescue),
          ),
        const SizedBox(height: 24),
        _CheckInPanel(controller: controller),
        const SizedBox(height: 16),
        RescueModeCard(controller: controller),
        const SizedBox(height: 12),
        PowerSavingCard(controller: controller),
        const SizedBox(height: 12),
        EmergencyGatewayCard(controller: gateway, preferences: preferences),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MapScreen(controller: controller),
            ),
          ),
          icon: const Icon(Icons.map_outlined),
          label: Text(context.l10n.mapOpenRescue),
        ),
        const SizedBox(height: 24),
        Text(
          context.l10n.checkInRecentTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (controller.latestCheckIns.isEmpty)
          Text(context.l10n.checkInNone)
        else
          ...controller.latestCheckIns.map(
            (checkIn) => _CheckInTile(checkIn: checkIn),
          ),
        const SizedBox(height: 24),
        Text(
          context.l10n.sosReceivedTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (sosMessages.isEmpty)
          Text(context.l10n.sosNoneReceived)
        else
          ...sosMessages.map(
            (message) => Card(
              child: ListTile(
                leading: Icon(
                  Icons.crisis_alert,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(message.sender),
                subtitle: Text(
                  '${message.sosDescription}\n'
                  '${_formatDateTime(context, message.timestamp)}',
                ),
                isThreeLine: true,
                trailing: _radarButton(context, message),
              ),
            ),
          ),
      ],
    );
  }

  Widget? _radarButton(BuildContext context, MeshMessage message) {
    if (message.isMine) return null;
    final peer = controller.peerById(message.senderPeerId);
    if (peer?.radarAllowed != true) return null;
    return IconButton.filledTonal(
      tooltip: context.l10n.actionTrack,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RadarScreen(
            peerId: message.senderPeerId,
            nickname: message.sender,
            consentExpiresAt: peer!.radarAllowedUntil!,
            consentSource: peer.radarConsentSource ?? 'sos',
            latitude: message.sosLatitude,
            longitude: message.sosLongitude,
          ),
        ),
      ),
      icon: const Icon(Icons.radar),
    );
  }
}

class _HoldSosButton extends StatefulWidget {
  const _HoldSosButton({
    required this.enabled,
    required this.active,
    required this.onActivated,
  });

  final bool enabled;
  final bool active;
  final Future<void> Function() onActivated;

  @override
  State<_HoldSosButton> createState() => _HoldSosButtonState();
}

class _HoldSosButtonState extends State<_HoldSosButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  var _triggered = false;

  @override
  void initState() {
    super.initState();
    _progress =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && !_triggered) {
              _triggered = true;
              widget.onActivated();
            }
          });
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _start() {
    if (!widget.enabled || widget.active) return;
    _triggered = false;
    _progress.forward(from: 0);
  }

  void _cancel() {
    if (_triggered) return;
    _progress.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.active
          ? context.l10n.emergencySosActive
          : context.l10n.emergencyHoldSos,
      onLongPress: _start,
      child: Listener(
        onPointerDown: (_) => _start(),
        onPointerUp: (_) => _cancel(),
        onPointerCancel: (_) => _cancel(),
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, child) => SizedBox.square(
            dimension: 210,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.square(
                  dimension: 210,
                  child: CircularProgressIndicator(
                    value: widget.active ? 1 : _progress.value,
                    strokeWidth: 12,
                    color: widget.active ? scheme.primary : scheme.error,
                    backgroundColor: scheme.errorContainer,
                  ),
                ),
                Material(
                  color: widget.active ? scheme.primary : scheme.error,
                  shape: const CircleBorder(),
                  elevation: 6,
                  child: SizedBox.square(
                    dimension: 178,
                    child: Center(
                      child: widget.enabled
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  widget.active ? Icons.shield : Icons.sos,
                                  size: 64,
                                  color: widget.active
                                      ? scheme.onPrimary
                                      : scheme.onError,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  widget.active
                                      ? context.l10n.emergencySosActive
                                      : context.l10n.emergencyHoldSos,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: widget.active
                                            ? scheme.onPrimary
                                            : scheme.onError,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            )
                          : CircularProgressIndicator(color: scheme.onError),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckInPanel extends StatelessWidget {
  const _CheckInPanel({required this.controller});

  final MeshController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.checkInTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(context.l10n.checkInBody),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: controller.canSend
                  ? () => controller.sendCheckIn(
                      CheckInStatus.ok,
                      context.l10n.checkInOk,
                    )
                  : null,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(context.l10n.checkInOk),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: controller.canSend
                  ? () => controller.sendCheckIn(
                      CheckInStatus.needsHelp,
                      context.l10n.checkInNeedsHelp,
                    )
                  : null,
              icon: const Icon(Icons.front_hand_outlined),
              label: Text(context.l10n.checkInNeedsHelp),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: controller.canSend
                  ? () => controller.sendCheckIn(
                      CheckInStatus.injured,
                      context.l10n.checkInInjured,
                    )
                  : null,
              icon: const Icon(Icons.medical_services_outlined),
              label: Text(context.l10n.checkInInjured),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckInTile extends StatelessWidget {
  const _CheckInTile({required this.checkIn});

  final EmergencyCheckIn checkIn;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (checkIn.status) {
      CheckInStatus.ok => (Icons.check_circle, Colors.green),
      CheckInStatus.needsHelp => (Icons.front_hand, Colors.orange),
      CheckInStatus.injured => (
        Icons.medical_services,
        Theme.of(context).colorScheme.error,
      ),
    };
    final coordinates = checkIn.latitude != null && checkIn.longitude != null
        ? '\nGPS ${checkIn.latitude!.toStringAsFixed(5)}, '
              '${checkIn.longitude!.toStringAsFixed(5)}'
        : '';
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(checkIn.sender),
        subtitle: Text(
          '${checkIn.message}$coordinates\n'
          '${_formatDateTime(context, checkIn.timestamp)}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

String _formatDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final material = MaterialLocalizations.of(context);
  return '${material.formatShortDate(local)} · '
      '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}
