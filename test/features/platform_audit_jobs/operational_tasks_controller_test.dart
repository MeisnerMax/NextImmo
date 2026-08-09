import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/operational_tasks_controller.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/platform_entity_type.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/task_dto.dart';

const _workspace = 'workspace-a';
const _actor = 'actor-a';

void main() {
  test('unresolved workspace stays idle and never queries', () async {
    final repository = _FakeTaskRepository(tasks: const <TaskDto>[]);
    final controller = OperationalTasksController(
      repository: repository,
      scope: const WorkspaceSessionScope.unresolved(),
    );

    await controller.load();

    expect(controller.state.listPhase, OperationalTasksListPhase.idle);
    expect(repository.searchCalls, 0);
  });

  test('forbidden read maps to a dedicated forbidden state', () async {
    final repository = _FakeTaskRepository(
      tasks: const <TaskDto>[],
      searchFailure: PlatformRepositoryFailureKind.forbidden,
    );
    final controller = OperationalTasksController(
      repository: repository,
      scope: _scope(const <String>{'task.read'}),
    );

    await controller.load();

    expect(controller.state.listPhase, OperationalTasksListPhase.forbidden);
    expect(controller.state.tasks, isEmpty);
  });

  test('loads every keyset page instead of silently showing only page one', () async {
    final repository = _FakeTaskRepository(
      tasks: <TaskDto>[
        _task('1', title: 'One'),
        _task('2', title: 'Two'),
        _task('3', title: 'Three'),
      ],
      pageSize: 2,
    );
    final controller = OperationalTasksController(
      repository: repository,
      scope: _scope(const <String>{'task.read'}),
    );

    await controller.load();

    expect(controller.state.listPhase, OperationalTasksListPhase.ready);
    expect(controller.state.tasks.map((task) => task.id), <String>['1', '2', '3']);
    expect(repository.searchCalls, 2);
    expect(controller.state.truncated, isFalse);
  });

  test('combines assignment, priority, context, attention and text filters', () async {
    final now = DateTime.utc(2026, 8, 9, 12);
    final repository = _FakeTaskRepository(
      tasks: <TaskDto>[
        _task(
          'overdue',
          title: 'Repair roof',
          priority: TaskPriority.high,
          assignedTo: _actor,
          dueAt: now.subtract(const Duration(days: 1)),
          entity: const PlatformEntityRef(
            type: PlatformEntityType.property,
            id: 'property-a',
          ),
        ),
        _task(
          'blocked',
          title: 'Await contractor',
          status: TaskStatus.blocked,
          dueAt: now.add(const Duration(days: 30)),
          entity: const PlatformEntityRef(
            type: PlatformEntityType.property,
            id: 'property-a',
          ),
        ),
        _task(
          'soon',
          title: 'Inspect lease',
          assignedTo: 'other-user',
          priority: TaskPriority.high,
          dueAt: now.add(const Duration(days: 5)),
          entity: const PlatformEntityRef(
            type: PlatformEntityType.lease,
            id: 'lease-a',
          ),
        ),
        _task(
          'done',
          title: 'Repair roof done',
          assignedTo: _actor,
          priority: TaskPriority.high,
          status: TaskStatus.done,
          dueAt: now.subtract(const Duration(days: 5)),
          entity: const PlatformEntityRef(
            type: PlatformEntityType.property,
            id: 'property-a',
          ),
        ),
      ],
    );
    final controller = OperationalTasksController(
      repository: repository,
      scope: _scope(const <String>{'task.read'}),
      clock: () => now,
    );
    await controller.load();

    controller.setAssignmentFilter(OperationalTaskAssignmentFilter.mine);
    controller.setPriorityFilter(TaskPriority.high);
    controller.setEntityTypeFilter(PlatformEntityType.property);
    controller.setAttentionFilter(OperationalTaskAttentionFilter.overdue);
    controller.setQuery('roof');

    expect(controller.visibleTasks().map((task) => task.id), <String>['overdue']);

    controller.clearFilters();
    expect(controller.state.hasActiveFilters, isFalse);
    expect(controller.visibleTasks(), hasLength(4));
  });

  test('needsAttention includes overdue, blocked and due-soon but not done', () async {
    final now = DateTime.utc(2026, 8, 9, 12);
    final repository = _FakeTaskRepository(
      tasks: <TaskDto>[
        _task('overdue', dueAt: now.subtract(const Duration(minutes: 1))),
        _task('blocked', status: TaskStatus.blocked),
        _task('soon', dueAt: now.add(const Duration(days: 7))),
        _task('later', dueAt: now.add(const Duration(days: 8))),
        _task(
          'done',
          status: TaskStatus.done,
          dueAt: now.subtract(const Duration(days: 1)),
        ),
      ],
    );
    final controller = OperationalTasksController(
      repository: repository,
      scope: _scope(const <String>{'task.read'}),
      clock: () => now,
    );
    await controller.load();

    controller.setAttentionFilter(OperationalTaskAttentionFilter.needsAttention);

    expect(
      controller.visibleTasks().map((task) => task.id).toSet(),
      <String>{'overdue', 'blocked', 'soon'},
    );
  });

  test('mutation is blocked client-side without task.manage', () async {
    final repository = _FakeTaskRepository(tasks: const <TaskDto>[]);
    final controller = OperationalTasksController(
      repository: repository,
      scope: _scope(const <String>{'task.read'}),
    );

    await controller.createTask(const TaskDraft(title: 'No permission'));

    expect(controller.state.actionPhase, OperationalTasksActionPhase.forbidden);
    expect(repository.createCalls, 0);
  });

  test('createTask sends the resolved workspace/actor and unique command ids', () async {
    var id = 0;
    final repository = _FakeTaskRepository(tasks: const <TaskDto>[]);
    final controller = OperationalTasksController(
      repository: repository,
      scope: _scope(const <String>{'task.read', 'task.manage'}),
      idFactory: () => 'id-${++id}',
    );

    await controller.createTask(
      const TaskDraft(
        title: 'Create me',
        entity: PlatformEntityRef(
          type: PlatformEntityType.property,
          id: 'property-a',
        ),
      ),
    );

    final command = repository.lastCreateCommand;
    expect(command, isNotNull);
    expect(command!.context.workspaceId, _workspace);
    expect(command.context.actorId, _actor);
    expect(command.context.mutationId, 'id-1');
    expect(command.context.correlationId, 'id-2');
    expect(command.draft.entity?.id, 'property-a');
  });

  test('version conflict preserves the structured conflict for the UI', () async {
    final current = _task('1', version: 2);
    final repository = _FakeTaskRepository(
      tasks: <TaskDto>[_task('1')],
      updateFailure: PlatformRepositoryFailure<TaskDto>(
        kind: PlatformRepositoryFailureKind.versionConflict,
        message: 'stale',
        versionConflict: PlatformVersionConflict(
          expectedVersion: 1,
          actualVersion: 2,
          currentTask: current,
        ),
      ),
    );
    final controller = OperationalTasksController(
      repository: repository,
      scope: _scope(const <String>{'task.read', 'task.manage'}),
    );

    await controller.updateTask(
      task: _task('1'),
      changes: const TaskUpdateDto(title: 'Changed'),
    );

    expect(controller.state.actionPhase, OperationalTasksActionPhase.conflict);
    expect(controller.state.versionConflict?.currentTask?.version, 2);
  });

  test('illegal status transition is rejected before calling the repository', () async {
    final repository = _FakeTaskRepository(tasks: const <TaskDto>[]);
    final controller = OperationalTasksController(
      repository: repository,
      scope: _scope(const <String>{'task.read', 'task.manage'}),
    );
    final task = _task('1', status: TaskStatus.open);

    await controller.transitionStatus(task: task, target: TaskStatus.done);

    expect(controller.state.actionPhase, OperationalTasksActionPhase.failed);
    expect(repository.transitionCalls, 0);
  });
}

