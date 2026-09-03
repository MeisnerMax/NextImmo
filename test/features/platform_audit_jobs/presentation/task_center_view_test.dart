import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/task_center_controller.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/platform_entity_type.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/task_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/presentation/task_center_screen.dart';
import 'package:neximmo_app/features/platform_audit_jobs/presentation/widgets/task_row.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

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
  final List<String> toggled = <String>[];
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
  double height = 900,
  bool dark = false,
}) async {
  final calls = _Calls();
  await tester.binding.setSurfaceSize(Size(width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
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
          onToggleSelected: calls.toggled.add,
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

  group('mobile foundation parity (§5)', () {
    testWidgets('at 390 px the list is the ListTile fallback with '
        'chevron_right, never the desktop row', (tester) async {
      final task = _task(
        assignedTo: _actor,
        entity: const PlatformEntityRef(
          type: PlatformEntityType.property,
          id: 'property-1',
        ),
        priority: TaskPriority.high,
      );
      final calls = await _pump(
        tester,
        _ready(<TaskDto>[task]),
        width: 390,
        height: 844,
      );

      // Foundation §6: the primary list falls back to a ListTile list with a
      // chevron on mobile; the desktop row layout is not squeezed in.
      expect(
        find.byKey(const Key('task-mobile-row-task-a')),
        findsOneWidget,
      );
      expect(find.byType(TaskRow), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsWidgets);
      expect(find.byKey(const Key('task-center-view-toggle')), findsNothing);

      // The tile carries the §15 text signals and opens the same detail.
      expect(find.textContaining('Offen'), findsWidgets);
      await tester.tap(find.byKey(const Key('task-mobile-row-task-a')));
      await tester.pump();
      expect(calls.selected.map((selected) => selected.id), contains('task-a'));
    });

    testWidgets('at 390 px selecting keeps the bulk semantics on the '
        'mobile tiles', (tester) async {
      final tasks = <TaskDto>[_task(id: 'task-a'), _task(id: 'task-b')];
      final calls = await _pump(
        tester,
        _ready(tasks).copyWith(
          selecting: true,
          selectedIds: <String>{'task-b'},
        ),
        width: 390,
        height: 844,
      );

      expect(
        find.byKey(const Key('task-mobile-check-task-a')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('task-mobile-row-task-a')));
      await tester.pump();
      expect(calls.toggled, contains('task-a'));
      expect(calls.selected, isEmpty);
    });

    testWidgets('the 320 px floor holds with long real-world data', (
      tester,
    ) async {
      final long = TaskDto(
        id: 'task-long',
        workspaceId: 'workspace-a',
        title:
            'Rauchwarnmelderprüfung in sämtlichen Wohneinheiten des '
            'Gebäudeteils B inklusive Dokumentation der Prüfergebnisse und '
            'Nachverfolgung aller festgestellten Mängel im Bestand',
        priority: TaskPriority.high,
        status: TaskStatus.inProgress,
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
        createdBy: _actor,
        updatedBy: _actor,
        version: 1,
        category: 'sonderpruefung-brandschutz-turnus-2026',
        assignedTo: '0b7cf3a2-9df5-4f6e-9a41-1c2d3e4f5a6b',
        dueAt: DateTime(2026, 8, 15),
        entity: const PlatformEntityRef(
          type: PlatformEntityType.maintenanceTicket,
          id: 'ticket-1',
        ),
      );
      await _pump(
        tester,
        _ready(<TaskDto>[long], nextCursor: 'more'),
        width: 320,
        height: 700,
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('task-mobile-row-task-long')),
        findsOneWidget,
      );
    });
  });

  group('responsive matrix (§17)', () {
    const viewports = <Size>[
      Size(320, 700),
      Size(390, 844),
      Size(1024, 768),
      Size(1440, 900),
    ];
    for (final size in viewports) {
      for (final dark in <bool>[false, true]) {
        testWidgets(
          'renders without overflow at ${size.width.toInt()} px '
          '(${dark ? 'dark' : 'light'})',
          (tester) async {
            final task = _task(
              assignedTo: _actor,
              entity: const PlatformEntityRef(
                type: PlatformEntityType.property,
                id: 'property-1',
              ),
              priority: TaskPriority.high,
            );
            await _pump(
              tester,
              _ready(<TaskDto>[task], nextCursor: 'more'),
              width: size.width,
              height: size.height,
              dark: dark,
            );

            expect(tester.takeException(), isNull);
            final mobile = size.width <= 767;
            if (mobile) {
              expect(
                find.byKey(const Key('task-mobile-row-task-a')),
                findsOneWidget,
              );
              expect(find.byType(TaskRow), findsNothing);
              expect(
                find.byKey(const Key('task-center-view-toggle')),
                findsNothing,
              );
            } else {
              expect(find.byType(TaskRow), findsWidgets);
              expect(
                find.byKey(const Key('task-mobile-row-task-a')),
                findsNothing,
              );
              expect(
                find.byKey(const Key('task-center-view-toggle')),
                findsOneWidget,
              );
            }
          },
        );
      }
    }

    testWidgets('1024 px narrow mode replaces the list with the detail and '
        'a back affordance', (tester) async {
      final task = _task();
      await _pump(
        tester,
        _ready(<TaskDto>[task]).copyWith(
          detailPhase: TaskDetailPhase.ready,
          selectedTask: task,
        ),
        width: 1024,
        height: 768,
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('task-detail')), findsOneWidget);
      expect(find.text('Zur Liste'), findsOneWidget);
      expect(find.byType(TaskRow), findsNothing);
    });

    testWidgets('1440 px shows list and detail side by side', (tester) async {
      final task = _task();
      await _pump(
        tester,
        _ready(<TaskDto>[task]).copyWith(
          detailPhase: TaskDetailPhase.ready,
          selectedTask: task,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('task-detail')), findsOneWidget);
      expect(find.byType(TaskRow), findsWidgets);
      expect(find.text('Zur Liste'), findsNothing);
    });
  });
}
