import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/data/supabase_platform_repository_adapter.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/import_job_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/notification_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/platform_entity_type.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/search_entry_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/task_dto.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException;

void main() {
  group('SupabasePlatformRepositoryAdapter', () {
    late _FakePlatformGateway gateway;
    late SupabasePlatformRepositoryAdapter repository;

    setUp(() {
      gateway = _FakePlatformGateway();
      repository = SupabasePlatformRepositoryAdapter.withGateway(gateway);
    });

    // --- tasks: reads ------------------------------------------------------

    test('searches tasks and forwards every filter', () async {
      gateway.taskRows = <Map<String, dynamic>>[
        _taskJson(id: 'task-a'),
        _taskJson(id: 'task-b'),
        _taskJson(id: 'task-c'),
      ];

      final result = await repository.searchTasks(
        const TaskListQuery(
          workspaceId: 'workspace-a',
          statuses: <TaskStatus>[TaskStatus.inProgress, TaskStatus.blocked],
          entity: PlatformEntityRef(
            type: PlatformEntityType.property,
            id: 'property-1',
          ),
          assignedTo: 'user-9',
          page: PlatformPageRequest(limit: 2),
        ),
      );

      expect(gateway.taskWorkspaceId, 'workspace-a');
      expect(gateway.taskStatuses, <String>['in_progress', 'blocked']);
      expect(gateway.taskEntityType, 'property');
      expect(gateway.taskEntityId, 'property-1');
      expect(gateway.taskAssignedTo, 'user-9');
      expect(gateway.taskIncludeArchived, isFalse);
      expect(gateway.taskLimit, 3); // limit + 1 has-next probe.

      final page =
          (result
                  as PlatformRepositorySuccess<PlatformPageResult<TaskDto>>)
              .value;
      expect(page.items.map((task) => task.id), <String>['task-a', 'task-b']);
      expect(page.nextCursor, isNotNull);
    });

    test('emits a composite cursor and consumes it on the next page', () async {
      gateway.taskRows = <Map<String, dynamic>>[
        _taskJson(id: 'task-a', createdAt: '2026-07-24T10:00:00.000Z'),
        _taskJson(id: 'task-b', createdAt: '2026-07-24T09:00:00.000Z'),
      ];

      final first = await repository.searchTasks(
        const TaskListQuery(
          workspaceId: 'workspace-a',
          page: PlatformPageRequest(limit: 1),
        ),
      );
      final cursor =
          (first
                  as PlatformRepositorySuccess<PlatformPageResult<TaskDto>>)
              .value
              .nextCursor;
      expect(cursor, '2026-07-24T10:00:00.000Z|task-a');

      await repository.searchTasks(
        TaskListQuery(
          workspaceId: 'workspace-a',
          page: PlatformPageRequest(limit: 1, cursor: cursor),
        ),
      );

      // The timestamp alone cannot page — one command writes many rows at the
      // same instant — so the id tie-break has to survive the round trip.
      expect(gateway.taskCursor?.id, 'task-a');
      expect(
        gateway.taskCursor?.timestamp.toUtc().toIso8601String(),
        '2026-07-24T10:00:00.000Z',
      );
    });

    test('includes archived tasks only when asked', () async {
      gateway.taskRows = const <Map<String, dynamic>>[];

      await repository.searchTasks(
        const TaskListQuery(workspaceId: 'workspace-a', includeArchived: true),
      );

      expect(gateway.taskIncludeArchived, isTrue);
    });

    // --- tasks: TASK-QUERY-01 filters, sort and count ------------------------

    test('forwards the My-Work filters', () async {
      gateway.taskRows = const <Map<String, dynamic>>[];

      await repository.searchTasks(
        TaskListQuery(
          workspaceId: 'workspace-a',
          unassignedOnly: true,
          propertyId: 'property-7',
          dueFrom: DateTime.utc(2026, 9, 1),
          dueUntil: DateTime.utc(2026, 9, 8),
          titleQuery: 'Heizung',
        ),
      );

      expect(gateway.taskUnassignedOnly, isTrue);
      expect(gateway.taskPropertyId, 'property-7');
      expect(gateway.taskDueFrom, DateTime.utc(2026, 9, 1));
      expect(gateway.taskDueUntil, DateTime.utc(2026, 9, 8));
      expect(gateway.taskWithoutDue, isFalse);
      expect(gateway.taskTitleQuery, 'Heizung');
      expect(gateway.taskSortByDue, isFalse);
    });

    test('forwards the no-due-date bucket', () async {
      gateway.taskRows = const <Map<String, dynamic>>[];

      await repository.searchTasks(
        const TaskListQuery(workspaceId: 'workspace-a', withoutDue: true),
      );

      expect(gateway.taskWithoutDue, isTrue);
    });

    test('a due-ordered read cursors on the due date, not created_at',
        () async {
      gateway.taskRows = <Map<String, dynamic>>[
        _taskJson(id: 'task-a', dueAt: '2026-09-10T09:00:00.000Z'),
        _taskJson(id: 'task-b', dueAt: '2026-09-20T09:00:00.000Z'),
      ];

      final result = await repository.searchTasks(
        const TaskListQuery(
          workspaceId: 'workspace-a',
          sort: TaskListSort.dueAsc,
          page: PlatformPageRequest(limit: 1),
        ),
      );

      expect(gateway.taskSortByDue, isTrue);
      final page =
          (result
                  as PlatformRepositorySuccess<PlatformPageResult<TaskDto>>)
              .value;
      expect(page.nextCursor, '2026-09-10T09:00:00.000Z|task-a');
    });

    test('parses the property roll-up', () async {
      gateway.taskRows = <Map<String, dynamic>>[
        _taskJson(id: 'task-a')..['property_id'] = 'property-7',
      ];

      final result = await repository.searchTasks(
        const TaskListQuery(workspaceId: 'workspace-a'),
      );

      final page =
          (result
                  as PlatformRepositorySuccess<PlatformPageResult<TaskDto>>)
              .value;
      expect(page.items.single.propertyId, 'property-7');
    });

    test('counts tasks through the count_tasks envelope', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': <String, Object?>{'count': 7},
      };

      final result = await repository.countTasks(
        TaskCountQuery(
          workspaceId: 'workspace-a',
          statuses: const <TaskStatus>[TaskStatus.open],
          unassignedOnly: true,
          propertyId: 'property-7',
          dueUntil: DateTime.utc(2026, 9, 8),
          titleQuery: 'Heizung',
        ),
      );

      expect(gateway.lastFunction, 'count_tasks');
      expect(gateway.lastParameters?['p_workspace_id'], 'workspace-a');
      expect(gateway.lastParameters?['p_statuses'], <String>['open']);
      expect(gateway.lastParameters?['p_unassigned_only'], isTrue);
      expect(gateway.lastParameters?['p_property_id'], 'property-7');
      expect(
        gateway.lastParameters?['p_due_until'],
        '2026-09-08T00:00:00.000Z',
      );
      expect(gateway.lastParameters?['p_title_query'], 'Heizung');
      expect((result as PlatformRepositorySuccess<int>).value, 7);
    });

    test('maps a count refusal onto the failure kinds', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'forbidden',
          'message': 'Task read is not permitted',
        },
      };

      final result = await repository.countTasks(
        const TaskCountQuery(workspaceId: 'workspace-a'),
      );

      final failure = result as PlatformRepositoryFailure<int>;
      expect(failure.kind, PlatformRepositoryFailureKind.forbidden);
      expect(failure.message, 'Task read is not permitted');
    });

    test('classifies a count infrastructure error as such', () async {
      gateway.rpcError = Exception('down');

      final result = await repository.countTasks(
        const TaskCountQuery(workspaceId: 'workspace-a'),
      );

      expect(
        (result as PlatformRepositoryFailure<int>).kind,
        PlatformRepositoryFailureKind.infrastructureFailure,
      );
    });

    test('escapes ilike wildcards in a title query', () {
      expect(
        SupabasePlatformGateway.escapeLikePattern(r'100%_of\it'),
        r'100\%\_of\\it',
      );
    });

    test('rejects a task row from a foreign workspace', () async {
      gateway.taskRows = <Map<String, dynamic>>[
        _taskJson(id: 'task-a', workspaceId: 'workspace-b'),
      ];

      final result = await repository.searchTasks(
        const TaskListQuery(workspaceId: 'workspace-a'),
      );

      expect(
        (result
                as PlatformRepositoryFailure<PlatformPageResult<TaskDto>>)
            .kind,
        PlatformRepositoryFailureKind.infrastructureFailure,
      );
    });

    test('reads a task by id', () async {
      gateway.taskRows = <Map<String, dynamic>>[
        _taskJson(id: 'task-a', generatedKey: 'monthly-2026-07'),
      ];

      final result = await repository.getTaskById(
        workspaceId: 'workspace-a',
        taskId: 'task-a',
      );

      final task = (result as PlatformRepositorySuccess<TaskDto>).value;
      expect(task.status, TaskStatus.open);
      expect(task.priority, TaskPriority.normal);
      expect(task.entity?.type, PlatformEntityType.property);
      expect(task.isGenerated, isTrue);
    });

    test('maps an empty task read to not found', () async {
      gateway.taskRows = const <Map<String, dynamic>>[];

      final result = await repository.getTaskById(
        workspaceId: 'workspace-a',
        taskId: 'missing',
      );

      expect(
        (result as PlatformRepositoryFailure<TaskDto>).kind,
        PlatformRepositoryFailureKind.notFound,
      );
    });

    test('rejects a half-set entity reference', () async {
      final row = _taskJson(id: 'task-a')..['entity_id'] = null;
      gateway.taskRows = <Map<String, dynamic>>[row];

      final result = await repository.getTaskById(
        workspaceId: 'workspace-a',
        taskId: 'task-a',
      );

      // The server enforces both-or-neither, so a half-set pair is a contract
      // violation rather than a link to degrade.
      expect(
        (result as PlatformRepositoryFailure<TaskDto>).kind,
        PlatformRepositoryFailureKind.infrastructureFailure,
      );
    });

    // --- tasks: commands ---------------------------------------------------

    test('rejects an actor mismatch before calling any RPC', () async {
      gateway.currentUserId = 'someone-else';

      final result = await repository.createTask(_createTaskCommand());

      expect(gateway.rpcCalls, 0);
      expect(
        (result as PlatformRepositoryFailure<TaskDto>).kind,
        PlatformRepositoryFailureKind.forbidden,
      );
    });

    test('creates a task with the exact RPC parameter names', () async {
      gateway.rpcResult = <String, Object?>{'ok': true, 'entity': _taskJson()};

      await repository.createTask(_createTaskCommand());

      expect(gateway.lastFunction, 'create_task');
      expect(gateway.lastParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_title': 'Heizung prüfen',
        'p_mutation_id': 'mutation-1',
        'p_correlation_id': 'correlation-1',
        'p_entity_type': 'property',
        'p_entity_id': 'property-1',
        'p_description': 'Wartung',
        'p_category': 'maintenance',
        'p_assigned_to': 'user-9',
        'p_priority': 'high',
        'p_due_at': '2026-08-01T12:00:00.000Z',
        'p_generated_key': 'monthly-2026-07',
        'p_reason': 'integration',
      });
    });

    test('omits absent update keys and sends explicit nulls for cleared ones', () async {
      gateway.rpcResult = <String, Object?>{'ok': true, 'entity': _taskJson()};

      await repository.updateTask(
        UpdateTaskCommand(
          context: _context(),
          taskId: 'task-a',
          expectedVersion: 3,
          changes: const TaskUpdateDto(
            title: 'Neuer Titel',
            category: TaskFieldEdit<String>.clear(),
            priority: TaskPriority.low,
          ),
        ),
      );

      final changes =
          gateway.lastParameters!['p_changes']! as Map<String, Object?>;
      expect(changes.keys.toSet(), <String>{'title', 'category', 'priority'});
      // "Leave alone" and "set to null" are different commands server-side.
      expect(changes.containsKey('description'), isFalse);
      expect(changes['category'], isNull);
      expect(changes['priority'], 'low');
      expect(gateway.lastParameters!['p_expected_version'], 3);
    });

    test('maps a task version conflict to the typed conflict', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'version_conflict',
          'message': 'Task version is stale',
          'expected_version': 2,
          'actual_version': 5,
          'current_entity': _taskJson(id: 'task-a', version: 5),
        },
      };

      final result = await repository.transitionTaskStatus(
        TransitionTaskStatusCommand(
          context: _context(),
          taskId: 'task-a',
          expectedVersion: 2,
          targetStatus: TaskStatus.done,
        ),
      );

      final failure = result as PlatformRepositoryFailure<TaskDto>;
      expect(failure.kind, PlatformRepositoryFailureKind.versionConflict);
      expect(failure.versionConflict!.expectedVersion, 2);
      expect(failure.versionConflict!.actualVersion, 5);
      expect(failure.versionConflict!.currentTask!.version, 5);
      expect(failure.versionConflict!.currentImportJob, isNull);
      expect(gateway.lastParameters!['p_to_status'], 'done');
    });

    // --- notifications -----------------------------------------------------

    test('reads an unread, recipient-scoped feed', () async {
      gateway.notificationRows = <Map<String, dynamic>>[_notificationJson()];

      final result = await repository.notificationFeed(
        const NotificationFeedQuery(
          workspaceId: 'workspace-a',
          recipientUserId: 'user-9',
          unreadOnly: true,
        ),
      );

      expect(gateway.notificationRecipientUserId, 'user-9');
      expect(gateway.notificationUnreadOnly, isTrue);
      final page =
          (result
                  as PlatformRepositorySuccess<
                    PlatformPageResult<NotificationDto>
                  >)
              .value;
      expect(page.items.single.isRead, isFalse);
      expect(page.items.single.kind, 'lease.expiring');
    });

    test('fans out to every recipient under one mutation id', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': <String, Object?>{
          'kind': 'lease.expiring',
          'recipient_count': 2,
          'notification_ids': <String>['notification-a', 'notification-b'],
        },
      };

      final result = await repository.fanOutNotification(
        CreateNotificationCommand(
          context: _context(),
          draft: const NotificationDraft(
            recipientUserIds: <String>['user-1', 'user-2'],
            kind: 'lease.expiring',
            title: 'Mietvertrag läuft aus',
            body: 'Details im Objekt',
          ),
        ),
      );

      expect(gateway.lastFunction, 'create_notification');
      expect(gateway.lastParameters!['p_recipient_user_ids'], <String>[
        'user-1',
        'user-2',
      ]);
      expect(gateway.lastParameters!['p_mutation_id'], 'mutation-1');
      final receipt =
          (result
                  as PlatformRepositorySuccess<NotificationFanOutReceipt>)
              .value;
      expect(receipt.recipientCount, 2);
      expect(receipt.notificationIds.length, 2);
    });

    test('rejects a fan-out receipt whose count disagrees with its ids', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': <String, Object?>{
          'kind': 'lease.expiring',
          'recipient_count': 3,
          'notification_ids': <String>['notification-a'],
        },
      };

      final result = await repository.fanOutNotification(
        CreateNotificationCommand(
          context: _context(),
          draft: const NotificationDraft(
            recipientUserIds: <String>['user-1'],
            kind: 'lease.expiring',
            title: 'Titel',
          ),
        ),
      );

      // The batch is all-or-nothing server-side; a partial delivery is not a
      // state this contract can represent.
      expect(
        (result as PlatformRepositoryFailure<NotificationFanOutReceipt>).kind,
        PlatformRepositoryFailureKind.infrastructureFailure,
      );
    });

    test('surfaces a foreign notification as not found, never forbidden', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'not_found',
          'message': 'Notification not found',
        },
      };

      final result = await repository.markNotificationRead(
        MarkNotificationReadCommand(
          context: _context(),
          notificationId: 'notification-x',
        ),
      );

      expect(gateway.lastFunction, 'mark_notification_read');
      expect(gateway.lastParameters!.containsKey('p_reason'), isFalse);
      expect(
        (result as PlatformRepositoryFailure<NotificationDto>).kind,
        PlatformRepositoryFailureKind.notFound,
      );
    });

    // --- import jobs -------------------------------------------------------

    test('creates an import job with its declared mapping', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _importJobJson(),
      };

      await repository.createImportJob(
        CreateImportJobCommand(
          context: _context(),
          draft: const ImportJobDraft(
            sourceKind: 'sqlite.legacy',
            targetScope: 'properties',
            mapping: <String, Object?>{'properties': 'p1-012'},
          ),
        ),
      );

      expect(gateway.lastFunction, 'create_import_job');
      expect(gateway.lastParameters!['p_source_kind'], 'sqlite.legacy');
      expect(gateway.lastParameters!['p_mapping'], <String, Object?>{
        'properties': 'p1-012',
      });
    });

    test('carries AGG-020 evidence on the ready transition only', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _importJobJson(status: 'ready'),
      };

      await repository.transitionImportJobStatus(
        TransitionImportJobStatusCommand(
          context: _context(),
          importJobId: 'job-a',
          expectedVersion: 2,
          targetStatus: ImportJobStatus.ready,
          evidence: const ImportJobTransitionEvidence.ready(
            manifest: <String, Object?>{'manifest_checksum': 'abc'},
            reconciled: <String, Object?>{'rows': 12},
          ),
        ),
      );

      expect(gateway.lastParameters!['p_to_status'], 'ready');
      expect(gateway.lastParameters!['p_dry_run'], <String, Object?>{
        'manifest_checksum': 'abc',
      });
      expect(gateway.lastParameters!['p_reconciliation'], <String, Object?>{
        'rows': 12,
      });
      expect(gateway.lastParameters!['p_error_report'], isNull);
    });

    test('carries an error report on the failure transition only', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _importJobJson(status: 'failed'),
      };

      await repository.transitionImportJobStatus(
        TransitionImportJobStatusCommand(
          context: _context(),
          importJobId: 'job-a',
          expectedVersion: 4,
          targetStatus: ImportJobStatus.failed,
          evidence: const ImportJobTransitionEvidence.failure(
            <String, Object?>{'message': 'checksum mismatch'},
          ),
        ),
      );

      expect(gateway.lastParameters!['p_error_report'], <String, Object?>{
        'message': 'checksum mismatch',
      });
      expect(gateway.lastParameters!['p_dry_run'], isNull);
      expect(gateway.lastParameters!['p_reconciliation'], isNull);
    });

    test('carries no artifact on an ordinary transition', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _importJobJson(status: 'validating'),
      };

      await repository.transitionImportJobStatus(
        TransitionImportJobStatusCommand(
          context: _context(),
          importJobId: 'job-a',
          expectedVersion: 1,
          targetStatus: ImportJobStatus.validating,
        ),
      );

      expect(gateway.lastParameters!['p_dry_run'], isNull);
      expect(gateway.lastParameters!['p_reconciliation'], isNull);
      expect(gateway.lastParameters!['p_error_report'], isNull);
    });

    test('maps an import job version conflict onto the job, not the task', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'version_conflict',
          'message': 'Import job version is stale',
          'expected_version': 1,
          'actual_version': 4,
          'current_entity': _importJobJson(version: 4),
        },
      };

      final result = await repository.updateImportJob(
        UpdateImportJobCommand(
          context: _context(),
          importJobId: 'job-a',
          expectedVersion: 1,
          changes: const ImportJobUpdateDto(targetScope: 'units'),
        ),
      );

      final failure = result as PlatformRepositoryFailure<ImportJobDto>;
      expect(failure.versionConflict!.currentImportJob!.version, 4);
      expect(failure.versionConflict!.currentTask, isNull);
      final changes =
          gateway.lastParameters!['p_changes']! as Map<String, Object?>;
      expect(changes, <String, Object?>{'target_scope': 'units'});
    });

    test('reads the commit evidence back off the job', () async {
      gateway.importJobRows = <Map<String, dynamic>>[
        _importJobJson(
          status: 'ready',
          dryRun: <String, Object?>{'manifest_checksum': 'abc'},
          reconciliation: <String, Object?>{'rows': 12},
        ),
      ];

      final result = await repository.getImportJobById(
        workspaceId: 'workspace-a',
        importJobId: 'job-a',
      );

      final job = (result as PlatformRepositorySuccess<ImportJobDto>).value;
      expect(job.status, ImportJobStatus.ready);
      expect(job.hasCommitEvidence, isTrue);
      expect(job.status.isEditable, isFalse);
    });

    // --- search index ------------------------------------------------------

    test('reindexes with no envelope parameters at all', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _searchEntryJson(),
      };

      await repository.reindexSearchEntry(
        const ReindexSearchEntryCommand(
          context: SearchIndexCommandContext(
            workspaceId: 'workspace-a',
            actorId: 'user-1',
          ),
          entity: PlatformEntityRef(
            type: PlatformEntityType.property,
            id: 'property-1',
          ),
          content: SearchEntryContent(
            title: 'Musterstraße 1',
            subtitle: 'Berlin',
          ),
        ),
      );

      expect(gateway.lastFunction, 'reindex_search_entry');
      // DOM-010: the index is derived, so there is no mutation id, no
      // correlation id, no expected version and no reason to carry.
      expect(gateway.lastParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_entity_type': 'property',
        'p_entity_id': 'property-1',
        'p_title': 'Musterstraße 1',
        'p_subtitle': 'Berlin',
        'p_body': null,
      });
    });

    test('rejects a search reindex whose actor is not the caller', () async {
      gateway.currentUserId = 'someone-else';

      final result = await repository.reindexSearchEntry(
        const ReindexSearchEntryCommand(
          context: SearchIndexCommandContext(
            workspaceId: 'workspace-a',
            actorId: 'user-1',
          ),
          entity: PlatformEntityRef(
            type: PlatformEntityType.property,
            id: 'property-1',
          ),
          content: SearchEntryContent(title: 'Musterstraße 1'),
        ),
      );

      expect(gateway.rpcCalls, 0);
      expect(
        (result as PlatformRepositoryFailure<SearchEntryDto>).kind,
        PlatformRepositoryFailureKind.forbidden,
      );
    });

    test('treats removing an absent entry as a success', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': <String, Object?>{
          'workspace_id': 'workspace-a',
          'entity_type': 'property',
          'entity_id': 'property-1',
          'removed': false,
        },
      };

      final result = await repository.removeSearchEntry(
        const RemoveSearchEntryCommand(
          context: SearchIndexCommandContext(
            workspaceId: 'workspace-a',
            actorId: 'user-1',
          ),
          entity: PlatformEntityRef(
            type: PlatformEntityType.property,
            id: 'property-1',
          ),
        ),
      );

      final removal =
          (result as PlatformRepositorySuccess<SearchEntryRemoval>).value;
      expect(removal.removed, isFalse);
      expect(removal.entity.type, PlatformEntityType.property);
    });

    test('resolves an explicit entity-ref list (TASK-QUERY-01)', () async {
      gateway.searchRows = <Map<String, dynamic>>[
        _searchEntryJson(id: 'entry-a'),
      ];

      final result = await repository.searchIndex(
        const SearchIndexQuery(
          workspaceId: 'workspace-a',
          entities: <PlatformEntityRef>[
            PlatformEntityRef(
              type: PlatformEntityType.property,
              id: 'property-1',
            ),
            PlatformEntityRef(type: PlatformEntityType.unit, id: 'unit-9'),
          ],
        ),
      );

      expect(gateway.searchEntities, <({String type, String id})>[
        (type: 'property', id: 'property-1'),
        (type: 'unit', id: 'unit-9'),
      ]);
      expect(
        result,
        isA<PlatformRepositorySuccess<PlatformPageResult<SearchEntryDto>>>(),
      );
    });

    test('pages the search index on its own updated_at keyset', () async {
      gateway.searchRows = <Map<String, dynamic>>[
        _searchEntryJson(id: 'entry-a', updatedAt: '2026-07-24T10:00:00.000Z'),
        _searchEntryJson(id: 'entry-b', updatedAt: '2026-07-24T09:00:00.000Z'),
      ];

      final result = await repository.searchIndex(
        const SearchIndexQuery(
          workspaceId: 'workspace-a',
          entityType: PlatformEntityType.property,
          page: PlatformPageRequest(limit: 1),
        ),
      );

      expect(gateway.searchEntityType, 'property');
      final page =
          (result
                  as PlatformRepositorySuccess<
                    PlatformPageResult<SearchEntryDto>
                  >)
              .value;
      expect(page.nextCursor, '2026-07-24T10:00:00.000Z|entry-a');
    });

    test('treats a version conflict from the index path as a contract breach', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'version_conflict',
          'message': 'unexpected',
          'expected_version': 1,
          'actual_version': 2,
          'current_entity': _searchEntryJson(),
        },
      };

      final result = await repository.removeSearchEntry(
        const RemoveSearchEntryCommand(
          context: SearchIndexCommandContext(
            workspaceId: 'workspace-a',
            actorId: 'user-1',
          ),
          entity: PlatformEntityRef(
            type: PlatformEntityType.property,
            id: 'property-1',
          ),
        ),
      );

      // A derived projection has no version, so a version conflict here would
      // mean the server contract moved — not something to surface as a
      // recoverable concurrency failure.
      expect(
        (result as PlatformRepositoryFailure<SearchEntryRemoval>).kind,
        PlatformRepositoryFailureKind.infrastructureFailure,
      );
    });

    // --- failure mapping ---------------------------------------------------

    for (final probe in <({String code, PlatformRepositoryFailureKind kind})>[
      (code: 'not_found', kind: PlatformRepositoryFailureKind.notFound),
      (code: 'forbidden', kind: PlatformRepositoryFailureKind.forbidden),
      (
        code: 'validation_failed',
        kind: PlatformRepositoryFailureKind.validationFailed,
      ),
      (
        code: 'mutation_conflict',
        kind: PlatformRepositoryFailureKind.mutationConflict,
      ),
      (
        code: 'in_progress',
        kind: PlatformRepositoryFailureKind.mutationInProgress,
      ),
      (
        code: 'infrastructure_failure',
        kind: PlatformRepositoryFailureKind.infrastructureFailure,
      ),
      (
        code: 'something_new',
        kind: PlatformRepositoryFailureKind.infrastructureFailure,
      ),
    ]) {
      test('maps the ${probe.code} error code', () async {
        gateway.rpcResult = <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': probe.code,
            'message': 'Server said so',
          },
        };

        final result = await repository.createTask(_createTaskCommand());

        expect(
          (result as PlatformRepositoryFailure<TaskDto>).kind,
          probe.kind,
        );
      });
    }

    test('never leaks an unexpected exception text into the failure', () async {
      gateway.rpcError = StateError('connection to 10.0.0.5:5432 refused');

      final result = await repository.createTask(_createTaskCommand());

      final failure = result as PlatformRepositoryFailure<TaskDto>;
      expect(failure.kind, PlatformRepositoryFailureKind.infrastructureFailure);
      expect(failure.message, 'Supabase platform command failed.');
      expect(failure.message, isNot(contains('10.0.0.5')));
    });

    test('passes the server message through for a controlled failure', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'validation_failed',
          'message': 'Assignee must be an active workspace member',
        },
      };

      final result = await repository.createTask(_createTaskCommand());

      final failure = result as PlatformRepositoryFailure<TaskDto>;
      expect(failure.message, 'Assignee must be an active workspace member');
      expect(failure.validationFields, isEmpty);
    });

    // --- validation field names (A15, Shared §12) --------------------------

    test('carries the single named field of a validation failure', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'validation_failed',
          'message': 'Title is required',
          'field': 'title',
        },
      };

      final result = await repository.createTask(_createTaskCommand());

      final failure = result as PlatformRepositoryFailure<TaskDto>;
      expect(failure.kind, PlatformRepositoryFailureKind.validationFailed);
      expect(failure.validationFields, <String>['title']);
    });

    test('carries the field list of a validation failure', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'validation_failed',
          'message': 'Unknown change keys',
          'fields': <Object?>['due_at', 'priority', 42],
        },
      };

      final result = await repository.updateTask(
        UpdateTaskCommand(
          context: _context(),
          taskId: 'task-a',
          expectedVersion: 1,
          changes: const TaskUpdateDto(title: 'Neu'),
        ),
      );

      final failure = result as PlatformRepositoryFailure<TaskDto>;
      // Non-string entries are a contract violation and dropped rather than
      // crashing the error path.
      expect(failure.validationFields, <String>['due_at', 'priority']);
    });

    // --- read-path classification (A15) ------------------------------------

    test('classifies a permission-denied task read as forbidden', () async {
      gateway.taskListError = PostgrestException(
        message: 'permission denied for table tasks',
        code: '42501',
      );

      final result = await repository.searchTasks(
        const TaskListQuery(workspaceId: 'workspace-a'),
      );

      final failure =
          result as PlatformRepositoryFailure<PlatformPageResult<TaskDto>>;
      expect(failure.kind, PlatformRepositoryFailureKind.forbidden);
      expect(failure.message, 'permission denied for table tasks');
    });

    test('classifies a PostgREST 403 refusal of the feed as forbidden', () async {
      gateway.notificationListError = PostgrestException(
        message: 'Forbidden',
        code: '403',
      );

      final result = await repository.notificationFeed(
        const NotificationFeedQuery(workspaceId: 'workspace-a'),
      );

      expect(
        (result
                as PlatformRepositoryFailure<
                  PlatformPageResult<NotificationDto>
                >)
            .kind,
        PlatformRepositoryFailureKind.forbidden,
      );
    });

    test('classifies a permission-denied task detail read as forbidden', () async {
      gateway.taskGetError = PostgrestException(
        message: 'permission denied for table tasks',
        code: '42501',
      );

      final result = await repository.getTaskById(
        workspaceId: 'workspace-a',
        taskId: 'task-a',
      );

      expect(
        (result as PlatformRepositoryFailure<TaskDto>).kind,
        PlatformRepositoryFailureKind.forbidden,
      );
    });

    test('keeps a transport error on the read path as infrastructure', () async {
      gateway.taskListError = StateError(
        'connection to 10.0.0.5:5432 refused',
      );

      final result = await repository.searchTasks(
        const TaskListQuery(workspaceId: 'workspace-a'),
      );

      final failure =
          result as PlatformRepositoryFailure<PlatformPageResult<TaskDto>>;
      expect(failure.kind, PlatformRepositoryFailureKind.infrastructureFailure);
      expect(failure.message, 'Supabase tasks could not be loaded.');
      expect(failure.message, isNot(contains('10.0.0.5')));
    });

    test(
      'keeps a non-authorization PostgrestException as infrastructure',
      () async {
        gateway.taskListError = PostgrestException(
          message: 'canceling statement due to statement timeout',
          code: '57014',
        );

        final result = await repository.searchTasks(
          const TaskListQuery(workspaceId: 'workspace-a'),
        );

        expect(
          (result
                  as PlatformRepositoryFailure<PlatformPageResult<TaskDto>>)
              .kind,
          PlatformRepositoryFailureKind.infrastructureFailure,
        );
      },
    );
  });
}

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

