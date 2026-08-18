import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void scheduleScrollToBottom(
  ScrollController controller, {
  bool animate = true,
  required bool Function() isMounted,
  required bool Function() markScheduled,
  required void Function(bool) setScheduled,
}) {
  if (markScheduled()) return;
  setScheduled(true);
  SchedulerBinding.instance.addPostFrameCallback((_) {
    setScheduled(false);
    if (!isMounted() || !controller.hasClients) return;
    final target = controller.position.maxScrollExtent;
    if (animate) {
      controller.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      controller.jumpTo(target);
    }
  });
}
