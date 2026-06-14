import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/core/models/scenario.dart';
import 'package:neximmo_app/core/models/task.dart';
import 'package:neximmo_app/data/repositories/tasks_repo.dart';
import 'package:neximmo_app/ui/screens/property_detail/property_shell.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/state/property_state.dart';
import 'package:neximmo_app/ui/state/scenario_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows grouped property navigation and breadcrumb context', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        propertiesControllerProvider.overrideWith(
          _FakePropertiesController.new,
        ),
        scenariosByPropertyProvider.overrideWith(
          () => _FakeScenariosByPropertyController(),
        ),
        tasksRepositoryProvider.overrideWithValue(_FakeTasksRepo()),
      ],
    );
    addTearDown(container.dispose);
    container.read(selectedPropertyIdProvider.notifier).state = 'p1';
    container.read(propertyDetailPageProvider.notifier).state =
        PropertyDetailPage.tasks;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: PropertyShell()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('ANSICHT'), findsAtLeastNWidgets(1));
    expect(find.text('TAGESGESCHAEFT'), findsAtLeastNWidgets(1));
    expect(
      find.text(
        'Asset Alpha / Tagesgeschaeft / Aufgaben',
      ),
      findsOneWidget,
    );
    expect(find.text('New Task'), findsOneWidget);
  });

  testWidgets('sale property shows sale modules instead of tenant module', (
    tester,
  ) async {
    await _pumpShellForType(
      tester,
      propertyType: 'sale',
      selectedPage: PropertyDetailPage.tasks,
    );

    await tester.tap(find.text('TAGESGESCHAEFT').first);
    await tester.pumpAndSettle();

    expect(find.text('Käufer/Interessenten'), findsOneWidget);
    expect(find.text('Besichtigungen'), findsOneWidget);
    expect(find.text('Angebote'), findsOneWidget);
    expect(find.text('Mieter'), findsNothing);
  });

  testWidgets('hotel property shows hotel modules instead of tenant module', (
    tester,
  ) async {
    await _pumpShellForType(
      tester,
      propertyType: 'hotel',
      selectedPage: PropertyDetailPage.tasks,
      hasHotelModules: true,
    );

    await tester.tap(find.text('TAGESGESCHAEFT').first);
    await tester.pumpAndSettle();

    expect(find.text('Zimmer'), findsOneWidget);
    expect(find.text('Reservierungen'), findsOneWidget);
    expect(find.text('Gäste'), findsOneWidget);
    expect(find.text('Mieter'), findsNothing);
  });

  testWidgets('mixed property keeps rental and sale modules', (tester) async {
    await _pumpShellForType(
      tester,
      propertyType: 'mixed',
      selectedPage: PropertyDetailPage.tasks,
    );

    await tester.tap(find.text('TAGESGESCHAEFT').first);
    await tester.pumpAndSettle();

    expect(find.text('Mieter'), findsOneWidget);
    expect(find.text('Mietverträge'), findsOneWidget);
    expect(find.text('Käufer/Interessenten'), findsOneWidget);
  });

  testWidgets('legacy multifamily property keeps rental modules', (tester) async {
    await _pumpShellForType(
      tester,
      propertyType: 'multifamily',
      selectedPage: PropertyDetailPage.tasks,
    );

    await tester.tap(find.text('TAGESGESCHAEFT').first);
    await tester.pumpAndSettle();

    expect(find.text('Mieter'), findsOneWidget);
    expect(find.text('Mietverträge'), findsOneWidget);
  });
}

Future<void> _pumpShellForType(
  WidgetTester tester, {
  required String propertyType,
  required PropertyDetailPage selectedPage,
  bool hasHotelModules = false,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      propertiesControllerProvider.overrideWith(
        () => _TypedPropertiesController(propertyType),
      ),
      scenariosByPropertyProvider.overrideWith(
        () => _FakeScenariosByPropertyController(),
      ),
      tasksRepositoryProvider.overrideWithValue(_FakeTasksRepo()),
      propertyHasHotelModulesProvider.overrideWith(
        (ref, propertyId) async => hasHotelModules,
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(selectedPropertyIdProvider.notifier).state = 'p1';
  container.read(propertyDetailPageProvider.notifier).state = selectedPage;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: PropertyShell()),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

class _FakePropertiesController extends PropertiesController {
  @override
  Future<List<PropertyRecord>> build() async {
    return const <PropertyRecord>[
      PropertyRecord(
        id: 'p1',
        name: 'Asset Alpha',
        addressLine1: 'Main Street 1',
        zip: '10115',
        city: 'Berlin',
        country: 'DE',
        propertyType: 'multifamily',
        units: 12,
        createdAt: 1,
        updatedAt: 1,
      ),
    ];
  }
}

class _TypedPropertiesController extends PropertiesController {
  _TypedPropertiesController(this.propertyType);

  final String propertyType;

  @override
  Future<List<PropertyRecord>> build() async {
    return <PropertyRecord>[
      PropertyRecord(
        id: 'p1',
        name: 'Asset Alpha',
        addressLine1: 'Main Street 1',
        zip: '10115',
        city: 'Berlin',
        country: 'DE',
        propertyType: propertyType,
        units: 12,
        createdAt: 1,
        updatedAt: 1,
      ),
    ];
  }
}

class _FakeScenariosByPropertyController extends ScenariosByPropertyController {
  @override
  Future<List<ScenarioRecord>> build(String propertyId) async {
    return const <ScenarioRecord>[
      ScenarioRecord(
        id: 's1',
        propertyId: 'p1',
        name: 'Base Case',
        strategyType: 'hold',
        isBase: true,
        createdAt: 1,
        updatedAt: 1,
      ),
    ];
  }
}

class _FakeTasksRepo extends TasksRepo {
  _FakeTasksRepo() : super(_NoopDatabase());

  @override
  Future<List<TaskRecord>> listTasks({
    String? status,
    int? dueFrom,
    int? dueTo,
    String? entityType,
    String? entityId,
  }) async {
    return const <TaskRecord>[
      TaskRecord(
        id: 't1',
        entityType: 'property',
        entityId: 'p1',
        title: 'Review insurance renewal',
        status: 'todo',
        priority: 'high',
        dueAt: null,
        createdAt: 1,
        updatedAt: 1,
        createdBy: null,
      ),
    ];
  }

  @override
  Future<List<TaskChecklistItemRecord>> listChecklistItems(
    String taskId,
  ) async {
    return const <TaskChecklistItemRecord>[];
  }
}

class _NoopDatabase extends Fake implements Database {}
