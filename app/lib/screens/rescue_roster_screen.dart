import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../controllers/rescue_roster_controller.dart';
import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../models/rescue_roster_models.dart';
import '../widgets/sensitive_screen.dart';
import 'optical_send_screen.dart';

class RescueRosterScreen extends StatefulWidget {
  const RescueRosterScreen({required this.controller, super.key});

  final RescueRosterController controller;

  @override
  State<RescueRosterScreen> createState() => _RescueRosterScreenState();
}

class _RescueRosterScreenState extends State<RescueRosterScreen> {
  XTypeGroup get _rosterFileType => XTypeGroup(
    label: context.l10n.rescueRosterFileType,
    extensions: const ['hbrt', 'txt'],
  );

  Future<void> _createRoster() async {
    final team = TextEditingController();
    final callsign = TextEditingController();
    final values = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.rescueRosterCreate),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: team,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: context.l10n.rescueRosterTeamName,
              ),
            ),
            TextField(
              controller: callsign,
              maxLength: 63,
              decoration: InputDecoration(
                labelText: context.l10n.rescueRosterCallsign,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, [
              team.text.trim(),
              callsign.text.trim(),
            ]),
            child: Text(context.l10n.actionSave),
          ),
        ],
      ),
    );
    team.dispose();
    callsign.dispose();
    if (values == null) return;
    try {
      await widget.controller.createRoster(
        teamName: values[0],
        leaderCallsign: values[1],
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _importText() async {
    final input = TextEditingController();
    final encoded = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.rescueRosterImportText),
        content: TextField(
          controller: input,
          minLines: 4,
          maxLines: 10,
          decoration: InputDecoration(
            hintText: context.l10n.rescueRosterPasteHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.text.trim()),
            child: Text(context.l10n.rescueRosterImport),
          ),
        ],
      ),
    );
    input.dispose();
    if (encoded == null || encoded.isEmpty) return;
    await _import(encoded);
  }

  Future<void> _importFile() async {
    final file = await openFile(acceptedTypeGroups: [_rosterFileType]);
    if (file == null) return;
    if (await file.length() > 100000) {
      _showError(const FormatException('Rescue roster file is too large'));
      return;
    }
    await _import(await file.readAsString());
  }

  Future<void> _scanQr() async {
    final encoded = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _RescueRosterScannerScreen()),
    );
    if (encoded != null && mounted) await _import(encoded);
  }

  Future<void> _import(String encoded) async {
    try {
      await widget.controller.importRoster(encoded);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.rescueRosterImported)),
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _exportFile() async {
    try {
      final location = await getSaveLocation(
        suggestedName: 'hearthbit-rescue-roster.hbrt',
        acceptedTypeGroups: [_rosterFileType],
      );
      if (location == null) return;
      await File(
        location.path,
      ).writeAsString(widget.controller.exportRoster(), flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.rescueRosterExported)),
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _showQrAndText() async {
    try {
      final encoded = widget.controller.exportRoster();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n.rescueRosterExportQr),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (encoded.length <= 2500)
                    ColoredBox(
                      color: Colors.white,
                      child: SizedBox.square(
                        dimension: 300,
                        child: CustomPaint(painter: QrFramePainter(encoded)),
                      ),
                    )
                  else
                    Text(context.l10n.rescueRosterQrTooLarge),
                  const SizedBox(height: 16),
                  SelectableText(
                    encoded,
                    maxLines: 6,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.actionClose),
            ),
          ],
        ),
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _addMember() async {
    final existingIds = widget.controller.members
        .map((member) => member.peerId)
        .toSet();
    final eligible = widget.controller.mesh.peers
        .where(
          (peer) =>
              peer.signingPublicKey?.length == 32 &&
              !existingIds.contains(peer.id),
        )
        .toList(growable: false);
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.rescueRosterNoEligiblePeers)),
      );
      return;
    }
    var selectedPeer = eligible.first;
    var selectedRole = RescueRosterRole.responder;
    final callsign = TextEditingController(text: selectedPeer.nickname);
    final input = await showDialog<_NewRosterMemberInput>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.rescueRosterAddMember),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<MeshPeer>(
                initialValue: selectedPeer,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.rescueRosterNearbyIdentity,
                ),
                items: eligible
                    .map(
                      (peer) => DropdownMenuItem(
                        value: peer,
                        child: Text(
                          '${peer.nickname} · ${peer.id}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (peer) {
                  if (peer == null) return;
                  setDialogState(() => selectedPeer = peer);
                  callsign.text = peer.nickname;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: callsign,
                maxLength: 63,
                decoration: InputDecoration(
                  labelText: context.l10n.rescueRosterMemberCallsign,
                ),
              ),
              DropdownButtonFormField<RescueRosterRole>(
                initialValue: selectedRole,
                decoration: InputDecoration(
                  labelText: context.l10n.rescueRosterMemberRole,
                ),
                items: RescueRosterRole.values
                    .where((role) => role != RescueRosterRole.leader)
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(_roleLabel(role)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (role) {
                  if (role != null) {
                    setDialogState(() => selectedRole = role);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _NewRosterMemberInput(
                  peer: selectedPeer,
                  callsign: callsign.text.trim(),
                  role: selectedRole,
                ),
              ),
              child: Text(context.l10n.rescueRosterAddMember),
            ),
          ],
        ),
      ),
    );
    callsign.dispose();
    if (input == null) return;
    try {
      await widget.controller.addMember(
        peerId: input.peer.id,
        callsign: input.callsign,
        role: input.role,
        signingPublicKey: input.peer.signingPublicKey!,
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _removeMember(RescueRosterMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.rescueRosterRemoveMemberTitle),
        content: Text(
          context.l10n.rescueRosterRemoveMemberBody(member.callsign),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.removeMember(member.peerId);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _clearRoster() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.rescueRosterRemoveTitle),
        content: Text(context.l10n.rescueRosterRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.clearRoster();
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.rescueRosterError('$error'))),
    );
  }

  String _roleLabel(RescueRosterRole role) => switch (role) {
    RescueRosterRole.leader => context.l10n.rescueRosterRoleLeader,
    RescueRosterRole.responder => context.l10n.rescueRosterRoleResponder,
    RescueRosterRole.medic => context.l10n.rescueRosterRoleMedic,
    RescueRosterRole.search => context.l10n.rescueRosterRoleSearch,
    RescueRosterRole.logistics => context.l10n.rescueRosterRoleLogistics,
    RescueRosterRole.communications =>
      context.l10n.rescueRosterRoleCommunications,
  };

  @override
  Widget build(BuildContext context) {
    return SensitiveScreen(
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final roster = widget.controller.activeRoster;
          return Scaffold(
            appBar: AppBar(title: Text(context.l10n.rescueRosterTitle)),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text(context.l10n.rescueRosterSecurityBody),
                const SizedBox(height: 16),
                if (roster == null) ...[
                  Text(context.l10n.rescueRosterEmpty),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _createRoster,
                    icon: const Icon(Icons.group_add_outlined),
                    label: Text(context.l10n.rescueRosterCreate),
                  ),
                ] else ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: Text(roster.name),
                      subtitle: Text(
                        context.l10n.rescueRosterMemberCount(
                          roster.members.length,
                        ),
                      ),
                    ),
                  ),
                  ...roster.members.map(
                    (member) => Card(
                      child: ListTile(
                        leading: Icon(
                          member.role == RescueRosterRole.leader
                              ? Icons.admin_panel_settings_outlined
                              : Icons.health_and_safety_outlined,
                        ),
                        title: Text(member.callsign),
                        subtitle: Text(
                          '${_roleLabel(member.role)} · ${member.peerId}',
                        ),
                        trailing:
                            widget.controller.canEdit &&
                                member.role != RescueRosterRole.leader
                            ? IconButton(
                                tooltip:
                                    context.l10n.rescueRosterRemoveMemberTitle,
                                onPressed: () => _removeMember(member),
                                icon: const Icon(Icons.person_remove_outlined),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.controller.canEdit)
                        FilledButton.tonalIcon(
                          onPressed: _addMember,
                          icon: const Icon(Icons.person_add_outlined),
                          label: Text(context.l10n.rescueRosterAddMember),
                        ),
                      FilledButton.tonalIcon(
                        onPressed: _showQrAndText,
                        icon: const Icon(Icons.qr_code_2),
                        label: Text(context.l10n.rescueRosterExportQr),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exportFile,
                        icon: const Icon(Icons.save_alt),
                        label: Text(context.l10n.rescueRosterExportFile),
                      ),
                      TextButton.icon(
                        onPressed: _clearRoster,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(context.l10n.actionDelete),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  context.l10n.rescueRosterImportTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _scanQr,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(context.l10n.rescueRosterScanQr),
                    ),
                    OutlinedButton.icon(
                      onPressed: _importText,
                      icon: const Icon(Icons.content_paste),
                      label: Text(context.l10n.rescueRosterImportText),
                    ),
                    OutlinedButton.icon(
                      onPressed: _importFile,
                      icon: const Icon(Icons.file_open_outlined),
                      label: Text(context.l10n.rescueRosterImportFile),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NewRosterMemberInput {
  const _NewRosterMemberInput({
    required this.peer,
    required this.callsign,
    required this.role,
  });

  final MeshPeer peer;
  final String callsign;
  final RescueRosterRole role;
}

class _RescueRosterScannerScreen extends StatefulWidget {
  const _RescueRosterScannerScreen();

  @override
  State<_RescueRosterScannerScreen> createState() =>
      _RescueRosterScannerScreenState();
}

class _RescueRosterScannerScreenState
    extends State<_RescueRosterScannerScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _detected = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_detected) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null || !raw.trim().startsWith('HBRT1:')) return;
    _detected = true;
    await _scanner.stop();
    if (mounted) Navigator.pop(context, raw);
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.rescueRosterScanQr)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: MobileScanner(controller: _scanner, onDetect: _onDetect),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.rescueRosterScanHint,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
