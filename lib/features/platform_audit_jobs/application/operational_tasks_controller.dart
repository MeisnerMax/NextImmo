/// Cloud-native screen orchestration for the operational Tasks workplace.
///
/// This deliberately builds on the already-shipped DOM-010 [TaskRepository]
/// instead of reviving the legacy SQLite task models. Reads are workspace-
/// scoped and permission-authorized by the backend; mutations keep the existing
/// audited/idempotent/versioned command envelope.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/authorization_port.dart';
import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/platform_entity_type.dart';
import '../domain/task_dto.dart';
import 'platform_providers.dart';
import 'platform_repository.dart';

enum OperationalTasksListPhase {
  idle,
  loading,
  ready,
  empty,
  forbidden,
  error,
}

enum OperationalTasksActionPhase {
  idle,
  submitting,
  succeeded,
  conflict,
  forbidden,
  failed,
}

enum OperationalTaskAssignmentFilter { all, mine, unassigned }

enum OperationalTaskAttentionFilter {
  all,
  needsAttention,
  overdue,
  blocked,
  dueSoon,
}

const Object _unchanged = Object();

class OperationalTasksState {
  const OperationalTasksState({
    required this.listPhase,
    this.actionPhase = OperationalTasksActionPhase.idle,
    this.tasks = const <TaskDto>[],
    this.statusFilter,
    this.priorityFilter,
    this.assignmentFilter = OperationalTaskAssignmentFilter.all,
    this.entityTypeFilter,
    this.attentionFilter = OperationalTaskAttentionFilter.all,
    this.query = '',
    this.truncated = false,
    this.versionConflict,
    this.message,
    this.actionMessage,
  });

  const OperationalTasksState.loading()
    : this(listPhase: OperationalTasksListPhase.loading);

  final OperationalTasksListPhase listPhase;
  final OperationalTasksActionPhase actionPhase;
  final List<TaskDto> tasks;
  final TaskStatus? statusFilter;
  final TaskPriority? priorityFilter;
  final OperationalTaskAssignmentFilter assignmentFilter;
  final PlatformEntityType? entityTypeFilter;
  final OperationalTaskAttentionFilter attentionFilter;
  final String query;
  final bool truncated;
  final PlatformVersionConflict? versionConflict;
  final String? message;
  final String? actionMessage;

  bool get hasActiveFilters =>
      statusFilter != null ||
      priorityFilter != null ||
      assignmentFilter != OperationalTaskAssignmentFilter.all ||
      entityTypeFilter != null ||
      attentionFilter != OperationalTaskAttentionFilter.all ||
      query.trim().isNotEmpty;

  OperationalTasksState copyWith({
    OperationalTasksListPhase? listPhase,
    OperationalTasksActionPhase? actionPhase,
    List<TaskDto>? tasks,
    Object? statusFilter = _unchanged,
    Object? priorityFilter = _unchanged,
    OperationalTaskAssignmentFilter? assignmentFilter,
    Object? entityTypeFilter = _unchanged,
    OperationalTaskAttentionFilter? attentionFilter,
    String? query,
    bool? truncated,
    Object? versionConflict = _unchanged,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
  }) {
    return OperationalTasksState(
      listPhase: listPhase ?? this.listPhase,
      actionPhase: actionPhase ?? this.actionPhase,
      tasks: tasks ?? this.tasks,
      statusFilter: identical(statusFilter, _unchanged)
          ? this.statusFilter
          : statusFilter as TaskStatus?,
      priorityFilter: identical(priorityFilter, _unchanged)
          ? this.priorityFilter
          : priorityFilter as TaskPriority?,
      assignmentFilter: assignmentFilter ?? this.assignmentFilter,
      entityTypeFilter: identical(entityTypeFilter, _unchanged)
          ? this.entityTypeFilter
          : entityTypeFilter as PlatformEntityType?,
      attentionFilter: attentionFilter ?? this.attentionFilter,
      query: query ?? this.query,
      truncated: truncated ?? this.truncated,
      versionConflict: identical(versionConflict, _unchanged)
          ? this.versionConflict
          : versionConflict as PlatformVersionConflict?,
      message: identical(message, _unchanged)
          ? this.message
          : message as String?,
      actionMessage: identical(actionMessage, _unchanged)
          ? this.actionMessage
          : actionMessage as String?,
    );
  }
}

typedef OperationalTasksIdFactory = String Function();

class OperationalTasksController extends StateNotifier<OperationalTasksState> {
  OperationalTasksController({
    required TaskRepository repository,
    required WorkspaceSessionScope scope,
    OperationalTasksIdFactory? idFactory,
    DateTime Function()? clock,
  }) : _repository = repository,
       _scope = scope,
       _idFactory = idFactory ?? const Uuid().v4,
       _clock = clock ?? DateTime.now,
       super(const OperationalTasksState.loading());

