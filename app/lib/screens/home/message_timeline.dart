import 'package:flutter/material.dart';

import '../../controllers/transfer_controller.dart';
import '../../services/voice_note_audio_controller.dart';
import '../../utils/message_timeline.dart';
import 'compact_sos_message.dart';
import 'date_separator.dart';
import 'message_bubble.dart';
import 'message_day_label.dart';

Widget buildMessageTimelineEntry(
  BuildContext context,
  MessageTimelineEntry entry, {
  TransferController? transfers,
  VoiceNoteAudioController? voiceAudio,
  bool compactSos = false,
}) {
  final day = entry.day;
  if (day != null) {
    return DateSeparator(label: formatMessageDayLabel(context, day));
  }
  final message = entry.message!;
  return compactSos && message.isSos
      ? CompactSosMessage(message: message)
      : MessageBubble(
          message: message,
          transfers: transfers,
          voiceAudio: voiceAudio,
        );
}
