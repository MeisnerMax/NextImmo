import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/task_center_controller.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/platform_entity_type.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/task_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/presentation/task_center_screen.dart';

const String _actor = 'user-1';

TaskDto _task({
  String id = 'task-a',
  TaskStatus status = TaskStatus.open,
  String? assignedTo,
  PlatformEntityRef? entity,
  TaskPriority priority = TaskPriority.normal,
}) {
  return TaskDto(
    id: id,
    workspaceId: 'workspace-a',
    title: 'Aufgabe $id',
    priority: priority,
    status: status,
    createdAt: DateTime.utc(2026, 8, 1),
    updatedAt: DateTime.utc(2026, 8, 1),
    createdBy: _actor,
    updatedBy: _actor,
    version: 1,
    assignedTo: assignedTo,
    entity: entity,
  );
}

class _Calls {
  final List<TaskCenterViewMode> viewModes = <TaskCenterViewMode>[];
  final List<TaskDto> selected = <TaskDto>[];
  int reloads = 0;
  int loadMores = 0;
  int idCounter = 0;
}

Future<_Calls> _pump(
  WidgetTester tester,
  TaskCenterState state, {
  bool canManage = true,
  bool embedded = false,
  double width = 1440,
}) async {
  final calls = _Calls();
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TaskCenterView(
          state: state,
          embedded: embedded,
          actorId: _actor,
          canManage: canManage,
          now: DateTime(2026, 9, 3),
          onReload: () async => calls.reloads++,
          onLoadMore: () async => calls.loadMores++,
          onLoadMoreInColumn: (_) async {},
          onSetStatusFilter: (_) async {},
          onSetAssignedToMe: (_) async {},
          onSetIncludeArchived: (_) async {},
          onResetFilters: () async {},
          onSetViewMode: (mode) async => calls.viewModes.add(mode),
          onSelectTask: calls.selected.add,
          onCloseDetail: () {},
          onCreateSubmit: (draft, mutationId) async => null,
          onEditSubmit: (task, changes, expectedVersion, mutationId) async =>
              null,
          onTransition: (task, target, {required mutationId, reason}) async =>
              null,
          onAssignSelf: (task, assigned, mutationId) async => null,
          onSetSelecting: (_) {},
          onToggleSelected: (_) {},
          onRunBulk: (_) async => null,
          onCancelBulk: () {},
          onDismissBulkReport: () {},
          newMutationId: () => 'gen-${calls.idCounter++}',
        ),
      ),
    ),
  );
  await tester.pump();
  return calls;
}

TaskCenterState _ready(List<TaskDto> tasks, {String? nextCursor}) {
  return TaskCenterState(
    listPhase: TaskCenterListPhase.ready,
    tasks: tasks,
    nextCursor: nextCursor,
  );
}