WorkspaceSessionScope _scope(Set<String> permissions) => WorkspaceSessionScope(
  workspaceId: _workspace,
  actorId: _actor,
  permissions: permissions,
  mutationsSupported: true,
);

TaskDto _task(
  String id, {
  String title = 'Task',
  TaskPriority priority = TaskPriority.normal,
  TaskStatus status = TaskStatus.open,
  String? assignedTo,
  DateTime? dueAt,
  PlatformEntityRef? entity,
  int version = 1,
}) => TaskDto(
  id: id,
  workspaceId: _workspace,
  title: title,
  priority: priority,
  status: status,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  createdBy: _actor,
  updatedBy: _actor,
  version: version,
  assignedTo: assignedTo,
  dueAt: dueAt,
  entity: entity,
);

class _FakeTaskRepository implements TaskRepository {
  _FakeTaskRepository({
    required this.tasks,
    this.pageSize = 100,
    this.searchFailure,
    this.updateFailure,
  });

  final List<TaskDto> tasks;
  final int pageSize;
  final PlatformRepositoryFailureKind? searchFailure;
  final PlatformRepositoryFailure<TaskDto>? updateFailure;

  int searchCalls = 0;
  int createCalls = 0;
  int transitionCalls = 0;
  CreateTaskCommand? lastCreateCommand;

  @override
  Future<PlatformRepositoryResult<PlatformPageResult<TaskDto>>> searchTasks(
    TaskListQuery query,
  ) async {
    searchCalls += 1;
    if (searchFailure != null) {
      return PlatformRepositoryFailure<PlatformPageResult<TaskDto>>(
        kind: searchFailure!,
        message: 'fail',
      );
    }
    final offset = query.page.cursor == null ? 0 : int.parse(query.page.cursor!);
    final effective = pageSize < query.page.limit ? pageSize : query.page.limit;
    final end = (offset + effective).clamp(0, tasks.length);
    final items = tasks.sublist(offset, end);
    final next = end < tasks.length ? '$end' : null;
    return PlatformRepositorySuccess<PlatformPageResult<TaskDto>>(
      PlatformPageResult<TaskDto>(items: items, nextCursor: next),
    );
  }

  @override
  Future<PlatformRepositoryResult<TaskDto>> getTaskById({
    required String workspaceId,
    required String taskId,
  }) async => throw UnimplementedError();

  @override
  Future<PlatformRepositoryResult<TaskDto>> createTask(
    CreateTaskCommand command,
  ) async {
    createCalls += 1;
    lastCreateCommand = command;
    return PlatformRepositorySuccess<TaskDto>(
      _task('created', title: command.draft.title),
    );
  }

  @override
  Future<PlatformRepositoryResult<TaskDto>> updateTask(
    UpdateTaskCommand command,
  ) async {
    final failure = updateFailure;
    if (failure != null) return failure;
    return PlatformRepositorySuccess<TaskDto>(
      _task(command.taskId, version: command.expectedVersion + 1),
    );
  }

  @override
  Future<PlatformRepositoryResult<TaskDto>> transitionTaskStatus(
    TransitionTaskStatusCommand command,
  ) async {
    transitionCalls += 1;
    return PlatformRepositorySuccess<TaskDto>(
      _task(
        command.taskId,
        status: command.targetStatus,
        version: command.expectedVersion + 1,
      ),
    );
  }
}
