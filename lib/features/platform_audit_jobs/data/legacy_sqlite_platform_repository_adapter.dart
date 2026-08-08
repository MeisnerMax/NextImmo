import 'dart:convert';

import '../../../core/models/import_job.dart';
import '../../../core/models/notification.dart';
import '../../../core/models/search.dart';
import '../../../core/models/task.dart';
import '../../../data/repositories/imports_repo.dart';
import '../../../data/repositories/notifications_repo.dart';
import '../../../data/repositories/search_repo.dart';
import '../../../data/repositories/tasks_repo.dart';
import '../application/platform_repository.dart';
import '../domain/import_job_dto.dart';
import '../domain/notification_dto.dart';
import '../domain/platform_entity_type.dart';
import '../domain/search_entry_dto.dart';
import '../domain/task_dto.dart';

/// Read-only projection of the parallel legacy `tasks` / `notifications` /
/// `import_jobs` + `import_mappings` / `search_index` stores onto the four
/// data-plane DOM-010 ports (P2-D04 increment 4, mirroring the P2-D02 party and
/// P2-D03 document adapters).
///
/// The five source methods return the legacy record models verbatim; every
/// interpretation of them lives in [LegacySqlitePlatformRepositoryAdapter], so
/// a test can drive the whole projection without a database.
abstract interface class LegacyPlatformReadSource {
  Future<List<TaskRecord>> listTasks();

  Future<List<NotificationRecord>> listNotifications();

  Future<List<ImportJobRecord>> listImportJobs();

  /// Legacy `import_mappings` rows are not an entity of their own: one job
  /// targets one scope, so they fold into that job's
  /// [ImportJobDto.mapping] object.
  Future<List<ImportMappingRecord>> listImportMappings();

  Future<List<SearchIndexRecord>> listSearchEntries();
}

/// [LegacyPlatformReadSource] backed by the concrete local repositories.
///
/// One of the five methods has no purpose-built repository call behind it and
/// is documented rather than papered over:
///
/// * [listSearchEntries] — `SearchRepo` exposes only the query-scoped
///   [SearchRepo.search]. It is called here with the SQL `LIKE` wildcard, which
///   is the one existing call that enumerates the index, bounded by
///   [searchIndexReadLimit] because `search` requires a limit. The cap is real:
///   an index larger than that reads short, so this source is a convenience for
///   local reads, not an enumeration to migrate from.
///
/// [listImportMappings] was the second such gap. It is not one any more:
/// `ImportsRepository.listMappings` was added for it, because projecting a job
/// with an empty [ImportJobDto.mapping] while `import_mappings` rows exist
/// would have stated something the source data contradicts — unlike a null
/// dry-run, which is a fact the legacy schema genuinely does not hold.
class RepositoryLegacyPlatformReadSource implements LegacyPlatformReadSource {
  const RepositoryLegacyPlatformReadSource({
    required TasksRepo tasksRepo,
    required NotificationsRepository notificationsRepo,
    required ImportsRepository importsRepo,
    required SearchRepo searchRepo,
  }) : _tasksRepo = tasksRepo,
       _notificationsRepo = notificationsRepo,
       _importsRepo = importsRepo,
       _searchRepo = searchRepo;

  /// The ceiling [listSearchEntries] reads under. `SearchRepo.search` takes a
  /// limit and has no unbounded variant, so the enumeration is truncated rather
  /// than unbounded — a deliberate, documented cap.
  static const int searchIndexReadLimit = 1000;

  /// Matches every indexed row: `search` builds `LIKE '%$query%'`, so a bare
  /// `%` widens to `LIKE '%%%'`. A blank query would instead short-circuit to an
  /// empty result, which is why this is not simply `''`.
  static const String _matchAllQuery = '%';

  final TasksRepo _tasksRepo;
  final NotificationsRepository _notificationsRepo;
  final ImportsRepository _importsRepo;
  final SearchRepo _searchRepo;

  @override
  Future<List<TaskRecord>> listTasks() => _tasksRepo.listTasks();

