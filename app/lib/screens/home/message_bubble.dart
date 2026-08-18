import 'package:flutter/material.dart';

import '../../controllers/transfer_controller.dart';
import '../../l10n/l10n.dart';
import '../../models/mesh_models.dart';
import '../../services/voice_note_audio_controller.dart';
import 'voice_note_content.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    this.transfers,
    this.voiceAudio,
    super.key,
  });

  final MeshMessage message;
  final TransferController? transfers;
  final VoiceNoteAudioController? voiceAudio;

  @override
  Widget build(BuildContext context) {
    final alignment = message.isMine
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final color = message.isDrill
        ? Theme.of(context).colorScheme.tertiaryContainer
        : message.isSos
        ? Theme.of(context).colorScheme.errorContainer
        : message.isMine
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final status = message.isPending
        ? context.l10n.privateMessagePending
        : message.isExpired
        ? context.l10n.deliveryExpired
        : message.isMine
        ? context.l10n.deliveryRelayed
        : '';
    final semanticLabel = [
      if (!message.isMine) message.sender,
      message.content.replaceFirst('SOS|', 'SOS: '),
      if (status.isNotEmpty) status,
      MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(message.timestamp.toLocal())),
    ].join(', ');
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Align(
          alignment: alignment,
          child: Container(
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.sizeOf(context).width *
                  (textScale >= 1.5 ? 0.92 : 0.78),
            ),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!message.isMine || message.isPrivate) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.isPrivate) ...[
                        const Icon(Icons.lock, size: 14),
                        const SizedBox(width: 4),
                      ],
                      if (!message.isMine)
                        Flexible(
                          child: Text(
                            message.sender,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                if (message.isVoiceNote)
                  VoiceNoteContent(
                    message: message,
                    transfers: transfers,
                    voiceAudio: voiceAudio,
                  )
                else if (message.isDrill)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.drillBadge,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message.drill?.readableMessage ??
                            context.l10n.drillInvalidMessage,
                      ),
                    ],
                  )
                else
                  Text(message.content.replaceFirst('SOS|', 'SOS: ')),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (message.isPending) ...[
                        const Icon(Icons.schedule, size: 13),
                        const SizedBox(width: 3),
                        Text(
                          context.l10n.privateMessagePending,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (message.isExpired) ...[
                        const Icon(Icons.timer_off_outlined, size: 13),
                        const SizedBox(width: 3),
                        Text(
                          context.l10n.deliveryExpired,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (message.isMine &&
                          !message.isPending &&
                          !message.isExpired) ...[
                        const Icon(Icons.campaign_outlined, size: 13),
                        const SizedBox(width: 3),
                        Text(
                          context.l10n.deliveryRelayed,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        MaterialLocalizations.of(context).formatTimeOfDay(
                          TimeOfDay.fromDateTime(message.timestamp.toLocal()),
                        ),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
