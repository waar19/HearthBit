import 'package:flutter/material.dart';

String formatConversationTime(BuildContext context, DateTime timestamp) {
  final local = timestamp.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
  }
  return MaterialLocalizations.of(context).formatShortDate(local);
}
