import '../models/mesh_models.dart';
import 'message_chronology.dart';

typedef MessageTimelineEntry = ({DateTime? day, MeshMessage? message});

List<MessageTimelineEntry> messageTimelineEntries(List<MeshMessage> messages) {
  final entries = <MessageTimelineEntry>[];
  DateTime? previousDay;
  for (final message in messages) {
    final day = localCalendarDay(message.timestamp);
    if (previousDay != day) {
      entries.add((day: day, message: null));
      previousDay = day;
    }
    entries.add((day: null, message: message));
  }
  return entries;
}