PlatformCommandContext _context() => const PlatformCommandContext(
  workspaceId: 'workspace-a',
  actorId: 'user-1',
  mutationId: 'mutation-1',
  correlationId: 'correlation-1',
  reason: 'integration',
);

CreateTaskCommand _createTaskCommand() => CreateTaskCommand(
  context: _context(),
  draft: TaskDraft(
    title: 'Heizung prüfen',
    entity: const PlatformEntityRef(
      type: PlatformEntityType.property,
      id: 'property-1',
    ),
    description: 'Wartung',
    category: 'maintenance',
    assignedTo: 'user-9',
    priority: TaskPriority.high,
    dueAt: DateTime.utc(2026, 8, 1, 12),
    generatedKey: 'monthly-2026-07',
  ),
);

Map<String, dynamic> _taskJson({
  String id = 'task-a',
  String workspaceId = 'workspace-a',
  String status = 'open',
  int version = 1,
  String createdAt = '2026-07-24T10:00:00.000Z',
  String? dueAt = '2026-08-01T12:00:00.000Z',
  String? generatedKey,
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'entity_type': 'property',
    'entity_id': 'property-1',
    'title': 'Heizung prüfen',
    'description': 'Wartung',
    'category': 'maintenance',
    'assigned_to': 'user-9',
    'priority': 'normal',
    'status': status,
    'due_at': dueAt,
    'generated_key': generatedKey,
    'archived_at': null,
    'created_at': createdAt,
    'updated_at': createdAt,
    'created_by': 'user-1',
    'updated_by': 'user-1',
    'version': version,
  };
}

