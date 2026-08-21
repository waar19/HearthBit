import 'package:flutter/material.dart';

import '../controllers/mesh_controller.dart';
import '../l10n/l10n.dart';
import '../models/anchor_admin_models.dart';
import '../models/mesh_models.dart';

class AnchorAdminScreen extends StatefulWidget {
  const AnchorAdminScreen({
    required this.controller,
    required this.peer,
    super.key,
  });

  final MeshController controller;
  final MeshPeer peer;

  @override
  State<AnchorAdminScreen> createState() => _AnchorAdminScreenState();
}

class _AnchorAdminScreenState extends State<AnchorAdminScreen> {
  AnchorAdminStatus? _status;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    await _run(
      command: 'status',
      onSuccess: (result) {
        if (result.status != null) {
          setState(() => _status = result.status);
        }
      },
      showSuccess: false,
    );
  }

  Future<bool> _run({
    required String command,
    String? password,
    String? value,
    String? newPassword,
    void Function(AnchorAdminResult result)? onSuccess,
    bool showSuccess = true,
  }) async {
    if (_working) return false;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final result = await widget.controller.requestAnchorAdmin(
        peer: widget.peer,
        command: command,
        password: password,
        value: value,
        newPassword: newPassword,
      );
      if (!mounted) return false;
      if (!result.succeeded) {
        setState(() => _error = _messageFor(result));
        return false;
      }
      onSuccess?.call(result);
      if (showSuccess) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.anchorAdminSaved)));
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.l10n.anchorAdminUnavailable);
      }
      return false;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _messageFor(AnchorAdminResult result) {
    return switch (result.statusCode) {
      2 => context.l10n.anchorAdminUnsupported,
      5 => context.l10n.anchorAdminWrongPassword,
      6 => context.l10n.anchorAdminLocked(result.retryAfterSeconds),
      _ => context.l10n.anchorAdminUnavailable,
    };
  }

  Future<void> _setPassword() async {
    final values = await _passwordDialog(includeCurrent: false);
    if (values == null) return;
    final succeeded = await _run(command: 'setPassword', password: values.$2);
    if (succeeded && mounted) await _refresh();
  }

  Future<void> _changePassword() async {
    final values = await _passwordDialog(includeCurrent: true);
    if (values == null) return;
    await _run(
      command: 'changePassword',
      password: values.$1,
      newPassword: values.$2,
    );
  }

  Future<void> _rename() async {
    final password = TextEditingController();
    final name = TextEditingController(
      text: _status?.nickname ?? widget.peer.nickname,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.anchorAdminRename),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              maxLength: 31,
              decoration: InputDecoration(
                labelText: context.l10n.anchorAdminName,
              ),
            ),
            TextField(
              controller: password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: context.l10n.anchorAdminPassword,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.actionSave),
          ),
        ],
      ),
    );
    final passwordValue = password.text;
    final nameValue = name.text.trim();
    password.dispose();
    name.dispose();
    if (confirmed != true || passwordValue.length < 10 || nameValue.isEmpty) {
      return;
    }
    final succeeded = await _run(
      command: 'rename',
      password: passwordValue,
      value: nameValue,
    );
    if (succeeded && mounted) await _refresh();
  }

  Future<void> _destructiveAction({
    required String command,
    required String title,
    required String body,
  }) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(title),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final password = await _singlePasswordDialog();
    if (password == null) return;
    await _run(command: command, password: password);
  }

  Future<(String, String)?> _passwordDialog({
    required bool includeCurrent,
  }) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final repeat = TextEditingController();
    String? validation;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            includeCurrent
                ? context.l10n.anchorAdminChangePassword
                : context.l10n.anchorAdminSetPassword,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (includeCurrent)
                TextField(
                  controller: current,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: context.l10n.anchorAdminPassword,
                  ),
                ),
              TextField(
                controller: next,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.anchorAdminNewPassword,
                  helperText: context.l10n.anchorAdminPasswordHint,
                ),
              ),
              TextField(
                controller: repeat,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.anchorAdminRepeatPassword,
                  errorText: validation,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () {
                if (next.text.length < 10 || next.text != repeat.text) {
                  setDialogState(() {
                    validation = next.text != repeat.text
                        ? context.l10n.anchorAdminPasswordMismatch
                        : context.l10n.anchorAdminPasswordHint;
                  });
                  return;
                }
                if (includeCurrent && current.text.length < 10) return;
                Navigator.pop(context, true);
              },
              child: Text(context.l10n.actionSave),
            ),
          ],
        ),
      ),
    );
    final result = accepted == true ? (current.text, next.text) : null;
    current.dispose();
    next.dispose();
    repeat.dispose();
    return result;
  }

  Future<String?> _singlePasswordDialog() async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.anchorAdminPassword),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(
            labelText: context.l10n.anchorAdminPassword,
            helperText: context.l10n.anchorAdminPasswordHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.actionSave),
          ),
        ],
      ),
    );
    final value = accepted == true && controller.text.length >= 10
        ? controller.text
        : null;
    controller.dispose();
    return value;
  }

  String _duration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    return days > 0 ? '${days}d ${hours}h' : '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final displayName = status?.nickname.isNotEmpty == true
        ? status!.nickname
        : widget.peer.nickname;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.anchorAdminTitle(displayName)),
        actions: [
          IconButton(
            onPressed: _working ? null : _refresh,
            tooltip: context.l10n.anchorAdminRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text(_error!),
                  ),
                ),
              if (status == null)
                const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _statusCard(context, status),
                const SizedBox(height: 12),
                _packetCard(context, status),
                const SizedBox(height: 12),
                _actionsCard(context, status),
              ],
            ],
          ),
          if (_working)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context, AnchorAdminStatus status) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.anchorAdminStatus,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(status.claimed ? Icons.lock : Icons.lock_open),
              title: Text(
                status.claimed
                    ? context.l10n.anchorAdminClaimed
                    : context.l10n.anchorAdminUnclaimed,
              ),
              subtitle: Text(
                context.l10n.anchorAdminFirmware(
                  status.firmwareVersion,
                  status.protocolVersion,
                ),
              ),
            ),
            Text(context.l10n.anchorAdminUptime(_duration(status.uptimeMs))),
            Text(context.l10n.anchorAdminBootCount(status.bootCount)),
            Text(
              context.l10n.anchorAdminMailbox(
                status.mailboxUsed,
                status.mailboxCapacity,
              ),
            ),
            Text(
              status.clockValid
                  ? context.l10n.anchorAdminClockReady
                  : context.l10n.anchorAdminClockPending,
            ),
          ],
        ),
      ),
    );
  }

  Widget _packetCard(BuildContext context, AnchorAdminStatus status) {
    final values = <(String, int)>[
      (context.l10n.anchorAdminReceived, status.packetsReceived),
      (context.l10n.anchorAdminForwarded, status.packetsForwarded),
      (context.l10n.anchorAdminStored, status.packetsStored),
      (context.l10n.anchorAdminDelivered, status.packetsDelivered),
      (context.l10n.anchorAdminDeduplicated, status.packetsDeduplicated),
      (context.l10n.anchorAdminExpired, status.packetsExpired),
      (context.l10n.anchorAdminRejected, status.packetsRejected),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.anchorAdminPackets,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...values.map(
              (value) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text(value.$1), Text('${value.$2}')],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsCard(BuildContext context, AnchorAdminStatus status) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!status.claimed)
              FilledButton.icon(
                onPressed: _working ? null : _setPassword,
                icon: const Icon(Icons.password),
                label: Text(context.l10n.anchorAdminSetPassword),
              )
            else ...[
              OutlinedButton.icon(
                onPressed: _working ? null : _changePassword,
                icon: const Icon(Icons.password),
                label: Text(context.l10n.anchorAdminChangePassword),
              ),
              OutlinedButton.icon(
                onPressed: _working ? null : _rename,
                icon: const Icon(Icons.edit),
                label: Text(context.l10n.anchorAdminRename),
              ),
              OutlinedButton.icon(
                onPressed: _working
                    ? null
                    : () => _destructiveAction(
                        command: 'reboot',
                        title: context.l10n.anchorAdminReboot,
                        body: context.l10n.anchorAdminConfirmReboot,
                      ),
                icon: const Icon(Icons.restart_alt),
                label: Text(context.l10n.anchorAdminReboot),
              ),
              FilledButton.tonalIcon(
                onPressed: _working
                    ? null
                    : () => _destructiveAction(
                        command: 'factoryReset',
                        title: context.l10n.anchorAdminFactoryReset,
                        body: context.l10n.anchorAdminConfirmFactoryReset,
                      ),
                icon: const Icon(Icons.delete_forever),
                label: Text(context.l10n.anchorAdminFactoryReset),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
