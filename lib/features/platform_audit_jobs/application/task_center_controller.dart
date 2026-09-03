/// Screen-facing orchestration for the Task Center (TASK-CENTER-01, TASKS-V2).
///
/// One controller drives both entries of the one task surface: the
/// workspace-wide `GlobalPage.tasks` destination and the property-scoped
/// embedding in the Property Workspace's `Betrieb` domain — the latter binds
/// the same controller with a [TaskCenterScope.lockedContext] instead of a
/// second implementation (spec `task_center.md` §3).
///
/// The OD-2 rule governs everything here: the state offers exactly the
/// filters `TaskListQuery` carries server-side (`status` — one value,
/// `assignedTo`, `includeArchived`, the entity pair) and nothing else. There
/// is no search, no due filter, no priority filter, no counter and no
/// client-side sort — [taskCenterOfferedFilters] is the machine-checkable
/// registry the §17 pretense-regression test verifies against the query
/// contract.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/platform_entity_type.dart';
import '../domain/task_dto.dart';
import 'platform_providers.dart';
import 'platform_query_invalidation_source.dart';
import 'platform_repository.dart';

const Object _unchanged = Object();

/// Identifies the workspace/actor/context a [TaskCenterController] is bound
/// to. Value equality keeps the Riverpod family stable across rebuilds
/// (same shape as `MembersAdminScope`).
class TaskCenterScope {
  TaskCenterScope({
    required this.workspaceId,
    required this.actorId,
    required Set<String> permissions,
    required this.canMutate,
    this.lockedContext,
  }) : permissions = Set<String>.unmodifiable(permissions);

  final String? workspaceId;
  final String? actorId;
  final Set<String> permissions;

  /// Whether the session is at AAL2. Every platform mutation is AAL2-gated
  /// server-side (DEC-025); the UI reflects the gate instead of firing a
  /// doomed call.
  final bool canMutate;

  /// Set when the surface is embedded with a fixed entity context (the
  /// Property Workspace's `Betrieb → Aufgaben`): the list is scoped to this
  /// ref and the create dialog presets it read-only. Null on the
  /// workspace-wide destination.
  final PlatformEntityRef? lockedContext;

  bool get canRead => permissions.contains('task.read');
  bool get canManage => permissions.contains('task.manage');

  @override
  bool operator ==(Object other) {
    return other is TaskCenterScope &&
        other.workspaceId == workspaceId &&
        other.actorId == actorId &&
        other.canMutate == canMutate &&
        other.lockedContext == lockedContext &&
        other.permissions.length == permissions.length &&
        other.permissions.containsAll(permissions);
  }

  @override
  int get hashCode => Object.hash(
    workspaceId,
    actorId,
    canMutate,
    lockedContext,
    Object.hashAllUnordered(permissions),
  );
}

/// The complete set of list controls the Task Center offers, each named with
/// the `TaskListQuery` field that serves it. This registry is deliberately
/// data, not prose: the §17 pretense-regression test iterates it and fails
/// when a control has no server-side counterpart — and the widget tests
/// assert the surface offers nothing beyond it.
const List<({String control, String queryField})> taskCenterOfferedFilters = [
  (control: 'status', queryField: 'statuses'),
  (control: 'assignedToMe', queryField: 'assignedTo'),
  (control: 'includeArchived', queryField: 'includeArchived'),
  (control: 'lockedContext', queryField: 'entity'),
];

/// The filter state of the surface — exactly the server-covered subset
/// (`task_center.md` §11). No due range, no priority, no multi-status, no
/// text: those are `TASK-QUERY-01` and deliberately not representable here.
class TaskCenterFilters {
  const TaskCenterFilters({
    this.status = TaskStatus.open,
    this.assignedToMe = false,
    this.includeArchived = false,
    this.context,
  });

  /// One lifecycle state or null for "Alle" (no filter). Defaults to `open`:
  /// "Alle offenen Aufgaben" is the only default the contract fully covers.
  final TaskStatus? status;

  /// True maps to `assignedTo = actorId` ("Mir zugewiesen"); a person picker
  /// is B6 (`TASK-ASSIGNEE-DIRECTORY-01`).
  final bool assignedToMe;

  final bool includeArchived;

  /// The locked entity context of an embedded surface; never user-editable
  /// in V1 (a free context picker needs the name resolution of
  /// `TASK-QUERY-01`).
  final PlatformEntityRef? context;

  bool get isDefault =>
      status == TaskStatus.open && !assignedToMe && !includeArchived;

