/// Task aggregate DTOs (P2-D04, DOM-010, STM-012).
///
/// Mirrors `private.task_snapshot` field for field and carries no SDK types.
library;

import 'platform_entity_type.dart';

/// STM-012. `archived` is terminal and has no delete path, which is what makes
/// a task row carrying a [TaskDto.generatedKey] the durable AGG-019 idempotency
/// ledger rather than a separate instances table.
enum TaskStatus {
  open('open'),
  inProgress('in_progress'),
  blocked('blocked'),
  done('done'),
  archived('archived');

  const TaskStatus(this.wireName);

  final String wireName;

  static TaskStatus? fromWire(String? value) {
    for (final status in TaskStatus.values) {
      if (status.wireName == value) return status;
    }
    return null;
  }

  /// A client-side mirror of `private.task_status_can_transition`, for
  /// enabling/disabling affordances before a round trip. The server remains
  /// authoritative — a client that skips this check still gets
  /// `validationFailed`, it does not get an illegal transition.
  bool canTransitionTo(TaskStatus target) {
    switch (this) {
      case TaskStatus.open:
        return const {
          TaskStatus.inProgress,
          TaskStatus.blocked,
          TaskStatus.archived,
        }.contains(target);
      case TaskStatus.inProgress:
        return const {
          TaskStatus.blocked,
          TaskStatus.done,
          TaskStatus.open,
          TaskStatus.archived,
        }.contains(target);
      case TaskStatus.blocked:
        return const {
          TaskStatus.inProgress,
          TaskStatus.done,
          TaskStatus.open,
          TaskStatus.archived,
        }.contains(target);
      case TaskStatus.done:
        return const {TaskStatus.open, TaskStatus.archived}.contains(target);
      case TaskStatus.archived:
        return false;
    }
  }

  bool get isTerminal => this == TaskStatus.archived;
}

enum TaskPriority {
  low('low'),
  normal('normal'),
  high('high');

  const TaskPriority(this.wireName);

  final String wireName;

  static TaskPriority? fromWire(String? value) {
    for (final priority in TaskPriority.values) {
      if (priority.wireName == value) return priority;
    }
    return null;
  }
}

class TaskDto {
  const TaskDto({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.priority,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    required this.version,
    this.entity,
    this.propertyId,
    this.description,
    this.category,
    this.assignedTo,
    this.dueAt,
    this.generatedKey,
    this.archivedAt,
  });

  final String id;
  final String workspaceId;
  final String title;
  final TaskPriority priority;
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;
  final int version;

  /// Optional link to a workflow entity.
  final PlatformEntityRef? entity;

  /// TASK-QUERY-01: the server-maintained property roll-up. Set when [entity]
  /// is a property or belongs to one (unit, lease, maintenance ticket, capex
  /// project); null for unlinked tasks and non-property contexts. Derived and
  /// immutable — the client never writes it.
  final String? propertyId;
  final String? description;
  final String? category;
  final String? assignedTo;
  final DateTime? dueAt;

  /// AGG-019: the business-level dedup key of a recurring generation, distinct
  /// from the per-call `mutationId`. Immutable once set.
  final String? generatedKey;
  final DateTime? archivedAt;

  bool get isGenerated => generatedKey != null;
}

/// Input for `create_task`. The server normalizes free text and starts every
/// task in [TaskStatus.open] — the draft cannot choose a status.
class TaskDraft {
  const TaskDraft({
    required this.title,
    this.entity,
    this.description,
    this.category,
    this.assignedTo,
    this.priority = TaskPriority.normal,
    this.dueAt,
    this.generatedKey,
  });

  final String title;
  final PlatformEntityRef? entity;
  final String? description;
  final String? category;
  final String? assignedTo;
  final TaskPriority priority;
  final DateTime? dueAt;
  final String? generatedKey;
}

/// A sparse edit for `update_task`. Only the fields the server accepts as
/// change keys are representable, and each is independently "absent" vs
/// "explicitly cleared" — sending `{'category': null}` clears the category
/// while omitting it leaves it untouched. Status is deliberately absent: it
/// moves only through `transition_task_status`.
class TaskUpdateDto {
  const TaskUpdateDto({
    this.title,
    this.description = const TaskFieldEdit.absent(),
    this.category = const TaskFieldEdit.absent(),
    this.assignedTo = const TaskFieldEdit.absent(),
    this.priority,
    this.dueAt = const TaskFieldEdit.absent(),
  });

  final String? title;
  final TaskFieldEdit<String> description;
  final TaskFieldEdit<String> category;
  final TaskFieldEdit<String> assignedTo;
  final TaskPriority? priority;
  final TaskFieldEdit<DateTime> dueAt;

  bool get isEmpty =>
      title == null &&
      !description.isPresent &&
      !category.isPresent &&
      !assignedTo.isPresent &&
      priority == null &&
      !dueAt.isPresent;
}

/// Distinguishes "leave this field alone" from "set this field to null" in a
/// sparse update, which a plain nullable field cannot express.
class TaskFieldEdit<T extends Object> {
  const TaskFieldEdit.absent() : _value = null, isPresent = false;

  const TaskFieldEdit.set(T value) : _value = value, isPresent = true;

  const TaskFieldEdit.clear() : _value = null, isPresent = true;

  final T? _value;
  final bool isPresent;

  T? get value => _value;
}
