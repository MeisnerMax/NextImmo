/// Backend-agnostic platform_audit_jobs contract (P2-D04, DOM-010).
///
/// Four of the five DOM-010 ports live here — [TaskRepository],
/// [NotificationPort], [JobRepository] and [SearchIndexPort]; the event ports
/// (`OutboxPort`/`DomainEventConsumer`) live in `platform_domain_event.dart`.
///
/// Task, notification and import-job mutations are workspace-scoped,
/// permission-gated server-side (`task.*`, `notification.*`, `import.*`; no
/// AAL2 — these are ordinary workspace business data), idempotent
/// (`mutationId`), versioned (`expectedVersion` wherever a row is edited) and
/// audited append-only: the same envelope as the property, party and document
/// contracts.
///
/// [SearchIndexPort] deliberately breaks that symmetry, because DOM-010 says
/// the search index is derived and not a source of truth. Its commands carry no
/// `mutationId`, no `expectedVersion` and produce no receipt — see the port's
/// own doc comment.
library;

import '../domain/import_job_dto.dart';
import '../domain/notification_dto.dart';
import '../domain/platform_entity_type.dart';
import '../domain/search_entry_dto.dart';
import '../domain/task_dto.dart';

/// The audited command envelope shared by every mutating platform command
/// except the search-index projection.
class PlatformCommandContext {
  const PlatformCommandContext({
    required this.workspaceId,
    required this.actorId,
    required this.mutationId,
    required this.correlationId,
    this.reason,
  });

  final String workspaceId;
  final String actorId;
  final String mutationId;
  final String correlationId;
  final String? reason;
}

/// The reduced context of the derived-index write path: a workspace to scope to
/// and an actor to attribute the projection to. There is no `mutationId` and no
/// `correlationId` because there is no receipt and no audit row to correlate —
/// that absence is the DOM-010 contract, not an oversight.
class SearchIndexCommandContext {
  const SearchIndexCommandContext({
    required this.workspaceId,
    required this.actorId,
  });

  final String workspaceId;
  final String actorId;
}

class PlatformPageRequest {
  const PlatformPageRequest({this.limit = 50, this.cursor})
    : assert(limit > 0 && limit <= 100);

  final int limit;

  /// Opaque to callers. Produced by a previous page's
  /// [PlatformPageResult.nextCursor]; see [PlatformKeysetCursor] for the shape
  /// both adapters agree on.
  final String? cursor;
}

class PlatformPageResult<T> {
  const PlatformPageResult({required this.items, this.nextCursor});

  final List<T> items;
  final String? nextCursor;
}

/// The composite keyset cursor every platform list uses: a timestamp plus the
/// row id that breaks ties.
///
/// A timestamp alone cannot order these rows — `now()` is transaction-bound, so
/// every row written by one command shares it (the same property increment 1
/// pinned for `domain_events.occurred_at`). A bare uuid cursor would be stable
/// but would order a notification feed at random. The pair is both stable and
/// meaningful.
class PlatformKeysetCursor {
  const PlatformKeysetCursor({required this.timestamp, required this.id});

  final DateTime timestamp;
  final String id;

  static PlatformKeysetCursor? decode(String? value) {
    if (value == null) {
      return null;
    }
    final separator = value.lastIndexOf('|');
    if (separator <= 0 || separator == value.length - 1) {
      return null;
    }
    final timestamp = DateTime.tryParse(value.substring(0, separator));
    if (timestamp == null) {
      return null;
    }
    return PlatformKeysetCursor(
      timestamp: timestamp,
      id: value.substring(separator + 1),
    );
  }

  String encode() => '${timestamp.toUtc().toIso8601String()}|$id';
}

// -----------------------------------------------------------------------------
// Queries
// -----------------------------------------------------------------------------

/// Sort order of a task list read (TASK-QUERY-01).
///
/// [dueAsc] orders by due date ascending and — deliberately — serves only
/// tasks that HAVE a due date: the keyset cursor is a (timestamp, id) pair
/// and cannot express null, and "kein Termin" is a filter bucket
/// ([TaskListQuery.withoutDue]), not a sort position the server would have to
/// invent.
enum TaskListSort { createdDesc, dueAsc }

