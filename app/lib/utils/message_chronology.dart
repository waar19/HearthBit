enum RelativeMessageDay { today, yesterday, other }

DateTime localCalendarDay(DateTime timestamp) {
  final local = timestamp.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool isSameMessageDay(DateTime first, DateTime second) =>
    localCalendarDay(first) == localCalendarDay(second);

RelativeMessageDay relativeMessageDay(DateTime timestamp, {DateTime? now}) {
  final day = localCalendarDay(timestamp);
  final current = localCalendarDay(now ?? DateTime.now());
  if (day == current) return RelativeMessageDay.today;
  if (day == current.subtract(const Duration(days: 1))) {
    return RelativeMessageDay.yesterday;
  }
  return RelativeMessageDay.other;
}