  @override
  Future<List<NotificationRecord>> listNotifications() =>
      _notificationsRepo.listNotifications();

  @override
  Future<List<ImportJobRecord>> listImportJobs() => _importsRepo.listJobs();

  @override
  Future<List<ImportMappingRecord>> listImportMappings() =>
      _importsRepo.listMappings();

  @override
  Future<List<SearchIndexRecord>> listSearchEntries() =>
      _searchRepo.search(query: _matchAllQuery, limit: searchIndexReadLimit);
}

/// The legacy local-SQLite implementation of the four data-plane DOM-010 ports.
///
/// Reads project legacy rows onto the canonical DTOs. **Every** mutation —
/// [createTask], [updateTask], [transitionTaskStatus], [fanOutNotification],
/// [markNotificationRead], [createImportJob], [updateImportJob],
/// [transitionImportJobStatus], [reindexSearchEntry] and [removeSearchEntry] —
/// fails with [PlatformRepositoryFailureKind.dependencyConflict]: the local
/// schema has no version token, no audited command envelope and no mutation
/// receipt, so it cannot honour the contract's concurrency, idempotency and
/// audit guarantees. Blocking is the honest answer; writing anyway would
/// silently drop those guarantees on the floor.
///
/// The scope check runs before any source call, on reads and mutations alike: a
/// workspace other than [legacyWorkspaceId] fails
/// [PlatformRepositoryFailureKind.forbidden] without the legacy database being
/// touched at all.
///
/// Keyset paging deliberately reproduces the Supabase adapter's contract —
/// newest first, ordered by (`createdAt`, `id`) descending for tasks,
/// notifications and import jobs and by (`updatedAt`, `id`) descending for
/// search entries, with an opaque [PlatformKeysetCursor] — so a caller can page
/// either backend with the same loop and the same cursors.
class LegacySqlitePlatformRepositoryAdapter
    implements TaskRepository, NotificationPort, JobRepository, SearchIndexPort {
  LegacySqlitePlatformRepositoryAdapter({
    required LegacyPlatformReadSource source,
    required String legacyWorkspaceId,
  }) : _source = source,
       _legacyWorkspaceId = legacyWorkspaceId;

  /// Legacy rows carry no optimistic-concurrency token, so every projected
  /// aggregate reports the one version it can honestly have. It is never a
  /// usable `expectedVersion` — nothing on this adapter accepts one.
  static const int unsupportedVersion = 0;

  /// The canonical `title` column is bounded; the legacy `message` column is
  /// not. Longer messages spill into `body` rather than being truncated away.
  static const int notificationTitleLimit = 300;

  /// Legacy rows are attributed to a synthetic actor. The local store predates
  /// workspace identity: `tasks.created_by` is free-text and there is no actor
  /// column at all on notifications, import jobs or the search index, so no row
  /// can name an authenticated user without inventing one.
  static const String _legacyActor = 'legacy';

  final LegacyPlatformReadSource _source;
  final String _legacyWorkspaceId;

  // ---------------------------------------------------------------------------
  // TaskRepository
  // ---------------------------------------------------------------------------

  @override
  Future<PlatformRepositoryResult<PlatformPageResult<TaskDto>>> searchTasks(
    TaskListQuery query,
  ) async {
    final scopeFailure = _scopeFailure<PlatformPageResult<TaskDto>>(
      query.workspaceId,
    );
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final records = await _source.listTasks();
      final tasks = <TaskDto>[];
      for (final record in records) {
        final TaskDto task;
        try {
          task = _mapTask(record);
        } on _LegacyProjectionFailure {
          // One row the canonical vocabulary cannot express must not cost the
          // caller the whole page; `getTaskById` still reports it precisely.
          continue;
        }
        if (query.status != null && task.status != query.status) {
          continue;
        }
        if (query.entity != null && task.entity != query.entity) {
          continue;
        }
        if (query.assignedTo != null && task.assignedTo != query.assignedTo) {
          continue;
        }
        // Kept for contract shape only: the legacy vocabulary has no archived
        // state, so this never excludes a legacy row.
        if (!query.includeArchived && task.status == TaskStatus.archived) {
          continue;
        }
        tasks.add(task);
      }
      return PlatformRepositorySuccess<PlatformPageResult<TaskDto>>(
        _keysetPage<TaskDto>(
          tasks,
          query.page,
          (task) => PlatformKeysetCursor(timestamp: task.createdAt, id: task.id),
        ),
      );
    } catch (_) {
      return _loadFailure<PlatformPageResult<TaskDto>>();
    }
  }

  @override
  Future<PlatformRepositoryResult<TaskDto>> getTaskById({
    required String workspaceId,
    required String taskId,
  }) async {
    final scopeFailure = _scopeFailure<TaskDto>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final records = await _source.listTasks();
      for (final record in records) {
        if (record.id != taskId) {
          continue;
        }
        try {
          return PlatformRepositorySuccess<TaskDto>(_mapTask(record));
        } on _LegacyProjectionFailure catch (failure) {
          return PlatformRepositoryFailure<TaskDto>(
            kind: PlatformRepositoryFailureKind.validationFailed,
            message: failure.message,
          );
        }
      }
      return const PlatformRepositoryFailure<TaskDto>(
        kind: PlatformRepositoryFailureKind.notFound,
        message: 'Task not found in the local store.',
      );
    } catch (_) {
      return _loadFailure<TaskDto>();
    }
  }

  @override
  Future<PlatformRepositoryResult<TaskDto>> createTask(
    CreateTaskCommand command,
  ) => _blockedMutation<TaskDto>(command.context.workspaceId);

  @override
  Future<PlatformRepositoryResult<TaskDto>> updateTask(
    UpdateTaskCommand command,
  ) => _blockedMutation<TaskDto>(command.context.workspaceId);

  @override
  Future<PlatformRepositoryResult<TaskDto>> transitionTaskStatus(
    TransitionTaskStatusCommand command,
  ) => _blockedMutation<TaskDto>(command.context.workspaceId);

  // ---------------------------------------------------------------------------
  // NotificationPort
  // ---------------------------------------------------------------------------

  @override
  Future<PlatformRepositoryResult<PlatformPageResult<NotificationDto>>>
  notificationFeed(NotificationFeedQuery query) async {
    final scopeFailure = _scopeFailure<PlatformPageResult<NotificationDto>>(
      query.workspaceId,
    );
    if (scopeFailure != null) {
      return scopeFailure;
    }

    // The legacy table has no recipient column, so every row belongs to the one
    // synthetic recipient. Another recipient's inbox is legitimately empty here
    // — it is not an error, and it is not this workspace's whole feed either.
    final recipient = query.recipientUserId;
    if (recipient != null && recipient != _legacyActor) {
      return const PlatformRepositorySuccess<
        PlatformPageResult<NotificationDto>
      >(PlatformPageResult<NotificationDto>(items: <NotificationDto>[]));
    }

    try {
      final records = await _source.listNotifications();
      final notifications = <NotificationDto>[];
      for (final record in records) {
        if (query.unreadOnly && record.readAt != null) {
          continue;
        }
        notifications.add(_mapNotification(record));
      }
      return PlatformRepositorySuccess<PlatformPageResult<NotificationDto>>(
        _keysetPage<NotificationDto>(
          notifications,
          query.page,
          (notification) => PlatformKeysetCursor(
            timestamp: notification.createdAt,
            id: notification.id,
          ),
        ),
      );
    } catch (_) {
      return _loadFailure<PlatformPageResult<NotificationDto>>();
    }
  }

  @override
  Future<PlatformRepositoryResult<NotificationFanOutReceipt>> fanOutNotification(
    CreateNotificationCommand command,
  ) => _blockedMutation<NotificationFanOutReceipt>(command.context.workspaceId);

  @override
  Future<PlatformRepositoryResult<NotificationDto>> markNotificationRead(
    MarkNotificationReadCommand command,
  ) => _blockedMutation<NotificationDto>(command.context.workspaceId);

  // ---------------------------------------------------------------------------
  // JobRepository
  // ---------------------------------------------------------------------------

  @override
  Future<PlatformRepositoryResult<PlatformPageResult<ImportJobDto>>>
  searchImportJobs(ImportJobListQuery query) async {
    final scopeFailure = _scopeFailure<PlatformPageResult<ImportJobDto>>(
      query.workspaceId,
    );
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final records = await _source.listImportJobs();
      final mappings = await _source.listImportMappings();
      final jobs = <ImportJobDto>[];
      for (final record in records) {
        final ImportJobDto job;
        try {
          job = _mapImportJob(record, mappings);
        } on _LegacyProjectionFailure {
          // Same reduction as tasks: an unmappable status drops the row from
          // the page and is reported precisely by `getImportJobById`.
          continue;
        }
        if (query.status != null && job.status != query.status) {
          continue;
        }
        if (query.targetScope != null && job.targetScope != query.targetScope) {
          continue;
        }
        jobs.add(job);
      }
      return PlatformRepositorySuccess<PlatformPageResult<ImportJobDto>>(
        _keysetPage<ImportJobDto>(
          jobs,
          query.page,
          (job) => PlatformKeysetCursor(timestamp: job.createdAt, id: job.id),
        ),
      );
    } catch (_) {
      return _loadFailure<PlatformPageResult<ImportJobDto>>();
    }
  }

  @override
  Future<PlatformRepositoryResult<ImportJobDto>> getImportJobById({
    required String workspaceId,
    required String importJobId,
  }) async {
    final scopeFailure = _scopeFailure<ImportJobDto>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final records = await _source.listImportJobs();
      for (final record in records) {
        if (record.id != importJobId) {
          continue;
        }
        final mappings = await _source.listImportMappings();
        try {
          return PlatformRepositorySuccess<ImportJobDto>(
            _mapImportJob(record, mappings),
          );
        } on _LegacyProjectionFailure catch (failure) {
          return PlatformRepositoryFailure<ImportJobDto>(
            kind: PlatformRepositoryFailureKind.validationFailed,
            message: failure.message,
          );
        }
      }
      return const PlatformRepositoryFailure<ImportJobDto>(
        kind: PlatformRepositoryFailureKind.notFound,
        message: 'Import job not found in the local store.',
      );
    } catch (_) {
      return _loadFailure<ImportJobDto>();
    }
  }

  @override
  Future<PlatformRepositoryResult<ImportJobDto>> createImportJob(
    CreateImportJobCommand command,
  ) => _blockedMutation<ImportJobDto>(command.context.workspaceId);

  @override
  Future<PlatformRepositoryResult<ImportJobDto>> updateImportJob(
    UpdateImportJobCommand command,
  ) => _blockedMutation<ImportJobDto>(command.context.workspaceId);

  @override
  Future<PlatformRepositoryResult<ImportJobDto>> transitionImportJobStatus(
    TransitionImportJobStatusCommand command,
  ) => _blockedMutation<ImportJobDto>(command.context.workspaceId);

  // ---------------------------------------------------------------------------
  // SearchIndexPort
  // ---------------------------------------------------------------------------

  @override
  Future<PlatformRepositoryResult<PlatformPageResult<SearchEntryDto>>>
  searchIndex(SearchIndexQuery query) async {
    final scopeFailure = _scopeFailure<PlatformPageResult<SearchEntryDto>>(
      query.workspaceId,
    );
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final records = await _source.listSearchEntries();
      final entries = <SearchEntryDto>[];
      for (final record in records) {
        final entity = _entityRef(record.entityType, record.entityId);
        if (entity == null) {
          // A search entry *is* its entity reference, so an unmappable legacy
          // type (`note`, `ledger_entry`, `task`, ...) cannot degrade to an
          // unlinked row the way a task or notification can — it drops out.
          continue;
        }
        if (query.entityType != null && entity.type != query.entityType) {
          continue;
        }
        entries.add(_mapSearchEntry(record, entity));
      }
      return PlatformRepositorySuccess<PlatformPageResult<SearchEntryDto>>(
        _keysetPage<SearchEntryDto>(
          entries,
          query.page,
          (entry) =>
              PlatformKeysetCursor(timestamp: entry.updatedAt, id: entry.id),
        ),
      );
    } catch (_) {
      return _loadFailure<PlatformPageResult<SearchEntryDto>>();
    }
  }

  @override
  Future<PlatformRepositoryResult<SearchEntryDto>> reindexSearchEntry(
    ReindexSearchEntryCommand command,
  ) => _blockedMutation<SearchEntryDto>(command.context.workspaceId);

  @override
  Future<PlatformRepositoryResult<SearchEntryRemoval>> removeSearchEntry(
    RemoveSearchEntryCommand command,
  ) => _blockedMutation<SearchEntryRemoval>(command.context.workspaceId);

  // ---------------------------------------------------------------------------
  // Projection
  // ---------------------------------------------------------------------------

  TaskDto _mapTask(TaskRecord record) {
    final status = _taskStatus(record.status);
    if (status == null) {
      throw _LegacyProjectionFailure(
        'Legacy task status "${record.status}" has no STM-012 counterpart.',
      );
    }
    final priority = TaskPriority.fromWire(record.priority);
    if (priority == null) {
      throw _LegacyProjectionFailure(
        'Legacy task priority "${record.priority}" has no canonical '
        'counterpart.',
      );
    }
    return TaskDto(
      id: record.id,
      workspaceId: _legacyWorkspaceId,
      title: record.title,
      priority: priority,
      status: status,
      createdAt: _timestamp(record.createdAt),
      updatedAt: _timestamp(record.updatedAt),
      createdBy: _legacyActor,
      updatedBy: _legacyActor,
      version: unsupportedVersion,
      entity: _entityRef(record.entityType, record.entityId),
      description: record.description,
      category: record.category,
      assignedTo: record.assignedTo,
      dueAt: _optionalTimestamp(record.dueAt),
      // AGG-019 keys live in the separate legacy `task_generated_instances`
      // table, which is not part of the task row and is not projected here.
      generatedKey: null,
      // The legacy vocabulary has no archived state, so no row can carry one.
      archivedAt: null,
    );
  }

  NotificationDto _mapNotification(NotificationRecord record) {
    final message = record.message;
    final overflows = message.length > notificationTitleLimit;
    final createdAt = _timestamp(record.createdAt);
    final readAt = _optionalTimestamp(record.readAt);
    return NotificationDto(
      id: record.id,
      workspaceId: _legacyWorkspaceId,
      // The legacy app is single-user and the table has no recipient column;
      // the migration mapper asks whoever runs it for the real answer, but a
      // read projection has nothing to ask.
      recipientUserId: _legacyActor,
      kind: record.kind,
      title: overflows ? message.substring(0, notificationTitleLimit) : message,
      createdAt: createdAt,
      // No `updated_at` column exists. Being marked read is the only mutation a
      // legacy notification undergoes, matching how `SearchRepo` derives the
      // notification index row's `updated_at`.
      updatedAt: readAt ?? createdAt,
      createdBy: _legacyActor,
      updatedBy: _legacyActor,
      version: unsupportedVersion,
      // Lossless split: the title is capped, the body carries the whole message
      // so nothing the legacy row said is lost.
      body: overflows ? message : null,
      entity: _entityRef(record.entityType, record.entityId),
      readAt: readAt,
    );
  }

  ImportJobDto _mapImportJob(
    ImportJobRecord record,
    List<ImportMappingRecord> mappings,
  ) {
    final status = _importJobStatus(record.status);
    if (status == null) {
      throw _LegacyProjectionFailure(
        'Legacy import job status "${record.status}" has no STM-013 '
        'counterpart.',
      );
    }
    final createdAt = _timestamp(record.createdAt);
    final finishedAt = _optionalTimestamp(record.finishedAt);
    final error = record.error;
    return ImportJobDto(
      id: record.id,
      workspaceId: _legacyWorkspaceId,
      sourceKind: record.kind,
      targetScope: record.targetScope,
      status: status,
      mapping: _foldMapping(record.id, mappings),
      createdAt: createdAt,
      // No `updated_at` column: finishing is the only recorded later mutation.
      updatedAt: finishedAt ?? createdAt,
      createdBy: _legacyActor,
      updatedBy: _legacyActor,
      version: unsupportedVersion,
      // AGG-020 pre-commit evidence has no legacy counterpart at all; a legacy
      // job therefore never reads back as carrying commit evidence.
      dryRun: null,
      reconciliation: null,
      errorReport: error == null
          ? null
          : <String, Object?>{'message': error},
      // The legacy table records only when a job finished, never when it began.
      startedAt: null,
      finishedAt: finishedAt,
    );
  }

  SearchEntryDto _mapSearchEntry(
    SearchIndexRecord record,
    PlatformEntityRef entity,
  ) {
    final updatedAt = _timestamp(record.updatedAt);
    return SearchEntryDto(
      id: record.id,
      workspaceId: _legacyWorkspaceId,
      entity: entity,
      title: record.title,
      updatedAt: updatedAt,
      // The legacy index row is a pure upsert target with no `created_at`; the
      // last projection is the only instant it can honestly report.
      createdAt: updatedAt,
      createdBy: _legacyActor,
      updatedBy: _legacyActor,
      subtitle: record.subtitle,
      body: record.body,
    );
  }

  /// Folds every `import_mappings` row of one job into a single
  /// `{'<target_table>': <mapping>}` object. Where two rows target the same
  /// table the newest wins, mirroring `ImportsRepository.runCsvImport`, which
  /// reads `ORDER BY created_at DESC LIMIT 1`.
  Map<String, Object?> _foldMapping(
    String jobId,
    List<ImportMappingRecord> mappings,
  ) {
    final newestByTable = <String, ImportMappingRecord>{};
    for (final mapping in mappings) {
      if (mapping.importJobId != jobId) {
        continue;
      }
      final existing = newestByTable[mapping.targetTable];
      if (existing == null || mapping.createdAt >= existing.createdAt) {
        newestByTable[mapping.targetTable] = mapping;
      }
    }
    return <String, Object?>{
      for (final entry in newestByTable.entries)
        entry.key: _decodeMappingJson(entry.value.mappingJson),
    };
  }

  /// `import_mappings.mapping_json` is plain `TEXT` with no JSON constraint, so
  /// a malformed value is possible. It is carried through verbatim rather than
  /// dropped or fatal: the caller sees a `String` instead of a `Map` under the
  /// target-table key, which is the honest report of what the row holds.
  static Object? _decodeMappingJson(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return raw;
    }
  }

  /// Legacy `todo` is the canonical [TaskStatus.open]; `blocked` and `archived`
  /// simply do not exist locally. Anything outside the three-value legacy
  /// vocabulary is a projection failure rather than a guess.
  static TaskStatus? _taskStatus(String value) {
    switch (value) {
      case 'todo':
        return TaskStatus.open;
      case 'in_progress':
        return TaskStatus.inProgress;
      case 'done':
        return TaskStatus.done;
      default:
        return null;
    }
  }

  /// The four literals `ImportsRepository` actually writes. STM-013's
  /// `validating` and `ready` have no legacy counterpart — the local importer
  /// has no pre-commit evidence gate — so a legacy job jumps `draft → running`.
  static ImportJobStatus? _importJobStatus(String value) {
    switch (value) {
      case 'pending':
        return ImportJobStatus.draft;
      case 'running':
        return ImportJobStatus.running;
      case 'succeeded':
        return ImportJobStatus.completed;
      case 'failed':
        return ImportJobStatus.failed;
      default:
        return null;
    }
  }

  /// Legacy `entity_type` is free text and `entity_id` is nullable on tasks,
  /// while the canonical link is both-or-neither. Either half missing — or a
  /// type outside the controlled [PlatformEntityType] registry — degrades to an
  /// unlinked row instead of throwing, the documented P2-D03 legacy-document
  /// precedent (DEBT-006).
  static PlatformEntityRef? _entityRef(String? entityType, String? entityId) {
    if (entityId == null || entityId.isEmpty) {
      return null;
    }
    final type = PlatformEntityType.fromWire(entityType);
    if (type == null) {
      return null;
    }
    return PlatformEntityRef(type: type, id: entityId);
  }

  /// Legacy timestamp columns are integer epoch milliseconds.
  static DateTime _timestamp(int value) =>
      DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

  static DateTime? _optionalTimestamp(int? value) =>
      value == null ? null : _timestamp(value);

  // ---------------------------------------------------------------------------
  // Paging and failures
  // ---------------------------------------------------------------------------

  /// The Supabase adapter's keyset contract, evaluated in memory: order
  /// descending by (timestamp, id), skip everything at or before the cursor,
  /// then read one row past the limit to decide whether a next cursor exists.
  static PlatformPageResult<T> _keysetPage<T>(
    List<T> items,
    PlatformPageRequest page,
    PlatformKeysetCursor Function(T item) cursorOf,
  ) {
    final ordered = items.toList()
      ..sort((a, b) {
        final left = cursorOf(a);
        final right = cursorOf(b);
        final byTimestamp = right.timestamp.compareTo(left.timestamp);
        return byTimestamp != 0 ? byTimestamp : right.id.compareTo(left.id);
      });

    // A malformed cursor decodes to null and reads as "start from the top",
    // matching what the Supabase gateway does with the same input.
    final after = PlatformKeysetCursor.decode(page.cursor);
    final remaining = after == null
        ? ordered
        : ordered.where((item) {
            final key = cursorOf(item);
            if (key.timestamp.isBefore(after.timestamp)) {
              return true;
            }
            return key.timestamp.isAtSameMomentAs(after.timestamp) &&
                key.id.compareTo(after.id) < 0;
          }).toList(growable: false);

    final hasNextPage = remaining.length > page.limit;
    final pageItems = (hasNextPage ? remaining.take(page.limit) : remaining)
        .toList(growable: false);
    return PlatformPageResult<T>(
      items: pageItems,
      nextCursor: hasNextPage && pageItems.isNotEmpty
          ? cursorOf(pageItems.last).encode()
          : null,
    );
  }

  Future<PlatformRepositoryResult<T>> _blockedMutation<T>(
    String workspaceId,
  ) async {
    final scopeFailure = _scopeFailure<T>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }
    return const PlatformRepositoryFailure(
      kind: PlatformRepositoryFailureKind.dependencyConflict,
      message:
          'The local SQLite backend is read-only for the platform contract: it '
          'has no version token, no audited command envelope and no mutation '
          'receipt, so it cannot honour the concurrency, idempotency and audit '
          'guarantees every platform command carries.',
    );
  }

  PlatformRepositoryFailure<T>? _scopeFailure<T>(String workspaceId) {
    if (workspaceId == _legacyWorkspaceId) {
      return null;
    }
    return PlatformRepositoryFailure<T>(
      kind: PlatformRepositoryFailureKind.forbidden,
      message: 'The legacy SQLite database is bound to another workspace.',
    );
  }

  /// A fixed message on purpose: an exception raised while reading the legacy
  /// store can carry SQL, file paths or row contents, none of which belongs in
  /// a failure a caller may surface.
  PlatformRepositoryFailure<T> _loadFailure<T>() {
    return const PlatformRepositoryFailure(
      kind: PlatformRepositoryFailureKind.infrastructureFailure,
      message: 'The legacy SQLite platform stores could not be read.',
    );
  }
}

/// A legacy row whose values the canonical vocabulary cannot express. Distinct
/// from an infrastructure error: the store answered correctly, the answer just
/// has no counterpart, so it maps to
/// [PlatformRepositoryFailureKind.validationFailed] on a single-row read and to
/// omission in a list.
class _LegacyProjectionFailure implements Exception {
  const _LegacyProjectionFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