/// Task list read. [entity] scopes to one workflow entity's tasks,
/// [propertyId] to one property's roll-up (a task linked to a unit, lease,
/// ticket or capex project counts toward its parent property), [assignedTo]
/// to one member's queue and [unassignedOnly] to the open pool, [statuses]
/// to a union of lifecycle states. [dueFrom] is inclusive, [dueUntil]
/// exclusive (half-open day buckets); [withoutDue] serves the no-date bucket
/// instead and therefore excludes a range. [titleQuery] is a plain substring
/// match (ilike, wildcards escaped by the adapter). Archived tasks are
/// excluded unless [includeArchived] is set — an archived task is terminal,
/// so it belongs in an audit view rather than a work list.
class TaskListQuery {
  const TaskListQuery({
    required this.workspaceId,
    this.statuses,
    this.entity,
    this.assignedTo,
    this.unassignedOnly = false,
    this.propertyId,
    this.dueFrom,
    this.dueUntil,
    this.withoutDue = false,
    this.titleQuery,
    this.includeArchived = false,
    this.sort = TaskListSort.createdDesc,
    this.page = const PlatformPageRequest(),
  }) : assert(
         assignedTo == null || !unassignedOnly,
         'An assignee filter and unassignedOnly are mutually exclusive.',
       ),
       assert(
         !withoutDue || (dueFrom == null && dueUntil == null),
         'A without-due filter excludes a due range.',
       ),
       assert(
         sort != TaskListSort.dueAsc || !withoutDue,
         'A due-ordered read cannot serve the no-due-date bucket.',
       );

  final String workspaceId;
  final List<TaskStatus>? statuses;
  final PlatformEntityRef? entity;
  final String? assignedTo;
  final bool unassignedOnly;
  final String? propertyId;
  final DateTime? dueFrom;
  final DateTime? dueUntil;
  final bool withoutDue;
  final String? titleQuery;
  final bool includeArchived;
  final TaskListSort sort;
  final PlatformPageRequest page;
}

/// The KPI count for the My-Work header (`count_tasks`). Field for field the
/// filter surface of [TaskListQuery] minus paging and sort, so a count can
/// never disagree with the list it captions.
class TaskCountQuery {
  const TaskCountQuery({
    required this.workspaceId,
    this.statuses,
    this.entity,
    this.assignedTo,
    this.unassignedOnly = false,
    this.propertyId,
    this.dueFrom,
    this.dueUntil,
    this.withoutDue = false,
    this.titleQuery,
    this.includeArchived = false,
  }) : assert(
         assignedTo == null || !unassignedOnly,
         'An assignee filter and unassignedOnly are mutually exclusive.',
       ),
       assert(
         !withoutDue || (dueFrom == null && dueUntil == null),
         'A without-due filter excludes a due range.',
       );

  final String workspaceId;
  final List<TaskStatus>? statuses;
  final PlatformEntityRef? entity;
  final String? assignedTo;
  final bool unassignedOnly;
  final String? propertyId;
  final DateTime? dueFrom;
  final DateTime? dueUntil;
  final bool withoutDue;
  final String? titleQuery;
  final bool includeArchived;
}

/// Newest-first notification feed. With [recipientUserId] set the caller reads
/// one member's inbox; without it, the whole workspace feed — which the server
/// only serves to a holder of `notification.read`.
class NotificationFeedQuery {
  const NotificationFeedQuery({
    required this.workspaceId,
    this.recipientUserId,
    this.unreadOnly = false,
    this.page = const PlatformPageRequest(),
  });

  final String workspaceId;
  final String? recipientUserId;
  final bool unreadOnly;
  final PlatformPageRequest page;
}

class ImportJobListQuery {
  const ImportJobListQuery({
    required this.workspaceId,
    this.status,
    this.targetScope,
    this.page = const PlatformPageRequest(),
  });

  final String workspaceId;
  final ImportJobStatus? status;
  final String? targetScope;
  final PlatformPageRequest page;
}

/// Search-index read. [entityType] scopes to one registry type; [entities]
/// instead resolves an explicit set of (type, id) pairs — the name-resolution
/// read the task center and the notification inbox use for entity chips and
/// deep-link labels (TASK-QUERY-01). The two scopes are mutually exclusive:
/// a pair list carries its own types. Keep an entity list within one page
/// ([PlatformPageRequest.limit] caps at 100); an empty list is ignored.
class SearchIndexQuery {
  const SearchIndexQuery({
    required this.workspaceId,
    this.entityType,
    this.entities,
    this.page = const PlatformPageRequest(),
  }) : assert(
         entityType == null || entities == null,
         'A type scope and an explicit entity list are mutually exclusive.',
       );

  final String workspaceId;
  final PlatformEntityType? entityType;
  final List<PlatformEntityRef>? entities;
  final PlatformPageRequest page;
}

// -----------------------------------------------------------------------------
// Commands
// -----------------------------------------------------------------------------

class CreateTaskCommand {
  const CreateTaskCommand({required this.context, required this.draft});

  final PlatformCommandContext context;
  final TaskDraft draft;
}

class UpdateTaskCommand {
  const UpdateTaskCommand({
    required this.context,
    required this.taskId,
    required this.expectedVersion,
    required this.changes,
  });

