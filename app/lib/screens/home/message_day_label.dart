import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../utils/message_chronology.dart';

String formatMessageDayLabel(BuildContext context, DateTime day) {
  return switch (relativeMessageDay(day)) {
    RelativeMessageDay.today => context.l10n.dateToday,
    RelativeMessageDay.yesterday => context.l10n.dateYesterday,
    RelativeMessageDay.other => MaterialLocalizations.of(
      context,
    ).formatMediumDate(day),
  };
}
