import 'package:flutter/material.dart';

import '../controllers/emergency_gateway_controller.dart';
import '../l10n/l10n.dart';
import '../services/app_preferences.dart';

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
            onChanged: preferences.setGatewayOptIn,
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
  var _tls = true;
  var _saving = false;

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
    _tls = config?.tls ?? true;
  }

  @override
  void dispose() {
    _server.dispose();
    _destination.dispose();
    _username.dispose();
    _port.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final port = int.tryParse(_port.text);
    if (port == null || port <= 0) return;
    setState(() => _saving = true);
    await widget.controller.saveConfig(
      EmergencyGatewayConfig(
        kind: _kind,
        server: _server.text,
        destination: _destination.text,
        username: _username.text,
        port: port,
        tls: _tls,
      ),
      _secret.text,
    );
    if (mounted) Navigator.pop(context);
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
              value: _tls,
              onChanged: (value) => setState(() => _tls = value),
              title: Text(context.l10n.gatewayTls),
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
          onPressed: _saving ? null : _save,
          child: Text(context.l10n.actionSave),
        ),
      ],
    );
  }
}
