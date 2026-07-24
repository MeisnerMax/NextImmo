import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/import_job.dart';
import 'package:neximmo_app/core/models/notification.dart';
import 'package:neximmo_app/core/models/search.dart';
import 'package:neximmo_app/core/models/task.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/data/legacy_sqlite_platform_repository_adapter.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/import_job_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/notification_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/platform_entity_type.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/search_entry_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/task_dto.dart';

const String _workspace = 'legacy-workspace';
const String _foreignWorkspace = 'other-workspace';

/// The synthetic actor every legacy row is attributed to, and therefore the
/// only recipient the legacy notification feed can answer for.
const String _legacyActor = 'legacy';

void main() {
  group('LegacySqlitePlatformRepositoryAdapter', () {
    late _FakeLegacyPlatformReadSource source;
    late LegacySqlitePlatformRepositoryAdapter repository;

    setUp(() {
      source = _FakeLegacyPlatformReadSource();
      repository = LegacySqlitePlatformRepositoryAdapter(
        source: source,
        legacyWorkspaceId: _workspace,
      );
    });

    test('blocks every mutation with a dependency conflict', () async {
      final results = <PlatformRepositoryResult<Object?>>[
        await repository.createTask(
          CreateTaskCommand(
            context: _context(),
            draft: const TaskDraft(title: 'New'),
          ),
        ),
        await repository.updateTask(
          UpdateTaskCommand(
            context: _context(),
            taskId: 't1',
            expectedVersion: 1,
            changes: const TaskUpdateDto(title: 'New'),
          ),
        ),
        await repository.transitionTaskStatus(
          TransitionTaskStatusCommand(
            context: _context(),
            taskId: 't1',
            expectedVersion: 1,
            targetStatus: TaskStatus.inProgress,
          ),
        ),
        await repository.fanOutNotification(
          CreateNotificationCommand(
            context: _context(),
            draft: const NotificationDraft(
              recipientUserIds: <String>['u1'],
              kind: 'task.due',
              title: 'Due',
            ),
          ),
        ),
        await repository.markNotificationRead(
          MarkNotificationReadCommand(
            context: _context(),
            notificationId: 'n1',
          ),
        ),
        await repository.createImportJob(
          CreateImportJobCommand(
            context: _context(),
            draft: const ImportJobDraft(
              sourceKind: 'csv',
              targetScope: 'properties',
            ),
          ),
        ),
        await repository.updateImportJob(
          UpdateImportJobCommand(
            context: _context(),
            importJobId: 'j1',
            expectedVersion: 1,
            changes: const ImportJobUpdateDto(sourceKind: 'csv'),
          ),
        ),
        await repository.transitionImportJobStatus(
          TransitionImportJobStatusCommand(
            context: _context(),
            importJobId: 'j1',
            expectedVersion: 1,
            targetStatus: ImportJobStatus.validating,
          ),
        ),
        await repository.reindexSearchEntry(
          ReindexSearchEntryCommand(
            context: _searchContext(),
            entity: _propertyRef,
            content: const SearchEntryContent(title: 'Objekt'),
          ),
        ),
        await repository.removeSearchEntry(
          RemoveSearchEntryCommand(
            context: _searchContext(),
            entity: _propertyRef,
          ),
        ),
      ];

      expect(results, hasLength(10));
      for (final result in results) {
        expect(
          (result as PlatformRepositoryFailure).kind,
          PlatformRepositoryFailureKind.dependencyConflict,
        );
      }
    });

    test('fails closed for a foreign workspace without reading', () async {
      final results = <PlatformRepositoryResult<Object?>>[
        await repository.searchTasks(
          const TaskListQuery(workspaceId: _foreignWorkspace),
        ),
        await repository.getTaskById(
          workspaceId: _foreignWorkspace,
          taskId: 't1',
        ),
        await repository.notificationFeed(
          const NotificationFeedQuery(workspaceId: _foreignWorkspace),
        ),
        await repository.searchImportJobs(
          const ImportJobListQuery(workspaceId: _foreignWorkspace),
        ),
        await repository.getImportJobById(
          workspaceId: _foreignWorkspace,
          importJobId: 'j1',
        ),
        await repository.searchIndex(
          const SearchIndexQuery(workspaceId: _foreignWorkspace),
        ),
        await repository.createTask(
          CreateTaskCommand(
            context: _context(workspaceId: _foreignWorkspace),
            draft: const TaskDraft(title: 'New'),
          ),
        ),
        await repository.removeSearchEntry(
          RemoveSearchEntryCommand(
            context: _searchContext(workspaceId: _foreignWorkspace),
            entity: _propertyRef,
          ),
        ),
      ];

      for (final result in results) {
        expect(
          (result as PlatformRepositoryFailure).kind,
          PlatformRepositoryFailureKind.forbidden,
        );
      }
      // The scope guard runs ahead of every source call, so a foreign workspace
      // never learns whether the legacy store even holds anything.
      expect(source.calls, 0);
    });

    test('projects the legacy task vocabulary onto STM-012', () async {
      final result = await repository.searchTasks(
        const TaskListQuery(workspaceId: _workspace),
      );

      final page =
          (result as PlatformRepositorySuccess<PlatformPageResult<TaskDto>>)
              .value;
      expect(page.items.map((task) => task.id), <String>['t3', 't2', 't1']);
      final byId = <String, TaskDto>{
        for (final task in page.items) task.id: task,
      };
      // The legacy `todo` is the canonical `open`; the other two keep their
      // names.
      expect(byId['t1']!.status, TaskStatus.open);
      expect(byId['t2']!.status, TaskStatus.inProgress);
      expect(byId['t3']!.status, TaskStatus.done);
      expect(byId['t1']!.priority, TaskPriority.normal);
      expect(byId['t2']!.priority, TaskPriority.high);
      expect(byId['t3']!.priority, TaskPriority.low);

      final task = byId['t1']!;
      expect(
        task.version,
        LegacySqlitePlatformRepositoryAdapter.unsupportedVersion,
      );
      expect(task.createdBy, _legacyActor);
      expect(task.updatedBy, _legacyActor);
      expect(
        task.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );
      expect(task.generatedKey, isNull);
      expect(task.archivedAt, isNull);
    });

    test('scopes the task list by status, entity and assignee', () async {
      source.tasks = <TaskRecord>[
        _task(id: 't1', assignedTo: 'anna'),
        _task(id: 't2', status: 'done', entityId: 'p2'),
      ];

      final byStatus = await _tasks(
        repository,
        const TaskListQuery(workspaceId: _workspace, status: TaskStatus.done),
      );
      expect(byStatus.items.map((task) => task.id), <String>['t2']);

      final byEntity = await _tasks(
        repository,
        const TaskListQuery(
          workspaceId: _workspace,
          entity: PlatformEntityRef(type: PlatformEntityType.property, id: 'p2'),
        ),
      );
      expect(byEntity.items.map((task) => task.id), <String>['t2']);

      final byAssignee = await _tasks(
        repository,
        const TaskListQuery(workspaceId: _workspace, assignedTo: 'anna'),
      );
      expect(byAssignee.items.map((task) => task.id), <String>['t1']);
    });

    test('omits an unprojectable task but reports it on read', () async {
      source.tasks = <TaskRecord>[
        _task(id: 't1'),
        _task(id: 'tx', status: 'cancelled'),
        _task(id: 'tp', priority: 'urgent'),
      ];

      final page = await _tasks(
        repository,
        const TaskListQuery(workspaceId: _workspace),
      );
      expect(page.items.map((task) => task.id), <String>['t1']);

      final unknownStatus = await repository.getTaskById(
        workspaceId: _workspace,
        taskId: 'tx',
      );
      expect(
        (unknownStatus as PlatformRepositoryFailure<TaskDto>).kind,
        PlatformRepositoryFailureKind.validationFailed,
      );

      final unknownPriority = await repository.getTaskById(
        workspaceId: _workspace,
        taskId: 'tp',
      );
      expect(
        (unknownPriority as PlatformRepositoryFailure<TaskDto>).kind,
        PlatformRepositoryFailureKind.validationFailed,
      );

      final missing = await repository.getTaskById(
        workspaceId: _workspace,
        taskId: 'nope',
      );
      expect(
        (missing as PlatformRepositoryFailure<TaskDto>).kind,
        PlatformRepositoryFailureKind.notFound,
      );
    });

    test('degrades an unusable entity link to no link', () async {
      source.tasks = <TaskRecord>[
        _task(id: 'linked'),
        // `tenant` is outside the controlled registry.
        _task(id: 'unmapped_type', entityType: 'tenant', entityId: 'tn1'),
        // The legacy column pair is not both-or-neither: entity_type is NOT
        // NULL while entity_id is nullable.
        _task(id: 'unmapped_id', entityId: null),
      ];

      final page = await _tasks(
        repository,
        const TaskListQuery(workspaceId: _workspace),
      );
      final byId = <String, TaskDto>{
        for (final task in page.items) task.id: task,
      };
      expect(byId, hasLength(3));
      expect(byId['linked']!.entity, _propertyRef);
      expect(byId['unmapped_type']!.entity, isNull);
      expect(byId['unmapped_id']!.entity, isNull);
    });

    test('splits an overlong notification message losslessly', () async {
      final long = 'x' * 305;
      final exact = 'y' * 300;
      source.notifications = <NotificationRecord>[
        _notification(id: 'short', message: 'Lease expiring', createdAt: 1000),
        _notification(id: 'exact', message: exact, createdAt: 2000),
        _notification(id: 'long', message: long, createdAt: 3000),
      ];

      final page = await _feed(
        repository,
        const NotificationFeedQuery(workspaceId: _workspace),
      );
      final byId = <String, NotificationDto>{
        for (final notification in page.items) notification.id: notification,
      };

      expect(byId['short']!.title, 'Lease expiring');
      expect(byId['short']!.body, isNull);
      expect(byId['exact']!.title, exact);
      expect(byId['exact']!.body, isNull);
      expect(byId['long']!.title, long.substring(0, 300));
      expect(byId['long']!.title, hasLength(300));
      // Lossless: the body keeps the whole message, not just the tail.
      expect(byId['long']!.body, long);

      // The legacy table has no recipient column at all.
      expect(byId['short']!.recipientUserId, _legacyActor);
    });

    test('returns an empty feed for a recipient the store cannot address', () async {
      final foreign = await _feed(
        repository,
        const NotificationFeedQuery(
          workspaceId: _workspace,
          recipientUserId: 'somebody-else',
        ),
      );
      expect(foreign.items, isEmpty);
      expect(foreign.nextCursor, isNull);

      final own = await _feed(
        repository,
        const NotificationFeedQuery(
          workspaceId: _workspace,
          recipientUserId: _legacyActor,
        ),
      );
      expect(own.items.map((notification) => notification.id), <String>[
        'n2',
        'n1',
      ]);
    });

    test('filters the feed to unread notifications', () async {
      final page = await _feed(
        repository,
        const NotificationFeedQuery(workspaceId: _workspace, unreadOnly: true),
      );
      expect(page.items.map((notification) => notification.id), <String>['n1']);
      expect(page.items.single.isRead, isFalse);
      expect(page.items.single.entity, _propertyRef);
    });

    test('maps the legacy import statuses and folds mappings in', () async {
      final page = await _jobs(
        repository,
        const ImportJobListQuery(workspaceId: _workspace),
      );
      expect(page.items.map((job) => job.id), <String>['j3', 'j2', 'j1']);
      final byId = <String, ImportJobDto>{
        for (final job in page.items) job.id: job,
      };

      expect(byId['j1']!.status, ImportJobStatus.draft);
      expect(byId['j2']!.status, ImportJobStatus.completed);
      expect(byId['j3']!.status, ImportJobStatus.failed);

      expect(byId['j1']!.mapping, <String, Object?>{
        'properties': <String, Object?>{'name': 'Name'},
      });
      expect(byId['j2']!.mapping, isEmpty);

      expect(byId['j3']!.errorReport, <String, Object?>{'message': 'boom'});
      expect(byId['j1']!.errorReport, isNull);

      // AGG-020 evidence has no legacy counterpart.
      expect(byId['j2']!.dryRun, isNull);
      expect(byId['j2']!.hasCommitEvidence, isFalse);
      expect(byId['j2']!.startedAt, isNull);
      expect(
        byId['j2']!.finishedAt,
        DateTime.fromMillisecondsSinceEpoch(2500, isUtc: true),
      );
    });

    test('carries a malformed mapping payload through as raw text', () async {
      source.importMappings = <ImportMappingRecord>[
        _mapping(id: 'm1', targetTable: 'properties'),
        _mapping(
          id: 'm2',
          targetTable: 'tenants',
          mappingJson: 'display_name=Name',
        ),
      ];

      final result = await repository.getImportJobById(
        workspaceId: _workspace,
        importJobId: 'j1',
      );
      final job = (result as PlatformRepositorySuccess<ImportJobDto>).value;
      expect(job.mapping['properties'], <String, Object?>{'name': 'Name'});
      expect(job.mapping['tenants'], 'display_name=Name');
    });

    test('omits an unmappable import status but reports it on read', () async {
      source.importJobs = <ImportJobRecord>[
        _job(id: 'j1', createdAt: 1000),
        _job(id: 'jx', status: 'queued', createdAt: 2000),
      ];

      final page = await _jobs(
        repository,
        const ImportJobListQuery(workspaceId: _workspace),
      );
      expect(page.items.map((job) => job.id), <String>['j1']);

      final unknown = await repository.getImportJobById(
        workspaceId: _workspace,
        importJobId: 'jx',
      );
      expect(
        (unknown as PlatformRepositoryFailure<ImportJobDto>).kind,
        PlatformRepositoryFailureKind.validationFailed,
      );
    });

    test('pages tasks newest first with a shared keyset cursor', () async {
      source.tasks = <TaskRecord>[
        _task(id: 't1', createdAt: 1000),
        _task(id: 't2', createdAt: 2000),
        // Two rows sharing an instant: the id tie-break decides, descending.
        _task(id: 'a3', createdAt: 3000),
        _task(id: 'b3', createdAt: 3000),
      ];

      final first = await _tasks(
        repository,
        const TaskListQuery(
          workspaceId: _workspace,
          page: PlatformPageRequest(limit: 2),
        ),
      );
      expect(first.items.map((task) => task.id), <String>['b3', 'a3']);
      expect(first.nextCursor, isNotNull);
      final cursor = PlatformKeysetCursor.decode(first.nextCursor);
      expect(cursor!.id, 'a3');
      expect(
        cursor.timestamp,
        DateTime.fromMillisecondsSinceEpoch(3000, isUtc: true),
      );

      final second = await _tasks(
        repository,
        TaskListQuery(
          workspaceId: _workspace,
          page: PlatformPageRequest(limit: 2, cursor: first.nextCursor),
        ),
      );
      expect(second.items.map((task) => task.id), <String>['t2', 't1']);
      expect(second.nextCursor, isNull);
    });

    test('projects and pages the search index by updated_at', () async {
      final first = await _entries(
        repository,
        const SearchIndexQuery(
          workspaceId: _workspace,
          page: PlatformPageRequest(limit: 1),
        ),
      );
      // `s3` indexes a legacy `note`, which is outside the controlled registry.
      // A search entry *is* its entity reference, so it cannot degrade — it is
      // dropped before paging.
      expect(first.items.map((entry) => entry.id), <String>['s2']);
      final entry = first.items.single;
      expect(
        entry.entity,
        const PlatformEntityRef(
          type: PlatformEntityType.scenario,
          id: 'sc1',
        ),
      );
      expect(entry.createdAt, entry.updatedAt);
      expect(entry.updatedBy, _legacyActor);

      final second = await _entries(
        repository,
        SearchIndexQuery(
          workspaceId: _workspace,
          page: PlatformPageRequest(limit: 1, cursor: first.nextCursor),
        ),
      );
      expect(second.items.map((entry) => entry.id), <String>['s1']);
      expect(second.nextCursor, isNull);
    });

    test('scopes the search index to one entity type', () async {
      final page = await _entries(
        repository,
        const SearchIndexQuery(
          workspaceId: _workspace,
          entityType: PlatformEntityType.property,
        ),
      );
      expect(page.items.map((entry) => entry.id), <String>['s1']);
    });

    test('reports a failing legacy store as an infrastructure failure', () async {
      source.failOnRead = true;

      final result = await repository.searchTasks(
        const TaskListQuery(workspaceId: _workspace),
      );
      final failure =
          result as PlatformRepositoryFailure<PlatformPageResult<TaskDto>>;
      expect(
        failure.kind,
        PlatformRepositoryFailureKind.infrastructureFailure,
      );
      // The raw exception text never reaches the caller.
      expect(failure.message, isNot(contains('legacy blew up')));
    });
  });
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

const PlatformEntityRef _propertyRef = PlatformEntityRef(
  type: PlatformEntityType.property,
  id: 'p1',
);

PlatformCommandContext _context({String workspaceId = _workspace}) {
  return PlatformCommandContext(
    workspaceId: workspaceId,
    actorId: 'actor',
    mutationId: 'mutation',
    correlationId: 'correlation',
  );
}

SearchIndexCommandContext _searchContext({String workspaceId = _workspace}) {
  return SearchIndexCommandContext(workspaceId: workspaceId, actorId: 'actor');
}

Future<PlatformPageResult<TaskDto>> _tasks(
  LegacySqlitePlatformRepositoryAdapter repository,
  TaskListQuery query,
) async {
  final result = await repository.searchTasks(query);
  return (result as PlatformRepositorySuccess<PlatformPageResult<TaskDto>>)
      .value;
}

Future<PlatformPageResult<NotificationDto>> _feed(
  LegacySqlitePlatformRepositoryAdapter repository,
  NotificationFeedQuery query,
) async {
  final result = await repository.notificationFeed(query);
  return (result
          as PlatformRepositorySuccess<PlatformPageResult<NotificationDto>>)
      .value;
}

Future<PlatformPageResult<ImportJobDto>> _jobs(
  LegacySqlitePlatformRepositoryAdapter repository,
  ImportJobListQuery query,
) async {
  final result = await repository.searchImportJobs(query);
  return (result as PlatformRepositorySuccess<PlatformPageResult<ImportJobDto>>)
      .value;
}

Future<PlatformPageResult<SearchEntryDto>> _entries(
  LegacySqlitePlatformRepositoryAdapter repository,
  SearchIndexQuery query,
) async {
  final result = await repository.searchIndex(query);
  return (result
          as PlatformRepositorySuccess<PlatformPageResult<SearchEntryDto>>)
      .value;
}

TaskRecord _task({
  required String id,
  String entityType = 'property',
  String? entityId = 'p1',
  String status = 'todo',
  String priority = 'normal',
  String? assignedTo,
  int createdAt = 1000,
}) {
  return TaskRecord(
    id: id,
    entityType: entityType,
    entityId: entityId,
    title: 'Task $id',
    description: 'Description $id',
    category: 'general',
    assignedTo: assignedTo,
    status: status,
    priority: priority,
    dueAt: 5000,
    createdAt: createdAt,
    updatedAt: createdAt,
    createdBy: 'legacy-user',
  );
}

NotificationRecord _notification({
  required String id,
  String message = 'Lease expiring',
  int createdAt = 1000,
  int? readAt,
}) {
  return NotificationRecord(
    id: id,
    entityType: 'property',
    entityId: 'p1',
    kind: 'lease.expiring',
    message: message,
    dueAt: null,
    readAt: readAt,
    createdAt: createdAt,
  );
}

ImportJobRecord _job({
  required String id,
  String status = 'pending',
  int createdAt = 1000,
  int? finishedAt,
  String? error,
}) {
  return ImportJobRecord(
    id: id,
    kind: 'csv',
    status: status,
    targetScope: 'properties',
    createdAt: createdAt,
    finishedAt: finishedAt,
    error: error,
  );
}

ImportMappingRecord _mapping({
  required String id,
  String importJobId = 'j1',
  String targetTable = 'properties',
  String mappingJson = '{"name":"Name"}',
  int createdAt = 1000,
}) {
  return ImportMappingRecord(
    id: id,
    importJobId: importJobId,
    targetTable: targetTable,
    mappingJson: mappingJson,
    createdAt: createdAt,
  );
}

SearchIndexRecord _entry({
  required String id,
  required String entityType,
  required String entityId,
  int updatedAt = 1000,
}) {
  return SearchIndexRecord(
    id: id,
    entityType: entityType,
    entityId: entityId,
    title: 'Entry $id',
    subtitle: 'Subtitle $id',
    body: null,
    updatedAt: updatedAt,
  );
}

class _FakeLegacyPlatformReadSource implements LegacyPlatformReadSource {
  List<TaskRecord> tasks = <TaskRecord>[
    _task(id: 't1', createdAt: 1000),
    _task(id: 't2', status: 'in_progress', priority: 'high', createdAt: 2000),
    _task(id: 't3', status: 'done', priority: 'low', createdAt: 3000),
  ];

  List<NotificationRecord> notifications = <NotificationRecord>[
    _notification(id: 'n1', createdAt: 1000),
    _notification(id: 'n2', createdAt: 2000, readAt: 2500),
  ];

  List<ImportJobRecord> importJobs = <ImportJobRecord>[
    _job(id: 'j1', createdAt: 1000),
    _job(id: 'j2', status: 'succeeded', createdAt: 2000, finishedAt: 2500),
    _job(id: 'j3', status: 'failed', createdAt: 3000, error: 'boom'),
  ];

  List<ImportMappingRecord> importMappings = <ImportMappingRecord>[
    _mapping(id: 'm1'),
  ];

  List<SearchIndexRecord> searchEntries = <SearchIndexRecord>[
    _entry(id: 's1', entityType: 'property', entityId: 'p1', updatedAt: 1000),
    _entry(id: 's2', entityType: 'scenario', entityId: 'sc1', updatedAt: 2000),
    // Outside the controlled registry.
    _entry(id: 's3', entityType: 'note', entityId: 'nt1', updatedAt: 3000),
  ];

  /// Counts every source call so a test can assert the scope guard reads
  /// nothing at all.
  int calls = 0;

  bool failOnRead = false;

  @override
  Future<List<TaskRecord>> listTasks() async => _answer(tasks);

  @override
  Future<List<NotificationRecord>> listNotifications() async =>
      _answer(notifications);

  @override
  Future<List<ImportJobRecord>> listImportJobs() async => _answer(importJobs);

  @override
  Future<List<ImportMappingRecord>> listImportMappings() async =>
      _answer(importMappings);

  @override
  Future<List<SearchIndexRecord>> listSearchEntries() async =>
      _answer(searchEntries);

  List<T> _answer<T>(List<T> rows) {
    calls++;
    if (failOnRead) {
      throw StateError('legacy blew up');
    }
    return rows;
  }
}
