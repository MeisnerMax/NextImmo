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
    'nullable override fields stay empty after clearing and reopening',
    (tester) async {
      const scenarioId = 'scenario-1';
      final store = _FakeScenarioAnalysisStore(scenarioId);

      Future<void> pumpScreen() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scenarioAnalysisControllerProvider.overrideWith(
                () => _FakeScenarioAnalysisController(store),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const Scaffold(body: InputsScreen(scenarioId: scenarioId)),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpScreen();

      Finder fieldByLabel(String label) {
        return find.ancestor(
          of: find.text(label),
          matching: find.byType(TextFormField),
        );
      }

      final arvField = fieldByLabel('ARV Override (empty = none)');
      final rentField = fieldByLabel('Rent Override (empty = none)');
      expect(arvField, findsOneWidget);
      expect(rentField, findsOneWidget);

      await tester.enterText(arvField, '');
      await tester.enterText(rentField, '');
      await tester.pumpAndSettle();

      expect(store.current.inputs.arvOverride, isNull);
      expect(store.current.inputs.rentOverride, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pumpScreen();

      expect(find.text('123456.0000'), findsNothing);
      expect(find.text('7890.0000'), findsNothing);

      final reopenedArv = tester.widget<TextFormField>(arvField);
      final reopenedRent = tester.widget<TextFormField>(rentField);
      expect(reopenedArv.controller?.text, '');
      expect(reopenedRent.controller?.text, '');
    },
  );
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
  void patchInputs(ScenarioInputs Function(ScenarioInputs current) updateFn) {
    final current = state.valueOrNull ?? _store.current;
    final nextInputs = updateFn(current.inputs).copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _store.updateInputs(nextInputs);
    state = AsyncValue.data(_store.current);
  }

  @override
  Future<void> flushPendingSave() async {}
}