  TaskCenterFilters copyWith({
    Object? status = _unchanged,
    bool? assignedToMe,
    bool? includeArchived,
  }) {
    return TaskCenterFilters(
      status: identical(status, _unchanged) ? this.status : status as TaskStatus?,
      assignedToMe: assignedToMe ?? this.assignedToMe,
      includeArchived: includeArchived ?? this.includeArchived,
      context: context,
    );
  }

  /// The one place UI filter state becomes a server query. Every field of
  /// this class lands here; the pretense-regression test pins that this
  /// method consumes [taskCenterOfferedFilters] completely and nothing more.
  TaskListQuery toQuery({
    required String workspaceId,
    required String? actorId,
    PlatformPageRequest page = const PlatformPageRequest(),
    TaskStatus? statusOverride,
    bool? includeArchivedOverride,
  }) {
    final effectiveStatus = statusOverride ?? status;
    return TaskListQuery(
      workspaceId: workspaceId,
      statuses: effectiveStatus == null ? null : <TaskStatus>[effectiveStatus],
      assignedTo: assignedToMe ? actorId : null,
      includeArchived: includeArchivedOverride ?? includeArchived,
      entity: context,
      page: page,
    );
  }
}

enum TaskCenterListPhase { loading, ready, forbidden, error }

enum TaskCenterViewMode { list, board }

enum TaskDetailPhase { idle, loading, ready, notFound, forbidden, error }

enum TaskActionPhase { idle, submitting, succeeded, failed }

/// The four status-bound board columns (`task_center.md` §5, A9). Archived
/// never appears on the board.
const List<TaskStatus> taskBoardStatuses = <TaskStatus>[
  TaskStatus.open,
  TaskStatus.inProgress,
  TaskStatus.blocked,
  TaskStatus.done,
];

class TaskBoardColumn {
  const TaskBoardColumn({
    this.phase = TaskCenterListPhase.loading,
    this.tasks = const <TaskDto>[],
    this.nextCursor,
    this.loadingMore = false,
    this.message,
  });

  final TaskCenterListPhase phase;
  final List<TaskDto> tasks;
  final String? nextCursor;
  final bool loadingMore;
  final String? message;

  TaskBoardColumn copyWith({
    TaskCenterListPhase? phase,
    List<TaskDto>? tasks,
    Object? nextCursor = _unchanged,
    bool? loadingMore,
    Object? message = _unchanged,
  }) {
    return TaskBoardColumn(
      phase: phase ?? this.phase,
      tasks: tasks ?? this.tasks,
      nextCursor: identical(nextCursor, _unchanged)
          ? this.nextCursor
          : nextCursor as String?,
      loadingMore: loadingMore ?? this.loadingMore,
      message: identical(message, _unchanged)
          ? this.message
          : message as String?,
    );
  }
}

/// The classified result of one bulk row (`task_center.md` §6.9): the report
/// separates version conflicts and disallowed transitions from other
/// failures, because they demand different follow-up.
enum TaskBulkFailureKind { versionConflict, invalidTransition, failed }

class TaskBulkFailureEntry {
  const TaskBulkFailureEntry({
    required this.task,
    required this.kind,
    required this.message,
  });

  final TaskDto task;
  final TaskBulkFailureKind kind;
  final String message;
}

class TaskBulkReport {
  const TaskBulkReport({
    required this.total,
    required this.succeeded,
    required this.failures,
    required this.cancelled,
  });

  final int total;
  final int succeeded;
  final List<TaskBulkFailureEntry> failures;

  /// True when the user aborted mid-run; unprocessed rows are simply not in
  /// the report rather than counted as failures.
  final bool cancelled;

  int countOf(TaskBulkFailureKind kind) =>
      failures.where((entry) => entry.kind == kind).length;
}

/// The bulk actions of §6.9 — status transitions to unambiguous targets plus
/// the two self-assignment edits. `blocked` is deliberately absent: §6.3
/// requires an individual reason per blocker, which a mass action cannot
/// honestly provide. "An Person X zuweisen" is B6; "Fälligkeit setzen" stays
/// out until a due view exists (B1).
enum TaskBulkAction {
  start('Starten', TaskStatus.inProgress),
  complete('Erledigt', TaskStatus.done),
  reopen('Zurück auf Offen', TaskStatus.open),
  archive('Archivieren', TaskStatus.archived),
  assignToMe('Mir zuweisen', null),
  unassign('Zuweisung entfernen', null);