  final PlatformCommandContext context;
  final String taskId;
  final int expectedVersion;
  final TaskUpdateDto changes;
}

class TransitionTaskStatusCommand {
  const TransitionTaskStatusCommand({
    required this.context,
    required this.taskId,
    required this.expectedVersion,
    required this.targetStatus,
  });

  final PlatformCommandContext context;
  final String taskId;
  final int expectedVersion;
  final TaskStatus targetStatus;
}

class CreateNotificationCommand {
  const CreateNotificationCommand({required this.context, required this.draft});

  final PlatformCommandContext context;
  final NotificationDraft draft;
}

/// Marking a notification read needs no `expectedVersion`: the operation is
/// idempotent and monotonic (unread → read, never back), so a stale version
/// cannot make it wrong. The server enforces that only the recipient may do it.
class MarkNotificationReadCommand {
  const MarkNotificationReadCommand({
    required this.context,
    required this.notificationId,
  });

  final PlatformCommandContext context;
  final String notificationId;
}

class CreateImportJobCommand {
  const CreateImportJobCommand({required this.context, required this.draft});

  final PlatformCommandContext context;
  final ImportJobDraft draft;
}

class UpdateImportJobCommand {
  const UpdateImportJobCommand({
    required this.context,
    required this.importJobId,
    required this.expectedVersion,
    required this.changes,
  });

  final PlatformCommandContext context;
  final String importJobId;
  final int expectedVersion;
  final ImportJobUpdateDto changes;
}

class TransitionImportJobStatusCommand {
  const TransitionImportJobStatusCommand({
    required this.context,
    required this.importJobId,
    required this.expectedVersion,
    required this.targetStatus,
    this.evidence = const ImportJobTransitionEvidence.none(),
  });

  final PlatformCommandContext context;
  final String importJobId;
  final int expectedVersion;
  final ImportJobStatus targetStatus;

  /// AGG-020 artifacts. The server accepts each on exactly one target status
  /// and rejects it anywhere else, so a mismatch here is a `validationFailed`,
  /// not a silently ignored field.
  final ImportJobTransitionEvidence evidence;
}

class ReindexSearchEntryCommand {
  const ReindexSearchEntryCommand({
    required this.context,
    required this.entity,
    required this.content,
  });

  final SearchIndexCommandContext context;
  final PlatformEntityRef entity;
  final SearchEntryContent content;
}

class RemoveSearchEntryCommand {
  const RemoveSearchEntryCommand({required this.context, required this.entity});

  final SearchIndexCommandContext context;
  final PlatformEntityRef entity;
}

// -----------------------------------------------------------------------------
// Results
// -----------------------------------------------------------------------------

enum PlatformRepositoryFailureKind {
  notFound,
  forbidden,
  validationFailed,
  versionConflict,
  mutationConflict,
  mutationInProgress,
  dependencyConflict,
  infrastructureFailure,
}

/// Structured optimistic-concurrency conflict. Exactly one of
/// [currentTask]/[currentImportJob] is set, matching the entity the failed
/// command targeted — the two versioned platform aggregates. Notifications
/// never produce one (no `expectedVersion`), and search entries have no
/// version at all.
class PlatformVersionConflict {
  const PlatformVersionConflict({
    required this.expectedVersion,
    required this.actualVersion,
    this.currentTask,
    this.currentImportJob,
  }) : assert((currentTask != null) != (currentImportJob != null));

  final int expectedVersion;
  final int actualVersion;
  final TaskDto? currentTask;
  final ImportJobDto? currentImportJob;
}

sealed class PlatformRepositoryResult<T> {
  const PlatformRepositoryResult();
}

class PlatformRepositorySuccess<T> extends PlatformRepositoryResult<T> {
  const PlatformRepositorySuccess(this.value);

  final T value;
}

class PlatformRepositoryFailure<T> extends PlatformRepositoryResult<T> {
  const PlatformRepositoryFailure({
    required this.kind,
    required this.message,
    this.versionConflict,
    this.validationFields = const <String>[],
  }) : assert(
         kind == PlatformRepositoryFailureKind.versionConflict
             ? versionConflict != null
             : versionConflict == null,
       );

  final PlatformRepositoryFailureKind kind;
  final String message;
  final PlatformVersionConflict? versionConflict;

  /// The change keys a `validation_failed` rejection named (the RPC error's
  /// `field` / `fields`), so a form can mark the exact input inline instead of
  /// showing one generic message (TASKS-NOTIFICATIONS shared contract §12).
  /// Empty when the server named none — and always empty for every other
  /// failure kind.
  final List<String> validationFields;
}

