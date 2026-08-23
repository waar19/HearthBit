import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/mesh_controller.dart';
import '../l10n/l10n.dart';
import '../models/anchor_admin_models.dart';
import '../models/anchor_ota_manifest.dart';
import '../models/mesh_models.dart';
import '../services/mesh_native_event.dart';
import '../widgets/anchor_sparkline.dart';

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

class _AnchorAdminScreenState extends State<AnchorAdminScreen>
    with WidgetsBindingObserver {
  AnchorAdminStatus? _status;
  AnchorOtaBundle? _otaBundle;
  final AnchorActivityHistory _activity = AnchorActivityHistory();
  Timer? _pollTimer;
  StreamSubscription<MeshAnchorOtaEvent>? _otaSubscription;
  bool _pollInFlight = false;
  bool _offline = false;
  bool _working = false;
  String? _otaState;
  double _otaProgress = 0;
  int? _otaTargetVersion;
  bool _otaPackageInvalid = false;
  String? _otaErrorCode;
  String? _error;

  bool get _otaBlocksPolling =>
      _otaState == 'preparing' || _otaState == 'transferring';

  bool get _otaActive => _otaBlocksPolling || _otaState == 'rebooting';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _otaSubscription = widget.controller.anchorOtaEvents
        .where((event) => event.peerId == widget.peer.id)
        .listen(_handleOtaEvent);
    _loadOtaBundle();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _otaSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _startPolling() {
    if (_otaBlocksPolling) return;
    _pollTimer?.cancel();
    _pollStatus(showProgress: _status == null);
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _pollStatus(),
    );
  }

  Future<void> _refresh() => _pollStatus(showProgress: true);

  Future<void> _pollStatus({bool showProgress = false}) async {
    if (_pollInFlight || _working || _otaBlocksPolling) return;
    _pollInFlight = true;
    if (showProgress && mounted) {
      setState(() {
        _working = true;
        _error = null;
      });
    }
    try {
      final result = await widget.controller.requestAnchorAdmin(
        peer: widget.peer,
        command: 'status',
      );
      if (!mounted) return;
      final status = result.status;
      if (!result.succeeded || status == null) {
        setState(() {
          _offline = true;
          if (_status == null) _error = _messageFor(result);
        });
        return;
      }
      _activity.add(status);
      setState(() {
        _status = status;
        _offline = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _offline = true;
          if (_status == null) _error = context.l10n.anchorAdminUnavailable;
        });
      }
    } finally {
      _pollInFlight = false;
      if (showProgress && mounted) setState(() => _working = false);
    }
  }

  Future<void> _loadOtaBundle() async {
    try {
      final bundle = await AnchorOtaBundle.load();
      if (!mounted) return;
      setState(() {
        _otaBundle = bundle;
        _otaPackageInvalid = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _otaBundle = null;
        _otaPackageInvalid = true;
      });
    }
  }

  void _handleOtaEvent(MeshAnchorOtaEvent event) {
    if (!mounted) return;
    final state = event.state;
    setState(() {
      _otaState = state;
      _otaTargetVersion = event.targetVersion ?? _otaTargetVersion;
      _otaErrorCode = event.error;
      _otaProgress = (event.progress ?? _otaProgress)
          .clamp(0.0, 1.0)
          .toDouble();
      if (state == 'failed') {
        _error = null;
      } else if (state == 'completed') {
        _error = null;
        _otaProgress = 1;
      }
    });
    if (state == 'rebooting' || state == 'failed' || state == 'completed') {
      _startPolling();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<void> _startOta() async {
    final status = _status;
    final bundle = _otaBundle;
    if (status == null ||
        bundle == null ||
        bundle.manifest.version <= status.firmwareVersion ||
        _otaActive) {
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.anchorOtaConfirmTitle),
        content: Text(context.l10n.anchorOtaConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.anchorOtaInstall),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    setState(() {
      _otaState = 'preparing';
      _otaProgress = 0;
      _otaTargetVersion = bundle.manifest.version;
      _otaErrorCode = null;
      _error = null;
    });
    try {
      await widget.controller.startAnchorOta(
        peer: widget.peer,
        manifest: bundle.manifestBytes,
        image: bundle.imageBytes,
        currentVersion: status.firmwareVersion,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _otaState = 'failed';
        _otaErrorCode = 'unavailable';
        _error = null;
      });
      _startPolling();
    }
  }

  Future<bool> _run({
    required String command,
    String? password,
    String? value,
    String? newPassword,
    void Function(AnchorAdminResult result)? onSuccess,
    bool showSuccess = true,
  }) async {
    if (_working || _otaActive) return false;
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
            onPressed: _working || _otaActive ? null : _refresh,
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
                if (_showOtaCard(status)) ...[
                  const SizedBox(height: 12),
                  _otaCard(context, status),
                ],
                const SizedBox(height: 12),
                _activityCard(context),
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

  bool _showOtaCard(AnchorAdminStatus status) {
    if (!widget.controller.supportsAnchorOta) return false;
    final target = _otaBundle?.manifest.version;
    return _otaPackageInvalid ||
        _otaState != null ||
        (target != null && target > status.firmwareVersion);
  }

  Widget _otaCard(BuildContext context, AnchorAdminStatus status) {
    final colors = Theme.of(context).colorScheme;
    final target = _otaTargetVersion ?? _otaBundle?.manifest.version;
    final canInstall =
        !_otaPackageInvalid &&
        !_otaActive &&
        target != null &&
        target > status.firmwareVersion;
    final message = switch (_otaState) {
      'preparing' => context.l10n.anchorOtaPreparing,
      'transferring' => context.l10n.anchorOtaTransferring(
        (_otaProgress * 100).round(),
      ),
      'rebooting' => context.l10n.anchorOtaRebooting,
      'completed' => context.l10n.anchorOtaCompleted(
        target ?? status.firmwareVersion,
      ),
      'failed' => _otaErrorMessage(context),
      _ when _otaPackageInvalid => context.l10n.anchorOtaPackageInvalid,
      _ when target != null => context.l10n.anchorOtaAvailable(
        status.firmwareVersion,
        target,
      ),
      _ => context.l10n.anchorOtaPackageInvalid,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.system_update_alt, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.anchorOtaTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(message),
            if (_otaActive) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _otaState == 'rebooting' ? null : _otaProgress,
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.anchorOtaKeepOpen,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (canInstall) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _startOta,
                icon: const Icon(Icons.system_update),
                label: Text(context.l10n.anchorOtaInstall),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _otaErrorMessage(BuildContext context) {
    return switch (_otaErrorCode) {
      'manifest_rejected' => context.l10n.anchorOtaManifestRejected,
      'remote_status' => context.l10n.anchorOtaRemoteRejected,
      'reconnect_timeout' => context.l10n.anchorOtaReconnectTimeout,
      _ => context.l10n.anchorOtaFailed,
    };
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

  Widget _activityCard(BuildContext context) {
    final samples = _activity.samples;
    if (samples.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final latest = samples.last;
    final currentHeap = latest.freeHeap;
    final minimumHeap = latest.minFreeHeap;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.anchorAdminActivity,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (_offline ? colors.error : colors.primary)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _offline
                        ? context.l10n.anchorAdminOffline
                        : context.l10n.anchorAdminLive,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _offline ? colors.error : colors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.anchorAdminLastFourMinutes,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _chartTile(
              context,
              title: context.l10n.anchorAdminTraffic,
              value: context.l10n.anchorAdminTrafficValue(
                latest.received,
                latest.forwarded,
              ),
              series: [
                samples.map((sample) => sample.received.toDouble()).toList(),
                samples.map((sample) => sample.forwarded.toDouble()).toList(),
              ],
              seriesColors: [colors.primary, colors.tertiary],
              style: AnchorSparklineStyle.bars,
            ),
            _chartTile(
              context,
              title: context.l10n.anchorAdminMailboxUsage,
              value: context.l10n.anchorAdminPercent(
                latest.mailboxPercent.round(),
              ),
              series: [samples.map((sample) => sample.mailboxPercent).toList()],
              seriesColors: [colors.secondary],
              style: AnchorSparklineStyle.lineArea,
            ),
            if (currentHeap != null)
              _chartTile(
                context,
                title: context.l10n.anchorAdminMemory,
                value: context.l10n.anchorAdminMemoryValue(
                  (currentHeap / 1024).round(),
                  ((minimumHeap ?? currentHeap) / 1024).round(),
                ),
                series: [
                  samples
                      .map((sample) => (sample.freeHeap ?? 0) / 1024)
                      .toList(),
                ],
                seriesColors: [colors.primary],
                style: AnchorSparklineStyle.lineArea,
              ),
            _chartTile(
              context,
              title: context.l10n.anchorAdminSecurity,
              value: context.l10n.anchorAdminSecurityValue(
                latest.rejected,
                latest.deduplicated,
              ),
              series: [
                samples.map((sample) => sample.rejected.toDouble()).toList(),
                samples
                    .map((sample) => sample.deduplicated.toDouble())
                    .toList(),
              ],
              seriesColors: [colors.error, colors.secondary],
              style: AnchorSparklineStyle.bars,
              showDivider: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartTile(
    BuildContext context, {
    required String title,
    required String value,
    required List<List<double>> series,
    required List<Color> seriesColors,
    required AnchorSparklineStyle style,
    bool showDivider = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Text(value, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        ExcludeSemantics(
          child: AnchorSparkline(
            series: series,
            colors: seriesColors,
            style: style,
          ),
        ),
        if (showDivider) const Divider(height: 24),
      ],
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
                onPressed: _working || _otaActive ? null : _setPassword,
                icon: const Icon(Icons.password),
                label: Text(context.l10n.anchorAdminSetPassword),
              )
            else ...[
              OutlinedButton.icon(
                onPressed: _working || _otaActive ? null : _changePassword,
                icon: const Icon(Icons.password),
                label: Text(context.l10n.anchorAdminChangePassword),
              ),
              OutlinedButton.icon(
                onPressed: _working || _otaActive ? null : _rename,
                icon: const Icon(Icons.edit),
                label: Text(context.l10n.anchorAdminRename),
              ),
              OutlinedButton.icon(
                onPressed: _working || _otaActive
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
                onPressed: _working || _otaActive
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
