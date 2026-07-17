import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/engine/analysis_engine.dart';
import 'package:neximmo_app/core/engine/sensitivity.dart';
import 'package:neximmo_app/core/models/inputs.dart';
import 'package:neximmo_app/core/models/settings.dart';

void main() {
  group('SensitivityEngine', () {
    test('GM-SEN-001 standard grid matches baseline and cashflow rises', () {
      const engine = SensitivityEngine();
      const analysisEngine = AnalysisEngine();
      const updatedAt = 1704067200000;
      const settings = AppSettingsRecord(updatedAt: updatedAt);
      final inputs = ScenarioInputs.defaults(
        scenarioId: 'gm-sen-001',
        settings: settings,
      ).copyWith(
        purchasePrice: 250000,
        rentMonthlyTotal: 2200,
        financingMode: 'loan',
        downPaymentPercent: 0.25,
        interestRatePercent: 0.06,
        termYears: 30,
        updatedAt: updatedAt,
      );

      final baseline = analysisEngine.run(
        inputs: inputs,
        settings: settings,
        incomeLines: const [],
        expenseLines: const [],
      );

      final standardDeltas = SensitivityEngine.rangeByPreset(
        SensitivityRangePreset.standard,
      );
      expect(standardDeltas, const <double>[-0.2, -0.1, 0, 0.1, 0.2]);

      final baselineByMetric = <SensitivityMetric, double?>{
        SensitivityMetric.cashOnCash: baseline.metrics.cashOnCash,
        SensitivityMetric.capRate: baseline.metrics.capRate,
        SensitivityMetric.irr: baseline.metrics.irr,
        SensitivityMetric.monthlyCashflow:
            baseline.metrics.monthlyCashflowYear1,
      };

      for (final metric in SensitivityMetric.values) {
        final result = engine.run(
          config: SensitivityConfig(
            metric: metric,
            rentDeltas: standardDeltas,
            purchasePriceDeltas: standardDeltas,
          ),
          inputs: inputs,
          settings: settings,
          incomeLines: const [],
          expenseLines: const [],
        );

        expect(result.cells, hasLength(5), reason: metric.name);
        for (final row in result.cells) {
          expect(row, hasLength(5), reason: metric.name);
          expect(row, everyElement(isNotNull), reason: metric.name);
        }

        final baselineValue = baselineByMetric[metric];
        expect(baselineValue, isNotNull, reason: metric.name);
        expect(
          result.cells[2][2],
          closeTo(baselineValue!, 1e-12),
          reason: metric.name,
        );

        if (metric == SensitivityMetric.monthlyCashflow) {
          for (final row in result.cells) {
            for (var rentIndex = 1; rentIndex < row.length; rentIndex++) {
              expect(
                row[rentIndex]!,
                greaterThanOrEqualTo(row[rentIndex - 1]! - 1e-9),
              );
            }
          }
        }
      }
    });
  });
}
