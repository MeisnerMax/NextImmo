import '../models/investment_modules.dart';
import 'formula_audit_service.dart';

class RenovationCalculationService {
  const RenovationCalculationService({
    FormulaAuditService formulaAuditService = const FormulaAuditService(),
  }) : _audit = formulaAuditService;

  final FormulaAuditService _audit;

  RenovationModuleResult calculate(
    RenovationModuleInputs inputs, {
    String? scenarioId,
  }) {
    const module = 'renovation_value_add';
    final formulas = <FormulaAuditEntry>[];
    final warnings = <String>[];

    double? safeDivide(double numerator, double denominator) {
      if (denominator == 0) {
        return null;
      }
      return numerator / denominator;
    }

    if (inputs.budget <= 0) {
      warnings.add('Budget fehlt oder ist 0.');
    }
    if (inputs.affectedAreaSqm <= 0) {
      warnings.add('Betroffene Flaeche fehlt oder ist 0.');
    }
    if (inputs.capRateBefore <= 0 || inputs.capRateAfter <= 0) {
      warnings.add('Cap Rate vor oder nach Renovierung fehlt.');
    }
    if (inputs.modernizationCapPerSqm <= 0) {
      warnings.add('Kappungsgrenze fuer Modernisierungsmodell fehlt oder ist 0.');
    }
    if (inputs.renovationHorizonYears <= 0) {
      warnings.add('NPV-Horizont fehlt oder ist 0.');
    }
    if (inputs.discountRate <= -1) {
      warnings.add('Diskontierungszins muss groesser als -100 Prozent sein.');
    }
    if (inputs.riskBufferPercent < 0) {
      warnings.add('Risikopuffer darf nicht negativ sein.');
    }

    int normalizeRisk(int value) => value.clamp(1, 5).toInt();

    final plannedTotalCosts =
        inputs.budget + (inputs.budget * inputs.reservePercent);
    formulas.add(_audit.entry(
      formulaName: 'Gesamtkosten geplant',
      description: 'Budget + Reserve',
      inputs: <String, Object?>{
        'budget': inputs.budget,
        'reserve_percent': inputs.reservePercent,
      },
      result: plannedTotalCosts,
      unit: 'EUR',
      module: module,
      propertyId: inputs.propertyId,
      scenarioId: scenarioId,
    ));

    final forecastTotalCosts = inputs.actualCosts + inputs.expectedRemainingCosts;
    final costVariance = forecastTotalCosts - inputs.budget;
    final costVariancePercent = safeDivide(costVariance, inputs.budget);
    final costPerSqm = safeDivide(forecastTotalCosts, inputs.affectedAreaSqm);
    final recoverableModernizationCosts = (
      forecastTotalCosts -
          inputs.maintenanceShare -
          inputs.subsidies -
          inputs.insuranceRecoveries -
          inputs.nonRecoverableCostShare
    ).clamp(0, double.infinity).toDouble();
    final theoreticalModernizationRentIncreaseAnnual =
        recoverableModernizationCosts * 0.08;
    final theoreticalModernizationRentIncreaseMonthly =
        theoreticalModernizationRentIncreaseAnnual / 12;
    final legalModelCapMonthly =
        inputs.modernizationCapPerSqm * inputs.affectedAreaSqm;
    final modeledAllowableRentIncreaseMonthly =
        theoreticalModernizationRentIncreaseMonthly < legalModelCapMonthly
            ? theoreticalModernizationRentIncreaseMonthly
            : legalModelCapMonthly;
    final plannedRentIncreaseMonthly =
        inputs.targetRentMonthly - inputs.currentRentMonthly;
    final additionalAnnualRent =
        plannedRentIncreaseMonthly * 12;
    final rentLossDuringWorks =
        inputs.currentRentMonthly * inputs.vacancyMonthsDuringWorks;
    final yearOneRentEffect = additionalAnnualRent - rentLossDuringWorks;
    final additionalNoi = inputs.noiAfter - inputs.noiBefore;
    final valueBefore = safeDivide(inputs.noiBefore, inputs.capRateBefore);
    final valueAfter = safeDivide(inputs.noiAfter, inputs.capRateAfter);
    final valueUplift = valueBefore == null || valueAfter == null
        ? null
        : valueAfter - valueBefore;
    final netValueUplift =
        valueUplift == null ? null : valueUplift - forecastTotalCosts;
    final returnOnCost = safeDivide(additionalNoi, forecastTotalCosts);
    final yieldOnCost =
        safeDivide(inputs.noiAfter, inputs.totalInvestmentAfterRenovation);
    final paybackYears = safeDivide(forecastTotalCosts, additionalNoi);
    final breakEvenRentIncreaseMonthly =
        (forecastTotalCosts * inputs.targetYield) / 12;
    final delayMonths = (
      inputs.actualConstructionMonths - inputs.plannedConstructionMonths
    ).clamp(0, double.infinity).toDouble();
    final delayDays = (delayMonths * 30).round();
    final delayCosts = delayMonths * inputs.delayCostPerMonth;
    final riskValues = <int>[
      normalizeRisk(inputs.permitRisk),
      normalizeRisk(inputs.costRisk),
      normalizeRisk(inputs.rentLossRisk),
      normalizeRisk(inputs.technicalRisk),
      normalizeRisk(inputs.contractorAvailabilityRisk),
    ];
    final averageRisk =
        riskValues.reduce((value, element) => value + element) / riskValues.length;
    final riskScore = (
      ((averageRisk - 1) / 4 * 100).round().clamp(0, 100) as num
    ).toInt();
    final riskBufferAmount = forecastTotalCosts * inputs.riskBufferPercent;
    final worstCaseCosts = forecastTotalCosts + delayCosts + riskBufferAmount;
    double? renovationNpv;
    double? renovationIrr;
    if (inputs.renovationHorizonYears > 0 && inputs.discountRate > -1) {
      var discountedNoi = 0.0;
      for (var year = 1; year <= inputs.renovationHorizonYears; year += 1) {
        discountedNoi +=
            additionalNoi / _pow(1 + inputs.discountRate, year);
      }
      renovationNpv = -forecastTotalCosts + discountedNoi;
    }
    if (forecastTotalCosts > 0 &&
        inputs.renovationHorizonYears > 0 &&
        additionalNoi != 0) {
      renovationIrr = _irr(<double>[
        (-forecastTotalCosts as double),
        for (var year = 1; year <= inputs.renovationHorizonYears; year += 1)
          (additionalNoi as double),
      ]);
      if (renovationIrr == null) {
        warnings.add('Renovierungs-IRR konnte mit den aktuellen Cashflows nicht eindeutig berechnet werden.');
      }
    } else {
      warnings.add('Renovierungs-IRR benoetigt Renovierungskosten, Horizont und zusaetzlichen NOI.');
    }

    formulas.addAll(<FormulaAuditEntry>[
      _audit.entry(
        formulaName: 'Kostenabweichung',
        description: 'Forecast Gesamtkosten - Budget',
        inputs: <String, Object?>{
          'forecast_total_costs': forecastTotalCosts,
          'budget': inputs.budget,
        },
        result: costVariance,
        unit: 'EUR',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Kosten pro Quadratmeter',
        description: 'Forecast Gesamtkosten / betroffene Flaeche',
        inputs: <String, Object?>{
          'forecast_total_costs': forecastTotalCosts,
          'affected_area_sqm': inputs.affectedAreaSqm,
        },
        result: costPerSqm,
        unit: 'EUR/sqm',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Umlagefaehige Modernisierungskosten',
        description:
            'Forecast Kosten - Instandhaltungsanteil - Foerdermittel - Erstattungen - nicht umlagefaehiger Anteil',
        inputs: <String, Object?>{
          'forecast_total_costs': forecastTotalCosts,
          'maintenance_share': inputs.maintenanceShare,
          'subsidies': inputs.subsidies,
          'insurance_recoveries': inputs.insuranceRecoveries,
          'non_recoverable_cost_share': inputs.nonRecoverableCostShare,
        },
        result: recoverableModernizationCosts,
        unit: 'EUR',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Modernisierungsmieterhoehung Modell',
        description: 'Umlagefaehige Modernisierungskosten * 8 Prozent / 12',
        inputs: <String, Object?>{
          'recoverable_modernization_costs': recoverableModernizationCosts,
          'annual_model_rate': 0.08,
        },
        result: theoreticalModernizationRentIncreaseMonthly,
        unit: 'EUR/month',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Zulaessige modellierte Mieterhoehung',
        description: 'Minimum aus theoretischer Erhoehung und eingegebener Kappungsgrenze',
        inputs: <String, Object?>{
          'theoretical_monthly': theoreticalModernizationRentIncreaseMonthly,
          'cap_monthly': legalModelCapMonthly,
        },
        result: modeledAllowableRentIncreaseMonthly,
        unit: 'EUR/month',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Nettoeffekt Miete Jahr 1',
        description: 'zusaetzlicher Jahresmietertrag - Mietausfall Bau',
        inputs: <String, Object?>{
          'additional_annual_rent': additionalAnnualRent,
          'rent_loss_during_works': rentLossDuringWorks,
        },
        result: yearOneRentEffect,
        unit: 'EUR/year',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Wertsteigerung',
        description: 'Wert nach Renovierung - Wert vor Renovierung',
        inputs: <String, Object?>{
          'value_before': valueBefore,
          'value_after': valueAfter,
        },
        result: valueUplift,
        unit: 'EUR',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Return on Cost',
        description: 'Zusaetzlicher NOI / Renovierungskosten',
        inputs: <String, Object?>{
          'additional_noi': additionalNoi,
          'forecast_total_costs': forecastTotalCosts,
        },
        result: returnOnCost,
        unit: 'ratio',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Payback Period',
        description: 'Renovierungskosten / zusaetzlicher jaehrlicher Cashflow',
        inputs: <String, Object?>{
          'forecast_total_costs': forecastTotalCosts,
          'additional_noi': additionalNoi,
        },
        result: paybackYears,
        unit: 'years',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Renovierungs-NPV',
        description:
            '-Renovierungskosten + diskontierter zusaetzlicher NOI ueber Horizont',
        inputs: <String, Object?>{
          'forecast_total_costs': forecastTotalCosts,
          'additional_noi': additionalNoi,
          'horizon_years': inputs.renovationHorizonYears,
          'discount_rate': inputs.discountRate,
        },
        result: renovationNpv,
        unit: 'EUR',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Renovierungs-IRR',
        description:
            'Interner Zinsfuss aus initialen Renovierungskosten und zusaetzlichem NOI je Jahr',
        inputs: <String, Object?>{
          'forecast_total_costs': forecastTotalCosts,
          'additional_noi': additionalNoi,
          'horizon_years': inputs.renovationHorizonYears,
        },
        result: renovationIrr,
        unit: 'ratio',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Verzoegerungskosten',
        description: 'Positive Abweichung Ist-Bauzeit - Plan-Bauzeit * Kosten je Monat',
        inputs: <String, Object?>{
          'planned_construction_months': inputs.plannedConstructionMonths,
          'actual_construction_months': inputs.actualConstructionMonths,
          'delay_cost_per_month': inputs.delayCostPerMonth,
        },
        result: delayCosts,
        unit: 'EUR',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Worst-Case-Kosten',
        description: 'Forecast Kosten + Verzoegerungskosten + Risikopuffer',
        inputs: <String, Object?>{
          'forecast_total_costs': forecastTotalCosts,
          'delay_costs': delayCosts,
          'risk_buffer_amount': riskBufferAmount,
        },
        result: worstCaseCosts,
        unit: 'EUR',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Renovierungs-Risiko-Score',
        description: 'Durchschnitt der Risiko-Eingaben 1 bis 5 skaliert auf 0 bis 100',
        inputs: <String, Object?>{
          'permit_risk': normalizeRisk(inputs.permitRisk),
          'cost_risk': normalizeRisk(inputs.costRisk),
          'rent_loss_risk': normalizeRisk(inputs.rentLossRisk),
          'technical_risk': normalizeRisk(inputs.technicalRisk),
          'contractor_availability_risk':
              normalizeRisk(inputs.contractorAvailabilityRisk),
        },
        result: riskScore.toDouble(),
        unit: 'score',
        module: module,
        propertyId: inputs.propertyId,
        scenarioId: scenarioId,
      ),
    ]);

    return RenovationModuleResult(
      plannedTotalCosts: plannedTotalCosts,
      forecastTotalCosts: forecastTotalCosts,
      costVariance: costVariance,
      costVariancePercent: costVariancePercent,
      costPerSqm: costPerSqm,
      recoverableModernizationCosts: recoverableModernizationCosts,
      theoreticalModernizationRentIncreaseAnnual:
          theoreticalModernizationRentIncreaseAnnual,
      theoreticalModernizationRentIncreaseMonthly:
          theoreticalModernizationRentIncreaseMonthly,
      legalModelCapMonthly: legalModelCapMonthly,
      modeledAllowableRentIncreaseMonthly: modeledAllowableRentIncreaseMonthly,
      plannedRentIncreaseMonthly: plannedRentIncreaseMonthly,
      additionalAnnualRent: additionalAnnualRent,
      rentLossDuringWorks: rentLossDuringWorks,
      yearOneRentEffect: yearOneRentEffect,
      additionalNoi: additionalNoi,
      valueBefore: valueBefore,
      valueAfter: valueAfter,
      valueUplift: valueUplift,
      netValueUplift: netValueUplift,
      returnOnCost: returnOnCost,
      yieldOnCost: yieldOnCost,
      paybackYears: paybackYears,
      breakEvenRentIncreaseMonthly: breakEvenRentIncreaseMonthly,
      renovationNpv: renovationNpv,
      renovationIrr: renovationIrr,
      delayMonths: delayMonths,
      delayDays: delayDays,
      delayCosts: delayCosts,
      riskBufferAmount: riskBufferAmount,
      worstCaseCosts: worstCaseCosts,
      riskScore: riskScore,
      warnings: warnings,
      formulas: formulas,
    );
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
