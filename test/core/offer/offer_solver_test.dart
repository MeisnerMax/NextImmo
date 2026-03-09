import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/offer/offer_solver.dart';
import 'package:neximmo_app/core/models/inputs.dart';
import 'package:neximmo_app/core/models/settings.dart';

void main() {
  test('solves MAO for cash on cash objective', () {
    const solver = OfferSolver();
    final settings = AppSettingsRecord(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final baseInputs = ScenarioInputs.defaults(
      scenarioId: 'scenario',
      settings: settings,
    ).copyWith(
      purchasePrice: 300000,
      rentMonthlyTotal: 2600,
      rehabBudget: 15000,
      financingMode: 'loan',
      downPaymentPercent: 0.25,
      interestRatePercent: 0.06,
      termYears: 30,
      sellAfterYears: 10,
    );

    final result = solver.solve(
      OfferSolveRequest(
        baseInputs: baseInputs,
        settings: settings,
        incomeLines: const [],
        expenseLines: const [],
        targetMetricKey: 'cash_on_cash',
        targetValue: 0.1,
        highBound: 400000,
      ),
    );

    expect(result.mao, greaterThan(0));
    expect(result.analysisAtMao.metrics.cashOnCash, greaterThanOrEqualTo(0));
  });

  test('marks infeasible target as not feasible', () {
    const solver = OfferSolver();
    final settings = AppSettingsRecord(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final baseInputs = ScenarioInputs.defaults(
      scenarioId: 'scenario',
      settings: settings,
    ).copyWith(
      purchasePrice: 300000,
      rentMonthlyTotal: 2600,
      rehabBudget: 15000,
      financingMode: 'loan',
      downPaymentPercent: 0.25,
      interestRatePercent: 0.06,
      termYears: 30,
      sellAfterYears: 10,
    );

    final result = solver.solve(
      OfferSolveRequest(
        baseInputs: baseInputs,
        settings: settings,
        incomeLines: const [],
        expenseLines: const [],
        targetMetricKey: 'monthly_cashflow',
        targetValue: 100000,
        highBound: 400000,
      ),
    );

    expect(result.isFeasible, isFalse);
    expect(result.warnings, isNotEmpty);
  });
}