Map<String, dynamic> _notificationJson({
  String id = 'notification-a',
  String workspaceId = 'workspace-a',
  String createdAt = '2026-07-24T10:00:00.000Z',
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'recipient_user_id': 'user-9',
    'kind': 'lease.expiring',
    'title': 'Mietvertrag läuft aus',
    'body': null,
    'entity_type': 'lease',
    'entity_id': 'lease-1',
    'read_at': null,
    'created_at': createdAt,
    'updated_at': createdAt,
    'created_by': 'user-1',
    'updated_by': 'user-1',
    'version': 1,
  };
}

Map<String, dynamic> _importJobJson({
  String id = 'job-a',
  String workspaceId = 'workspace-a',
  String status = 'draft',
  int version = 1,
  Map<String, Object?>? dryRun,
  Map<String, Object?>? reconciliation,
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'source_kind': 'sqlite.legacy',
    'target_scope': 'properties',
    'status': status,
    'mapping': <String, Object?>{'properties': 'p1-012'},
    'dry_run': dryRun,
    'reconciliation': reconciliation,
    'error_report': null,
    'started_at': null,
    'finished_at': null,
    'created_at': '2026-07-24T10:00:00.000Z',
    'updated_at': '2026-07-24T10:00:00.000Z',
    'created_by': 'user-1',
    'updated_by': 'user-1',
    'version': version,
  };
}

