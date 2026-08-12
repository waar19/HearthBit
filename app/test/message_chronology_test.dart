import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/utils/message_chronology.dart';

void main() {
  test('clasifica hoy ayer y fechas anteriores con hora local', () {
    final now = DateTime(2026, 8, 12, 15, 30);

    expect(
      relativeMessageDay(DateTime(2026, 8, 12, 1), now: now),
      RelativeMessageDay.today,
    );
    expect(
      relativeMessageDay(DateTime(2026, 8, 11, 23, 59), now: now),
      RelativeMessageDay.yesterday,
    );
    expect(
      relativeMessageDay(DateTime(2026, 8, 10, 23, 59), now: now),
      RelativeMessageDay.other,
    );
  });

  test('solo crea un nuevo grupo cuando cambia el día', () {
    final messages = [
      DateTime(2026, 8, 11, 22),
      DateTime(2026, 8, 11, 23),
      DateTime(2026, 8, 12, 0, 1),
    ];
    var groups = 0;
    DateTime? previous;
    for (final timestamp in messages) {
      if (previous == null || !isSameMessageDay(previous, timestamp)) {
        groups += 1;
      }
      previous = timestamp;
    }

    expect(groups, 2);
  });
}
