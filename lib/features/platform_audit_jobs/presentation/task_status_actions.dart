/// The status action vocabulary of the Task Center (`task_center.md` §6.3):
/// per lifecycle state exactly the transitions STM-012 allows, with the
/// binding German labels. A test pins this table congruent with
/// [TaskStatus.canTransitionTo] so client affordances and the SQL matrix
/// cannot drift apart.
library;

import '../domain/task_dto.dart';

class TaskStatusAction {
  const TaskStatusAction({required this.label, required this.target});

  final String label;
  final TaskStatus target;

  bool get isArchive => target == TaskStatus.archived;

  /// §6.3: a transition into `blocked` demands an individual reason — a
  /// blocker without one is worthless to everyone else.
  bool get requiresReason => target == TaskStatus.blocked;
}

/// §6.3 table, in its row order. "Erledigt" deliberately never appears on an
/// `open` task — `open → done` is a server error, not a shortcut.
List<TaskStatusAction> taskStatusActions(TaskStatus current) {
  return switch (current) {
    TaskStatus.open => const <TaskStatusAction>[
      TaskStatusAction(label: 'Starten', target: TaskStatus.inProgress),
      TaskStatusAction(label: 'Blockiert', target: TaskStatus.blocked),
      TaskStatusAction(label: 'Archivieren', target: TaskStatus.archived),
    ],
    TaskStatus.inProgress => const <TaskStatusAction>[
      TaskStatusAction(label: 'Erledigt', target: TaskStatus.done),
      TaskStatusAction(label: 'Blockiert', target: TaskStatus.blocked),
      TaskStatusAction(label: 'Zurück auf Offen', target: TaskStatus.open),
      TaskStatusAction(label: 'Archivieren', target: TaskStatus.archived),
    ],
    TaskStatus.blocked => const <TaskStatusAction>[
      TaskStatusAction(label: 'Fortsetzen', target: TaskStatus.inProgress),
      TaskStatusAction(label: 'Erledigt', target: TaskStatus.done),
      TaskStatusAction(label: 'Zurück auf Offen', target: TaskStatus.open),
      TaskStatusAction(label: 'Archivieren', target: TaskStatus.archived),
    ],
    TaskStatus.done => const <TaskStatusAction>[
      TaskStatusAction(label: 'Wieder öffnen', target: TaskStatus.open),
      TaskStatusAction(label: 'Archivieren', target: TaskStatus.archived),
    ],
    TaskStatus.archived => const <TaskStatusAction>[],
  };
}
