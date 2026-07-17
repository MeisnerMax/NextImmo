import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/investment_modules.dart';
import 'package:neximmo_app/core/services/renovation_calculation_service.dart';

void main() {
  const service = RenovationCalculationService();

  test('berechnet deterministischen Sanierungs-Referenzfall', () {
    final result = service.calculate(_inputs());

    const forecastCosts = 60000.0 + 40000.0;
    const additionalNoi = 160000.0 - 100000.0;
    final expectedNpv =
        -forecastCosts + additionalNoi / 1.1 + additionalNoi / math.pow(1.1, 2);
    final expectedIrr = (3 + math.sqrt(69)) / 10 - 1;

    expect(result.plannedTotalCosts, closeTo(90000 * 1.1, 1e-9));
    expect(result.forecastTotalCosts, closeTo(forecastCosts, 1e-9));
    expect(result.costVariance, closeTo(forecastCosts - 90000, 1e-9));
    expect(result.costVariancePercent, closeTo(10000 / 90000, 1e-12));
    expect(result.costPerSqm, closeTo(forecastCosts / 200, 1e-9));
    expect(
      result.recoverableModernizationCosts,
      closeTo(forecastCosts - 10000 - 5000 - 2000 - 3000, 1e-9),
    );
    expect(
      result.modeledAllowableRentIncreaseMonthly,
      closeTo(math.min(80000 * 0.08 / 12, 2 * 200), 1e-9),
    );
    expect(
      result.yearOneRentEffect,
      closeTo((12000 - 10000) * 12 - 10000 * 2, 1e-9),
    );

    expect(result.additionalNoi, closeTo(additionalNoi, 1e-9));
    expect(result.valueUplift, closeTo(160000 / 0.04 - 100000 / 0.05, 1e-8));
    expect(
      result.netValueUplift,
      closeTo(160000 / 0.04 - 100000 / 0.05 - forecastCosts, 1e-8),
    );
    expect(result.returnOnCost, closeTo(additionalNoi / forecastCosts, 1e-12));
    expect(result.yieldOnCost, closeTo(160000 / 2500000, 1e-12));
    expect(result.paybackYears, closeTo(forecastCosts / additionalNoi, 1e-12));
    expect(result.renovationNpv, closeTo(expectedNpv, 1e-8));
    expect(result.renovationIrr, closeTo(expectedIrr, 1e-10));

    expect(result.delayMonths, closeTo(10 - 8, 1e-9));
    expect(result.delayCosts, closeTo((10 - 8) * 3000, 1e-9));
    expect(result.riskBufferAmount, closeTo(forecastCosts * 0.15, 1e-9));
    expect(
      result.worstCaseCosts,
      closeTo(forecastCosts + 2 * 3000 + forecastCosts * 0.15, 1e-9),
    );
    expect(result.riskScore, 50);
    expect(result.warnings, isEmpty);
  });

  test('liefert bei Nullwerten keine dividierten Renditekennzahlen', () {
    final result = service.calculate(
      _inputs(
        budget: 0,
        actualCosts: 0,
        expectedRemainingCosts: 0,
        affectedAreaSqm: 0,
        noiBefore: 100000,
        noiAfter: 100000,
        capRateBefore: 0,
        capRateAfter: 0,
        totalInvestmentAfterRenovation: 0,
        renovationHorizonYears: 0,
      ),
    );

    expect(result.costVariancePercent, isNull);
    expect(result.costPerSqm, isNull);
    expect(result.valueBefore, isNull);
    expect(result.valueAfter, isNull);
    expect(result.returnOnCost, isNull);
    expect(result.yieldOnCost, isNull);
    expect(result.paybackYears, isNull);
    expect(result.renovationNpv, isNull);
    expect(result.renovationIrr, isNull);
    expect(result.warnings, contains('Budget fehlt oder ist 0.'));
    expect(result.warnings, contains('NPV-Horizont fehlt oder ist 0.'));
    expect(
      result.warnings,
      contains(
        'Renovierungs-IRR benoetigt Renovierungskosten, Horizont und zusaetzlichen NOI.',
      ),
    );
  });
}

RenovationModuleInputs _inputs({
  double budget = 90000,
  double actualCosts = 60000,
  double expectedRemainingCosts = 40000,
  double affectedAreaSqm = 200,
  double noiBefore = 100000,
  double noiAfter = 160000,
  double capRateBefore = 0.05,
  double capRateAfter = 0.04,
  double totalInvestmentAfterRenovation = 2500000,
  int renovationHorizonYears = 2,
}) {
  return RenovationModuleInputs(
    projectName: 'Referenzsanierung',
    budget: budget,
    actualCosts: actualCosts,
    expectedRemainingCosts: expectedRemainingCosts,
    reservePercent: 0.1,
    maintenanceShare: 10000,
    subsidies: 5000,
    insuranceRecoveries: 2000,
    nonRecoverableCostShare: 3000,
    modernizationCapPerSqm: 2,
    affectedAreaSqm: affectedAreaSqm,
    currentRentMonthly: 10000,
    targetRentMonthly: 12000,
    vacancyMonthsDuringWorks: 2,
    noiBefore: noiBefore,
    noiAfter: noiAfter,
    capRateBefore: capRateBefore,
    capRateAfter: capRateAfter,
    totalInvestmentAfterRenovation: totalInvestmentAfterRenovation,
    targetYield: 0.06,
    renovationHorizonYears: renovationHorizonYears,
    discountRate: 0.1,
    plannedConstructionMonths: 8,
    actualConstructionMonths: 10,
    delayCostPerMonth: 3000,
    permitRisk: 1,
    costRisk: 2,
    rentLossRisk: 3,
    technicalRisk: 4,
    contractorAvailabilityRisk: 5,
    riskBufferPercent: 0.15,
  );
}
