import '../models/investment_modules.dart';
import 'formula_audit_service.dart';

class DispositionCalculationService {
  const DispositionCalculationService({
    FormulaAuditService formulaAuditService = const FormulaAuditService(),
  }) : _audit = formulaAuditService;

  final FormulaAuditService _audit;

  DispositionModuleResult calculate(
    DispositionModuleInputs inputs, {
    String? scenarioId,
  }) {
    const module = 'disposition_exit';
    final formulas = <FormulaAuditEntry>[];
    final warnings = <String>[];

    double? safeDivide(double numerator, double denominator) {
      if (denominator == 0) {
        return null;
      }
      return numerator / denominator;
    }

    if (inputs.expectedSalePrice <= 0) {
      warnings.add('Erwarteter Verkaufspreis fehlt oder ist 0.');
    }
    if (inputs.areaSqm <= 0) {
      warnings.add('Flaeche fehlt oder ist 0.');
    }
    if (inputs.equityInvested <= 0) {
      warnings.add('Eingesetztes Eigenkapital fehlt oder ist 0.');
    }
    if (inputs.holdPeriodYears <= 0) {
      warnings.add('Haltedauer fehlt oder ist 0.');
    }

    final grossSaleProceeds = inputs.expectedSalePrice;
    formulas.add(_audit.entry(
      formulaName: 'Bruttoverkaufserloes',
      description: 'Verkaufspreis',
      inputs: <String, Object?>{'expected_sale_price': inputs.expectedSalePrice},
      result: grossSaleProceeds,
      unit: 'EUR',
      module: module,
      propertyId: inputs.propertyId,
      scenarioId: scenarioId,
    ));

    final totalSaleCostsBeforeTax = inputs.brokerCosts +
        inputs.legalCosts +
        inputs.notaryCosts +
        inputs.dueDiligenceCosts +
        inputs.prepaymentPenalty +
        inputs.remainingDebt +
        inputs.openCapex +
        inputs.marketingCosts +
        inputs.otherCosts;
    final totalSaleCosts = totalSaleCostsBeforeTax + inputs.taxes;
    final netSaleProceedsBeforeTax = grossSaleProceeds - totalSaleCostsBeforeTax;
    final netSaleProceeds = grossSaleProceeds - totalSaleCosts;
    formulas.add(_audit.entry(
      formulaName: 'Nettoverkaufserloes',
      description:
          'Verkaufspreis - Verkaufskosten - Restschuld - Vorfaelligkeit - Steuern - sonstige Abzuege',
      inputs: <String, Object?>{
        'gross_sale_proceeds': grossSaleProceeds,
        'total_sale_costs_before_tax': totalSaleCostsBeforeTax,
        'taxes': inputs.taxes,
        'total_sale_costs': totalSaleCosts,
      },
      result: netSaleProceeds,
      unit: 'EUR',
      module: module,
      propertyId: inputs.propertyId,
      scenarioId: scenarioId,
    ));

    final totalInvestment = inputs.originalPurchasePrice +
        inputs.acquisitionCosts +
        inputs.renovationCosts;
    final acquisitionBasis = inputs.originalPurchasePrice + inputs.acquisitionCosts;
    final totalReturnBeforeTax =
        netSaleProceedsBeforeTax + inputs.runningCashflows;
    final totalReturnAfterTax = netSaleProceeds + inputs.runningCashflows;
    final profitBeforeTax =
        totalReturnBeforeTax - inputs.equityInvested;
    final profitAfterTax = totalReturnAfterTax - inputs.equityInvested;
    final profitMargin = safeDivide(profitAfterTax, totalInvestment);
    final gainVsTotalInvestment = totalReturnAfterTax - totalInvestment;
    final gainOnCost = safeDivide(gainVsTotalInvestment, totalInvestment);
    final performanceVsAcquisitionCost = totalReturnAfterTax - acquisitionBasis;
    final performanceVsRenovationAdjustedCost =
        totalReturnAfterTax - totalInvestment;
    final salePricePerSqm = safeDivide(inputs.expectedSalePrice, inputs.areaSqm);
    final salePriceFactor =
        safeDivide(inputs.expectedSalePrice, inputs.annualColdRent);
    final exitCapRate = safeDivide(inputs.currentNoi, inputs.expectedSalePrice);
    final valueByTargetCapRate =
        safeDivide(inputs.stabilizedNoi, inputs.exitCapRate);
    double? irr;
    if (inputs.equityInvested > 0 && inputs.holdPeriodYears > 0) {
      final annualCashflow = inputs.runningCashflows / inputs.holdPeriodYears;
      irr = _irr(<double>[
        (-inputs.equityInvested as double),
        for (var year = 1; year < inputs.holdPeriodYears; year += 1)
          (annualCashflow as double),
        (annualCashflow + netSaleProceeds as double),
      ]);
      if (irr == null) {
        warnings.add('Verkaufs-IRR konnte mit den aktuellen Cashflows nicht eindeutig berechnet werden.');
      }
    }
    final equityMultiple = safeDivide(
      netSaleProceeds + inputs.runningCashflows,
      inputs.equityInvested,
    );
    final holdVsSellDifference = netSaleProceeds - inputs.holdValue;
    final minimumSalePriceForTarget = inputs.minimumSalePrice +
        totalSaleCosts -
        inputs.runningCashflows +
        inputs.equityInvested;

    formulas.addAll(<FormulaAuditEntry>[
      _audit.entry(
        formulaName: 'Gewinn vor Steuern',
        description:
            'Nettoverkaufserloes vor Steuern + laufende Cashflows - Eigenkapitalinvestition',
        inputs: <String, Object?>{
          'net_sale_proceeds_before_tax': netSaleProceedsBeforeTax,
          'running_cashflows': inputs.runningCashflows,
          'equity_invested': inputs.equityInvested,
        },
        result: profitBeforeTax,
        unit: 'EUR',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Gewinn nach Steuern',
        description:
            'Nettoverkaufserloes nach Steuern + laufende Cashflows - Eigenkapitalinvestition',
        inputs: <String, Object?>{
          'net_sale_proceeds': netSaleProceeds,
          'running_cashflows': inputs.runningCashflows,
          'equity_invested': inputs.equityInvested,
          'taxes': inputs.taxes,
        },
        result: profitAfterTax,
        unit: 'EUR',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Gesamtergebnis gegen Gesamtinvestition',
        description:
            'Nettoverkaufserloes + laufende Cashflows - Kaufpreis - Kaufnebenkosten - Renovierungskosten',
        inputs: <String, Object?>{
          'net_sale_proceeds': netSaleProceeds,
          'running_cashflows': inputs.runningCashflows,
          'original_purchase_price': inputs.originalPurchasePrice,
          'acquisition_costs': inputs.acquisitionCosts,
          'renovation_costs': inputs.renovationCosts,
        },
        result: gainVsTotalInvestment,
        unit: 'EUR',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Performance gegen Ankaufskosten',
        description:
            'Nettoverkaufserloes + laufende Cashflows - Kaufpreis - Kaufnebenkosten',
        inputs: <String, Object?>{
          'total_return_after_tax': totalReturnAfterTax,
          'original_purchase_price': inputs.originalPurchasePrice,
          'acquisition_costs': inputs.acquisitionCosts,
        },
        result: performanceVsAcquisitionCost,
        unit: 'EUR',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Performance gegen Renovierungsszenario',
        description:
            'Nettoverkaufserloes + laufende Cashflows - Kaufpreis - Kaufnebenkosten - Renovierungskosten',
        inputs: <String, Object?>{
          'total_return_after_tax': totalReturnAfterTax,
          'total_investment': totalInvestment,
        },
        result: performanceVsRenovationAdjustedCost,
        unit: 'EUR',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Verkaufspreis pro Quadratmeter',
        description: 'Verkaufspreis / Flaeche',
        inputs: <String, Object?>{
          'expected_sale_price': inputs.expectedSalePrice,
          'area_sqm': inputs.areaSqm,
        },
        result: salePricePerSqm,
        unit: 'EUR/sqm',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Exit Cap Rate',
        description: 'NOI / Verkaufspreis',
        inputs: <String, Object?>{
          'current_noi': inputs.currentNoi,
          'expected_sale_price': inputs.expectedSalePrice,
        },
        result: exitCapRate,
        unit: 'ratio',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Equity Multiple',
        description: 'gesamte Rueckfluesse / eingesetztes Eigenkapital',
        inputs: <String, Object?>{
          'net_sale_proceeds': netSaleProceeds,
          'running_cashflows': inputs.runningCashflows,
          'equity_invested': inputs.equityInvested,
        },
        result: equityMultiple,
        unit: 'multiple',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Verkaufs-IRR',
        description:
            'Interner Zinsfuss aus Eigenkapitaleinsatz, laufenden Cashflows und Nettoverkaufserloes',
        inputs: <String, Object?>{
          'equity_invested': inputs.equityInvested,
          'running_cashflows': inputs.runningCashflows,
          'net_sale_proceeds': netSaleProceeds,
          'hold_period_years': inputs.holdPeriodYears,
        },
        result: irr,
        unit: 'ratio',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Hold-vs-Sell-Differenz',
        description: 'Sell Value - Hold Value',
        inputs: <String, Object?>{
          'sell_value': netSaleProceeds,
          'hold_value': inputs.holdValue,
        },
        result: holdVsSellDifference,
        unit: 'EUR',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
    ]);

    return DispositionModuleResult(
      grossSaleProceeds: grossSaleProceeds,
      totalSaleCostsBeforeTax: totalSaleCostsBeforeTax,
      totalSaleCosts: totalSaleCosts,
      netSaleProceedsBeforeTax: netSaleProceedsBeforeTax,
      netSaleProceeds: netSaleProceeds,
      totalInvestment: totalInvestment,
      totalReturnBeforeTax: totalReturnBeforeTax,
      totalReturnAfterTax: totalReturnAfterTax,
      profitBeforeTax: profitBeforeTax,
      profitAfterTax: profitAfterTax,
      profitMargin: profitMargin,
      gainVsTotalInvestment: gainVsTotalInvestment,
      gainOnCost: gainOnCost,
      performanceVsAcquisitionCost: performanceVsAcquisitionCost,
      performanceVsRenovationAdjustedCost:
          performanceVsRenovationAdjustedCost,
      salePricePerSqm: salePricePerSqm,
      salePriceFactor: salePriceFactor,
      exitCapRate: exitCapRate,
      valueByTargetCapRate: valueByTargetCapRate,
      irr: irr,
      equityMultiple: equityMultiple,
      holdVsSellDifference: holdVsSellDifference,
      minimumSalePriceForTarget: minimumSalePriceForTarget,
      warnings: warnings,
      formulas: formulas,
    );
  }

  List<DispositionOfferRanking> rankOffers({
    required List<DispositionOfferInput> offers,
    required double targetSalePrice,
  }) {
    final ranked = offers.map((offer) {
      final probability = offer.closingProbability.clamp(0, 1).toDouble();
      final riskPenalty =
          ((offer.riskScore.clamp(1, 5) as num).toDouble() - 1) * 0.04;
      final financingPenalty = offer.financingConfirmed ? 0.0 : 0.08;
      final riskAdjustedValue =
          offer.offerPrice * (probability - riskPenalty - financingPenalty);
      return DispositionOfferRanking(
        offer: offer,
        deviationToTarget: offer.offerPrice - targetSalePrice,
        riskAdjustedValue: riskAdjustedValue,
        rank: 0,
        warning: offer.financingConfirmed
            ? null
            : 'Finanzierungsnachweis fehlt.',
      );
    }).toList()
      ..sort((a, b) => b.riskAdjustedValue.compareTo(a.riskAdjustedValue));

    return <DispositionOfferRanking>[
      for (var i = 0; i < ranked.length; i++)
        DispositionOfferRanking(
          offer: ranked[i].offer,
          deviationToTarget: ranked[i].deviationToTarget,
          riskAdjustedValue: ranked[i].riskAdjustedValue,
          rank: i + 1,
          warning: ranked[i].warning,
        ),
    ];
  }

  double? _irr(List<double> cashflows) {
    if (cashflows.length < 2) {
      return null;
    }
    final hasPositive = cashflows.any((value) => value > 0);
    final hasNegative = cashflows.any((value) => value < 0);
    if (!hasPositive || !hasNegative) {
      return null;
    }

    var low = -0.99;
    var high = 10.0;
    var lowValue = _npv(cashflows, low);
    var highValue = _npv(cashflows, high);
    if (lowValue == null || highValue == null) {
      return null;
    }
    var expansions = 0;
    while (lowValue!.sign == highValue!.sign && expansions < 20) {
      high *= 2;
      highValue = _npv(cashflows, high);
      if (highValue == null) {
        return null;
      }
      expansions += 1;
    }
    if (lowValue!.sign == highValue!.sign) {
      return null;
    }

    for (var i = 0; i < 100; i += 1) {
      final mid = (low + high) / 2;
      final midValue = _npv(cashflows, mid);
      if (midValue == null) {
        return null;
      }
      if (midValue.abs() < 0.000001) {
        return mid;
      }
      if (midValue.sign == lowValue!.sign) {
        low = mid;
        lowValue = midValue;
      } else {
        high = mid;
      }
    }
    return (low + high) / 2;
  }

  double? _npv(List<double> cashflows, double rate) {
    if (rate <= -1) {
      return null;
    }
    var value = 0.0;
    for (var period = 0; period < cashflows.length; period += 1) {
      value += cashflows[period] / _pow(1 + rate, period);
    }
    return value;
  }

  double _pow(double base, int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i += 1) {
      result *= base;
    }
    return result;
  }
}
