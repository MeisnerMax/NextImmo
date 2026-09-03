import 'package:flutter/material.dart';

import '../../../ui/components/nx_status_badge.dart';
import '../domain/task_dto.dart';

/// German labels and badge kinds for [TaskStatus], kept beside the domain
/// enum's consumers per Foundation §12 (the badge text, not the color,
/// carries the meaning; `maintenance_capex_badges.dart` and
/// `membership_badges.dart` are the models). Mapping per shared contract
/// §5.1; "Überfällig" is deliberately absent — it overrides the due chip,
/// never the status badge.
String taskStatusLabel(TaskStatus status) {
  return switch (status) {
    TaskStatus.open => 'Offen',
    TaskStatus.inProgress => 'In Bearbeitung',
    TaskStatus.blocked => 'Blockiert',
    TaskStatus.done => 'Erledigt',
    TaskStatus.archived => 'Archiviert',
  };
}

NxBadgeKind taskStatusBadgeKind(TaskStatus status) {
  return switch (status) {
    TaskStatus.open => NxBadgeKind.neutral,
    TaskStatus.inProgress => NxBadgeKind.info,
    TaskStatus.blocked => NxBadgeKind.warning,
    TaskStatus.done => NxBadgeKind.success,
    TaskStatus.archived => NxBadgeKind.neutral,
  };
}

/// The one task status rendering: §5.1 shows `archived` as neutral *dimmed* —
/// terminal and out of the working set, but still legible in archive lists.
/// Centralizing the dim here keeps every consumer from re-inventing it.
class TaskStatusBadge extends StatelessWidget {
  const TaskStatusBadge({super.key, required this.status});

  static const double _archivedOpacity = 0.6;

  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final badge = NxStatusBadge(
      label: taskStatusLabel(status),
      kind: taskStatusBadgeKind(status),
    );
    if (status != TaskStatus.archived) {
      return badge;
    }
    return Opacity(opacity: _archivedOpacity, child: badge);
  }
}
