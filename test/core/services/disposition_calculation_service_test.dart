import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/investment_modules.dart';
import 'package:neximmo_app/core/services/disposition_calculation_service.dart';

void main() {
  const service = DispositionCalculationService();

  DispositionModuleInputs inputs({
    double areaSqm = 200,
    double equityInvested = 500000,
    int holdPeriodYears = 2,
  }) {
    return DispositionModuleInputs(
      caseName: 'Referenzverkauf',
      expectedSalePrice: 1000000,
      minimumSalePrice: 50000,
      targetSalePrice: 1000000,
      brokerOpinionValue: 1000000,
      appraiserValue: 1000000,
      internalTargetValue: 1000000,
      marketValue: 1000000,
      currentNoi: 50000,
      stabilizedNoi: 60000,
      exitCapRate: 0.06,
      annualColdRent: 50000,
      areaSqm: areaSqm,
      brokerCosts: 30000,
      legalCosts: 10000,
      notaryCosts: 5000,
      dueDiligenceCosts: 5000,
      prepaymentPenalty: 20000,
      remainingDebt: 300000,
      taxes: 100000,
      openCapex: 15000,
      marketingCosts: 5000,
      otherCosts: 10000,
      originalPurchasePrice: 400000,
      acquisitionCosts: 40000,
      renovationCosts: 60000,
      runningCashflows: 100000,
      equityInvested: equityInvested,
      holdPeriodYears: holdPeriodYears,
      holdValue: 450000,
    );
  }

  test(
    'berechnet Nettoerloes, Steuern, Renditen und IRR per Referenzformel',
    () {
      final result = service.calculate(inputs());

      const salePrice = 1000000.0;
      const costsBeforeTax =
          30000 + 10000 + 5000 + 5000 + 20000 + 300000 + 15000 + 5000 + 10000;
      const taxes = 100000.0;
      const runningCashflows = 100000.0;
      const equity = 500000.0;
      const totalInvestment = 400000 + 40000 + 60000.0;
      const netBeforeTax = salePrice - costsBeforeTax;
      const netAfterTax = netBeforeTax - taxes;
      const returnBeforeTax = netBeforeTax + runningCashflows;
      const returnAfterTax = netAfterTax + runningCashflows;
      const profitBeforeTax = returnBeforeTax - equity;
      const profitAfterTax = returnAfterTax - equity;

      expect(result.totalSaleCostsBeforeTax, closeTo(costsBeforeTax, 1e-9));
      expect(result.totalSaleCosts, closeTo(costsBeforeTax + taxes, 1e-9));
      expect(result.netSaleProceedsBeforeTax, closeTo(netBeforeTax, 1e-9));
      expect(result.netSaleProceeds, closeTo(netAfterTax, 1e-9));
      expect(result.profitBeforeTax, closeTo(profitBeforeTax, 1e-9));
      expect(result.profitAfterTax, closeTo(profitAfterTax, 1e-9));
      expect(
        result.profitBeforeTax - result.profitAfterTax,
        closeTo(taxes, 1e-9),
      );
      expect(
        result.profitMargin,
        closeTo(profitAfterTax / totalInvestment, 1e-12),
      );
      expect(
        result.gainOnCost,
        closeTo((returnAfterTax - totalInvestment) / totalInvestment, 1e-12),
      );
      expect(result.equityMultiple, closeTo(returnAfterTax / equity, 1e-12));
      expect(result.exitCapRate, closeTo(50000 / salePrice, 1e-12));
      expect(result.irr, closeTo(0.10, 1e-8));
      expect(result.warnings, isEmpty);
    },
  );

  test('liefert bei fehlenden Bezugswerten null und passende Warnungen', () {
    final result = service.calculate(
      inputs(areaSqm: 0, equityInvested: 0, holdPeriodYears: 0),
    );

    expect(result.salePricePerSqm, isNull);
    expect(result.equityMultiple, isNull);
    expect(result.irr, isNull);
    expect(result.warnings, contains('Flaeche fehlt oder ist 0.'));
    expect(
      result.warnings,
      contains('Eingesetztes Eigenkapital fehlt oder ist 0.'),
    );
    expect(result.warnings, contains('Haltedauer fehlt oder ist 0.'));
  });
}
