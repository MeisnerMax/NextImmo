import 'package:flutter/material.dart';

import '../../../../ui/components/nx_status_badge.dart';
import '../../../../ui/theme/app_theme.dart';
import '../../domain/task_dto.dart';
import '../task_badges.dart';
import '../task_formatting.dart';
import 'entity_ref_chip.dart';

/// Only the own membership is resolvable in V1; a foreign uuid renders as
/// "Zugewiesen" and never as the raw id (§7).
String taskAssigneeLabel(TaskDto task, String? actorId) {
  final assignedTo = task.assignedTo;
  if (assignedTo == null) {
    return '—';
  }
  return assignedTo == actorId ? 'Mir zugewiesen' : 'Zugewiesen';
}

/// The mobile fallback of the task list (Foundation §6, `task_center.md` §5):
/// a `ListTile` with a chevron instead of the desktop row layout, which a
/// 320–390 px viewport cannot carry. Same data, same tap target, same bulk
/// semantics — status, due and priority stay text signals (§15), never a
/// squeezed chip row.
class TaskMobileRow extends StatelessWidget {
  const TaskMobileRow({
    super.key,
    required this.task,
    required this.onTap,
    this.actorId,
    this.now,
    this.selected = false,
    this.selecting = false,
    this.checked = false,
    this.onCheckedChanged,
  });

  final TaskDto task;
  final VoidCallback onTap;
  final String? actorId;
  final DateTime? now;
  final bool selected;
  final bool selecting;
  final bool checked;
  final ValueChanged<bool>? onCheckedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = taskDueLabel(task.dueAt, now: now ?? DateTime.now());
    final statusLine = <String>[
      taskStatusLabel(task.status),
      if (due != null) due.text,
      if (task.priority == TaskPriority.high) 'Hoch',
    ].join(' · ');
    final category = taskCategoryDisplayLabel(task.category);
    final metaLine = <String>[
      if (category != null) category,
      'Zuständig: ${taskAssigneeLabel(task, actorId)}',
      if (task.entity != null) platformEntityTypeLabel(task.entity!.type),
    ].join(' · ');
    return ListTile(
      key: Key('task-mobile-row-${task.id}'),
      selected: selected,
      onTap: onTap,
      leading: selecting
          ? Semantics(
              label: 'Aufgabe auswählen: ${task.title}',
              child: Checkbox(
                key: Key('task-mobile-check-${task.id}'),
                value: checked,
                onChanged: onCheckedChanged == null
                    ? null
                    : (value) => onCheckedChanged!(value ?? false),
              ),
            )
          : null,
      title: Text(
        task.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statusLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: due?.isOverdue ?? false
                ? theme.textTheme.bodySmall?.copyWith(
                    color: context.semanticColors.error,
                  )
                : theme.textTheme.bodySmall,
          ),
          Text(
            metaLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      isThreeLine: true,
      trailing: selecting ? null : const Icon(Icons.chevron_right),
    );
  }
}

/// The one task row (Shared §5.1, candidate `SHARED-UI-TASKROW-01`): status
/// badge, title and due chip on the first line; category, assignee and the
/// context chip on the second. "Überfällig" overrides the *due chip*, never
/// the status badge, and priority appears as its own chip only at `high`.
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.onTap,
    this.actorId,
    this.now,
    this.selected = false,
    this.selecting = false,
    this.checked = false,
    this.onCheckedChanged,
    this.dense = false,
  });

  final TaskDto task;
  final VoidCallback onTap;
  final String? actorId;

  /// Injectable clock for deterministic due chips in tests.
  final DateTime? now;
  final bool selected;

  /// Bulk mode: the checkbox column exists only while it is active (§5).
  final bool selecting;
  final bool checked;
  final ValueChanged<bool>? onCheckedChanged;

  /// Compact variant for board cards.
  final bool dense;

  String get _assigneeLabel => taskAssigneeLabel(task, actorId);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = taskDueLabel(task.dueAt, now: now ?? DateTime.now());
    final categoryLabel = taskCategoryDisplayLabel(task.category);
    return Semantics(
      label:
          '${task.title}, ${taskStatusLabel(task.status)}'
          '${due == null ? '' : ', ${due.text}'}',
      child: InkWell(
        key: Key('task-row-${task.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        child: Container(
          padding: EdgeInsets.all(dense ? AppSpacing.xs : AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.surfaceContainerHighest
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selecting) ...[
                Semantics(
                  label: 'Aufgabe auswählen: ${task.title}',
                  child: Checkbox(
                    key: Key('task-row-check-${task.id}'),
                    value: checked,
                    onChanged: onCheckedChanged == null
                        ? null
                        : (value) => onCheckedChanged!(value ?? false),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TaskStatusBadge(status: task.status),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (due != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          NxStatusBadge(label: due.text, kind: due.kind),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          categoryLabel == null
                              ? 'Zuständig: $_assigneeLabel'
                              : '$categoryLabel · Zuständig: $_assigneeLabel',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (task.priority == TaskPriority.high)
                          const NxStatusBadge(
                            label: 'Hoch',
                            kind: NxBadgeKind.warning,
                          ),
                        if (task.entity != null)
                          EntityRefChip(entity: task.entity!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
