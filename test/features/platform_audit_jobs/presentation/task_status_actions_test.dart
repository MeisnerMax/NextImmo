import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/task_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/presentation/task_status_actions.dart';

void main() {
  test('the action table is congruent with STM-012 (§6.3 / Shared §17)', () {
    for (final status in TaskStatus.values) {
      final offeredTargets = taskStatusActions(
        status,
      ).map((action) => action.target).toSet();
      final allowedTargets = TaskStatus.values
          .where((target) => status.canTransitionTo(target))
          .toSet();
      // Congruent in both directions: no offered action the automaton
      // forbids, no allowed transition the UI hides.
      expect(offeredTargets, allowedTargets, reason: status.name);
    }
  });

  test('"Erledigt" never appears on an open task', () {
    expect(
      taskStatusActions(TaskStatus.open).map((action) => action.label),
      isNot(contains('Erledigt')),
    );
    expect(
      taskStatusActions(TaskStatus.inProgress).map((action) => action.label),
      contains('Erledigt'),
    );
  });

  test('archived is terminal and blocked demands a reason', () {
    expect(taskStatusActions(TaskStatus.archived), isEmpty);
    for (final status in TaskStatus.values) {
      for (final action in taskStatusActions(status)) {
        expect(
          action.requiresReason,
          action.target == TaskStatus.blocked,
          reason: '${status.name} → ${action.target.name}',
        );
        expect(action.isArchive, action.target == TaskStatus.archived);
      }
    }
  });

  test('labels follow the §6.3 table', () {
    expect(
      taskStatusActions(TaskStatus.open).map((action) => action.label),
      <String>['Starten', 'Blockiert', 'Archivieren'],
    );
    expect(
      taskStatusActions(TaskStatus.blocked).map((action) => action.label),
      <String>['Fortsetzen', 'Erledigt', 'Zurück auf Offen', 'Archivieren'],
    );
    expect(
      taskStatusActions(TaskStatus.done).map((action) => action.label),
      <String>['Wieder öffnen', 'Archivieren'],
    );
  });
}