  const TaskBulkAction(this.label, this.targetStatus);

  final String label;
  final TaskStatus? targetStatus;

  bool get isTransition => targetStatus != null;
}

/// Maximum rows per bulk run: there is no batch RPC, every row is its own
/// call with its own `mutationId` and `expectedVersion`.
const int taskBulkLimit = 50;

class TaskCenterState {
  const TaskCenterState({
    this.listPhase = TaskCenterListPhase.loading,
    this.tasks = const <TaskDto>[],
    this.nextCursor,
    this.loadingMore = false,
    this.refreshing = false,
    this.filters = const TaskCenterFilters(),
    this.viewMode = TaskCenterViewMode.list,
    this.board = const <TaskStatus, TaskBoardColumn>{},
    this.detailPhase = TaskDetailPhase.idle,
    this.selectedTask,
    this.detailMessage,
    this.selecting = false,
    this.selectedIds = const <String>{},
    this.bulkRunning = false,
    this.bulkDone = 0,
    this.bulkTotal = 0,
    this.bulkReport,
    this.actionPhase = TaskActionPhase.idle,
    this.actionMessage,
    this.liveUpdatesDegraded = false,
    this.message,
  });

  final TaskCenterListPhase listPhase;

  /// Accumulated keyset pages of the current filter set.
  final List<TaskDto> tasks;
  final String? nextCursor;
  final bool loadingMore;

  /// True while a background reload runs; visible data stays (§10
  /// `task-center-refreshing`).
  final bool refreshing;

  final TaskCenterFilters filters;
  final TaskCenterViewMode viewMode;
  final Map<TaskStatus, TaskBoardColumn> board;

  final TaskDetailPhase detailPhase;
  final TaskDto? selectedTask;
  final String? detailMessage;

  /// Bulk selection mode (§5: the checkbox column appears only after
  /// "Auswählen" is activated).
  final bool selecting;
  final Set<String> selectedIds;
  final bool bulkRunning;
  final int bulkDone;
  final int bulkTotal;
  final TaskBulkReport? bulkReport;

  final TaskActionPhase actionPhase;
  final String? actionMessage;

  final bool liveUpdatesDegraded;

  /// Message of a list-level failure (error/forbidden phases).
  final String? message;

  bool get hasActiveFilters => !filters.isDefault;

  TaskCenterState copyWith({
    TaskCenterListPhase? listPhase,
    List<TaskDto>? tasks,
    Object? nextCursor = _unchanged,
    bool? loadingMore,
    bool? refreshing,
    TaskCenterFilters? filters,
    TaskCenterViewMode? viewMode,
    Map<TaskStatus, TaskBoardColumn>? board,
    TaskDetailPhase? detailPhase,
    Object? selectedTask = _unchanged,
    Object? detailMessage = _unchanged,
    bool? selecting,
    Set<String>? selectedIds,
    bool? bulkRunning,
    int? bulkDone,
    int? bulkTotal,
    Object? bulkReport = _unchanged,
    TaskActionPhase? actionPhase,
    Object? actionMessage = _unchanged,
    bool? liveUpdatesDegraded,
    Object? message = _unchanged,
  }) {
    return TaskCenterState(
      listPhase: listPhase ?? this.listPhase,
      tasks: tasks ?? this.tasks,
      nextCursor: identical(nextCursor, _unchanged)
          ? this.nextCursor
          : nextCursor as String?,
      loadingMore: loadingMore ?? this.loadingMore,
      refreshing: refreshing ?? this.refreshing,
      filters: filters ?? this.filters,
      viewMode: viewMode ?? this.viewMode,
      board: board ?? this.board,
      detailPhase: detailPhase ?? this.detailPhase,
      selectedTask: identical(selectedTask, _unchanged)
          ? this.selectedTask
          : selectedTask as TaskDto?,
      detailMessage: identical(detailMessage, _unchanged)
          ? this.detailMessage
          : detailMessage as String?,
      selecting: selecting ?? this.selecting,
      selectedIds: selectedIds ?? this.selectedIds,
      bulkRunning: bulkRunning ?? this.bulkRunning,
      bulkDone: bulkDone ?? this.bulkDone,
      bulkTotal: bulkTotal ?? this.bulkTotal,
      bulkReport: identical(bulkReport, _unchanged)
          ? this.bulkReport
          : bulkReport as TaskBulkReport?,
      actionPhase: actionPhase ?? this.actionPhase,
      actionMessage: identical(actionMessage, _unchanged)
          ? this.actionMessage
          : actionMessage as String?,
      liveUpdatesDegraded: liveUpdatesDegraded ?? this.liveUpdatesDegraded,
      message: identical(message, _unchanged)
          ? this.message
          : message as String?,
    );
  }
}

