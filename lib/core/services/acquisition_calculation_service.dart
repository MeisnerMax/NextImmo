import '../models/investment_modules.dart';
import 'formula_audit_service.dart';

class AcquisitionCalculationService {
  const AcquisitionCalculationService({
    FormulaAuditService formulaAuditService = const FormulaAuditService(),
  }) : _audit = formulaAuditService;

  final FormulaAuditService _audit;

  AcquisitionQuickResult calculateQuickEvaluation(
    AcquisitionQuickInputs inputs, {
    String? propertyId,
    String? scenarioId,
  }) {
    const module = 'acquisition_quick';
    final formulas = <FormulaAuditEntry>[];
    final warnings = <String>[];

    double? safeDivide(double numerator, double denominator) {
      if (denominator == 0) {
        return null;
      }
      return numerator / denominator;
    }

    void warnIfMissing(bool condition, String message) {
      if (condition) {
        warnings.add(message);
      }
    }

    final area = inputs.totalAreaSqm;
    warnIfMissing(area <= 0, 'Flaeche fehlt oder ist 0.');
    warnIfMissing(inputs.offerPrice <= 0, 'Angebotspreis fehlt oder ist 0.');
    warnIfMissing(inputs.targetCapRate <= 0, 'Ziel-Cap-Rate fehlt oder ist 0.');
    warnIfMissing(inputs.equity <= 0, 'Eigenkapital fehlt oder ist 0.');

    final purchasePricePerSqm = safeDivide(inputs.offerPrice, area);
    formulas.add(_audit.entry(
      formulaName: 'Kaufpreis pro Quadratmeter',
      description: 'Angebotspreis / Gesamtflaeche',
      inputs: <String, Object?>{
        'offer_price': inputs.offerPrice,
        'area_sqm': area,
      },
      result: purchasePricePerSqm,
      unit: 'EUR/sqm',
      module: module,
      propertyId: propertyId,
      scenarioId: scenarioId,
    ));

    final percentClosingCosts = inputs.offerPrice * inputs.closingCostPercent;
    final renovationSafety =
        inputs.renovationBudget * inputs.renovationSafetyPercent;
    final totalInvestment = inputs.offerPrice +
        percentClosingCosts +
        inputs.brokerFee +
        inputs.transferTax +
        inputs.notaryAndLandRegistry +
        inputs.otherAcquisitionCosts +
        inputs.renovationBudget +
        renovationSafety;
    formulas.add(_audit.entry(
      formulaName: 'Gesamtinvestition',
      description:
          'Kaufpreis + Kaufnebenkosten + Renovierung + Sicherheitsaufschlag',
      inputs: <String, Object?>{
        'offer_price': inputs.offerPrice,
        'closing_costs_percent_amount': percentClosingCosts,
        'broker_fee': inputs.brokerFee,
        'transfer_tax': inputs.transferTax,
        'notary_and_land_registry': inputs.notaryAndLandRegistry,
        'other_acquisition_costs': inputs.otherAcquisitionCosts,
        'renovation_budget': inputs.renovationBudget,
        'renovation_safety': renovationSafety,
      },
      result: totalInvestment,
      unit: 'EUR',
      module: module,
      propertyId: propertyId,
      scenarioId: scenarioId,
    ));

    final annualColdRent = inputs.currentColdRentMonthly * 12;
    final grossInitialYield = safeDivide(annualColdRent, inputs.offerPrice);
    formulas.add(_audit.entry(
      formulaName: 'Bruttoanfangsrendite',
      description: 'Jahreskaltmiete / Kaufpreis',
      inputs: <String, Object?>{
        'annual_cold_rent': annualColdRent,
        'offer_price': inputs.offerPrice,
      },
      result: grossInitialYield,
      unit: 'ratio',
      module: module,
      propertyId: propertyId,
      scenarioId: scenarioId,
    ));

    final annualRent = inputs.currentColdRentMonthly * 12;
    final annualOtherIncome = inputs.otherIncomeMonthly * 12;
    final vacancyLoss = (annualRent + annualOtherIncome) * inputs.vacancyPercent;
    final effectiveGrossIncome = annualRent + annualOtherIncome - vacancyLoss;
    formulas.add(_audit.entry(
      formulaName: 'Effective Gross Income',
      description: 'Jahresmiete + sonstige Einnahmen - Leerstandsverlust',
      inputs: <String, Object?>{
        'annual_rent': annualRent,
        'annual_other_income': annualOtherIncome,
        'vacancy_loss': vacancyLoss,
      },
      result: effectiveGrossIncome,
      unit: 'EUR/year',
      module: module,
      propertyId: propertyId,
      scenarioId: scenarioId,
    ));

    final maintenanceMonthly = inputs.maintenancePerSqmYear * area / 12;
    final operatingExpenses = (inputs.nonRecoverableCostsMonthly +
            maintenanceMonthly +
            inputs.managementCostsMonthly +
            inputs.insuranceMonthly +
            inputs.propertyTaxMonthly +
            inputs.otherCostsMonthly) *
        12;
    formulas.add(_audit.entry(
      formulaName: 'Operating Expenses',
      description: 'Summe laufender nicht umlagefaehiger Kosten',
      inputs: <String, Object?>{
        'non_recoverable_costs_monthly': inputs.nonRecoverableCostsMonthly,
        'maintenance_monthly': maintenanceMonthly,
        'management_costs_monthly': inputs.managementCostsMonthly,
        'insurance_monthly': inputs.insuranceMonthly,
        'property_tax_monthly': inputs.propertyTaxMonthly,
        'other_costs_monthly': inputs.otherCostsMonthly,
      },
      result: operatingExpenses,
      unit: 'EUR/year',
      module: module,
      propertyId: propertyId,
      scenarioId: scenarioId,
    ));

    final noi = effectiveGrossIncome - operatingExpenses;
    formulas.add(_audit.entry(
      formulaName: 'NOI',
      description: 'Effective Gross Income - Operating Expenses',
      inputs: <String, Object?>{
        'effective_gross_income': effectiveGrossIncome,
        'operating_expenses': operatingExpenses,
      },
      result: noi,
      unit: 'EUR/year',
      module: module,
      propertyId: propertyId,
      scenarioId: scenarioId,
    ));

    final netInitialYield = safeDivide(noi, totalInvestment);
    final annualInterest = inputs.loanAmount * inputs.interestRatePercent;
    final annualAmortization = inputs.loanAmount * inputs.amortizationPercent;
    final debtServiceAnnual = annualInterest + annualAmortization;
    final cashflowBeforeTax = noi - debtServiceAnnual;
    final cashOnCash = safeDivide(cashflowBeforeTax, inputs.equity);
    final loanToValue = safeDivide(inputs.loanAmount, inputs.offerPrice);
    final valueBasedOnCapRate = safeDivide(noi, inputs.targetCapRate);
    final maxReasonablePurchasePrice = valueBasedOnCapRate == null
        ? null
        : valueBasedOnCapRate -
            percentClosingCosts -
            inputs.brokerFee -
            inputs.transferTax -
            inputs.notaryAndLandRegistry -
            inputs.otherAcquisitionCosts -
            inputs.renovationBudget -
            renovationSafety -
            inputs.desiredMargin;

    formulas.addAll(<FormulaAuditEntry>[
      _audit.entry(
        formulaName: 'Kapitaldienst',
        description: 'Darlehen * Zinssatz + Darlehen * Tilgung',
        inputs: <String, Object?>{
          'loan_amount': inputs.loanAmount,
          'interest_rate_percent': inputs.interestRatePercent,
          'amortization_percent': inputs.amortizationPercent,
        },
        result: debtServiceAnnual,
        unit: 'EUR/year',
        module: module,
        propertyId: propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Cashflow vor Steuern',
        description: 'NOI - Kapitaldienst',
        inputs: <String, Object?>{
          'noi': noi,
          'debt_service_annual': debtServiceAnnual,
        },
        result: cashflowBeforeTax,
        unit: 'EUR/year',
        module: module,
        propertyId: propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Cash-on-Cash-Rendite',
        description: 'Cashflow vor Steuern / eingesetztes Eigenkapital',
        inputs: <String, Object?>{
          'cashflow_before_tax': cashflowBeforeTax,
          'equity': inputs.equity,
        },
        result: cashOnCash,
        unit: 'ratio',
        module: module,
        propertyId: propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Loan-to-Value',
        description: 'Darlehensbetrag / Immobilienwert',
        inputs: <String, Object?>{
          'loan_amount': inputs.loanAmount,
          'offer_price': inputs.offerPrice,
        },
        result: loanToValue,
        unit: 'ratio',
        module: module,
        propertyId: propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Value based on Cap Rate',
        description: 'NOI / Ziel-Cap-Rate',
        inputs: <String, Object?>{
          'noi': noi,
          'target_cap_rate': inputs.targetCapRate,
        },
        result: valueBasedOnCapRate,
        unit: 'EUR',
        module: module,
        propertyId: propertyId,
        scenarioId: scenarioId,
      ),
      _audit.entry(
        formulaName: 'Maximaler sinnvoller Kaufpreis',
        description:
            'Zielwert minus Erwerbskosten, Renovierung, Sicherheit und Marge',
        inputs: <String, Object?>{
          'value_based_on_cap_rate': valueBasedOnCapRate,
          'costs_and_margin': valueBasedOnCapRate == null
              ? null
              : valueBasedOnCapRate - maxReasonablePurchasePrice!,
        },
        result: maxReasonablePurchasePrice,
        unit: 'EUR',
        module: module,
        propertyId: propertyId,
        scenarioId: scenarioId,
      ),
    ]);

    final criteria = <CriterionTrafficLight>[
      CriterionTrafficLight(
        label: 'Mindest-Cashflow',
        value: cashflowBeforeTax / 12,
        target: inputs.minimumCashflow,
        status: _minStatus(cashflowBeforeTax / 12, inputs.minimumCashflow),
      ),
      CriterionTrafficLight(
        label: 'Mindestmietrendite',
        value: grossInitialYield ?? 0,
        target: inputs.minimumGrossYield,
        status: _minStatus(grossInitialYield, inputs.minimumGrossYield),
      ),
      CriterionTrafficLight(
        label: 'Mindest-Cap-Rate',
        value: netInitialYield ?? 0,
        target: inputs.minimumCapRate,
        status: _minStatus(netInitialYield, inputs.minimumCapRate),
      ),
      CriterionTrafficLight(
        label: 'Mindest-Cash-on-Cash',
        value: cashOnCash ?? 0,
        target: inputs.minimumCashOnCash,
        status: _minStatus(cashOnCash, inputs.minimumCashOnCash),
      ),
      CriterionTrafficLight(
        label: 'Max. Kaufpreis pro qm',
        value: purchasePricePerSqm ?? 0,
        target: inputs.maxPurchasePricePerSqm,
        status: _maxStatus(purchasePricePerSqm, inputs.maxPurchasePricePerSqm),
      ),
      CriterionTrafficLight(
        label: 'Max. LTV',
        value: loanToValue ?? 0,
        target: inputs.maxLoanToValue,
        status: _maxStatus(loanToValue, inputs.maxLoanToValue),
      ),
      CriterionTrafficLight(
        label: 'Max. Renovierungsanteil',
        value: safeDivide(inputs.renovationBudget + renovationSafety, totalInvestment) ?? 0,
        target: inputs.maxRenovationShare,
        status: _maxStatus(
          safeDivide(inputs.renovationBudget + renovationSafety, totalInvestment),
          inputs.maxRenovationShare,
        ),
      ),
    ];

    final score = _score(criteria, warnings);
    final recommendation = score >= 75
        ? 'Kaufen'
        : score >= 50
            ? 'Pruefen'
            : 'Ablehnen';

    return AcquisitionQuickResult(
      purchasePricePerSqm: purchasePricePerSqm,
      totalInvestment: totalInvestment,
      grossInitialYield: grossInitialYield,
      netInitialYield: netInitialYield,
      effectiveGrossIncome: effectiveGrossIncome,
      operatingExpenses: operatingExpenses,
      noi: noi,
      debtServiceAnnual: debtServiceAnnual,
      cashflowBeforeTax: cashflowBeforeTax,
      cashOnCash: cashOnCash,
      loanToValue: loanToValue,
      valueBasedOnCapRate: valueBasedOnCapRate,
      maxReasonablePurchasePrice: maxReasonablePurchasePrice,
      score: score,
      recommendation: recommendation,
      criteria: criteria,
      warnings: warnings,
      formulas: formulas,
    );
  }

  String _minStatus(double? value, double target) {
    if (value == null || target == 0) {
      return 'yellow';
    }
    if (value >= target) {
      return 'green';
    }
    if (value >= target * 0.85) {
      return 'yellow';
    }
    return 'red';
  }

  String _maxStatus(double? value, double target) {
    if (value == null || target == 0) {
      return 'yellow';
    }
    if (value <= target) {
      return 'green';
    }
    if (value <= target * 1.15) {
      return 'yellow';
    }
    return 'red';
  }

  int _score(List<CriterionTrafficLight> criteria, List<String> warnings) {
    if (criteria.isEmpty) {
      return 0;
    }
    final raw = criteria.fold<int>(0, (sum, item) {
      if (item.status == 'green') {
        return sum + 100;
      }
      if (item.status == 'yellow') {
        return sum + 55;
      }
      return sum;
    });
    final warningPenalty = warnings.length * 5;
    return ((raw / criteria.length).round() - warningPenalty)
        .clamp(0, 100)
        .toInt();
  }
}
