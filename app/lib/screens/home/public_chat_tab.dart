import 'package:flutter/material.dart';

import '../../controllers/mesh_controller.dart';
import '../../l10n/l10n.dart';
import '../../utils/message_timeline.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/message_composer.dart';
import 'message_timeline.dart' as timeline;

class PublicChatTab extends StatelessWidget {
  const PublicChatTab({
    required this.controller,
    required this.messageController,
    required this.scrollController,
    required this.onSend,
    super.key,
  });

  final MeshController controller;
  final TextEditingController messageController;
  final ScrollController scrollController;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    final publicMessages = controller.messages
        .where((message) => !message.isPrivate)
        .toList(growable: false);
    final entries = messageTimelineEntries(publicMessages);
    return Column(
      children: [
        Expanded(
          child: publicMessages.isEmpty
              ? EmptyState(
                  icon: Icons.bluetooth_searching,
                  title: context.l10n.emptyChatTitle,
                  description: context.l10n.emptyChatBody,
                )
              : ListView.builder(
                  controller: scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  itemBuilder: (context, index) =>
                      timeline.buildMessageTimelineEntry(
                        context,
                        entries[index],
                        compactSos: true,
                      ),
                ),
        ),
        MessageComposer(
          controller: messageController,
          enabled: controller.canSend,
          hint: context.l10n.composerPublicHint,
          onSend: onSend,
        ),
      ],
    );
  }
}
