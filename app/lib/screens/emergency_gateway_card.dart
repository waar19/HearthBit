import 'package:flutter/material.dart';

import '../controllers/emergency_gateway_controller.dart';
import '../l10n/l10n.dart';
import '../services/app_preferences.dart';
import '../services/tls_peer_verifier.dart';

class EmergencyGatewayCard extends StatelessWidget {
  const EmergencyGatewayCard({
    required this.controller,
    required this.preferences,
    super.key,
  });

  final EmergencyGatewayController controller;
  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.public),
            title: Text(
              context.l10n.gatewayTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(context.l10n.gatewayBody),
            value: preferences.gatewayOptIn,
            onChanged: (enabled) async {
              if (!enabled) {
                await preferences.setGatewayOptIn(false);
                return;
              }
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(context.l10n.gatewayTitle),
                  content: Text(context.l10n.gatewayPrivacyConfirm),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(context.l10n.actionCancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(context.l10n.gatewayEnableAction),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await preferences.setGatewayOptIn(true);
              }
            },
          ),
          ListTile(
            leading: Icon(
              controller.internetTransportAvailable
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
            ),
            title: Text(
              controller.internetTransportAvailable
                  ? context.l10n.gatewayAvailable
                  : context.l10n.gatewayUnavailable,
            ),
            subtitle: Text(
              context.l10n.gatewayPending(controller.pendingCount),
            ),
            trailing: controller.publishing
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: context.l10n.gatewayConfigure,
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          _GatewayConfigDialog(controller: controller),
                    ),
                    icon: const Icon(Icons.settings_outlined),
                  ),
          ),
          if (controller.lastError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                controller.lastError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              context.l10n.gatewayPrivacy,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _GatewayConfigDialog extends StatefulWidget {
  const _GatewayConfigDialog({required this.controller});

  final EmergencyGatewayController controller;

  @override
  State<_GatewayConfigDialog> createState() => _GatewayConfigDialogState();
}

class _GatewayConfigDialogState extends State<_GatewayConfigDialog> {
  late EmergencyGatewayKind _kind;
  late final TextEditingController _server;
  late final TextEditingController _destination;
  late final TextEditingController _username;
  late final TextEditingController _port;
  late final TextEditingController _secret;
  late final TextEditingController _fingerprint;
  late TlsTrustMode _trustMode;
  var _includeSensitiveContent = false;
  var _includeCoordinates = false;
  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final config = widget.controller.config;
    _kind = config?.kind ?? EmergencyGatewayKind.matrix;
    _server = TextEditingController(text: config?.server ?? '');
    _destination = TextEditingController(text: config?.destination ?? '');
    _username = TextEditingController(text: config?.username ?? '');
    _port = TextEditingController(text: '${config?.port ?? 443}');
    _secret = TextEditingController();
    _fingerprint = TextEditingController(text: config?.certificateSha256 ?? '');
    _trustMode = config?.trustMode ?? TlsTrustMode.system;
    _includeSensitiveContent = config?.includeSensitiveContent ?? false;
    _includeCoordinates = config?.includeCoordinates ?? false;
  }

  @override
  void dispose() {
    _server.dispose();
    _destination.dispose();
    _username.dispose();
    _port.dispose();
    _secret.dispose();
    _fingerprint.dispose();
    super.dispose();
  }

  EmergencyGatewayConfig _draftConfig(int port) => EmergencyGatewayConfig(
    kind: _kind,
    server: _server.text,
    destination: _destination.text,
    username: _username.text,
    port: port,
    tls: true,
    trustMode: _trustMode,
    certificateSha256: _trustMode == TlsTrustMode.pinned
        ? _fingerprint.text
        : null,
    includeSensitiveContent: _includeSensitiveContent,
    includeCoordinates: _includeCoordinates,
  );

  Future<void> _save() async {
    final port = int.tryParse(_port.text);
    if (port == null || port <= 0) return;
    if (_trustMode == TlsTrustMode.pinned &&
        !TlsPeerVerifier.isValidFingerprint(_fingerprint.text)) {
      setState(() => _error = context.l10n.gatewayFingerprintInvalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.saveConfig(_draftConfig(port), _secret.text);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _resetTofuTrust() async {
    final port = int.tryParse(_port.text);
    if (port == null || port <= 0) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.resetTofuTrust(_draftConfig(port));
      if (mounted) {
        setState(() {
          _saving = false;
          _error = context.l10n.gatewayResetTofuDone;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final matrix = _kind == EmergencyGatewayKind.matrix;
    return AlertDialog(
      title: Text(context.l10n.gatewayConfigure),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<EmergencyGatewayKind>(
              segments: [
                ButtonSegment(
                  value: EmergencyGatewayKind.matrix,
                  label: Text(context.l10n.gatewayKindMatrix),
                ),
                ButtonSegment(
                  value: EmergencyGatewayKind.mqtt,
                  label: Text(context.l10n.gatewayKindMqtt),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (selected) {
                setState(() {
                  _kind = selected.single;
                  _port.text = _kind == EmergencyGatewayKind.matrix
                      ? '443'
                      : '8883';
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _server,
              decoration: InputDecoration(
                labelText: matrix
                    ? context.l10n.gatewayHomeserver
                    : context.l10n.gatewayBroker,
              ),
            ),
            TextField(
              controller: _destination,
              decoration: InputDecoration(
                labelText: matrix
                    ? context.l10n.gatewayRoom
                    : context.l10n.gatewayTopic,
              ),
            ),
            if (!matrix)
              TextField(
                controller: _username,
                decoration: InputDecoration(
                  labelText: context.l10n.gatewayUsername,
                ),
              ),
            TextField(
              controller: _secret,
              obscureText: true,
              decoration: InputDecoration(
                labelText: matrix
                    ? context.l10n.gatewayAccessToken
                    : context.l10n.gatewayPassword,
              ),
            ),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: context.l10n.gatewayPort),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: true,
              onChanged: null,
              title: Text(context.l10n.gatewayTls),
              subtitle: Text(context.l10n.gatewayTlsRequired),
            ),
            const Divider(),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                context.l10n.gatewayTrustTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  key: const Key('gateway-trust-system'),
                  selected: _trustMode == TlsTrustMode.system,
                  onSelected: _saving
                      ? null
                      : (_) {
                          setState(() => _trustMode = TlsTrustMode.system);
                        },
                  avatar: const Icon(Icons.verified_user_outlined),
                  label: Text(context.l10n.gatewayTrustSystem),
                ),
                ChoiceChip(
                  key: const Key('gateway-trust-tofu'),
                  selected: _trustMode == TlsTrustMode.tofu,
                  onSelected: _saving
                      ? null
                      : (_) {
                          setState(() => _trustMode = TlsTrustMode.tofu);
                        },
                  avatar: const Icon(Icons.fingerprint),
                  label: Text(context.l10n.gatewayTrustTofu),
                ),
                ChoiceChip(
                  key: const Key('gateway-trust-pinned'),
                  selected: _trustMode == TlsTrustMode.pinned,
                  onSelected: _saving
                      ? null
                      : (_) {
                          setState(() => _trustMode = TlsTrustMode.pinned);
                        },
                  avatar: const Icon(Icons.push_pin_outlined),
                  label: Text(context.l10n.gatewayTrustPinned),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(switch (_trustMode) {
                TlsTrustMode.system => context.l10n.gatewayTrustSystemBody,
                TlsTrustMode.tofu => context.l10n.gatewayTrustTofuBody,
                TlsTrustMode.pinned => context.l10n.gatewayTrustPinnedBody,
              }, style: Theme.of(context).textTheme.bodySmall),
            ),
            if (_trustMode == TlsTrustMode.pinned)
              TextField(
                key: const Key('gateway-fingerprint'),
                controller: _fingerprint,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                decoration: InputDecoration(
                  labelText: context.l10n.gatewayFingerprint,
                  helperText: context.l10n.gatewayFingerprintHint,
                ),
              ),
            if (_trustMode == TlsTrustMode.tofu)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('gateway-reset-tofu'),
                  onPressed: _saving ? null : _resetTofuTrust,
                  icon: const Icon(Icons.restart_alt),
                  label: Text(context.l10n.gatewayResetTofu),
                ),
              ),
            const Divider(),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                context.l10n.gatewayPrivacyScopeTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            SwitchListTile(
              key: const Key('gateway-sensitive-consent'),
              contentPadding: EdgeInsets.zero,
              value: _includeSensitiveContent,
              onChanged: _saving
                  ? null
                  : (value) {
                      setState(() => _includeSensitiveContent = value);
                    },
              title: Text(context.l10n.gatewaySensitiveContentConsent),
              subtitle: Text(context.l10n.gatewaySensitiveContentConsentBody),
            ),
            SwitchListTile(
              key: const Key('gateway-coordinates-consent'),
              contentPadding: EdgeInsets.zero,
              value: _includeCoordinates,
              onChanged: _saving
                  ? null
                  : (value) {
                      setState(() => _includeCoordinates = value);
                    },
              title: Text(context.l10n.gatewayCoordinatesConsent),
              subtitle: Text(context.l10n.gatewayCoordinatesConsentBody),
            ),
            Text(
              context.l10n.gatewayPrivacyScopeWarning,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(context.l10n.actionCancel),
        ),
        FilledButton(
          key: const Key('gateway-save'),
          onPressed: _saving ? null : _save,
          child: Text(context.l10n.actionSave),
        ),
      ],
    );
  }
}
