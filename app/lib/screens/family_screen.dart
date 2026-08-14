import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../controllers/family_controller.dart';
import '../l10n/l10n.dart';
import '../models/family_models.dart';
import '../widgets/sensitive_screen.dart';
import 'optical_send_screen.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({required this.controller, super.key});

  final FamilyController controller;

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  int? _selectedGroupId;

  FamilyGroup? get _selectedGroup {
    final groups = widget.controller.groups;
    if (groups.isEmpty) return null;
    return groups.cast<FamilyGroup?>().firstWhere(
      (group) => group!.id == _selectedGroupId,
      orElse: () => groups.first,
    );
  }

  Future<void> _createGroup() async {
    final name = await _askName(context.l10n.familyCreateGroup, '');
    if (name == null) return;
    try {
      final group = await widget.controller.createGroup(name);
      if (mounted) setState(() => _selectedGroupId = group.id);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _renameGroup(FamilyGroup group) async {
    final name = await _askName(context.l10n.familyRenameGroup, group.name);
    if (name == null) return;
    try {
      await widget.controller.renameGroup(group.id, name);
    } catch (error) {
      _showError(error);
    }
  }

  Future<String?> _askName(String title, String initialValue) {
    final input = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 80,
          decoration: InputDecoration(hintText: context.l10n.familyGroupHint),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(input.text.trim()),
            child: Text(context.l10n.actionSave),
          ),
        ],
      ),
    ).whenComplete(input.dispose);
  }

  Future<void> _scanMember(FamilyGroup group) async {
    final identity = await Navigator.of(context).push<FamilyQrIdentity>(
      MaterialPageRoute(
        builder: (_) => _FamilyScannerScreen(controller: widget.controller),
      ),
    );
    if (identity == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.familyConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              identity.nickname,
              style: Theme.of(context).textTheme.titleLarge,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            SelectableText(
              context.l10n.familyFingerprint(identity.fingerprint),
            ),
            const SizedBox(height: 8),
            Text(context.l10n.familyConfirmBody),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.familyAddMember),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.addVerifiedMember(group.id, identity);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteMember(FamilyMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.familyRemoveTitle),
        content: Text(context.l10n.familyRemoveBody(member.nickname)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.familyRemoveAction),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.deleteMember(member.id);
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.familySaveError('$error'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SensitiveScreen(
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final group = _selectedGroup;
          final members = group == null
              ? const <FamilyMember>[]
              : widget.controller.members
                    .where((member) => member.groupId == group.id)
                    .toList(growable: false);
          return Scaffold(
            appBar: AppBar(title: Text(context.l10n.familyTitle)),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Text(context.l10n.familySecurityBody),
                  const SizedBox(height: 16),
                  if (widget.controller.groups.isNotEmpty)
                    DropdownButtonFormField<int>(
                      initialValue: group?.id,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: context.l10n.familyGroupLabel,
                      ),
                      items: widget.controller.groups
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(
                                item.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) =>
                          setState(() => _selectedGroupId = value),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _createGroup,
                        icon: const Icon(Icons.group_add_outlined),
                        label: Text(context.l10n.familyCreateGroup),
                      ),
                      if (group != null)
                        OutlinedButton.icon(
                          onPressed: () => _renameGroup(group),
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(context.l10n.familyRenameGroup),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _LocalIdentityCard(controller: widget.controller),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.familyMembersTitle,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      if (group != null)
                        IconButton.filledTonal(
                          tooltip: context.l10n.familyScanAction,
                          onPressed: () => _scanMember(group),
                          icon: const Icon(Icons.qr_code_scanner),
                        ),
                    ],
                  ),
                  if (group == null)
                    Text(context.l10n.familyCreateFirst)
                  else if (members.isEmpty)
                    Text(context.l10n.familyNoMembers)
                  else
                    ...members.map(
                      (member) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.verified_user_outlined),
                          title: Text(
                            member.nickname,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: SelectableText(
                            context.l10n.familyFingerprint(member.fingerprint),
                          ),
                          trailing: IconButton(
                            tooltip: context.l10n.familyRemoveAction,
                            onPressed: () => _deleteMember(member),
                            icon: const Icon(Icons.person_remove_outlined),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LocalIdentityCard extends StatelessWidget {
  const _LocalIdentityCard({required this.controller});

  final FamilyController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.canShowIdentityQr) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(context.l10n.familyQrUnavailable),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.familyMyQr,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(context.l10n.familyMyQrBody),
            const SizedBox(height: 16),
            FutureBuilder<String>(
              future: controller.buildLocalQr(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ColoredBox(
                        color: Colors.white,
                        child: CustomPaint(
                          painter: QrFramePainter(snapshot.data!),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            SelectableText(
              context.l10n.familyFingerprint(controller.localFingerprint!),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilyScannerScreen extends StatefulWidget {
  const _FamilyScannerScreen({required this.controller});

  final FamilyController controller;

  @override
  State<_FamilyScannerScreen> createState() => _FamilyScannerScreenState();
}

class _FamilyScannerScreenState extends State<_FamilyScannerScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _verifying = false;
  String? _error;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_verifying) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null) return;
    _verifying = true;
    try {
      final identity = await widget.controller.verifyQr(raw);
      await _scanner.stop();
      if (mounted) Navigator.of(context).pop(identity);
    } on FormatException {
      if (mounted) setState(() => _error = context.l10n.familyQrInvalid);
      _verifying = false;
    }
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.familyScanTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: MobileScanner(controller: _scanner, onDetect: _onDetect),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error ?? context.l10n.familyScanHint,
                textAlign: TextAlign.center,
                style: _error == null
                    ? null
                    : TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
