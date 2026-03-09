import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/engine/analysis_engine.dart';
import 'package:neximmo_app/core/models/inputs.dart';
import 'package:neximmo_app/core/models/scenario_valuation.dart';
import 'package:neximmo_app/core/models/settings.dart';
import 'package:neximmo_app/ui/screens/property_detail/inputs_screen.dart';
import 'package:neximmo_app/ui/state/analysis_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'basic mode shows business labels and keeps advanced overrides hidden',
    (tester) async {
      const scenarioId = 'scenario-1';
      final store = _FakeScenarioAnalysisStore(scenarioId);

      await _pumpScreen(tester, scenarioId: scenarioId, store: store);

      expect(find.text('Purchase Price'), findsOneWidget);
      expect(find.text('Interest Rate'), findsOneWidget);
      expect(find.text('Interest Rate % (0-1)'), findsNothing);
      expect(find.text('Value Override'), findsNothing);
      expect(find.text('Rent Override'), findsNothing);

      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();

      expect(find.text('Value Override'), findsOneWidget);
      expect(find.text('Rent Override'), findsOneWidget);
    },
  );

  testWidgets(
    'nullable override fields stay empty after clearing and reopening',
    (tester) async {
      const scenarioId = 'scenario-1';
      final store = _FakeScenarioAnalysisStore(scenarioId);

      await _pumpScreen(tester, scenarioId: scenarioId, store: store);
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();

      Finder fieldByLabel(String label) {
        return find.ancestor(
          of: find.text(label),
          matching: find.byType(TextFormField),
        );
      }

      final valueOverrideField = fieldByLabel('Value Override');
      final rentOverrideField = fieldByLabel('Rent Override');

      await tester.enterText(valueOverrideField, '');
      await tester.enterText(rentOverrideField, '');
      await tester.pumpAndSettle();

      expect(store.current.inputs.arvOverride, isNull);
      expect(store.current.inputs.rentOverride, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await _pumpScreen(tester, scenarioId: scenarioId, store: store);
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();

      final reopenedValue = tester.widget<TextFormField>(valueOverrideField);
      final reopenedRent = tester.widget<TextFormField>(rentOverrideField);
      expect(reopenedValue.controller?.text, '');
      expect(reopenedRent.controller?.text, '');
    },
  );

  testWidgets('percent fields show inline validation', (tester) async {
    const scenarioId = 'scenario-1';
    final store = _FakeScenarioAnalysisStore(scenarioId);

    await _pumpScreen(tester, scenarioId: scenarioId, store: store);

    final interestRateField = find.ancestor(
      of: find.text('Interest Rate'),
      matching: find.byType(TextFormField),
    );

    await tester.enterText(interestRateField, '150');
    await tester.pumpAndSettle();

    expect(find.text('Enter a value between 0% and 100%.'), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required String scenarioId,
  required _FakeScenarioAnalysisStore store,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        scenarioAnalysisControllerProvider.overrideWith(
          () => _FakeScenarioAnalysisController(store),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: InputsScreen(scenarioId: scenarioId)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeScenarioAnalysisStore {
  _FakeScenarioAnalysisStore(String scenarioId)
    : settings = AppSettingsRecord(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      valuation = ScenarioValuationRecord.defaults(scenarioId: scenarioId) {
    final baseInputs = ScenarioInputs.defaults(
      scenarioId: scenarioId,
      settings: settings,
    ).copyWith(
      arvOverride: 123456,
      rentOverride: 7890,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    current = _buildState(
      settings: settings,
      inputs: baseInputs,
      valuation: valuation,
    );
  }

  final AppSettingsRecord settings;
  final ScenarioValuationRecord valuation;
  late ScenarioAnalysisState current;

  void updateInputs(ScenarioInputs inputs) {
    current = _buildState(
      settings: settings,
      inputs: inputs,
      valuation: valuation,
    );
  }

  static ScenarioAnalysisState _buildState({
    required AppSettingsRecord settings,
    required ScenarioInputs inputs,
    required ScenarioValuationRecord valuation,
  }) {
    final analysis = const AnalysisEngine().run(
      inputs: inputs,
      settings: settings,
      incomeLines: const <IncomeLine>[],
      expenseLines: const <ExpenseLine>[],
      valuation: valuation,
    );
    return ScenarioAnalysisState(
      propertyId: 'property-1',
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
}

class _FakeScenarioAnalysisController extends ScenarioAnalysisController {
  _FakeScenarioAnalysisController(this._store);

  final _FakeScenarioAnalysisStore _store;

  @override
  Future<ScenarioAnalysisState> build(String scenarioId) async {
    return _store.current;
  }

  @override
  void patchInputs(
    ScenarioInputs Function(ScenarioInputs current) updateFn, {
    Iterable<String> dirtyFields = const <String>[],
  }) {
    final current = state.valueOrNull ?? _store.current;
    final nextInputs = updateFn(
      current.inputs,
    ).copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch);
    _store.updateInputs(nextInputs);
    state = AsyncValue.data(
      _store.current.copyWith(
        hasUnsavedChanges: true,
        dirtyFields: {...dirtyFields},
      ),
    );
  }

  @override
  Future<void> flushPendingSave() async {}
}
