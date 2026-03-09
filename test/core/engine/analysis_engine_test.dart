import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/engine/analysis_engine.dart';
import 'package:neximmo_app/core/models/inputs.dart';
import 'package:neximmo_app/core/models/scenario_valuation.dart';
import 'package:neximmo_app/core/models/settings.dart';

void main() {
  group('AnalysisEngine', () {
    test('computes deterministic core metrics for loan scenario', () {
      const engine = AnalysisEngine();
      final settings = AppSettingsRecord(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      final inputs = ScenarioInputs.defaults(
        scenarioId: 's1',
        settings: settings,
      ).copyWith(
        purchasePrice: 250000,
        rehabBudget: 20000,
        rentMonthlyTotal: 2200,
        vacancyPercent: 0.05,
        propertyTaxMonthly: 250,
        insuranceMonthly: 120,
        utilitiesMonthly: 100,
        hoaMonthly: 0,
        managementPercent: 0.08,
        maintenancePercent: 0.05,
        capexPercent: 0.05,
        otherExpensesMonthly: 100,
        financingMode: 'loan',
        downPaymentPercent: 0.25,
        interestRatePercent: 0.06,
        termYears: 30,
        sellAfterYears: 10,
      );

      final result = engine.run(
        inputs: inputs,
        settings: settings,
        incomeLines: const [],
        expenseLines: const [],
      );

      expect(result.proformaYears, isNotEmpty);
      expect(result.metrics.noiYear1, greaterThan(0));
      expect(result.metrics.capRate, greaterThan(0));
      expect(result.metrics.monthlyCashflowYear1, isA<double>());
      expect(result.metrics.totalCashInvested, greaterThan(0));
    });

    test('cash mode yields null dscr', () {
      const engine = AnalysisEngine();
      final settings = AppSettingsRecord(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      final inputs = ScenarioInputs.defaults(
        scenarioId: 's2',
        settings: settings,
      ).copyWith(
        purchasePrice: 180000,
        rentMonthlyTotal: 1600,
        financingMode: 'cash',
      );

      final result = engine.run(
        inputs: inputs,
        settings: settings,
        incomeLines: const [],
        expenseLines: const [],
      );

      expect(result.metrics.dscr, isNull);
    });

    test('exit cap mode uses stabilized noi and cap rate for sale price', () {
      const engine = AnalysisEngine();
      final settings = AppSettingsRecord(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      final inputs = ScenarioInputs.defaults(
        scenarioId: 's3',
        settings: settings,
      ).copyWith(
        purchasePrice: 300000,
        rentMonthlyTotal: 3000,
        financingMode: 'cash',
      );
      final valuation = ScenarioValuationRecord.defaults(
        scenarioId: 's3',
      ).copyWith(
        valuationMode: 'exit_cap',
        exitCapRatePercent: 0.05,
        stabilizedNoiMode: 'manual_noi',
        stabilizedNoiManual: 25000,
      );

      final result = engine.run(
        inputs: inputs,
        settings: settings,
        incomeLines: const [],
        expenseLines: const [],
        valuation: valuation,
      );

      expect(result.metrics.valuationMode, 'exit_cap');
      expect(result.metrics.exitStabilizedNoi, 25000);
      expect(result.metrics.exitSalePrice, closeTo(500000, 0.0001));
    });

    test('appreciation mode remains unchanged when selected', () {
      const engine = AnalysisEngine();
      final settings = AppSettingsRecord(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      final inputs = ScenarioInputs.defaults(
        scenarioId: 's4',
        settings: settings,
      ).copyWith(
        purchasePrice: 200000,
        appreciationPercent: 0.03,
        sellAfterYears: 10,
      );

      final result = engine.run(
        inputs: inputs,
        settings: settings,
        incomeLines: const [],
        expenseLines: const [],
      );
      final expected = 200000 * _pow(1.03, 10);
      expect(result.metrics.valuationMode, 'appreciation');
      expect(result.metrics.exitSalePrice, closeTo(expected, 0.001));
    });
  });
}

double _pow(double base, int exponent) {
  var result = 1.0;
  for (var i = 0; i < exponent; i++) {
    result *= base;
  }
  return result;
}
