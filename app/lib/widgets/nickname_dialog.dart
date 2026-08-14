import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

class NicknameDialog extends StatefulWidget {
  const NicknameDialog({required this.initialNickname, super.key});

  final String initialNickname;

  @override
  State<NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<NicknameDialog> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialNickname);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.nicknameDialogTitle),
      content: TextField(
        controller: _textController,
        autofocus: true,
        maxLength: 31,
        decoration: InputDecoration(hintText: context.l10n.nicknameDialogHint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _textController.text),
          child: Text(context.l10n.actionSave),
        ),
      ],
    );
  }
}
