import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_providers.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/platform_entity_type.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/task_dto.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart'
    as portfolio;
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';
import 'package:neximmo_app/ui/screens/tasks/operational_tasks_panel.dart';

const _workspace = 'workspace-a';
const _actor = 'actor-a';
const _propertyId = 'property-a';

void main() {
  testWidgets('renders an empty cloud Task workplace', (tester) async {
    await _pump(tester);

    expect(find.text('Noch keine Aufgaben'), findsOneWidget);
    expect(find.text('Aufgabe anlegen'), findsWidgets);
  });

  testWidgets('forbidden read names the task.read permission', (tester) async {
    await _pump(
      tester,
      searchFailure: PlatformRepositoryFailureKind.forbidden,
    );

    expect(find.text('Kein Zugriff auf Aufgaben'), findsOneWidget);
    expect(find.textContaining('task.read'), findsOneWidget);
  });

  testWidgets('ready state shows NexImmo context, attention and filters', (
    tester,
  ) async {
    await _pump(
      tester,
      tasks: <TaskDto>[
        _task(
          'task-a',
          title: 'Dach prüfen',
          priority: TaskPriority.high,
          assignedTo: _actor,
          dueAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
          entity: const PlatformEntityRef(
            type: PlatformEntityType.property,
            id: _propertyId,
          ),
        ),
      ],
      properties: const <PropertySummaryDto>[_property],
    );

    expect(find.text('Dach prüfen'), findsWidgets);
    expect(find.text('Hotel Test'), findsWidgets);
    expect(find.text('Hoch'), findsWidgets);
    expect(find.textContaining('Überfällig'), findsWidgets);
    expect(find.text('Attention'), findsOneWidget);
    expect(find.text('Zuweisung'), findsOneWidget);
    expect(find.text('Kontext'), findsWidgets);
  });

  testWidgets('task.manage gates mutations without hiding readable work', (
    tester,
  ) async {
    await _pump(
      tester,
      permissions: const <String>{'task.read'},
      tasks: <TaskDto>[_task('task-a', title: 'Nur lesen')],
    );

    expect(find.text('Nur lesen'), findsWidgets);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Aufgabe anlegen').first,
    );
    expect(button.onPressed, isNull);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('lawful status action surfaces a structured version conflict', (
    tester,
  ) async {
    await _pump(
      tester,
      tasks: <TaskDto>[_task('task-a', title: 'Status ändern')],
      transitionFailure: PlatformRepositoryFailure<TaskDto>(
        kind: PlatformRepositoryFailureKind.versionConflict,
        message: 'stale',
        versionConflict: PlatformVersionConflict(
          expectedVersion: 1,
          actualVersion: 2,
          currentTask: _task('task-a', version: 2),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'In Bearbeitung'));
    await tester.pumpAndSettle();

    expect(
      find.text('Aufgabe wurde zwischenzeitlich geändert'),
      findsOneWidget,
    );
    expect(find.textContaining('Version 2'), findsOneWidget);
  });

  testWidgets('filtering removes a hidden selected task from the detail pane', (
    tester,
  ) async {
    await _pump(
      tester,
      tasks: <TaskDto>[
        _task('normal', title: 'Normale Aufgabe'),
        _task('high', title: 'Hohe Aufgabe', priority: TaskPriority.high),
      ],
    );

    await tester.tap(find.text('Hohe Aufgabe').first);
    await tester.pump();
    expect(find.text('Hohe Aufgabe'), findsWidgets);

    await tester.tap(find.text('Alle').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Normal').last);
    await tester.pumpAndSettle();

    expect(find.text('Normale Aufgabe'), findsWidgets);
  });

  for (final size in const <Size>[
    Size(390, 844),
    Size(1024, 768),
    Size(1440, 900),
  ]) {
    testWidgets('lays out without overflow at $size', (tester) async {
      await _pump(
        tester,
        size: size,
        tasks: <TaskDto>[
          _task('a', title: 'Dach prüfen'),
          _task('b', title: 'Handwerker beauftragen', status: TaskStatus.blocked),
          _task('c', title: 'Abnahme vorbereiten', priority: TaskPriority.high),
        ],
      );

      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester, {
  List<TaskDto> tasks = const <TaskDto>[],
  List<PropertySummaryDto> properties = const <PropertySummaryDto>[],
  Set<String> permissions = const <String>{'task.read', 'task.manage'},
  PlatformRepositoryFailureKind? searchFailure,
  PlatformRepositoryFailure<TaskDto>? transitionFailure,
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        workspaceSessionScopeProvider.overrideWithValue(
          WorkspaceSessionScope(
            workspaceId: _workspace,
            actorId: _actor,
            permissions: permissions,
            mutationsSupported: true,
          ),
        ),
        taskRepositoryProvider.overrideWithValue(
          _FakeTaskRepository(
            tasks: tasks,
            searchFailure: searchFailure,
            transitionFailure: transitionFailure,
          ),
        ),
        referenceSliceControllerProvider.overrideWith(
          (ref) => _FakeReferenceSliceController(properties),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: OperationalTasksPanel()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _property = PropertySummaryDto(
  id: _propertyId,
  workspaceId: _workspace,
  name: 'Hotel Test',
  addressLine1: 'Teststraße 1',
  zip: '96450',
  city: 'Coburg',
  status: PropertyStatus.active,
  version: 1,
);

TaskDto _task(
  String id, {
  String title = 'Aufgabe',
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
    this.searchFailure,
    this.transitionFailure,
  });

  final List<TaskDto> tasks;
  final PlatformRepositoryFailureKind? searchFailure;
  final PlatformRepositoryFailure<TaskDto>? transitionFailure;

  @override
  Future<PlatformRepositoryResult<PlatformPageResult<TaskDto>>> searchTasks(
    TaskListQuery query,
  ) async {
    final failure = searchFailure;
    if (failure != null) {
      return PlatformRepositoryFailure<PlatformPageResult<TaskDto>>(
        kind: failure,
        message: 'fail',
      );
    }
    return PlatformRepositorySuccess<PlatformPageResult<TaskDto>>(
      PlatformPageResult<TaskDto>(items: tasks, nextCursor: null),
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
  ) async => PlatformRepositorySuccess<TaskDto>(
    _task('created', title: command.draft.title),
  );

  @override
  Future<PlatformRepositoryResult<TaskDto>> updateTask(
    UpdateTaskCommand command,
  ) async => PlatformRepositorySuccess<TaskDto>(
    _task(command.taskId, version: command.expectedVersion + 1),
  );

  @override
  Future<PlatformRepositoryResult<TaskDto>> transitionTaskStatus(
    TransitionTaskStatusCommand command,
  ) async {
    final failure = transitionFailure;
    if (failure != null) return failure;
    return PlatformRepositorySuccess<TaskDto>(
      _task(
        command.taskId,
        status: command.targetStatus,
        version: command.expectedVersion + 1,
      ),
    );
  }
}

class _FakeReferenceSliceController extends ReferenceSliceController {
  _FakeReferenceSliceController(List<PropertySummaryDto> properties)
    : super(
        identityRepository: _NoopIdentityAccessRepository(),
        propertyRepository: _NoopPortfolioPropertyRepository(),
      ) {
    state = ReferenceSliceState(
      authPhase: ReferenceAuthPhase.authenticated,
      workspacePhase: WorkspacePhase.selected,
      propertyListPhase: PropertyListPhase.ready,
      propertyDetailPhase: PropertyDetailPhase.idle,
      mutationPhase: PropertyMutationPhase.idle,
      properties: properties,
    );
  }
}

class _NoopIdentityAccessRepository implements IdentityAccessRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopPortfolioPropertyRepository implements portfolio.PropertyRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
