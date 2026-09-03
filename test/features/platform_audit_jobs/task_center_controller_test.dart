import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_query_invalidation_source.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/task_center_controller.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/platform_entity_type.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/task_dto.dart';

const String _workspace = 'workspace-a';
const String _actor = 'user-1';

TaskDto _task({
  String id = 'task-a',
  TaskStatus status = TaskStatus.open,
  int version = 1,
  String? assignedTo,
  DateTime? createdAt,
}) {
  final stamp = createdAt ?? DateTime.utc(2026, 8, 1, 12);
  return TaskDto(
    id: id,
    workspaceId: _workspace,
    title: 'Aufgabe $id',
    priority: TaskPriority.normal,
    status: status,
    createdAt: stamp,
    updatedAt: stamp,
    createdBy: _actor,
    updatedBy: _actor,
    version: version,
    assignedTo: assignedTo,
  );
}

PlatformRepositorySuccess<PlatformPageResult<TaskDto>> _page(
  List<TaskDto> items, {
  String? nextCursor,
}) {
  return PlatformRepositorySuccess<PlatformPageResult<TaskDto>>(
    PlatformPageResult<TaskDto>(items: items, nextCursor: nextCursor),
  );
}

class _FakeTasks implements TaskRepository {
  @override
  Future<PlatformRepositoryResult<int>> countTasks(TaskCountQuery query) async {
    return const PlatformRepositorySuccess<int>(0);
  }

  final List<TaskListQuery> queries = <TaskListQuery>[];
  final List<CreateTaskCommand> creates = <CreateTaskCommand>[];
  final List<UpdateTaskCommand> updates = <UpdateTaskCommand>[];
  final List<TransitionTaskStatusCommand> transitions =
      <TransitionTaskStatusCommand>[];

  PlatformRepositoryResult<PlatformPageResult<TaskDto>> Function(
    TaskListQuery query,
  )?
  onSearch;
  PlatformRepositoryResult<TaskDto> Function(String taskId)? onGet;
  PlatformRepositoryResult<TaskDto> Function(CreateTaskCommand command)?
  onCreate;
  PlatformRepositoryResult<TaskDto> Function(UpdateTaskCommand command)?
  onUpdate;
  PlatformRepositoryResult<TaskDto> Function(
    TransitionTaskStatusCommand command,
  )?
  onTransition;

  @override
  Future<PlatformRepositoryResult<PlatformPageResult<TaskDto>>> searchTasks(
    TaskListQuery query,
  ) async {
    queries.add(query);
    return onSearch?.call(query) ?? _page(const <TaskDto>[]);
  }

  @override
  Future<PlatformRepositoryResult<TaskDto>> getTaskById({
    required String workspaceId,
    required String taskId,
  }) async {
    return onGet?.call(taskId) ?? PlatformRepositorySuccess<TaskDto>(_task());
  }

  @override
  Future<PlatformRepositoryResult<TaskDto>> createTask(
    CreateTaskCommand command,
  ) async {
    creates.add(command);
    return onCreate?.call(command) ??
        PlatformRepositorySuccess<TaskDto>(_task(id: 'task-created'));
  }

  @override
  Future<PlatformRepositoryResult<TaskDto>> updateTask(
    UpdateTaskCommand command,
  ) async {
    updates.add(command);
    return onUpdate?.call(command) ??
        PlatformRepositorySuccess<TaskDto>(_task(id: command.taskId));
  }

  @override
  Future<PlatformRepositoryResult<TaskDto>> transitionTaskStatus(
    TransitionTaskStatusCommand command,
  ) async {
    transitions.add(command);
    return onTransition?.call(command) ??
        PlatformRepositorySuccess<TaskDto>(
          _task(id: command.taskId, status: command.targetStatus),
        );
  }
}

class _FakeInvalidation implements PlatformQueryInvalidationSource {
  final StreamController<PlatformQueryInvalidation> controller =
      StreamController<PlatformQueryInvalidation>.broadcast();

  @override
  Stream<PlatformQueryInvalidation> watchWorkspace({
    required String workspaceId,
  }) => controller.stream;
}

TaskCenterScope _scope({
  Set<String> permissions = const <String>{'task.read', 'task.manage'},
  PlatformEntityRef? lockedContext,
}) {
  return TaskCenterScope(
    workspaceId: _workspace,
    actorId: _actor,
    permissions: permissions,
    canMutate: true,
    lockedContext: lockedContext,
  );
}

