import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/investment_modules.dart';
import 'package:neximmo_app/core/services/acquisition_calculation_service.dart';

void main() {
  group('AcquisitionCalculationService', () {
    test('berechnet zentrale Ankaufskennzahlen deterministisch', () {
      const service = AcquisitionCalculationService();

      final result = service.calculateQuickEvaluation(_inputs());

      const expectedClosingCosts = 300000.0 * 0.05;
      const expectedRenovationSafety = 40000.0 * 0.10;
      const expectedTotalInvestment =
          300000.0 +
          expectedClosingCosts +
          6000.0 +
          18000.0 +
          4500.0 +
          1500.0 +
          40000.0 +
          expectedRenovationSafety;
      const expectedEffectiveGrossIncome = (3000.0 + 200.0) * 12 * (1 - 0.05);
      const expectedOperatingExpenses =
          (300.0 + (12.0 * 120.0 / 12) + 200.0 + 100.0 + 150.0 + 50.0) * 12;
      const expectedNoi =
          expectedEffectiveGrossIncome - expectedOperatingExpenses;
      const expectedDebtService = 225000.0 * (0.04 + 0.02);
      const expectedCashflow = expectedNoi - expectedDebtService;
      const expectedValueBasedOnCapRate = expectedNoi / 0.06;
      const expectedMaxPurchasePrice =
          expectedValueBasedOnCapRate -
          expectedClosingCosts -
          6000.0 -
          18000.0 -
          4500.0 -
          1500.0 -
          40000.0 -
          expectedRenovationSafety -
          20000.0;

      expect(result.purchasePricePerSqm, closeTo(300000 / 120, 1e-9));
      expect(result.totalInvestment, closeTo(expectedTotalInvestment, 1e-9));
      expect(result.grossInitialYield, closeTo(3000 * 12 / 300000, 1e-12));
      expect(
        result.effectiveGrossIncome,
        closeTo(expectedEffectiveGrossIncome, 1e-9),
      );
      expect(
        result.operatingExpenses,
        closeTo(expectedOperatingExpenses, 1e-9),
      );
      expect(result.noi, closeTo(expectedNoi, 1e-9));
      expect(
        result.netInitialYield,
        closeTo(expectedNoi / expectedTotalInvestment, 1e-12),
      );
      expect(result.debtServiceAnnual, closeTo(expectedDebtService, 1e-9));
      expect(result.cashflowBeforeTax, closeTo(expectedCashflow, 1e-9));
      expect(result.cashOnCash, closeTo(expectedCashflow / 100000, 1e-12));
      expect(result.loanToValue, closeTo(225000 / 300000, 1e-12));
      expect(
        result.valueBasedOnCapRate,
        closeTo(expectedValueBasedOnCapRate, 1e-9),
      );
      expect(
        result.maxReasonablePurchasePrice,
        closeTo(expectedMaxPurchasePrice, 1e-9),
      );
      expect(result.score, 100);
      expect(result.recommendation, 'Kaufen');
      expect(result.warnings, isEmpty);
    });

    test('liefert bei Eigenkapital null keine Cash-on-Cash-Rendite', () {
      const service = AcquisitionCalculationService();

      final result = service.calculateQuickEvaluation(_inputs(equity: 0));

      expect(result.cashOnCash, isNull);
      expect(result.warnings, contains('Eigenkapital fehlt oder ist 0.'));
      expect(result.cashflowBeforeTax, closeTo(25440 - 13500, 1e-9));
    });
  });
}

AcquisitionQuickInputs _inputs({double equity = 100000}) {
  return AcquisitionQuickInputs(
    objectName: 'Referenzobjekt',
    propertyType: 'multi_family',
    residentialAreaSqm: 100,
    commercialAreaSqm: 20,
    landAreaSqm: 500,
    units: 6,
    vacancyPercent: 0.05,
    condition: 'good',
    monumentProtected: false,
    offerPrice: 300000,
    closingCostPercent: 0.05,
    brokerFee: 6000,
    transferTax: 18000,
    notaryAndLandRegistry: 4500,
    otherAcquisitionCosts: 1500,
    renovationBudget: 40000,
    renovationSafetyPercent: 0.10,
    currentColdRentMonthly: 3000,
    marketRentPerSqm: 12,
    otherIncomeMonthly: 200,
    nonRecoverableCostsMonthly: 300,
    maintenancePerSqmYear: 12,
    managementCostsMonthly: 200,
    insuranceMonthly: 100,
    propertyTaxMonthly: 150,
    otherCostsMonthly: 50,
    equity: equity,
    loanAmount: 225000,
    interestRatePercent: 0.04,
    amortizationPercent: 0.02,
    loanTermYears: 25,
    minimumCashflow: 900,
    minimumGrossYield: 0.10,
    minimumCapRate: 0.06,
    minimumCashOnCash: 0.10,
    maxPurchasePricePerSqm: 2600,
    maxLoanToValue: 0.80,
    maxRenovationShare: 0.12,
    targetCapRate: 0.06,
    desiredMargin: 20000,
  );
}