void main() {
  testWidgets('offers nothing the contract does not carry '
      '(§17 pretense regression, widget half)', (tester) async {
    await _pump(tester, _ready(<TaskDto>[_task()]));

    // No search field anywhere on the surface (B3), no tab bar and no
    // templates entry of any kind (B9), no counters/KPIs (B5) and no sort
    // control — only the stated fixed order.
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    expect(find.textContaining('Vorlage'), findsNothing);
    expect(find.textContaining('Suche'), findsNothing);
    expect(find.byKey(const Key('task-center-sort-note')), findsOneWidget);
    expect(find.text('Neueste zuerst'), findsOneWidget);

    // What IS offered are exactly the contract-covered controls.
    expect(
      find.byKey(const Key('task-center-filter-status')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('task-center-filter-assigned')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('task-center-filter-archived')),
      findsOneWidget,
    );
  });

  testWidgets('renders the §10 states at their keys', (tester) async {
    await _pump(tester, const TaskCenterState());
    expect(find.byKey(const Key('task-center-loading')), findsOneWidget);

    await _pump(tester, _ready(const <TaskDto>[]));
    expect(find.byKey(const Key('task-center-empty')), findsOneWidget);
    expect(
      find.byKey(const Key('task-center-empty-create')),
      findsOneWidget,
    );

    await _pump(
      tester,
      const TaskCenterState(
        listPhase: TaskCenterListPhase.ready,
        filters: TaskCenterFilters(assignedToMe: true),
      ),
    );
    expect(find.byKey(const Key('task-center-no-match')), findsOneWidget);
    expect(
      find.byKey(const Key('task-center-reset-filters')),
      findsOneWidget,
    );

    await _pump(
      tester,
      const TaskCenterState(listPhase: TaskCenterListPhase.forbidden),
    );
    expect(find.byKey(const Key('task-center-forbidden')), findsOneWidget);
    expect(find.textContaining('(task.read)'), findsOneWidget);

    await _pump(
      tester,
      const TaskCenterState(
        listPhase: TaskCenterListPhase.error,
        message: 'Ausfall',
      ),
    );
    expect(find.byKey(const Key('task-center-error')), findsOneWidget);

    await _pump(tester, _ready(<TaskDto>[_task()], nextCursor: 'cursor'));
    expect(find.byKey(const Key('task-center-partial')), findsOneWidget);
    expect(find.byKey(const Key('task-center-load-more')), findsOneWidget);

    await _pump(
      tester,
      const TaskCenterState(liveUpdatesDegraded: true, listPhase: TaskCenterListPhase.ready, tasks: <TaskDto>[]),
    );
    expect(
      find.byKey(const Key('task-center-live-degraded')),
      findsOneWidget,
    );
  });

  testWidgets('detail: "Erledigt" absent at open, edit disabled at archived '
      '(§6.2/§6.3)', (tester) async {
    final openTask = _task();
    await _pump(
      tester,
      _ready(<TaskDto>[openTask]).copyWith(
        detailPhase: TaskDetailPhase.ready,
        selectedTask: openTask,
      ),
    );
    expect(find.byKey(const Key('task-detail')), findsOneWidget);
    expect(
      find.byKey(const Key('task-detail-action-in_progress')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('task-detail-action-done')), findsNothing);
    final edit = tester.widget<OutlinedButton>(
      find.byKey(const Key('task-detail-edit')),
    );
    expect(edit.onPressed, isNotNull);

    final archivedTask = _task(id: 'task-b', status: TaskStatus.archived);
    await _pump(
      tester,
      _ready(<TaskDto>[archivedTask]).copyWith(
        detailPhase: TaskDetailPhase.ready,
        selectedTask: archivedTask,
      ),
    );
    final editArchived = tester.widget<OutlinedButton>(
      find.byKey(const Key('task-detail-edit')),
    );
    expect(editArchived.onPressed, isNull);
    // Archived is terminal: no transition actions at all.
    expect(
      find.byKey(const Key('task-detail-action-in_progress')),
      findsNothing,
    );
  });

  testWidgets('without task.manage the primary action is disabled with a '
      'tooltip and bulk is hidden (§8)', (tester) async {
    await _pump(tester, _ready(<TaskDto>[_task()]), canManage: false);

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('task-center-new')),
    );
    expect(button.onPressed, isNull);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == 'Benötigt task.manage',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('task-center-select-toggle')),
      findsNothing,
    );
  });

  testWidgets('never renders a raw UUID (§7, acceptance 3)', (tester) async {
    const uuid = '0b7cf3a2-9df5-4f6e-9a41-1c2d3e4f5a6b';
    final task = _task(
      assignedTo: uuid,
      entity: const PlatformEntityRef(
        type: PlatformEntityType.lease,
        id: 'e57f2b19-1234-4c00-9d0e-aa41bb52cc63',
      ),
    );
    await _pump(
      tester,
      _ready(<TaskDto>[task]).copyWith(
        detailPhase: TaskDetailPhase.ready,
        selectedTask: task,
      ),
    );

    expect(find.textContaining(uuid), findsNothing);
    expect(find.textContaining('e57f2b19'), findsNothing);
    expect(find.text('Vertrag'), findsWidgets);
    expect(find.textContaining('Zugewiesen'), findsWidgets);
  });

  testWidgets('the board shows loaded counts with "+" and per-column '
      'load-more; mobile hides it entirely (§5)', (tester) async {
    final boardState = TaskCenterState(
      listPhase: TaskCenterListPhase.ready,
      viewMode: TaskCenterViewMode.board,
      board: <TaskStatus, TaskBoardColumn>{
        TaskStatus.open: TaskBoardColumn(
          phase: TaskCenterListPhase.ready,
          tasks: <TaskDto>[_task(id: 'open-1'), _task(id: 'open-2')],
          nextCursor: 'more',
        ),
        TaskStatus.inProgress: const TaskBoardColumn(
          phase: TaskCenterListPhase.ready,
        ),
        TaskStatus.blocked: const TaskBoardColumn(
          phase: TaskCenterListPhase.ready,
        ),
        TaskStatus.done: const TaskBoardColumn(
          phase: TaskCenterListPhase.ready,
        ),
      },
    );
    await _pump(tester, boardState);

    expect(find.byKey(const Key('task-center-board')), findsOneWidget);
    // Loaded count plus "+" while another page exists — never a total.
    expect(find.text('Offen (2+)'), findsOneWidget);
    expect(find.text('Erledigt (0)'), findsOneWidget);
    expect(
      find.byKey(const Key('task-center-board-more-open')),
      findsOneWidget,
    );

    final calls = await _pump(tester, boardState, width: 390);
    await tester.pump();
    expect(find.byKey(const Key('task-center-board')), findsNothing);
    expect(find.byKey(const Key('task-center-view-toggle')), findsNothing);
    expect(calls.viewModes, contains(TaskCenterViewMode.list));
  });

  testWidgets('the embedded property variant states its honest scope (§3)', (
    tester,
  ) async {
    await _pump(
      tester,
      const TaskCenterState(
        listPhase: TaskCenterListPhase.ready,
        filters: TaskCenterFilters(
          context: PlatformEntityRef(
            type: PlatformEntityType.property,
            id: 'property-1',
          ),
        ),
      ),
      embedded: true,
    );

    expect(
      find.text('Zeigt Aufgaben, die direkt an diesem Objekt hängen.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('bulk overlay reports partial success in the §6.9 wording', (
    tester,
  ) async {
    final failures = <TaskBulkFailureEntry>[
      TaskBulkFailureEntry(
        task: _task(id: 'conflict-1'),
        kind: TaskBulkFailureKind.versionConflict,
        message: 'Task version is stale',
      ),
      TaskBulkFailureEntry(
        task: _task(id: 'invalid-1'),
        kind: TaskBulkFailureKind.invalidTransition,
        message: 'Statuswechsel nicht zulässig.',
      ),
    ];
    await _pump(
      tester,
      _ready(<TaskDto>[_task()]).copyWith(
        bulkReport: TaskBulkReport(
          total: 42,
          succeeded: 38,
          failures: failures + failures,
          cancelled: false,
        ),
      ),
    );

    expect(
      find.byKey(const Key('task-center-bulk-overlay')),
      findsOneWidget,
    );
    expect(
      find.textContaining('38 von 42 aktualisiert.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('2 Versionskonflikte, 2 unzulässige Statuswechsel'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('task-center-bulk-failed-only')),
      findsOneWidget,
    );
  });
}