Map<String, dynamic> _searchEntryJson({
  String id = 'entry-a',
  String workspaceId = 'workspace-a',
  String updatedAt = '2026-07-24T10:00:00.000Z',
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'entity_type': 'property',
    'entity_id': 'property-1',
    'title': 'Musterstraße 1',
    'subtitle': 'Berlin',
    'body': null,
    'updated_at': updatedAt,
    'created_at': '2026-07-24T09:00:00.000Z',
    'created_by': 'user-1',
    'updated_by': 'user-1',
  };
}

class _FakePlatformGateway implements PlatformSupabaseGateway {
  @override
  String? currentUserId = 'user-1';

  List<Map<String, dynamic>> taskRows = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> notificationRows = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> importJobRows = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> searchRows = const <Map<String, dynamic>>[];

  String? taskWorkspaceId;
  List<String>? taskStatuses;
  String? taskEntityType;
  String? taskEntityId;
  String? taskAssignedTo;
  bool? taskUnassignedOnly;
  String? taskPropertyId;
  DateTime? taskDueFrom;
  DateTime? taskDueUntil;
  bool? taskWithoutDue;
  String? taskTitleQuery;
  bool? taskIncludeArchived;
  bool? taskSortByDue;
  PlatformKeysetCursor? taskCursor;
  int? taskLimit;