// -----------------------------------------------------------------------------
// Ports
// -----------------------------------------------------------------------------

/// DOM-010 `TaskRepository`: the STM-012 task lifecycle plus its keyset read.
/// Reads are server-authorized on `task.read`; mutations run through the
/// audited RPC envelope only.
/// Method names are aggregate-qualified rather than the bare `search`/`create`
/// of the single-aggregate features, because one adapter legitimately
/// implements several of these ports at once and Dart has no per-interface
/// method scoping.
abstract interface class TaskRepository {
  Future<PlatformRepositoryResult<PlatformPageResult<TaskDto>>> searchTasks(
    TaskListQuery query,
  );

  /// The `count_tasks` KPI read. Server-gated on `task.read` through the same
  /// predicate as the list policy, so the number can never include rows a
  /// list read would not serve.
  Future<PlatformRepositoryResult<int>> countTasks(TaskCountQuery query);

  Future<PlatformRepositoryResult<TaskDto>> getTaskById({
    required String workspaceId,
    required String taskId,
  });

  /// Registers a task. When [TaskDraft.generatedKey] is set and a task already
  /// carries that key, AGG-019 makes this return the *existing* task as a
  /// success — a recurring generation converges rather than duplicating, and
  /// that is distinct from the `mutationId` replay layer.
  Future<PlatformRepositoryResult<TaskDto>> createTask(
    CreateTaskCommand command,
  );

  /// Edits mutable fields. Status is not among them.
  Future<PlatformRepositoryResult<TaskDto>> updateTask(
    UpdateTaskCommand command,
  );

  Future<PlatformRepositoryResult<TaskDto>> transitionTaskStatus(
    TransitionTaskStatusCommand command,
  );
}

/// DOM-010 `NotificationPort`: recipient-addressed delivery and the feed read.
abstract interface class NotificationPort {
  Future<PlatformRepositoryResult<PlatformPageResult<NotificationDto>>>
  notificationFeed(NotificationFeedQuery query);

  /// Fans one platform event out to one row per recipient under a single
  /// `mutationId`, returning the batch receipt rather than any one row.
  Future<PlatformRepositoryResult<NotificationFanOutReceipt>> fanOutNotification(
    CreateNotificationCommand command,
  );

  /// Recipient-scoped and idempotent. A notification addressed to somebody else
  /// fails as [PlatformRepositoryFailureKind.notFound], never `forbidden` — the
  /// server must not even confirm that the row exists.
  Future<PlatformRepositoryResult<NotificationDto>> markNotificationRead(
    MarkNotificationReadCommand command,
  );
}

/// DOM-010 `JobRepository`, backed by the `import_jobs` aggregate (STM-013,
/// AGG-020).
abstract interface class JobRepository {
  Future<PlatformRepositoryResult<PlatformPageResult<ImportJobDto>>>
  searchImportJobs(ImportJobListQuery query);

  Future<PlatformRepositoryResult<ImportJobDto>> getImportJobById({
    required String workspaceId,
    required String importJobId,
  });

  Future<PlatformRepositoryResult<ImportJobDto>> createImportJob(
    CreateImportJobCommand command,
  );

  /// Only a draft job accepts an edit; the server rejects any later state with
  /// [PlatformRepositoryFailureKind.validationFailed], which is what freezes a
  /// mapping once validation has begun.
  Future<PlatformRepositoryResult<ImportJobDto>> updateImportJob(
    UpdateImportJobCommand command,
  );

  Future<PlatformRepositoryResult<ImportJobDto>> transitionImportJobStatus(
    TransitionImportJobStatusCommand command,
  );
}

/// DOM-010 `SearchIndexPort`: the derived, non-authoritative projection.
///
/// Every other port on this contract is enveloped. This one is not, and the
/// asymmetry is the design: a reindex is a content-addressed upsert keyed by
/// (workspace, entity), so last-writer-wins is the correct semantics and it is
/// idempotent by construction. A mutation receipt would wrongly *block* a
/// legitimate re-projection, and a version token would invent authority the
/// projection does not have. It is also the only platform port with a removal
/// path, because stale index rows must be removable.
abstract interface class SearchIndexPort {
  Future<PlatformRepositoryResult<PlatformPageResult<SearchEntryDto>>>
  searchIndex(SearchIndexQuery query);

  Future<PlatformRepositoryResult<SearchEntryDto>> reindexSearchEntry(
    ReindexSearchEntryCommand command,
  );

  /// Idempotent: removing an absent entry succeeds with
  /// [SearchEntryRemoval.removed] false.
  Future<PlatformRepositoryResult<SearchEntryRemoval>> removeSearchEntry(
    RemoveSearchEntryCommand command,
  );
}
