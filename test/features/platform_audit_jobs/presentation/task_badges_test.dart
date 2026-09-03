import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/task_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/presentation/task_badges.dart';
import 'package:neximmo_app/ui/components/nx_status_badge.dart';

void main() {
  test('maps every task status to its §5.1 label and badge kind', () {
    const expected = <TaskStatus, (String, NxBadgeKind)>{
      TaskStatus.open: ('Offen', NxBadgeKind.neutral),
      TaskStatus.inProgress: ('In Bearbeitung', NxBadgeKind.info),
      TaskStatus.blocked: ('Blockiert', NxBadgeKind.warning),
      TaskStatus.done: ('Erledigt', NxBadgeKind.success),
      TaskStatus.archived: ('Archiviert', NxBadgeKind.neutral),
    };

    // Exhaustive by construction: a new status without a row here fails.
    expect(expected.keys, TaskStatus.values);
    expected.forEach((status, mapping) {
      expect(taskStatusLabel(status), mapping.$1, reason: status.name);
      expect(taskStatusBadgeKind(status), mapping.$2, reason: status.name);
    });
  });

  testWidgets('renders an archived badge dimmed and every other one plain', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: <Widget>[
            TaskStatusBadge(status: TaskStatus.open),
            TaskStatusBadge(status: TaskStatus.archived),
          ],
        ),
      ),
    );

    expect(find.text('Offen'), findsOneWidget);
    expect(find.text('Archiviert'), findsOneWidget);
    // §5.1: archived is neutral *dimmed* — the dim lives here once instead of
    // in every consumer.
    expect(
      find.ancestor(
        of: find.text('Offen'),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    final dimmed = tester.widget<Opacity>(
      find.ancestor(
        of: find.text('Archiviert'),
        matching: find.byType(Opacity),
      ),
    );
    expect(dimmed.opacity, lessThan(1));
  });
}
