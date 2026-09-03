import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/presentation/task_formatting.dart';
import 'package:neximmo_app/ui/components/nx_status_badge.dart';

void main() {
  final now = DateTime(2026, 9, 3, 10);

  test('formats dates as dd.MM.yyyy', () {
    expect(formatTaskDate(DateTime(2026, 1, 5)), '05.01.2026');
  });

  test('due chip: overdue overrides as text, relative within seven days', () {
    expect(taskDueLabel(null, now: now), isNull);

    final overdue = taskDueLabel(DateTime(2026, 9, 2), now: now)!;
    expect(overdue.text, 'Überfällig');
    expect(overdue.kind, NxBadgeKind.error);

    expect(taskDueLabel(DateTime(2026, 9, 3, 23), now: now)!.text, 'Heute');
    expect(taskDueLabel(DateTime(2026, 9, 4), now: now)!.text, 'Morgen');
    expect(
      taskDueLabel(DateTime(2026, 9, 10), now: now)!.text,
      'In 7 Tagen',
    );
    expect(
      taskDueLabel(DateTime(2026, 9, 11), now: now)!.text,
      '11.09.2026',
    );
  });
}