  static const String managePermission = 'task.manage';
  static const int _pageSize = 100;
  static const int _maxLoadedTasks = 1000;

  final TaskRepository _repository;
  final WorkspaceSessionScope _scope;
  final OperationalTasksIdFactory _idFactory;
  final DateTime Function() _clock;

  AuthorizationPort get _authorization => _scope.authorization;

  bool get canMutate =>
      _scope.mutationsSupported &&
      _scope.isResolved &&
      _authorization.can(managePermission);

  String? get actorId => _scope.actorId;

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        listPhase: OperationalTasksListPhase.idle,
        tasks: const <TaskDto>[],
        truncated: false,
        message: null,
      );
      return;
    }

    state = state.copyWith(
      listPhase: OperationalTasksListPhase.loading,
      message: null,
    );

    final loaded = <TaskDto>[];
    String? cursor;
    var truncated = false;

    while (true) {
      final result = await _repository.searchTasks(
        TaskListQuery(
          workspaceId: workspaceId,
          includeArchived: false,
          page: PlatformPageRequest(limit: _pageSize, cursor: cursor),
        ),
      );
      switch (result) {
        case PlatformRepositoryFailure<PlatformPageResult<TaskDto>>(
          :final kind,
          :final message,
        ):
          state = state.copyWith(
            listPhase: kind == PlatformRepositoryFailureKind.forbidden
                ? OperationalTasksListPhase.forbidden
                : OperationalTasksListPhase.error,
            tasks: const <TaskDto>[],
            truncated: false,
            message: message,
          );
          return;
        case PlatformRepositorySuccess<PlatformPageResult<TaskDto>>(
          :final value,
        ):
          loaded.addAll(value.items);
          if (loaded.length >= _maxLoadedTasks && value.nextCursor != null) {
            truncated = true;
            break;
          }
          cursor = value.nextCursor;
          if (cursor == null) {
            break;
          }
          continue;
      }
      break;
    }

    state = state.copyWith(
      listPhase: loaded.isEmpty
          ? OperationalTasksListPhase.empty
          : OperationalTasksListPhase.ready,
      tasks: List<TaskDto>.unmodifiable(loaded.take(_maxLoadedTasks)),
      truncated: truncated,
      message: null,
    );
  }

  List<TaskDto> visibleTasks() {
    final now = _clock().toUtc();
    final normalizedQuery = _normalize(state.query);
    final actor = _scope.actorId;

    return state.tasks.where((task) {
      if (state.statusFilter != null && task.status != state.statusFilter) {
        return false;
      }
      if (state.priorityFilter != null && task.priority != state.priorityFilter) {
        return false;
      }
      switch (state.assignmentFilter) {
        case OperationalTaskAssignmentFilter.all:
          break;
        case OperationalTaskAssignmentFilter.mine:
          if (actor == null || task.assignedTo != actor) return false;
        case OperationalTaskAssignmentFilter.unassigned:
          if (task.assignedTo != null) return false;
      }
      if (state.entityTypeFilter != null &&
          task.entity?.type != state.entityTypeFilter) {
        return false;
      }
      if (!_matchesAttention(task, state.attentionFilter, now)) {
        return false;
      }
      if (normalizedQuery.isNotEmpty &&
          !_searchHaystack(task).contains(normalizedQuery)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  void setStatusFilter(TaskStatus? value) {
    state = state.copyWith(statusFilter: value);
  }

  void setPriorityFilter(TaskPriority? value) {
    state = state.copyWith(priorityFilter: value);
  }

  void setAssignmentFilter(OperationalTaskAssignmentFilter value) {
    state = state.copyWith(assignmentFilter: value);
  }

  void setEntityTypeFilter(PlatformEntityType? value) {
    state = state.copyWith(entityTypeFilter: value);
  }

  void setAttentionFilter(OperationalTaskAttentionFilter value) {
    state = state.copyWith(attentionFilter: value);
  }

  void setQuery(String value) {
    state = state.copyWith(query: value);
  }

  void clearFilters() {
    state = state.copyWith(
      statusFilter: null,
      priorityFilter: null,
      assignmentFilter: OperationalTaskAssignmentFilter.all,
      entityTypeFilter: null,
      attentionFilter: OperationalTaskAttentionFilter.all,
      query: '',
    );
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: OperationalTasksActionPhase.idle,
      actionMessage: null,
      versionConflict: null,
    );
  }

  Future<void> createTask(TaskDraft draft) async {
    if (_applyMutationGate()) return;
    state = state.copyWith(
      actionPhase: OperationalTasksActionPhase.submitting,
      actionMessage: null,
      versionConflict: null,
    );
    final result = await _repository.createTask(
      CreateTaskCommand(context: _commandContext(), draft: draft),
    );
    await _handleTaskMutationResult(result, successMessage: 'Aufgabe angelegt.');
  }

  Future<void> updateTask({
    required TaskDto task,
    required TaskUpdateDto changes,
  }) async {
    if (_applyMutationGate()) return;
    if (changes.isEmpty) {
      state = state.copyWith(
        actionPhase: OperationalTasksActionPhase.succeeded,
        actionMessage: 'Keine Änderungen.',
      );
      return;
    }
    state = state.copyWith(
      actionPhase: OperationalTasksActionPhase.submitting,
      actionMessage: null,
      versionConflict: null,
    );
    final result = await _repository.updateTask(
      UpdateTaskCommand(
        context: _commandContext(),
        taskId: task.id,
        expectedVersion: task.version,
        changes: changes,
      ),
    );
    await _handleTaskMutationResult(
      result,
      successMessage: 'Aufgabe aktualisiert.',
    );
  }

  Future<void> transitionStatus({
    required TaskDto task,
    required TaskStatus target,
  }) async {
    if (_applyMutationGate()) return;
    if (!task.status.canTransitionTo(target)) {
      state = state.copyWith(
        actionPhase: OperationalTasksActionPhase.failed,
        actionMessage: 'Dieser Statuswechsel ist nicht zulässig.',
      );
      return;
    }
    state = state.copyWith(
      actionPhase: OperationalTasksActionPhase.submitting,
      actionMessage: null,
      versionConflict: null,
    );
    final result = await _repository.transitionTaskStatus(
      TransitionTaskStatusCommand(
        context: _commandContext(),
        taskId: task.id,
        expectedVersion: task.version,
        targetStatus: target,
      ),
    );
    await _handleTaskMutationResult(
      result,
      successMessage: 'Aufgabenstatus aktualisiert.',
    );
  }

  Future<void> _handleTaskMutationResult(
    PlatformRepositoryResult<TaskDto> result, {
    required String successMessage,
  }) async {
    switch (result) {
      case PlatformRepositorySuccess<TaskDto>():
        await load();
        state = state.copyWith(
          actionPhase: OperationalTasksActionPhase.succeeded,
          actionMessage: successMessage,
          versionConflict: null,
        );
      case PlatformRepositoryFailure<TaskDto>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        state = state.copyWith(
          actionPhase: switch (kind) {
            PlatformRepositoryFailureKind.versionConflict =>
              OperationalTasksActionPhase.conflict,
            PlatformRepositoryFailureKind.forbidden =>
              OperationalTasksActionPhase.forbidden,
            _ => OperationalTasksActionPhase.failed,
          },
          actionMessage: message,
          versionConflict: versionConflict,
        );
    }
  }

  bool _applyMutationGate() {
    if (canMutate) return false;
    state = state.copyWith(
      actionPhase: OperationalTasksActionPhase.forbidden,
      actionMessage: 'Für diese Aktion fehlt die Berechtigung task.manage.',
      versionConflict: null,
    );
    return true;
  }

  PlatformCommandContext _commandContext() {
    return PlatformCommandContext(
      workspaceId: _scope.workspaceId!,
      actorId: _scope.actorId!,
      mutationId: _idFactory(),
      correlationId: _idFactory(),
    );
  }

  static bool _matchesAttention(
    TaskDto task,
    OperationalTaskAttentionFilter filter,
    DateTime now,
  ) {
    if (filter == OperationalTaskAttentionFilter.all) return true;
    final active = task.status != TaskStatus.done &&
        task.status != TaskStatus.archived;
    if (!active) return false;
    final due = task.dueAt?.toUtc();
    final overdue = due != null && due.isBefore(now);
    final dueSoon = due != null &&
        !due.isBefore(now) &&
        !due.isAfter(now.add(const Duration(days: 7)));
    final blocked = task.status == TaskStatus.blocked;

    return switch (filter) {
      OperationalTaskAttentionFilter.all => true,
      OperationalTaskAttentionFilter.needsAttention =>
        overdue || blocked || dueSoon,
      OperationalTaskAttentionFilter.overdue => overdue,
      OperationalTaskAttentionFilter.blocked => blocked,
      OperationalTaskAttentionFilter.dueSoon => dueSoon,
    };
  }

  static String _searchHaystack(TaskDto task) {
    return _normalize(<String?>[
      task.id,
      task.title,
      task.description,
      task.category,
      task.assignedTo,
      task.entity?.type.wireName,
      task.entity?.id,
    ].whereType<String>().join(' '));
  }

  static String _normalize(String value) => value.trim().toLowerCase();
}

final operationalTasksControllerProvider = StateNotifierProvider.autoDispose<
  OperationalTasksController,
  OperationalTasksState
>((ref) {
  final controller = OperationalTasksController(
    repository: ref.watch(taskRepositoryProvider),
    scope: ref.watch(workspaceSessionScopeProvider),
  );
  controller.load();
  return controller;
});
