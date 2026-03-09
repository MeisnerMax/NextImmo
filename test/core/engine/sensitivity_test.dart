import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/engine/analysis_engine.dart';
import 'package:neximmo_app/core/engine/sensitivity.dart';
import 'package:neximmo_app/core/models/inputs.dart';
import 'package:neximmo_app/core/models/settings.dart';

void main() {
  group('SensitivityEngine', () {
    test('grid dimensions are correct and center equals baseline metric', () {
      const engine = SensitivityEngine();
      const analysisEngine = AnalysisEngine();
      final settings = AppSettingsRecord(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      final inputs = ScenarioInputs.defaults(
        scenarioId: 's1',
        settings: settings,
      ).copyWith(
        purchasePrice: 250000,
        rentMonthlyTotal: 2200,
        financingMode: 'loan',
        downPaymentPercent: 0.25,
        interestRatePercent: 0.06,
        termYears: 30,
      );

      final baseline = analysisEngine.run(
        inputs: inputs,
        settings: settings,
        incomeLines: const [],
        expenseLines: const [],
      );

      final deltas = SensitivityEngine.rangeByPreset(
        SensitivityRangePreset.standard,
      );
      final result = engine.run(
        config: SensitivityConfig(
          metric: SensitivityMetric.cashOnCash,
          rentDeltas: deltas,
          purchasePriceDeltas: deltas,
        ),
        inputs: inputs,
        settings: settings,
        incomeLines: const [],
        expenseLines: const [],
      );

      expect(result.cells.length, deltas.length);
      for (final row in result.cells) {
        expect(row.length, deltas.length);
      }
      final center = result.cells[deltas.length ~/ 2][deltas.length ~/ 2];
      expect(center, isNotNull);
      expect(center!, closeTo(baseline.metrics.cashOnCash, 1e-9));
    });

    test('monthly cashflow grows monotonically for rising rent deltas', () {
      const engine = SensitivityEngine();
      final settings = AppSettingsRecord(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      final inputs = ScenarioInputs.defaults(
        scenarioId: 's2',
        settings: settings,
      ).copyWith(
        purchasePrice: 220000,
        rentMonthlyTotal: 1900,
        financingMode: 'cash',
      );

      final result = engine.run(
        config: const SensitivityConfig(
          metric: SensitivityMetric.monthlyCashflow,
          rentDeltas: <double>[-0.2, -0.1, 0, 0.1, 0.2],
          purchasePriceDeltas: <double>[0],
        ),
        inputs: inputs,
        settings: settings,
        incomeLines: const [],
        expenseLines: const [],
      );

      final row = result.cells.single.whereType<double>().toList();
      expect(row, hasLength(5));
      for (var i = 1; i < row.length; i++) {
        expect(row[i], greaterThanOrEqualTo(row[i - 1]));
      }
    });
  });
}
