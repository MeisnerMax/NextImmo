import 'package:flutter/material.dart';

import '../../../../ui/components/nx_status_badge.dart';
import '../../../../ui/theme/app_theme.dart';
import '../../domain/task_dto.dart';
import '../task_badges.dart';
import '../task_formatting.dart';
import 'entity_ref_chip.dart';

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

  String get _assigneeLabel {
    final assignedTo = task.assignedTo;
    if (assignedTo == null) {
      return '—';
    }
    // Only the own membership is resolvable in V1; a foreign uuid renders as
    // "Zugewiesen" and never as the raw id (§7).
    return assignedTo == actorId ? 'Mir zugewiesen' : 'Zugewiesen';
  }

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