  String? notificationRecipientUserId;
  bool? notificationUnreadOnly;

  String? searchEntityType;
  List<({String type, String id})>? searchEntities;

  Object? taskListError;
  Object? taskGetError;
  Object? notificationListError;

  Object? rpcResult;
  Object? rpcError;
  int rpcCalls = 0;
  String? lastFunction;
  Map<String, Object?>? lastParameters;

  @override
  Future<List<Map<String, dynamic>>> listTasks({
    required String workspaceId,
    required List<String>? statuses,
    required String? entityType,
    required String? entityId,
    required String? assignedTo,
    required bool unassignedOnly,
    required String? propertyId,
    required DateTime? dueFrom,
    required DateTime? dueUntil,
    required bool withoutDue,
    required String? titleQuery,
    required bool includeArchived,
    required bool sortByDue,
    required PlatformKeysetCursor? after,
    required int limit,
  }) async {
    taskWorkspaceId = workspaceId;
    taskStatuses = statuses;
    taskEntityType = entityType;
    taskEntityId = entityId;
    taskAssignedTo = assignedTo;
    taskUnassignedOnly = unassignedOnly;
    taskPropertyId = propertyId;
    taskDueFrom = dueFrom;
    taskDueUntil = dueUntil;
    taskWithoutDue = withoutDue;
    taskTitleQuery = titleQuery;
    taskIncludeArchived = includeArchived;
    taskSortByDue = sortByDue;
    taskCursor = after;
    taskLimit = limit;
    final error = taskListError;
    if (error != null) {
      throw error;
    }
    return taskRows;
  }

