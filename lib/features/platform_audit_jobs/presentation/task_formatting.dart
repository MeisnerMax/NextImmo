/// Pure display formatting for task fields (`task_center.md` §5.1/§7):
/// the due chip is relative within seven days, "Überfällig" overrides it as
/// text (never only color), and dates render as dd.MM.yyyy.
library;

import '../../../ui/components/nx_status_badge.dart';

String formatTaskDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day.$month.${local.year}';
}

class TaskDueLabel {
  const TaskDueLabel({required this.text, required this.kind});

  final String text;
  final NxBadgeKind kind;

  bool get isOverdue => kind == NxBadgeKind.error;
}

/// Null when the task has no due date. Comparison is by calendar day in the
/// device's local time — the client has no workspace-timezone source, and a
/// wrong-by-hours boundary beats a fabricated timezone.
TaskDueLabel? taskDueLabel(DateTime? dueAt, {required DateTime now}) {
  if (dueAt == null) {
    return null;
  }
  final today = DateTime(now.year, now.month, now.day);
  final due = dueAt.toLocal();
  final dueDay = DateTime(due.year, due.month, due.day);
  final days = dueDay.difference(today).inDays;
  if (days < 0) {
    return const TaskDueLabel(text: 'Überfällig', kind: NxBadgeKind.error);
  }
  if (days == 0) {
    return const TaskDueLabel(text: 'Heute', kind: NxBadgeKind.warning);
  }
  if (days == 1) {
    return const TaskDueLabel(text: 'Morgen', kind: NxBadgeKind.info);
  }
  if (days <= 7) {
    return TaskDueLabel(text: 'In $days Tagen', kind: NxBadgeKind.info);
  }
  return TaskDueLabel(text: formatTaskDate(due), kind: NxBadgeKind.neutral);
}
