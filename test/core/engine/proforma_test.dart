import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/engine/normalize.dart';
import 'package:neximmo_app/core/engine/proforma.dart';
import 'package:neximmo_app/core/models/inputs.dart';
import 'package:neximmo_app/core/models/scenario_valuation.dart';
import 'package:neximmo_app/core/models/settings.dart';

void main() {
  group('buildProforma financing', () {
    test(
      'auto loan uses total acquisition cost basis when loan amount is zero',
      () {
        final settings = AppSettingsRecord(
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        final inputs = ScenarioInputs.defaults(
          scenarioId: 's1',
          settings: settings,
        ).copyWith(
          purchasePrice: 200000,
          rehabBudget: 20000,
          closingCostBuyPercent: 0.05,
          closingCostBuyFixed: 5000,
          financingMode: 'loan',
          downPaymentPercent: 0.2,
          loanAmount: 0,
        );
        final normalized = normalizeInputs(
          inputs: inputs,
          settings: settings,
          incomeLines: const [],
          expenseLines: const [],
        );

        final result = buildProforma(
          normalized,
          valuation: ScenarioValuationRecord.defaults(scenarioId: 's1'),
        );

        expect(result.loanPrincipal, closeTo(188000, 0.0001));
        expect(result.totalCashInvested, closeTo(47000, 0.0001));
      },
    );

    test('manual loan amount overrides auto loan mode', () {
      final settings = AppSettingsRecord(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      final inputs = ScenarioInputs.defaults(
        scenarioId: 's2',
        settings: settings,
      ).copyWith(
        purchasePrice: 200000,
        rehabBudget: 20000,
        closingCostBuyPercent: 0.05,
        closingCostBuyFixed: 5000,
        financingMode: 'loan',
        downPaymentPercent: 0.2,
        loanAmount: 150000,
      );
      final normalized = normalizeInputs(
        inputs: inputs,
        settings: settings,
        incomeLines: const [],
        expenseLines: const [],
      );

      final result = buildProforma(
        normalized,
        valuation: ScenarioValuationRecord.defaults(scenarioId: 's2'),
      );

      expect(result.loanPrincipal, closeTo(150000, 0.0001));
      expect(result.totalCashInvested, closeTo(85000, 0.0001));
    });

    test('loan amount is capped at total acquisition cost', () {
      final settings = AppSettingsRecord(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      final inputs = ScenarioInputs.defaults(
        scenarioId: 's3',
        settings: settings,
      ).copyWith(
        purchasePrice: 200000,
        rehabBudget: 20000,
        closingCostBuyPercent: 0.05,
        closingCostBuyFixed: 5000,
        financingMode: 'loan',
        loanAmount: 400000,
      );
      final normalized = normalizeInputs(
        inputs: inputs,
        settings: settings,
        incomeLines: const [],
        expenseLines: const [],
      );

      final result = buildProforma(
        normalized,
        valuation: ScenarioValuationRecord.defaults(scenarioId: 's3'),
      );

      expect(result.loanPrincipal, closeTo(235000, 0.0001));
      expect(result.totalCashInvested, 0);
      expect(
        result.warnings,
        contains('Loan amount exceeded total acquisition cost and was capped.'),
      );
    });

    test('debt service stops after the loan term ends', () {
      final settings = AppSettingsRecord(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      final inputs = ScenarioInputs.defaults(
        scenarioId: 's4',
        settings: settings,
      ).copyWith(
        purchasePrice: 100000,
        rentMonthlyTotal: 1200,
        financingMode: 'loan',
        loanAmount: 60000,
        interestRatePercent: 0.06,
        termYears: 1,
        holdMonths: 24,
        sellAfterYears: 2,
      );
      final normalized = normalizeInputs(
        inputs: inputs,
        settings: settings,
        incomeLines: const [],
        expenseLines: const [],
      );

      final result = buildProforma(
        normalized,
        valuation: ScenarioValuationRecord.defaults(scenarioId: 's4'),
      );

      expect(result.proformaYears, hasLength(2));
      expect(result.proformaYears.first.debtService, greaterThan(0));
      expect(result.proformaYears.last.debtService, closeTo(0, 0.0001));
    });
  });
}