  @override
  Future<List<Map<String, dynamic>>> getTask({
    required String workspaceId,
    required String taskId,
  }) async {
    final error = taskGetError;
    if (error != null) {
      throw error;
    }
    return taskRows;
  }

  @override
  Future<List<Map<String, dynamic>>> listNotifications({
    required String workspaceId,
    required String? recipientUserId,
    required bool unreadOnly,
    required PlatformKeysetCursor? after,
    required int limit,
  }) async {
    notificationRecipientUserId = recipientUserId;
    notificationUnreadOnly = unreadOnly;
    final error = notificationListError;
    if (error != null) {
      throw error;
    }
    return notificationRows;
  }

  @override
  Future<List<Map<String, dynamic>>> listImportJobs({
    required String workspaceId,
    required String? status,
    required String? targetScope,
    required PlatformKeysetCursor? after,
    required int limit,
  }) async => importJobRows;

  @override
  Future<List<Map<String, dynamic>>> getImportJob({
    required String workspaceId,
    required String importJobId,
  }) async => importJobRows;

  @override
  Future<List<Map<String, dynamic>>> listSearchEntries({
    required String workspaceId,
    required String? entityType,
    required List<({String type, String id})>? entities,
    required PlatformKeysetCursor? after,
    required int limit,
  }) async {
    searchEntityType = entityType;
    searchEntities = entities;
    return searchRows;
  }

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) async {
    rpcCalls++;
    lastFunction = function;
    lastParameters = parameters;
    final error = rpcError;
    if (error != null) {
      throw error;
    }
    return rpcResult;
  }
}
