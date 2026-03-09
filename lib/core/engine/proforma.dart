import '../models/analysis_result.dart';
import '../models/inputs.dart';
import '../models/scenario_valuation.dart';
import 'amortization.dart';

class ProformaComputation {
  const ProformaComputation({
    required this.proformaYears,
    required this.amortizationSchedule,
    required this.annualCashflows,
    required this.totalCashInvested,
    required this.debtServiceYear1,
    required this.exitCashflow,
    required this.warnings,
    required this.buyClosingCosts,
    required this.loanPrincipal,
    required this.exitSalePrice,
    required this.exitSaleCosts,
    required this.exitLoanPayoff,
    required this.exitNetSale,
    required this.exitStabilizedNoi,
    required this.valuationMode,
  });

  final List<DerivedProformaYear> proformaYears;
  final List<AmortizationEntry> amortizationSchedule;
  final List<double> annualCashflows;
  final double totalCashInvested;
  final double debtServiceYear1;
  final double exitCashflow;
  final List<String> warnings;
  final double buyClosingCosts;
  final double loanPrincipal;
  final double exitSalePrice;
  final double exitSaleCosts;
  final double exitLoanPayoff;
  final double exitNetSale;
  final double? exitStabilizedNoi;
  final String valuationMode;
}

ProformaComputation buildProforma(
  NormalizedInputs normalized, {
  required ScenarioValuationRecord valuation,
}) {
  final inputs = normalized.inputs;
  final warnings = <String>[];

  final gsiBase =
      (normalized.effectiveRentMonthly +
          normalized.enabledIncomeLinesMonthly +
          inputs.otherIncomeMonthly) *
      12;

  final fixedExpensesAnnualBase =
      (inputs.propertyTaxMonthly +
          inputs.insuranceMonthly +
          inputs.utilitiesMonthly +
          inputs.hoaMonthly +
          inputs.otherExpensesMonthly +
          normalized.enabledExpenseLinesFixedMonthly) *
      12;

  final percentExpenseRate =
      inputs.managementPercent +
      inputs.maintenancePercent +
      inputs.capexPercent +
      normalized.enabledExpenseLinesPercent;

  final buyClosingCosts =
      (inputs.purchasePrice * inputs.closingCostBuyPercent) +
      inputs.closingCostBuyFixed;

  final totalAcquisitionCost =
      inputs.purchasePrice + inputs.rehabBudget + buyClosingCosts;
  final downPayment = totalAcquisitionCost * inputs.downPaymentPercent;
  final computedLoan =
      (totalAcquisitionCost - downPayment).clamp(0, double.infinity).toDouble();

  final loanPrincipal =
      inputs.financingMode == 'loan'
          ? (inputs.loanAmount > 0 ? inputs.loanAmount : computedLoan)
          : 0.0;

  final totalCashInvested =
      inputs.financingMode == 'loan' ? downPayment : totalAcquisitionCost;

  final amortization = buildAmortizationSchedule(
    principal: loanPrincipal,
    annualRate: inputs.interestRatePercent,
    termYears: inputs.termYears,
  );

  final debtServiceYear1 =
      inputs.financingMode == 'loan' ? amortization.monthlyPayment * 12 : 0.0;

  final years = <DerivedProformaYear>[];
  final annualCashflows = <double>[];

  for (var year = 1; year <= normalized.horizonYears; year++) {
    final rentGrowthFactor = _pow(1 + inputs.rentGrowthPercent, year - 1);
    final expenseGrowthFactor = _pow(1 + inputs.expenseGrowthPercent, year - 1);

    final gsi = gsiBase * rentGrowthFactor;
    final vacancyLoss = gsi * inputs.vacancyPercent;
    final egi = gsi - vacancyLoss;

    final fixedAnnual = fixedExpensesAnnualBase * expenseGrowthFactor;
    final percentAnnual = gsi * percentExpenseRate;
    final opex = fixedAnnual + percentAnnual;
    final noi = egi - opex;

    final debtService = inputs.financingMode == 'loan' ? debtServiceYear1 : 0.0;
    final cashflow = noi - debtService;

    final monthIndex =
        amortization.schedule.isEmpty
            ? 0
            : (year * 12).clamp(1, amortization.schedule.length);
    final loanBalanceEnd =
        monthIndex == 0 ? 0.0 : amortization.schedule[monthIndex - 1].balance;

    final marketValue =
        (inputs.arvOverride ?? inputs.purchasePrice) *
        _pow(1 + inputs.appreciationPercent, year);

    final equity = marketValue - loanBalanceEnd;

    years.add(
      DerivedProformaYear(
        yearIndex: year,
        gsi: gsi,
        vacancyLoss: vacancyLoss,
        egi: egi,
        opex: opex,
        noi: noi,
        debtService: debtService,
        cashflowBeforeTax: cashflow,
        loanBalanceEnd: loanBalanceEnd,
        equityEnd: equity,
      ),
    );
    annualCashflows.add(cashflow);
  }

  if (years.isEmpty) {
    warnings.add('No projection years were generated.');
    return ProformaComputation(
      proformaYears: const <DerivedProformaYear>[],
      amortizationSchedule: amortization.schedule,
      annualCashflows: const <double>[],
      totalCashInvested: totalCashInvested,
      debtServiceYear1: debtServiceYear1,
      exitCashflow: 0,
      warnings: warnings,
      buyClosingCosts: buyClosingCosts,
      loanPrincipal: loanPrincipal,
      exitSalePrice: 0,
      exitSaleCosts: 0,
      exitLoanPayoff: 0,
      exitNetSale: 0,
      exitStabilizedNoi: null,
      valuationMode: valuation.valuationMode,
    );
  }

  double salePrice;
  double? stabilizedNoiUsed;
  var valuationModeUsed = valuation.valuationMode;
  if (valuation.valuationMode == 'exit_cap') {
    final capRate = valuation.exitCapRatePercent;
    if (capRate == null || capRate <= 0) {
      warnings.add(
        'Exit cap rate is missing or invalid. Falling back to appreciation.',
      );
      salePrice =
          (inputs.arvOverride ?? inputs.purchasePrice) *
          _pow(1 + inputs.appreciationPercent, normalized.horizonYears);
      valuationModeUsed = 'appreciation';
    } else {
      stabilizedNoiUsed = _resolveStabilizedNoi(
        years: years,
        valuation: valuation,
        warnings: warnings,
      );
      salePrice = stabilizedNoiUsed / capRate;
    }
  } else {
    final saleBase = inputs.arvOverride ?? inputs.purchasePrice;
    salePrice =
        saleBase *
        _pow(1 + inputs.appreciationPercent, normalized.horizonYears);
  }

  final sellCosts =
      salePrice * inputs.saleCostPercent +
      salePrice * inputs.closingCostSellPercent;
  final loanBalanceRemaining = years.last.loanBalanceEnd;
  final netSale = salePrice - sellCosts - loanBalanceRemaining;
  final exitCashflow = netSale;

  if (annualCashflows.isNotEmpty) {
    annualCashflows[annualCashflows.length - 1] += exitCashflow;
  }

  return ProformaComputation(
    proformaYears: years,
    amortizationSchedule: amortization.schedule,
    annualCashflows: annualCashflows,
    totalCashInvested: totalCashInvested,
    debtServiceYear1: debtServiceYear1,
    exitCashflow: exitCashflow,
    warnings: warnings,
    buyClosingCosts: buyClosingCosts,
    loanPrincipal: loanPrincipal,
    exitSalePrice: salePrice,
    exitSaleCosts: sellCosts,
    exitLoanPayoff: loanBalanceRemaining,
    exitNetSale: netSale,
    exitStabilizedNoi: stabilizedNoiUsed,
    valuationMode: valuationModeUsed,
  );
}

double _pow(double base, int exponent) {
  if (exponent == 0) {
    return 1;
  }

  var value = 1.0;
  for (var i = 0; i < exponent; i++) {
    value *= base;
  }
  return value;
}

double _resolveStabilizedNoi({
  required List<DerivedProformaYear> years,
  required ScenarioValuationRecord valuation,
  required List<String> warnings,
}) {
  if (years.isEmpty) {
    return 0;
  }
  final mode = valuation.stabilizedNoiMode ?? 'use_year1_noi';
  if (mode == 'manual_noi') {
    final manual = valuation.stabilizedNoiManual;
    if (manual == null || manual <= 0) {
      warnings.add(
        'Manual stabilized NOI is missing or invalid. Falling back to NOI year 1.',
      );
      return years.first.noi;
    }
    return manual;
  }
  if (mode == 'average_years') {
    final n = (valuation.stabilizedNoiAvgYears ?? 1).clamp(1, years.length);
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += years[i].noi;
    }
    return sum / n;
  }
  return years.first.noi;
}
