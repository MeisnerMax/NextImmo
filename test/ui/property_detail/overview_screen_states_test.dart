import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/engine/analysis_engine.dart';
import 'package:neximmo_app/core/models/inputs.dart';
import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/core/models/scenario_valuation.dart';
import 'package:neximmo_app/core/models/settings.dart';
import 'package:neximmo_app/ui/screens/property_detail/overview_screen.dart';
import 'package:neximmo_app/ui/state/analysis_state.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/state/property_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Mandatory-state coverage for the redesigned `OverviewScreen`
/// (Phase 2, Wave 1, Arbeitspaket 3 / SCR-011): per-section loading
/// skeletons without a full-page spinner, per-section error with retry and
/// no raw exception text, the onboarding "next steps" guidance, metric-tile
/// navigation, and a responsive smoke check at the three golden widths.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const propertyId = 'p1';
  const scenarioId = 's1';

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    required ScenarioAnalysisController Function() analysisFactory,
    Size size = const Size(1280, 800),
    bool basicsOnlyProperty = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        scenarioAnalysisControllerProvider.overrideWith(analysisFactory),
        propertiesControllerProvider.overrideWith(
          () => _FakePropertiesController(basicsOnly: basicsOnlyProperty),
        ),
        propertyTitleImageProvider.overrideWith(
          (ref, propertyId) async => null,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: OverviewScreen(
              propertyId: propertyId,
              scenarioId: scenarioId,
            ),
          ),
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

  testWidgets('loading shows section skeletons instead of a full-page spinner',
      (tester) async {
    await pumpScreen(
      tester,
      analysisFactory: _PendingAnalysisController.new,
      settle: false,
    );

    expect(
      find.byKey(const ValueKey<String>('overview_pipeline_skeleton')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('overview_metric_skeleton')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('overview_snapshot_skeleton')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('error shows per-section retry without raw exception text', (
    tester,
  ) async {
    var attempts = 0;
    await pumpScreen(
      tester,
      analysisFactory: () => _FlakyAnalysisController(
        shouldFail: () => ++attempts == 1,
      ),
    );

    expect(find.text('Erneut versuchen'), findsWidgets);
    expect(
      find.text('Kennzahlen konnten nicht geladen werden'),
      findsOneWidget,
    );
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('analysis failed'), findsNothing);

    await tester.tap(find.text('Erneut versuchen').first);
    await tester.pumpAndSettle();

    expect(find.text('Erneut versuchen'), findsNothing);
    expect(find.text('Property Workflow'), findsOneWidget);
  });

  testWidgets('basics-only property surfaces the onboarding guidance', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      analysisFactory: _BasicsAnalysisController.new,
      basicsOnlyProperty: true,
    );

    expect(find.text('Next Steps'), findsOneWidget);
    expect(find.text('Add financial assumptions'), findsOneWidget);
    expect(find.text('Set strategy'), findsOneWidget);
  });

  testWidgets('seeded scenario hides onboarding and renders all sections', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      analysisFactory: _HealthyAnalysisController.new,
    );

    expect(find.text('Next Steps'), findsNothing);
    expect(find.text('Property Workflow'), findsOneWidget);
    expect(find.text('MONTHLY CASHFLOW'), findsOneWidget);
    expect(find.text('Objekt-Stammdaten'), findsOneWidget);
    expect(find.text('Cashflow Projection'), findsOneWidget);
    expect(find.text('Rent Projection'), findsOneWidget);
  });

  testWidgets('metric tile navigates to the analysis module', (tester) async {
    final container = await pumpScreen(
      tester,
      analysisFactory: _HealthyAnalysisController.new,
    );

    await tester.tap(find.text('MONTHLY CASHFLOW'));
    await tester.pumpAndSettle();

    expect(
      container.read(propertyDetailPageProvider),
      PropertyDetailPage.analysis,
    );
  });

  testWidgets('phone width stacks the sections without overflow', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      analysisFactory: _HealthyAnalysisController.new,
      size: const Size(390, 844),
    );

    expect(
      find.byKey(const ValueKey<String>('overview_stacked_layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('overview_wide_layout')),
      findsNothing,
    );
  });

  testWidgets('tablet width stacks the sections without overflow', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      analysisFactory: _HealthyAnalysisController.new,
      size: const Size(1024, 768),
    );

    expect(
      find.byKey(const ValueKey<String>('overview_stacked_layout')),
      findsOneWidget,
    );
  });

  testWidgets('desktop width renders the two-column layout without overflow', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      analysisFactory: _HealthyAnalysisController.new,
      size: const Size(1440, 900),
    );

    expect(
      find.byKey(const ValueKey<String>('overview_wide_layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('overview_stacked_layout')),
      findsNothing,
    );
  });
}

ScenarioAnalysisState _buildAnalysisState({
  double purchasePrice = 0,
  double rentMonthlyTotal = 0,
}) {
  final settings = AppSettingsRecord(
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );
  final inputs = ScenarioInputs.defaults(
    scenarioId: 's1',
    settings: settings,
  ).copyWith(
    purchasePrice: purchasePrice,
    rentMonthlyTotal: rentMonthlyTotal,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );
  final valuation = ScenarioValuationRecord.defaults(scenarioId: 's1');
  final analysis = const AnalysisEngine().run(
    inputs: inputs,
    settings: settings,
    incomeLines: const <IncomeLine>[],
    expenseLines: const <ExpenseLine>[],
    valuation: valuation,
  );
  return ScenarioAnalysisState(
    propertyId: 'p1',
    settings: settings,
    inputs: inputs,
    valuation: valuation,
    incomeLines: const <IncomeLine>[],
    expenseLines: const <ExpenseLine>[],
    analysis: analysis,
    criteria: null,
    isSaving: false,
    hasUnsavedChanges: false,
    lastSavedAt: DateTime.now().millisecondsSinceEpoch,
    dirtyFields: const <String>{},
    saveError: null,
  );
}

class _HealthyAnalysisController extends ScenarioAnalysisController {
  @override
  Future<ScenarioAnalysisState> build(String scenarioId) async {
    return _buildAnalysisState(
      purchasePrice: 250000,
      rentMonthlyTotal: 1800,
    );
  }

  @override
  Future<void> flushPendingSave() async {}
}

class _BasicsAnalysisController extends ScenarioAnalysisController {
  @override
  Future<ScenarioAnalysisState> build(String scenarioId) async {
    return _buildAnalysisState();
  }

  @override
  Future<void> flushPendingSave() async {}
}

class _PendingAnalysisController extends ScenarioAnalysisController {
  @override
  Future<ScenarioAnalysisState> build(String scenarioId) {
    return Completer<ScenarioAnalysisState>().future;
  }

  @override
  Future<void> flushPendingSave() async {}
}

class _FlakyAnalysisController extends ScenarioAnalysisController {
  _FlakyAnalysisController({required this.shouldFail});

  final bool Function() shouldFail;

  @override
  Future<ScenarioAnalysisState> build(String scenarioId) async {
    if (shouldFail()) {
      throw Exception('analysis failed');
    }
    return _buildAnalysisState(
      purchasePrice: 250000,
      rentMonthlyTotal: 1800,
    );
  }

  @override
  Future<void> flushPendingSave() async {}
}

class _FakePropertiesController extends PropertiesController {
  _FakePropertiesController({required this.basicsOnly});

  final bool basicsOnly;

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
        units: basicsOnly ? 0 : 12,
        yearBuilt: basicsOnly ? null : 1998,
        createdAt: 1,
        updatedAt: 1,
      ),
    ];
  }
}
