import 'dart:async';

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

/// Mandatory-state coverage for the property shell frame (AP2, SCR-010):
/// loading skeleton, error with retry, no-scenario auto-creation hint,
/// status badge, and the phone-width dropdown navigation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pumpShell(
    WidgetTester tester, {
    required ScenariosByPropertyController Function() scenariosFactory,
    Size viewSize = const Size(1280, 800),
    bool archived = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        propertiesControllerProvider.overrideWith(
          () => _FakePropertiesController(archived: archived),
        ),
        scenariosByPropertyProvider.overrideWith(scenariosFactory),
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return container;
  }

  testWidgets('loading shows the shell skeleton instead of a spinner', (
    tester,
  ) async {
    await pumpShell(
      tester,
      scenariosFactory: _PendingScenariosController.new,
      settle: false,
    );

    expect(
      find.byKey(const ValueKey<String>('property_shell_skeleton')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('error shows retry action without raw exception text', (
    tester,
  ) async {
    var attempts = 0;
    await pumpShell(
      tester,
      scenariosFactory: () => _FlakyScenariosController(
        shouldFail: () => ++attempts == 1,
      ),
    );

    expect(
      find.text('Szenarien konnten nicht geladen werden'),
      findsOneWidget,
    );
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);

    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();

    expect(find.text('Szenarien konnten nicht geladen werden'), findsNothing);
    expect(find.text('Asset Alpha'), findsOneWidget);
  });

  testWidgets('empty scenario list surfaces the auto-creation hint', (
    tester,
  ) async {
    await pumpShell(
      tester,
      scenariosFactory: _EmptyScenariosController.new,
    );

    expect(
      find.text('Basisszenario wird erstellt...'),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('active property shows the Aktiv status badge in the header', (
    tester,
  ) async {
    await pumpShell(
      tester,
      scenariosFactory: _HealthyScenariosController.new,
    );

    expect(find.text('Aktiv'), findsOneWidget);
    expect(find.text('Archiviert'), findsNothing);
  });

  testWidgets('archived property shows the Archiviert status badge', (
    tester,
  ) async {
    await pumpShell(
      tester,
      scenariosFactory: _HealthyScenariosController.new,
      archived: true,
    );

    expect(find.text('Archiviert'), findsOneWidget);
    expect(find.text('Aktiv'), findsNothing);
  });

  testWidgets('phone width switches to the dropdown navigation', (
    tester,
  ) async {
    await pumpShell(
      tester,
      scenariosFactory: _HealthyScenariosController.new,
      viewSize: const Size(390, 844),
    );

    expect(find.text('Property Navigation'), findsOneWidget);
    expect(
      find.byType(DropdownButtonFormField<PropertyDetailPage>),
      findsOneWidget,
    );
  });

  testWidgets('1024 width is the narrow zone and uses dropdown navigation', (
    tester,
  ) async {
    await pumpShell(
      tester,
      scenariosFactory: _HealthyScenariosController.new,
      viewSize: const Size(1024, 768),
    );

    expect(find.text('Property Navigation'), findsOneWidget);
    expect(
      find.byType(DropdownButtonFormField<PropertyDetailPage>),
      findsOneWidget,
    );
  });

  testWidgets('large width keeps the grouped horizontal navigation', (
    tester,
  ) async {
    await pumpShell(
      tester,
      scenariosFactory: _HealthyScenariosController.new,
      viewSize: const Size(1440, 900),
    );

    expect(find.text('TAGESGESCHAEFT'), findsAtLeastNWidgets(1));
    expect(
      find.byType(DropdownButtonFormField<PropertyDetailPage>),
      findsNothing,
    );
  });
}

const _scenario = ScenarioRecord(
  id: 's1',
  propertyId: 'p1',
  name: 'Base Case',
  strategyType: 'hold',
  isBase: true,
  createdAt: 1,
  updatedAt: 1,
);

class _FakePropertiesController extends PropertiesController {
  _FakePropertiesController({required this.archived});

  final bool archived;

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
        propertyType: 'multifamily',
        units: 12,
        archived: archived,
        createdAt: 1,
        updatedAt: 1,
      ),
    ];
  }
}

class _HealthyScenariosController extends ScenariosByPropertyController {
  @override
  Future<List<ScenarioRecord>> build(String propertyId) async {
    return const <ScenarioRecord>[_scenario];
  }
}

class _PendingScenariosController extends ScenariosByPropertyController {
  @override
  Future<List<ScenarioRecord>> build(String propertyId) {
    return Completer<List<ScenarioRecord>>().future;
  }
}

class _FlakyScenariosController extends ScenariosByPropertyController {
  _FlakyScenariosController({required this.shouldFail});

  final bool Function() shouldFail;

  @override
  Future<List<ScenarioRecord>> build(String propertyId) async {
    if (shouldFail()) {
      throw Exception('load failed');
    }
    return const <ScenarioRecord>[_scenario];
  }
}

class _EmptyScenariosController extends ScenariosByPropertyController {
  @override
  Future<List<ScenarioRecord>> build(String propertyId) async {
    return const <ScenarioRecord>[];
  }

  @override
  Future<ScenarioRecord?> create({
    required String name,
    required String strategyType,
    String scenarioCaseType = 'base',
  }) async {
    return null;
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
    return const <TaskRecord>[];
  }

  @override
  Future<List<TaskChecklistItemRecord>> listChecklistItems(
    String taskId,
  ) async {
    return const <TaskChecklistItemRecord>[];
  }
}

class _NoopDatabase extends Fake implements Database {}
