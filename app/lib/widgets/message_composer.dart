import 'package:flutter/material.dart';

class MessageComposer extends StatelessWidget {
  const MessageComposer({
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.onSend,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              maxLength: 240,
              decoration: InputDecoration(
                hintText: hint,
                counterText: '',
                border: const OutlineInputBorder(),
              ),
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            enabled: enabled,
            label: hint,
            child: IconButton.filled(
              tooltip: hint,
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.send),
            ),
          ),
        ],
      ),
    );
  }
}
