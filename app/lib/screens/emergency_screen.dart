import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/mesh_controller.dart';
import '../controllers/emergency_gateway_controller.dart';
import '../controllers/family_controller.dart';
import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../services/app_preferences.dart';
import 'emergency_contacts_screen.dart';
import 'emergency_gateway_card.dart';
import 'map_screen.dart';
import 'optical_receive_screen.dart';
import 'radar_screen.dart';
import 'rescue_power_cards.dart';
import 'sos_qr_screen.dart';

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({
    required this.controller,
    required this.preferences,
    required this.gateway,
    required this.family,
    this.emergencyHoldDuration = const Duration(seconds: 2),
    super.key,
  });

  final MeshController controller;
  final AppPreferences preferences;
  final EmergencyGatewayController gateway;
  final FamilyController family;
  final Duration emergencyHoldDuration;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: preferences,
    builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final sosMessages = controller.messages
        .where((message) => message.isSos)
        .toList(growable: false)
        .reversed;
    final drillMode = controller.drillModeEnabled;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (drillMode) ...[_DrillBanner(), const SizedBox(height: 12)],
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
            holdDuration: emergencyHoldDuration,
            onActivated: () => _activateRealEmergency(context),
          ),
        ),
        const SizedBox(height: 16),
        if (controller.rescueMode)
          FilledButton.tonalIcon(
            onPressed: () => _confirmStopRescue(context),
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(context.l10n.emergencyStopRescue),
          ),
        if (controller.rescueMode && controller.latestSosQr != null) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SosQrScreen(bundle: controller.latestSosQr!),
              ),
            ),
            icon: const Icon(Icons.qr_code_2),
            label: Text(context.l10n.sosQrOpen),
          ),
        ],
        if (drillMode && controller.latestDrillQr != null) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SosQrScreen(bundle: controller.latestDrillQr!),
              ),
            ),
            icon: const Icon(Icons.science_outlined),
            label: Text('${context.l10n.drillBadge} · QR'),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => OpticalReceiveScreen(mesh: controller),
            ),
          ),
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(context.l10n.sosQrScan),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: controller.acousticSosListening
              ? controller.stopAcousticSosListening
              : controller.startAcousticSosListening,
          icon: Icon(
            controller.acousticSosListening
                ? Icons.hearing_disabled
                : Icons.hearing,
          ),
          label: Text(
            controller.acousticSosListening
                ? context.l10n.acousticSosStopListening
                : context.l10n.acousticSosListen,
          ),
        ),
        if (controller.rescueMode &&
            controller.emergencyChannelsUsed.isNotEmpty) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.sosChannelsTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: controller.emergencyChannelsUsed
                          .map(
                            (channel) => Chip(
                              label: Text(_emergencyChannelLabel(channel)),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (controller.lastError != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              controller.lastError!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        if (controller.emergencyDeliveries.isNotEmpty) ...[
          const SizedBox(height: 12),
          _EmergencyDeliveryPanel(controller: controller),
        ],
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: drillMode
              ? (controller.localBeaconActive
                    ? controller.stopLocalBeacon
                    : null)
              : controller.localBeaconActive
              ? controller.stopLocalBeacon
              : controller.startLocalBeacon,
          icon: Icon(
            controller.localBeaconActive
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
          label: Text(
            controller.localBeaconActive
                ? context.l10n.beaconStopVisible
                : context.l10n.beaconMakeVisible,
          ),
        ),
        const SizedBox(height: 16),
        _DrillModeCard(
          enabled: drillMode,
          canSend: controller.canSend,
          onEnable: () => _confirmEnableDrill(context),
          onDisable: () => _confirmDisableDrill(context),
          onSend: () => controller.sendDrillCheckIn(
            CheckInStatus.needsHelp,
            context.l10n.drillPracticeMessage,
          ),
        ),
        const SizedBox(height: 24),
        _CheckInPanel(
          controller: controller,
          family: family,
          drillMode: drillMode,
        ),
        const SizedBox(height: 16),
        if (!drillMode) ...[
          RescueModeCard(controller: controller),
          const SizedBox(height: 12),
          PowerSavingCard(controller: controller),
          const SizedBox(height: 12),
        ],
        EmergencyGatewayCard(controller: gateway, preferences: preferences),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EmergencyContactsScreen(preferences: preferences),
            ),
          ),
          icon: const Icon(Icons.contact_phone_outlined),
          label: Text(context.l10n.emergencyContactsOpen),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _composeEmergencySms(context),
          icon: const Icon(Icons.sms_outlined),
          label: Text(context.l10n.emergencySmsOpen),
        ),
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
            (checkIn) => _CheckInTile(
              checkIn: checkIn,
              isFamily: family.verifiedMemberForPeerId(checkIn.peerId) != null,
            ),
          ),
        const SizedBox(height: 24),
        Text(
          context.l10n.drillReceivedTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (controller.drillMessages.isEmpty)
          Text(context.l10n.drillNoneReceived)
        else
          ...controller.drillMessages.map(
            (message) => _DrillMessageTile(message: message),
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
              color: family.isVerifiedFamilyMessage(message)
                  ? Theme.of(context).colorScheme.errorContainer
                  : null,
              child: ListTile(
                leading: Icon(
                  Icons.crisis_alert,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message.sender),
                    if (family.isVerifiedFamilyMessage(message))
                      Text(
                        context.l10n.familyAlertBadge,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (message.external)
                      Text(
                        context.l10n.externalNetworkBadge,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
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

  Future<void> _confirmEnableDrill(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.science_outlined),
        title: Text(context.l10n.drillConfirmTitle),
        content: Text(context.l10n.drillConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.drillEnableAction),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.activateDrill();
  }

  Future<void> _confirmDisableDrill(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.drillDisableTitle),
        content: Text(context.l10n.drillDisableBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.drillDisableAction),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.deactivateDrill();
  }

  Future<void> _confirmStopRescue(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.emergencyStopRescue),
        content: Text(context.l10n.rescueRadarWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.emergencyStopRescue),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.setRescueMode(false);
  }

  Future<void> _activateRealEmergency(BuildContext context) async {
    if (controller.drillModeEnabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(dialogContext).colorScheme.error,
          ),
          title: Text(context.l10n.drillExitForRealTitle),
          content: Text(context.l10n.drillExitForRealBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.l10n.actionCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.l10n.drillSendRealSos),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!context.mounted) return;
    final precision = await _chooseSosLocationPrecision(context);
    if (precision == null) return;
    await controller.activateEmergency(locationPrecision: precision);
  }

  Future<SosLocationPrecision?> _chooseSosLocationPrecision(
    BuildContext context,
  ) async {
    var selected = SosLocationPrecision.approximate;
    return showDialog<SosLocationPrecision>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: Icon(Icons.public, color: Theme.of(context).colorScheme.error),
          title: Text(context.l10n.sosPrivacyTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.sosPrivacyPublicWarning),
                RadioGroup<SosLocationPrecision>(
                  groupValue: selected,
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selected = value);
                    }
                  },
                  child: Column(
                    children: [
                      RadioListTile<SosLocationPrecision>(
                        value: SosLocationPrecision.approximate,
                        title: Text(context.l10n.sosLocationApproximate),
                        subtitle: Text(context.l10n.sosLocationApproximateBody),
                      ),
                      RadioListTile<SosLocationPrecision>(
                        value: SosLocationPrecision.exact,
                        title: Text(context.l10n.sosLocationExact),
                        subtitle: Text(context.l10n.sosLocationExactBody),
                      ),
                      RadioListTile<SosLocationPrecision>(
                        value: SosLocationPrecision.none,
                        title: Text(context.l10n.sosLocationNone),
                        subtitle: Text(context.l10n.sosLocationNoneBody),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: Text(context.l10n.sosSendPublic),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _composeEmergencySms(BuildContext context) async {
    final recipientController = TextEditingController();
    final messageController = TextEditingController(
      text: context.l10n.sosDefaultMessage,
    );
    var precision = SosLocationPrecision.approximate;
    final draft = await showDialog<_EmergencySmsDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.sms_outlined),
          title: Text(context.l10n.emergencySmsTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.emergencySmsBody),
                const SizedBox(height: 12),
                TextField(
                  controller: recipientController,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: InputDecoration(
                    labelText: context.l10n.emergencySmsRecipient,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageController,
                  maxLength: 160,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: context.l10n.emergencySmsMessage,
                  ),
                ),
                RadioGroup<SosLocationPrecision>(
                  groupValue: precision,
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => precision = value);
                    }
                  },
                  child: Column(
                    children: [
                      RadioListTile<SosLocationPrecision>(
                        value: SosLocationPrecision.approximate,
                        title: Text(context.l10n.sosLocationApproximate),
                      ),
                      RadioListTile<SosLocationPrecision>(
                        value: SosLocationPrecision.exact,
                        title: Text(context.l10n.sosLocationExact),
                      ),
                      RadioListTile<SosLocationPrecision>(
                        value: SosLocationPrecision.none,
                        title: Text(context.l10n.sosLocationNone),
                      ),
                    ],
                  ),
                ),
                Text(
                  context.l10n.emergencySmsDisclaimer,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _EmergencySmsDraft(
                  recipient: recipientController.text,
                  message: messageController.text,
                  precision: precision,
                ),
              ),
              child: Text(context.l10n.emergencySmsCompose),
            ),
          ],
        ),
      ),
    );
    recipientController.dispose();
    messageController.dispose();
    if (draft == null || !context.mounted) return;
    try {
      final opened = await controller.composeEmergencySms(
        recipient: draft.recipient,
        message: draft.message,
        locationPrecision: draft.precision,
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.emergencySmsUnavailable)),
        );
      }
    } on FormatException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.emergencySmsInvalidRecipient)),
      );
    }
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

