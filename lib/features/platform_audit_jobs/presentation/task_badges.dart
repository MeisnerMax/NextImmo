import 'package:flutter/material.dart';

import '../../../ui/components/nx_status_badge.dart';
import '../domain/task_category.dart';
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

/// German display labels of the §7.5 category vocabulary. An unknown server
/// value has no row here on purpose: it renders as its raw wire string
/// ("angezeigt und erhalten") via [taskCategoryDisplayLabel].
String taskCategoryLabel(TaskCategory category) {
  return switch (category) {
    TaskCategory.general => 'Allgemein',
    TaskCategory.letting => 'Vermietung',
    TaskCategory.maintenance => 'Instandhaltung',
    TaskCategory.renovation => 'Sanierung',
    TaskCategory.finance => 'Finanzen',
    TaskCategory.document => 'Dokumente',
    TaskCategory.compliance => 'Compliance',
    TaskCategory.valuation => 'Bewertung',
  };
}

/// Label for a raw wire value: the German label for vocabulary members, the
/// raw string itself for unknown ones, null for an absent category.
String? taskCategoryDisplayLabel(String? wire) {
  if (wire == null) {
    return null;
  }
  final known = TaskCategory.tryFromWire(wire);
  return known == null ? wire : taskCategoryLabel(known);
}

/// German priority labels (`task_center.md` §13). Visually, priority appears
/// as its own chip only at `high` (§5.1) — the label set still covers all
/// three for the dialog dropdown.
String taskPriorityLabel(TaskPriority priority) {
  return switch (priority) {
    TaskPriority.low => 'Niedrig',
    TaskPriority.normal => 'Normal',
    TaskPriority.high => 'Hoch',
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