({TaskCenterController controller, _FakeTasks tasks, _FakeInvalidation inv})
_build({TaskCenterScope? scope, List<String>? idLog}) {
  final tasks = _FakeTasks();
  final inv = _FakeInvalidation();
  var idCounter = 0;
  final controller = TaskCenterController(
    tasks: tasks,
    scope: scope ?? _scope(),
    invalidationSource: inv,
    invalidationCoalesceWindow: Duration.zero,
    idFactory: () {
      final id = 'gen-${idCounter++}';
      idLog?.add(id);
      return id;
    },
  );
  addTearDown(controller.dispose);
  addTearDown(inv.controller.close);
  return (controller: controller, tasks: tasks, inv: inv);
}

Future<void> _settle() async {
  // Two microtask/event-loop hops: one for the zero-length coalesce timer,
  // one for the reload future it kicks off.
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('OD-2 pretense regression (§17)', () {
    test('every offered filter control maps onto a TaskListQuery field', () {
      // The server-side capability set of TaskListQuery, pinned by name. A
      // control claiming a capability outside this set fails here — that is
      // the machine-checkable form of "was der Contract nicht trägt, wird
      // nicht angeboten".
      const contractFields = <String>{
        'statuses',
        'assignedTo',
        'includeArchived',
        'entity',
      };
      expect(taskCenterOfferedFilters, hasLength(4));
      for (final offered in taskCenterOfferedFilters) {
        expect(
          contractFields.contains(offered.queryField),
          isTrue,
          reason:
              'Control "${offered.control}" claims server capability '
              '"${offered.queryField}" which TaskListQuery does not carry.',
        );
      }
      // No due-, priority-, search- or sort-control is offered.
      expect(
        taskCenterOfferedFilters.map((entry) => entry.control),
        isNot(
          anyElement(
            anyOf(contains('due'), contains('priority'), contains('search')),
          ),
        ),
      );
    });

    test('the filter state itself carries nothing beyond the contract', () {
      const filters = TaskCenterFilters(
        status: TaskStatus.blocked,
        assignedToMe: true,
        includeArchived: true,
        context: PlatformEntityRef(
          type: PlatformEntityType.property,
          id: 'property-1',
        ),
      );
      final query = filters.toQuery(workspaceId: _workspace, actorId: _actor);
      // Every filter field lands in the query — and the query is fully
      // determined by them, so no hidden client-side narrowing exists.
      expect(query.statuses, const <TaskStatus>[TaskStatus.blocked]);
      expect(query.assignedTo, _actor);
      expect(query.includeArchived, isTrue);
      expect(query.entity?.id, 'property-1');
    });
  });

  group('list', () {
    test('opens on "Alle offenen Aufgaben" (§2 default)', () async {
      final harness = _build();
      await harness.controller.load();

      final query = harness.tasks.queries.single;
      expect(query.statuses, const <TaskStatus>[TaskStatus.open]);
      expect(query.includeArchived, isFalse);
      expect(query.assignedTo, isNull);
      expect(query.entity, isNull);
    });

    test('a locked context scopes every query (§3 property entry)', () async {
      const locked = PlatformEntityRef(
        type: PlatformEntityType.property,
        id: 'property-1',
      );
      final harness = _build(scope: _scope(lockedContext: locked));
      await harness.controller.load();

      expect(harness.tasks.queries.single.entity, locked);
      // Resetting filters keeps the lock — it is scope, not a filter chip.
      await harness.controller.resetFilters();
      expect(harness.tasks.queries.last.entity, locked);
    });

    test('a forbidden read lands in the forbidden phase', () async {
      final harness = _build();
      harness.tasks.onSearch = (_) =>
          const PlatformRepositoryFailure<PlatformPageResult<TaskDto>>(
            kind: PlatformRepositoryFailureKind.forbidden,
            message: 'permission denied for table tasks',
          );
      await harness.controller.load();

      expect(
        harness.controller.state.listPhase,
        TaskCenterListPhase.forbidden,
      );
    });

    test('loadMore consumes the cursor and appends', () async {
      final harness = _build();
      harness.tasks.onSearch = (query) => query.page.cursor == null
          ? _page(<TaskDto>[_task(id: 'task-a')], nextCursor: 'cursor-1')
          : _page(<TaskDto>[_task(id: 'task-b')]);
      await harness.controller.load();
      await harness.controller.loadMore();

      expect(harness.tasks.queries.last.page.cursor, 'cursor-1');
      expect(
        harness.controller.state.tasks.map((task) => task.id),
        <String>['task-a', 'task-b'],
      );
      expect(harness.controller.state.nextCursor, isNull);
    });

    test('filter setters reload with the new query', () async {
      final harness = _build();
      await harness.controller.load();
      await harness.controller.setStatusFilter(null);
      await harness.controller.setAssignedToMe(true);
      await harness.controller.setIncludeArchived(true);

      final last = harness.tasks.queries.last;
      expect(last.statuses, isNull);
      expect(last.assignedTo, _actor);
      expect(last.includeArchived, isTrue);
    });
  });

  group('board (A9)', () {
    test('loads four independent status-bound keysets', () async {
      final harness = _build();
      harness.tasks.onSearch = (query) => query.statuses?.single == TaskStatus.open
          ? _page(<TaskDto>[_task(id: 'open-1')], nextCursor: 'open-cursor')
          : _page(const <TaskDto>[]);
      await harness.controller.load();
      harness.tasks.queries.clear();
      await harness.controller.setViewMode(TaskCenterViewMode.board);

      expect(
        harness.tasks.queries.map((query) => query.statuses?.single),
        containsAll(taskBoardStatuses),
      );
      expect(harness.tasks.queries, hasLength(4));
      // The board never includes archived, whatever the list toggle says.
      expect(
        harness.tasks.queries.every((query) => !query.includeArchived),
        isTrue,
      );
      final openColumn = harness.controller.state.board[TaskStatus.open]!;
      expect(openColumn.tasks.single.id, 'open-1');
      expect(openColumn.nextCursor, 'open-cursor');
      expect(
        harness.controller.state.board[TaskStatus.done]!.tasks,
        isEmpty,
      );
    });

    test('loadMoreInColumn pages exactly one column', () async {
      final harness = _build();
      harness.tasks.onSearch = (query) => query.statuses?.single == TaskStatus.open
          ? _page(<TaskDto>[_task(id: 'open-${query.page.cursor ?? '1'}')],
              nextCursor: query.page.cursor == null ? 'open-cursor' : null)
          : _page(const <TaskDto>[]);
      await harness.controller.load();
      await harness.controller.setViewMode(TaskCenterViewMode.board);
      harness.tasks.queries.clear();

      await harness.controller.loadMoreInColumn(TaskStatus.open);

      final query = harness.tasks.queries.single;
      expect(query.statuses, const <TaskStatus>[TaskStatus.open]);
      expect(query.page.cursor, 'open-cursor');
      expect(
        harness.controller.state.board[TaskStatus.open]!.tasks,
        hasLength(2),
      );
    });
  });

  group('realtime (§9)', () {
    test('a reconnect burst coalesces into exactly one reload', () async {
      final harness = _build();
      await harness.controller.load();
      final before = harness.tasks.queries.length;

      // Up to three reconcile signals after a full reconnect (§9).
      harness.inv.controller
        ..add(const PlatformQueryInvalidation.reconcile(workspaceId: _workspace))
        ..add(const PlatformQueryInvalidation.reconcile(workspaceId: _workspace))
        ..add(
          const PlatformQueryInvalidation.reconcile(workspaceId: _workspace),
        );
      await _settle();

      expect(harness.tasks.queries.length, before + 1);
    });

    test('a foreign aggregate event does not reload the task list', () async {
      final harness = _build();
      await harness.controller.load();
      final before = harness.tasks.queries.length;

      harness.inv.controller.add(
        const PlatformQueryInvalidation(
          workspaceId: _workspace,
          aggregate: PlatformAggregate.importJob,
          eventType: 'import_job.updated',
        ),
      );
      await _settle();

      expect(harness.tasks.queries.length, before);
    });

    test('a board event invalidates all four keysets', () async {
      final harness = _build();
      await harness.controller.load();
      await harness.controller.setViewMode(TaskCenterViewMode.board);
      harness.tasks.queries.clear();

      harness.inv.controller.add(
        const PlatformQueryInvalidation(
          workspaceId: _workspace,
          aggregate: PlatformAggregate.task,
          eventType: 'task.status_changed',
        ),
      );
      await _settle();

      expect(harness.tasks.queries, hasLength(4));
    });

    test('stream errors degrade, the next signal recovers', () async {
      final harness = _build();
      await harness.controller.load();

      harness.inv.controller.addError(StateError('channel down'));
      await _settle();
      expect(harness.controller.state.liveUpdatesDegraded, isTrue);

      harness.inv.controller.add(
        const PlatformQueryInvalidation.reconcile(workspaceId: _workspace),
      );
      await _settle();
      expect(harness.controller.state.liveUpdatesDegraded, isFalse);
    });
  });

  group('mutations', () {
    test('createTask succeeds, selects the task and reloads', () async {
      final harness = _build();
      await harness.controller.load();
      final before = harness.tasks.queries.length;

      final failure = await harness.controller.createTask(
        draft: const TaskDraft(title: 'Neue Aufgabe'),
        mutationId: 'intent-1',
        reason: 'Manuell angelegt (Task Center)',
      );

      expect(failure, isNull);
      final command = harness.tasks.creates.single;
      expect(command.context.mutationId, 'intent-1');
      expect(command.context.reason, 'Manuell angelegt (Task Center)');
      expect(command.context.correlationId, startsWith('gen-'));
      expect(harness.controller.state.selectedTask?.id, 'task-created');
      expect(harness.tasks.queries.length, before + 1);
    });

    test('a failed create returns the classified failure', () async {
      final harness = _build();
      harness.tasks.onCreate = (_) => const PlatformRepositoryFailure<TaskDto>(
        kind: PlatformRepositoryFailureKind.validationFailed,
        message: 'Title is required',
        validationFields: <String>['title'],
      );

      final failure = await harness.controller.createTask(
        draft: const TaskDraft(title: ''),
        mutationId: 'intent-1',
        reason: 'Test',
      );

      expect(failure?.validationFields, <String>['title']);
    });

    test('setAssignedToSelf sends set/clear on assigned_to (A6)', () async {
      final harness = _build();
      final task = _task(version: 3);

      await harness.controller.setAssignedToSelf(
        task: task,
        assigned: true,
        mutationId: 'intent-1',
      );
      final set = harness.tasks.updates.single.changes.assignedTo;
      expect(set.isPresent, isTrue);
      expect(set.value, _actor);

      await harness.controller.setAssignedToSelf(
        task: task,
        assigned: false,
        mutationId: 'intent-2',
      );
      final clear = harness.tasks.updates.last.changes.assignedTo;
      expect(clear.isPresent, isTrue);
      expect(clear.value, isNull);
      expect(harness.tasks.updates.last.expectedVersion, 3);
    });

    test('openById maps notFound onto the detail phase', () async {
      final harness = _build();
      harness.tasks.onGet = (_) => const PlatformRepositoryFailure<TaskDto>(
        kind: PlatformRepositoryFailureKind.notFound,
        message: 'Task not found.',
      );
      await harness.controller.openById('missing');

      expect(harness.controller.state.detailPhase, TaskDetailPhase.notFound);
    });
  });

  group('bulk (§6.9)', () {
    test('reports successes, conflicts and disallowed transitions', () async {
      final harness = _build();
      final rows = <TaskDto>[
        _task(id: 'open-1', status: TaskStatus.open),
        _task(id: 'open-2', status: TaskStatus.open),
        _task(id: 'run-1', status: TaskStatus.inProgress),
        _task(id: 'run-2', status: TaskStatus.inProgress),
        _task(id: 'run-conflict', status: TaskStatus.inProgress, version: 2),
        _task(id: 'blocked-1', status: TaskStatus.blocked),
      ];
      harness.tasks.onSearch = (_) => _page(rows);
      harness.tasks.onTransition = (command) =>
          command.taskId == 'run-conflict'
          ? PlatformRepositoryFailure<TaskDto>(
              kind: PlatformRepositoryFailureKind.versionConflict,
              message: 'Task version is stale',
              versionConflict: PlatformVersionConflict(
                expectedVersion: command.expectedVersion,
                actualVersion: 9,
                currentTask: _task(id: command.taskId, version: 9),
              ),
            )
          : PlatformRepositorySuccess<TaskDto>(
              _task(id: command.taskId, status: command.targetStatus),
            );
      await harness.controller.load();
      harness.controller.setSelecting(true);
      for (final row in rows) {
        harness.controller.toggleSelected(row.id);
      }

      final report = await harness.controller.runBulk(TaskBulkAction.complete);

      // "3 von 6 aktualisiert. 3 übersprungen (1 Versionskonflikt,
      // 2 unzulässige Statuswechsel)." — open → done is forbidden by STM-012
      // and never even reaches the server.
      expect(report!.total, 6);
      expect(report.succeeded, 3);
      expect(report.countOf(TaskBulkFailureKind.versionConflict), 1);
      expect(report.countOf(TaskBulkFailureKind.invalidTransition), 2);
      expect(report.countOf(TaskBulkFailureKind.failed), 0);
      expect(
        harness.tasks.transitions.map((command) => command.taskId),
        isNot(contains('open-1')),
      );
      // Every server-reaching row carried its own intent id and the bulk
      // reason (§12).
      final ids = harness.tasks.transitions
          .map((command) => command.context.mutationId)
          .toSet();
      expect(ids, hasLength(harness.tasks.transitions.length));
      expect(
        harness.tasks.transitions.every(
          (command) => command.context.reason == 'Massenaktion: Erledigt',
        ),
        isTrue,
      );
    });

    test('selection is capped at $taskBulkLimit rows', () async {
      final harness = _build();
      final rows = <TaskDto>[
        for (var index = 0; index < taskBulkLimit + 1; index++)
          _task(id: 'task-$index'),
      ];
      harness.tasks.onSearch = (_) => _page(rows);
      await harness.controller.load();
      harness.controller.setSelecting(true);
      for (final row in rows) {
        harness.controller.toggleSelected(row.id);
      }

      expect(harness.controller.state.selectedIds, hasLength(taskBulkLimit));
      expect(harness.controller.state.actionMessage, contains('Maximal'));
    });
  });
}