String _emergencyChannelLabel(String channel) => switch (channel) {
  'ble' => 'BLE',
  'lan' => 'Wi-Fi LAN',
  'wifiDirect' => 'Wi-Fi Direct',
  'wifiAware' => 'Wi-Fi Aware',
  'multipeer' => 'Multipeer',
  'qr' => 'QR',
  'audio' => 'Audio',
  _ => channel,
};

class _EmergencySmsDraft {
  const _EmergencySmsDraft({
    required this.recipient,
    required this.message,
    required this.precision,
  });

  final String recipient;
  final String message;
  final SosLocationPrecision precision;
}

class _EmergencyDeliveryPanel extends StatelessWidget {
  const _EmergencyDeliveryPanel({required this.controller});

  final MeshController controller;

  @override
  Widget build(BuildContext context) {
    final deliveries = controller.emergencyDeliveries.take(5);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.emergencyDeliveryTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...deliveries.map(
              (delivery) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  delivery.state == EmergencyDeliveryState.acknowledged
                      ? Icons.verified_outlined
                      : delivery.state == EmergencyDeliveryState.expired
                      ? Icons.timer_off_outlined
                      : Icons.cell_tower_outlined,
                ),
                title: Text(_deliveryState(context, delivery.state)),
                subtitle: Text(
                  '${context.l10n.deliveryAttemptsLabel}: ${delivery.attempts}\n'
                  '${context.l10n.deliveryConfirmationsLabel}: '
                  '${delivery.confirmationCount}\n'
                  '${context.l10n.deliveryLastAttemptLabel}: '
                  '${delivery.lastAttemptAt == null ? '—' : _formatDateTime(context, delivery.lastAttemptAt!)}\n'
                  '${context.l10n.deliveryExpiresLabel}: '
                  '${_formatDateTime(context, delivery.expiresAt)}'
                  '${delivery.state == EmergencyDeliveryState.relayed && delivery.confirmationCount == 0 ? '\n${context.l10n.deliveryNoHearthBitConfirmation}' : ''}',
                ),
                isThreeLine: true,
                trailing:
                    delivery.state == EmergencyDeliveryState.expired ||
                        delivery.state == EmergencyDeliveryState.pending
                    ? IconButton(
                        tooltip: context.l10n.deliveryRetry,
                        onPressed: () =>
                            controller.retryEmergency(delivery.localId),
                        icon: const Icon(Icons.refresh),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _deliveryState(BuildContext context, EmergencyDeliveryState state) {
    return switch (state) {
      EmergencyDeliveryState.pending => context.l10n.deliveryPending,
      EmergencyDeliveryState.relayed => context.l10n.deliveryRelayed,
      EmergencyDeliveryState.acknowledged => context.l10n.deliveryAcknowledged,
      EmergencyDeliveryState.expired => context.l10n.deliveryExpired,
    };
  }
}

class _DrillBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: context.l10n.drillSafetyBanner,
      child: Container(
        key: const Key('drill-safety-banner'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          border: Border.all(color: scheme.tertiary, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.science_outlined, color: scheme.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.drillSafetyBanner,
                style: TextStyle(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrillModeCard extends StatelessWidget {
  const _DrillModeCard({
    required this.enabled,
    required this.canSend,
    required this.onEnable,
    required this.onDisable,
    required this.onSend,
  });

  final bool enabled;
  final bool canSend;
  final Future<void> Function() onEnable;
  final Future<void> Function() onDisable;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: enabled ? scheme.tertiaryContainer : null,
      child: Column(
        children: [
          SwitchListTile(
            key: const Key('drill-mode-switch'),
            secondary: const Icon(Icons.science_outlined),
            value: enabled,
            onChanged: (value) => value ? onEnable() : onDisable(),
            title: Text(
              context.l10n.drillModeTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(context.l10n.drillModeBody),
          ),
          if (enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  key: const Key('drill-hold-button'),
                  onPressed: null,
                  onLongPress: canSend ? onSend : null,
                  icon: const Icon(Icons.science_outlined),
                  label: Text(context.l10n.drillHoldToSend),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DrillMessageTile extends StatelessWidget {
  const _DrillMessageTile({required this.message});

  final MeshMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final metadata = message.drill;
    return Card(
      key: ValueKey('drill-message-${message.id}'),
      color: scheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(Icons.science_outlined, color: scheme.tertiary),
        title: Text('${context.l10n.drillBadge} · ${message.sender}'),
        subtitle: Text(
          '${metadata?.readableMessage ?? context.l10n.drillInvalidMessage}\n'
          '${_formatDateTime(context, message.timestamp)}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _HoldSosButton extends StatefulWidget {
  const _HoldSosButton({
    required this.enabled,
    required this.active,
    required this.holdDuration,
    required this.onActivated,
  });

  final bool enabled;
  final bool active;
  final Duration holdDuration;
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
    _progress = AnimationController(vsync: this, duration: widget.holdDuration)
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

  void _activateAccessible() {
    if (!widget.enabled || widget.active || _triggered) return;
    _triggered = true;
    unawaited(widget.onActivated());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final dimension = 210.0 + ((textScale - 1).clamp(0, 1) * 50);
    return Semantics(
      button: true,
      enabled: widget.enabled,
      liveRegion: widget.active,
      label: widget.active
          ? context.l10n.emergencySosActive
          : context.l10n.emergencyHoldSos,
      onLongPress: _start,
      onTap: widget.enabled && !widget.active ? _activateAccessible : null,
      child: ExcludeSemantics(
        child: Listener(
          key: const Key('emergency-hold-button'),
          onPointerDown: (_) => _start(),
          onPointerUp: (_) => _cancel(),
          onPointerCancel: (_) => _cancel(),
          child: AnimatedBuilder(
            animation: _progress,
            builder: (context, child) => SizedBox.square(
              dimension: dimension,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.square(
                    dimension: dimension,
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
                      dimension: dimension - 32,
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
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
      ),
    );
  }
}

class _CheckInPanel extends StatelessWidget {
  const _CheckInPanel({
    required this.controller,
    required this.family,
    required this.drillMode,
  });

  final MeshController controller;
  final FamilyController family;
  final bool drillMode;

  Future<void> _send(
    BuildContext context,
    CheckInStatus status,
    String message,
  ) async {
    if (drillMode) {
      await controller.sendDrillCheckIn(status, message);
      return;
    }
    final accepted = await controller.sendCircleCheckIn(
      status,
      message,
      family.members.map((member) => member.peerId),
    );
    if (accepted == 0 && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.checkInNoCircle)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              drillMode
                  ? context.l10n.drillCheckInTitle
                  : context.l10n.checkInTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              drillMode
                  ? context.l10n.drillCheckInBody
                  : context.l10n.checkInPrivateBody,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: controller.canSend
                  ? () =>
                        _send(context, CheckInStatus.ok, context.l10n.checkInOk)
                  : null,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(context.l10n.checkInOk),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: controller.canSend
                  ? () => _send(
                      context,
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
                  ? () => _send(
                      context,
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
  const _CheckInTile({required this.checkIn, required this.isFamily});

  final EmergencyCheckIn checkIn;
  final bool isFamily;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (checkIn.status) {
      CheckInStatus.ok => (Icons.check_circle, scheme.primary),
      CheckInStatus.needsHelp => (Icons.front_hand, scheme.tertiary),
      CheckInStatus.injured => (Icons.medical_services, scheme.error),
    };
    final coordinates = checkIn.latitude != null && checkIn.longitude != null
        ? '\nGPS ${checkIn.latitude!.toStringAsFixed(5)}, '
              '${checkIn.longitude!.toStringAsFixed(5)}'
        : '';
    return Card(
      color: isFamily ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(checkIn.sender),
            if (isFamily)
              Text(
                context.l10n.familyAlertBadge,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
          ],
        ),
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