class TaskCenterController extends StateNotifier<TaskCenterState> {
  TaskCenterController({
    required TaskRepository tasks,
    required TaskCenterScope scope,
    PlatformQueryInvalidationSource? invalidationSource,
    Duration invalidationCoalesceWindow = const Duration(milliseconds: 250),
    String Function()? idFactory,
  }) : _tasks = tasks,
       _scope = scope,
       _invalidationSource = invalidationSource,
       _coalesceWindow = invalidationCoalesceWindow,
       _idFactory = idFactory ?? const Uuid().v4,
       super(
         TaskCenterState(
           filters: TaskCenterFilters(context: scope.lockedContext),
         ),
       );

  final TaskRepository _tasks;
  final TaskCenterScope _scope;
  final PlatformQueryInvalidationSource? _invalidationSource;
  final Duration _coalesceWindow;
  final String Function() _idFactory;

  StreamSubscription<PlatformQueryInvalidation>? _invalidationSubscription;
  Timer? _invalidationTimer;
  int _generation = 0;
  bool _bulkCancelRequested = false;

  TaskCenterScope get scope => _scope;
  bool get canManage => _scope.canManage && _scope.canMutate;

  /// A fresh intent id for actions that are their own intent (a status
  /// transition, a quick assign). Dialogs create their own at open.
  String newMutationId() => _idFactory();

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    _subscribeToInvalidation(workspaceId);
    await reload();
  }

  /// Reloads the first page of the current view. With [background] set the
  /// visible content stays and only [TaskCenterState.refreshing] flips —
  /// a background refresh never blanks visible data (Foundation §11).
  Future<void> reload({bool background = false}) async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    final generation = ++_generation;
    if (state.viewMode == TaskCenterViewMode.board) {
      await _loadBoard(workspaceId, generation, background: background);
      return;
    }
    state = background
        ? state.copyWith(refreshing: true)
        : state.copyWith(listPhase: TaskCenterListPhase.loading, message: null);
    final result = await _tasks.searchTasks(
      state.filters.toQuery(workspaceId: workspaceId, actorId: _scope.actorId),
    );
    if (generation != _generation || !mounted) {
      return;
    }
    switch (result) {
      case PlatformRepositoryFailure<PlatformPageResult<TaskDto>>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          listPhase: kind == PlatformRepositoryFailureKind.forbidden
              ? TaskCenterListPhase.forbidden
              : TaskCenterListPhase.error,
          tasks: const <TaskDto>[],
          nextCursor: null,
          refreshing: false,
          message: message,
        );
      case PlatformRepositorySuccess<PlatformPageResult<TaskDto>>(
        :final value,
      ):
        state = state.copyWith(
          listPhase: TaskCenterListPhase.ready,
          tasks: value.items,
          nextCursor: value.nextCursor,
          refreshing: false,
          message: null,
          selectedIds: state.selectedIds
              .where((id) => value.items.any((task) => task.id == id))
              .toSet(),
        );
    }
  }

  Future<void> loadMore() async {
    final workspaceId = _scope.workspaceId;
    final cursor = state.nextCursor;
    if (workspaceId == null || cursor == null || state.loadingMore) {
      return;
    }
    final generation = _generation;
    state = state.copyWith(loadingMore: true);
    final result = await _tasks.searchTasks(
      state.filters.toQuery(
        workspaceId: workspaceId,
        actorId: _scope.actorId,
        page: PlatformPageRequest(cursor: cursor),
      ),
    );
    if (generation != _generation || !mounted) {
      return;
    }
    switch (result) {
      case PlatformRepositoryFailure<PlatformPageResult<TaskDto>>(
        :final message,
      ):
        state = state.copyWith(loadingMore: false, actionMessage: message);
      case PlatformRepositorySuccess<PlatformPageResult<TaskDto>>(
        :final value,
      ):
        state = state.copyWith(
          loadingMore: false,
          tasks: <TaskDto>[...state.tasks, ...value.items],
          nextCursor: value.nextCursor,
        );
    }
  }

  Future<void> _loadBoard(
    String workspaceId,
    int generation, {
    bool background = false,
  }) async {
    if (!background) {
      state = state.copyWith(
        board: <TaskStatus, TaskBoardColumn>{
          for (final status in taskBoardStatuses) status: const TaskBoardColumn(),
        },
        refreshing: false,
      );
    } else {
      state = state.copyWith(refreshing: true);
    }
    // Four independent status-bound keysets (A9), loaded concurrently; each
    // column carries its own phase so one broken read never blanks the rest.
    await Future.wait(<Future<void>>[
      for (final status in taskBoardStatuses)
        _loadBoardColumn(workspaceId, status, generation),
    ]);
    if (generation == _generation && mounted) {
      state = state.copyWith(refreshing: false);
    }
  }

  Future<void> _loadBoardColumn(
    String workspaceId,
    TaskStatus status,
    int generation,
  ) async {
    final result = await _tasks.searchTasks(
      state.filters.toQuery(
        workspaceId: workspaceId,
        actorId: _scope.actorId,
        statusOverride: status,
        // The board never shows archived; the toggle only affects the list.
        includeArchivedOverride: false,
      ),
    );
    if (generation != _generation || !mounted) {
      return;
    }
    final column = switch (result) {
      PlatformRepositoryFailure<PlatformPageResult<TaskDto>>(
        :final kind,
        :final message,
      ) =>
        TaskBoardColumn(
          phase: kind == PlatformRepositoryFailureKind.forbidden
              ? TaskCenterListPhase.forbidden
              : TaskCenterListPhase.error,
          message: message,
        ),
      PlatformRepositorySuccess<PlatformPageResult<TaskDto>>(:final value) =>
        TaskBoardColumn(
          phase: TaskCenterListPhase.ready,
          tasks: value.items,
          nextCursor: value.nextCursor,
        ),
    };
    state = state.copyWith(
      board: <TaskStatus, TaskBoardColumn>{...state.board, status: column},
    );
  }

  Future<void> loadMoreInColumn(TaskStatus status) async {
    final workspaceId = _scope.workspaceId;
    final column = state.board[status];
    final cursor = column?.nextCursor;
    if (workspaceId == null ||
        column == null ||
        cursor == null ||
        column.loadingMore) {
      return;
    }
    final generation = _generation;
    state = state.copyWith(
      board: <TaskStatus, TaskBoardColumn>{
        ...state.board,
        status: column.copyWith(loadingMore: true),
      },
    );
    final result = await _tasks.searchTasks(
      state.filters.toQuery(
        workspaceId: workspaceId,
        actorId: _scope.actorId,
        statusOverride: status,
        includeArchivedOverride: false,
        page: PlatformPageRequest(cursor: cursor),
      ),
    );
    if (generation != _generation || !mounted) {
      return;
    }
    final current = state.board[status] ?? column;
    final next = switch (result) {
      PlatformRepositoryFailure<PlatformPageResult<TaskDto>>(:final message) =>
        current.copyWith(loadingMore: false, message: message),
      PlatformRepositorySuccess<PlatformPageResult<TaskDto>>(:final value) =>
        current.copyWith(
          loadingMore: false,
          tasks: <TaskDto>[...current.tasks, ...value.items],
          nextCursor: value.nextCursor,
        ),
    };
    state = state.copyWith(
      board: <TaskStatus, TaskBoardColumn>{...state.board, status: next},
    );
  }

  // ---------------------------------------------------------------------------
  // Filters and view
  // ---------------------------------------------------------------------------

  Future<void> setStatusFilter(TaskStatus? status) async {
    state = state.copyWith(filters: state.filters.copyWith(status: status));
    await reload();
  }

  Future<void> setAssignedToMe(bool value) async {
    state = state.copyWith(
      filters: state.filters.copyWith(assignedToMe: value),
    );
    await reload();
  }

  Future<void> setIncludeArchived(bool value) async {
    state = state.copyWith(
      filters: state.filters.copyWith(includeArchived: value),
    );
    await reload();
  }

  Future<void> resetFilters() async {
    state = state.copyWith(
      filters: TaskCenterFilters(context: _scope.lockedContext),
    );
    await reload();
  }

  Future<void> setViewMode(TaskCenterViewMode mode) async {
    if (mode == state.viewMode) {
      return;
    }
    // Bulk selection is a list concept; leaving the list drops it.
    state = state.copyWith(
      viewMode: mode,
      selecting: false,
      selectedIds: const <String>{},
    );
    await reload();
  }

  // ---------------------------------------------------------------------------
  // Detail
  // ---------------------------------------------------------------------------

  void select(TaskDto task) {
    state = state.copyWith(
      detailPhase: TaskDetailPhase.ready,
      selectedTask: task,
      detailMessage: null,
    );
  }

  /// Deep-link entry (`/tasks/:taskId`): the task may not be on the first
  /// page, so it is read canonically by id.
  Future<void> openById(String taskId) async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    state = state.copyWith(
      detailPhase: TaskDetailPhase.loading,
      selectedTask: null,
      detailMessage: null,
    );
    final result = await _tasks.getTaskById(
      workspaceId: workspaceId,
      taskId: taskId,
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case PlatformRepositoryFailure<TaskDto>(:final kind, :final message):
        state = state.copyWith(
          detailPhase: switch (kind) {
            PlatformRepositoryFailureKind.notFound => TaskDetailPhase.notFound,
            PlatformRepositoryFailureKind.forbidden =>
              TaskDetailPhase.forbidden,
            _ => TaskDetailPhase.error,
          },
          detailMessage: message,
        );
      case PlatformRepositorySuccess<TaskDto>(:final value):
        state = state.copyWith(
          detailPhase: TaskDetailPhase.ready,
          selectedTask: value,
          detailMessage: null,
        );
    }
  }

  void closeDetail() {
    state = state.copyWith(
      detailPhase: TaskDetailPhase.idle,
      selectedTask: null,
      detailMessage: null,
    );
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  PlatformCommandContext? _commandContext({
    required String mutationId,
    String? reason,
  }) {
    final workspaceId = _scope.workspaceId;
    final actorId = _scope.actorId;
    if (workspaceId == null || actorId == null) {
      return null;
    }
    return PlatformCommandContext(
      workspaceId: workspaceId,
      actorId: actorId,
      mutationId: mutationId,
      correlationId: _idFactory(),
      reason: reason,
    );
  }

  static const PlatformRepositoryFailure<TaskDto> _noSessionFailure =
      PlatformRepositoryFailure<TaskDto>(
        kind: PlatformRepositoryFailureKind.forbidden,
        message: 'Kein aktiver Arbeitsbereich.',
      );

  /// Creates a task. Returns null on success (the caller's dialog closes)
  /// and the classified failure otherwise, so the dialog can keep input
  /// alive and map it per Shared §12. [mutationId] is the caller's intent id,
  /// created when its dialog opened.
  Future<PlatformRepositoryFailure<TaskDto>?> createTask({
    required TaskDraft draft,
    required String mutationId,
    required String reason,
  }) async {
    final context = _commandContext(mutationId: mutationId, reason: reason);
    if (context == null) {
      return _noSessionFailure;
    }
    final result = await _tasks.createTask(
      CreateTaskCommand(context: context, draft: draft),
    );
    switch (result) {
      case PlatformRepositoryFailure<TaskDto>():
        return result;
      case PlatformRepositorySuccess<TaskDto>(:final value):
        if (mounted) {
          state = state.copyWith(
            detailPhase: TaskDetailPhase.ready,
            selectedTask: value,
            actionPhase: TaskActionPhase.succeeded,
            actionMessage: 'Aufgabe angelegt.',
          );
          await reload(background: true);
        }
        return null;
    }
  }

  /// Edits mutable fields (§6.2). Same outcome contract as [createTask]; a
  /// `version_conflict` failure carries the server's `current_entity` for
  /// the dialog's reseed affordance.
  Future<PlatformRepositoryFailure<TaskDto>?> updateTask({
    required String taskId,
    required int expectedVersion,
    required TaskUpdateDto changes,
    required String mutationId,
    required String reason,
  }) async {
    final context = _commandContext(mutationId: mutationId, reason: reason);
    if (context == null) {
      return _noSessionFailure;
    }
    final result = await _tasks.updateTask(
      UpdateTaskCommand(
        context: context,
        taskId: taskId,
        expectedVersion: expectedVersion,
        changes: changes,
      ),
    );
    switch (result) {
      case PlatformRepositoryFailure<TaskDto>():
        return result;
      case PlatformRepositorySuccess<TaskDto>(:final value):
        if (mounted) {
          _replaceTask(value);
          state = state.copyWith(
            actionPhase: TaskActionPhase.succeeded,
            actionMessage: 'Aufgabe gespeichert.',
          );
          await reload(background: true);
        }
        return null;
    }
  }

  /// Moves a task along STM-012. [reason] is mandatory for `blocked`
  /// (§6.3) and carries the bulk label for mass actions (§12).
  Future<PlatformRepositoryFailure<TaskDto>?> transitionStatus({
    required TaskDto task,
    required TaskStatus target,
    required String mutationId,
    String? reason,
  }) async {
    final context = _commandContext(mutationId: mutationId, reason: reason);
    if (context == null) {
      return _noSessionFailure;
    }
    final result = await _tasks.transitionTaskStatus(
      TransitionTaskStatusCommand(
        context: context,
        taskId: task.id,
        expectedVersion: task.version,
        targetStatus: target,
      ),
    );
    switch (result) {
      case PlatformRepositoryFailure<TaskDto>():
        return result;
      case PlatformRepositorySuccess<TaskDto>(:final value):
        if (mounted) {
          _replaceTask(value);
          state = state.copyWith(
            actionPhase: TaskActionPhase.succeeded,
            actionMessage: target == TaskStatus.archived
                ? 'Aufgabe archiviert.'
                : 'Status aktualisiert.',
          );
          await reload(background: true);
        }
        return null;
    }
  }

  /// "Mir zuweisen" / "Zuweisung entfernen" (§6.4) — the only assignment
  /// edits V1 offers; assigning others is B6.
  Future<PlatformRepositoryFailure<TaskDto>?> setAssignedToSelf({
    required TaskDto task,
    required bool assigned,
    required String mutationId,
    String? reason,
  }) {
    final actorId = _scope.actorId;
    if (actorId == null) {
      return Future.value(_noSessionFailure);
    }
    return updateTask(
      taskId: task.id,
      expectedVersion: task.version,
      changes: TaskUpdateDto(
        assignedTo: assigned
            ? TaskFieldEdit<String>.set(actorId)
            : const TaskFieldEdit<String>.clear(),
      ),
      mutationId: mutationId,
      reason: reason ?? (assigned ? 'Mir zugewiesen' : 'Zuweisung entfernt'),
    );
  }

  /// Replaces [task] wherever the current view holds it, so the surface
  /// reflects a mutation immediately while the background reload confirms it.
  void _replaceTask(TaskDto task) {
    state = state.copyWith(
      tasks: <TaskDto>[
        for (final existing in state.tasks)
          if (existing.id == task.id) task else existing,
      ],
      board: <TaskStatus, TaskBoardColumn>{
        for (final entry in state.board.entries)
          entry.key: entry.value.copyWith(
            tasks: <TaskDto>[
              for (final existing in entry.value.tasks)
                if (existing.id == task.id) task else existing,
            ],
          ),
      },
      selectedTask: state.selectedTask?.id == task.id
          ? task
          : state.selectedTask,
      detailPhase: state.selectedTask?.id == task.id
          ? TaskDetailPhase.ready
          : state.detailPhase,
    );
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: TaskActionPhase.idle,
      actionMessage: null,
    );
  }

  // ---------------------------------------------------------------------------
  // Bulk (§6.9)
  // ---------------------------------------------------------------------------

  void setSelecting(bool value) {
    state = state.copyWith(
      selecting: value,
      selectedIds: value ? state.selectedIds : const <String>{},
    );
  }

  void toggleSelected(String taskId) {
    final selected = Set<String>.of(state.selectedIds);
    if (selected.contains(taskId)) {
      selected.remove(taskId);
    } else {
      if (selected.length >= taskBulkLimit) {
        state = state.copyWith(
          actionPhase: TaskActionPhase.failed,
          actionMessage:
              'Maximal $taskBulkLimit Aufgaben je Massenaktion — jede Zeile '
              'ist ein eigener Serveraufruf.',
        );
        return;
      }
      selected.add(taskId);
    }
    state = state.copyWith(selectedIds: selected);
  }

  void cancelBulk() {
    _bulkCancelRequested = true;
  }

  void dismissBulkReport() {
    state = state.copyWith(bulkReport: null);
  }

  /// Runs [action] over the selected rows: N individual RPCs, each with its
  /// own `mutationId` and the row's own `expectedVersion`, then the partial
  /// success report. Disallowed transitions are skipped client-side — the
  /// server would reject them identically, and the report names them.
  Future<TaskBulkReport?> runBulk(TaskBulkAction action) async {
    if (state.bulkRunning) {
      return null;
    }
    final rows = state.tasks
        .where((task) => state.selectedIds.contains(task.id))
        .toList(growable: false);
    if (rows.isEmpty || rows.length > taskBulkLimit) {
      return null;
    }
    _bulkCancelRequested = false;
    state = state.copyWith(
      bulkRunning: true,
      bulkDone: 0,
      bulkTotal: rows.length,
      bulkReport: null,
    );
    final reason = 'Massenaktion: ${action.label}';
    var succeeded = 0;
    var cancelled = false;
    final failures = <TaskBulkFailureEntry>[];
    for (final task in rows) {
      if (_bulkCancelRequested) {
        cancelled = true;
        break;
      }
      final target = action.targetStatus;
      if (target != null && !task.status.canTransitionTo(target)) {
        failures.add(
          TaskBulkFailureEntry(
            task: task,
            kind: TaskBulkFailureKind.invalidTransition,
            message:
                'Statuswechsel „${task.status.wireName} → ${target.wireName}“ '
                'ist nicht zulässig.',
          ),
        );
        if (mounted) {
          state = state.copyWith(bulkDone: state.bulkDone + 1);
        }
        continue;
      }
      final failure = target != null
          ? await transitionStatus(
              task: task,
              target: target,
              mutationId: _idFactory(),
              reason: reason,
            )
          : await setAssignedToSelf(
              task: task,
              assigned: action == TaskBulkAction.assignToMe,
              mutationId: _idFactory(),
              reason: reason,
            );
      if (failure == null) {
        succeeded++;
      } else {
        failures.add(
          TaskBulkFailureEntry(
            task: task,
            kind: failure.kind == PlatformRepositoryFailureKind.versionConflict
                ? TaskBulkFailureKind.versionConflict
                : TaskBulkFailureKind.failed,
            message: failure.message,
          ),
        );
      }
      if (mounted) {
        state = state.copyWith(bulkDone: state.bulkDone + 1);
      }
    }
    final report = TaskBulkReport(
      total: rows.length,
      succeeded: succeeded,
      failures: List<TaskBulkFailureEntry>.unmodifiable(failures),
      cancelled: cancelled,
    );
    if (mounted) {
      state = state.copyWith(
        bulkRunning: false,
        bulkReport: report,
        selecting: false,
        selectedIds: const <String>{},
        // The per-row successes each queued a background reload; one more
        // explicit pass keeps the final picture canonical.
        actionPhase: TaskActionPhase.idle,
        actionMessage: null,
      );
      await reload(background: true);
    }
    return report;
  }

  // ---------------------------------------------------------------------------
  // Realtime
  // ---------------------------------------------------------------------------

  void _subscribeToInvalidation(String workspaceId) {
    final source = _invalidationSource;
    if (source == null || _invalidationSubscription != null) {
      return;
    }
    _invalidationSubscription = source
        .watchWorkspace(workspaceId: workspaceId)
        .listen(
          (invalidation) {
            if (invalidation.workspaceId != _scope.workspaceId) {
              return;
            }
            if (!invalidation.isReconciliation &&
                invalidation.aggregate != PlatformAggregate.task) {
              return;
            }
            if (mounted && state.liveUpdatesDegraded) {
              // The channel is delivering again; the passive notice
              // self-clears on the next signal (Foundation §13).
              state = state.copyWith(liveUpdatesDegraded: false);
            }
            _scheduleInvalidationReload();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (mounted) {
              state = state.copyWith(liveUpdatesDegraded: true);
            }
          },
        );
  }

  /// Coalesces bursts — up to three reconcile signals after a full reconnect
  /// — into exactly one reload (§9).
  void _scheduleInvalidationReload() {
    _invalidationTimer?.cancel();
    _invalidationTimer = Timer(_coalesceWindow, () {
      unawaited(reload(background: true));
      final selected = state.selectedTask;
      if (selected != null && state.detailPhase == TaskDetailPhase.ready) {
        // The detail is canonical state, not an open form: refresh it by id
        // so a deleted/archived task surfaces as notFound instead of going
        // quietly stale. Open dialogs are never touched (§9).
        unawaited(openById(selected.id));
      }
    });
  }

  @override
  void dispose() {
    _invalidationTimer?.cancel();
    _invalidationTimer = null;
    unawaited(_invalidationSubscription?.cancel());
    _invalidationSubscription = null;
    super.dispose();
  }
}

final taskCenterControllerProvider = StateNotifierProvider.autoDispose
    .family<TaskCenterController, TaskCenterState, TaskCenterScope>((
      ref,
      scope,
    ) {
      final controller = TaskCenterController(
        tasks: ref.watch(taskRepositoryProvider),
        scope: scope,
        invalidationSource: ref.watch(platformQueryInvalidationSourceProvider),
      );
      unawaited(controller.load());
      return controller;
    });
