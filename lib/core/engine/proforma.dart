import 'dart:math' as math;

import '../models/analysis_result.dart';
import '../models/inputs.dart';
import '../models/scenario_valuation.dart';
import 'amortization.dart';
import 'financing.dart';

class ProformaComputation {
  const ProformaComputation({
    required this.proformaMonths,
    required this.proformaYears,
    required this.amortizationSchedule,
    required this.monthlyCashflows,
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

  final List<DerivedProformaMonth> proformaMonths;
  final List<DerivedProformaYear> proformaYears;
  final List<AmortizationEntry> amortizationSchedule;
  final List<double> monthlyCashflows;
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
      normalized.effectiveRentMonthly +
      normalized.enabledIncomeLinesMonthly +
      inputs.otherIncomeMonthly;

  final fixedExpensesBase =
      inputs.propertyTaxMonthly +
      inputs.insuranceMonthly +
      inputs.utilitiesMonthly +
      inputs.hoaMonthly +
      inputs.otherExpensesMonthly +
      normalized.enabledExpenseLinesFixedMonthly;

  final percentExpenseRate =
      inputs.managementPercent +
      inputs.maintenancePercent +
      inputs.capexPercent +
      normalized.enabledExpenseLinesPercent;

  final financing = resolveFinancing(inputs);
  final buyClosingCosts = financing.buyClosingCosts;
  final loanPrincipal = financing.loanPrincipal;
  final totalCashInvested = financing.totalCashInvested;
  if (financing.wasLoanPrincipalCapped) {
    warnings.add(
      'Loan amount exceeded total acquisition cost and was capped.',
    );
  }

  final amortization = buildAmortizationSchedule(
    principal: loanPrincipal,
    annualRate: inputs.interestRatePercent,
    termYears: inputs.termYears,
  );

  final months = <DerivedProformaMonth>[];
  final monthlyCashflows = <double>[];
  final years = <DerivedProformaYear>[];
  final annualCashflows = <double>[];

  for (var month = 1; month <= normalized.horizonMonths; month++) {
    final yearIndex = ((month - 1) / 12).floor() + 1;
    final rentGrowthFactor = _powAnnual(inputs.rentGrowthPercent, month - 1);
    final expenseGrowthFactor = _powAnnual(
      inputs.expenseGrowthPercent,
      month - 1,
    );

    final gsi = gsiBase * rentGrowthFactor;
    final vacancyLoss = gsi * inputs.vacancyPercent;
    final egi = gsi - vacancyLoss;

    final fixedMonthly = fixedExpensesBase * expenseGrowthFactor;
    final percentMonthly = gsi * percentExpenseRate;
    final opex = fixedMonthly + percentMonthly;
    final noi = egi - opex;

    final debtService =
        inputs.financingMode == 'loan' && month <= amortization.schedule.length
            ? amortization.schedule[month - 1].payment
            : 0.0;
    final cashflow = noi - debtService;

    final loanBalanceEnd =
        month <= amortization.schedule.length
            ? amortization.schedule[month - 1].balance
            : 0.0;

    final marketValue =
        (inputs.arvOverride ?? inputs.purchasePrice) *
        _powAnnual(inputs.appreciationPercent, month);

    final equity = marketValue - loanBalanceEnd;

    months.add(
      DerivedProformaMonth(
        monthIndex: month,
        yearIndex: yearIndex,
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
    monthlyCashflows.add(cashflow);
  }

  for (var year = 1; year <= normalized.horizonYears; year++) {
    final start = (year - 1) * 12;
    if (start >= months.length) {
      break;
    }
    final end = math.min(start + 12, months.length);
    final slice = months.sublist(start, end);
    final lastMonth = slice.last;

    final yearGsi = slice.fold<double>(0, (sum, month) => sum + month.gsi);
    final yearVacancy = slice.fold<double>(
      0,
      (sum, month) => sum + month.vacancyLoss,
    );
    final yearEgi = slice.fold<double>(0, (sum, month) => sum + month.egi);
    final yearOpex = slice.fold<double>(0, (sum, month) => sum + month.opex);
    final yearNoi = slice.fold<double>(0, (sum, month) => sum + month.noi);
    final yearDebt = slice.fold<double>(
      0,
      (sum, month) => sum + month.debtService,
    );
    final yearCashflow = slice.fold<double>(
      0,
      (sum, month) => sum + month.cashflowBeforeTax,
    );

    years.add(
      DerivedProformaYear(
        yearIndex: year,
        gsi: yearGsi,
        vacancyLoss: yearVacancy,
        egi: yearEgi,
        opex: yearOpex,
        noi: yearNoi,
        debtService: yearDebt,
        cashflowBeforeTax: yearCashflow,
        loanBalanceEnd: lastMonth.loanBalanceEnd,
        equityEnd: lastMonth.equityEnd,
      ),
    );
    annualCashflows.add(yearCashflow);
  }

  final debtServiceYear1 = months
      .take(math.min(12, months.length))
      .fold<double>(0, (sum, month) => sum + month.debtService);

  if (months.isEmpty || years.isEmpty) {
    warnings.add('No projection years were generated.');
    return ProformaComputation(
      proformaMonths: const <DerivedProformaMonth>[],
      proformaYears: const <DerivedProformaYear>[],
      amortizationSchedule: amortization.schedule,
      monthlyCashflows: const <double>[],
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
          _powAnnual(inputs.appreciationPercent, normalized.horizonMonths);
      valuationModeUsed = 'appreciation';
    } else {
      stabilizedNoiUsed = _resolveStabilizedNoi(
        months: months,
        years: years,
        valuation: valuation,
        warnings: warnings,
      );
      salePrice = stabilizedNoiUsed / capRate;
    }
  } else {
    final saleBase = inputs.arvOverride ?? inputs.purchasePrice;
    salePrice =
        saleBase * _powAnnual(inputs.appreciationPercent, normalized.horizonMonths);
  }

  final sellCosts =
      salePrice * inputs.saleCostPercent +
      salePrice * inputs.closingCostSellPercent;
  final loanBalanceRemaining = years.last.loanBalanceEnd;
  final netSale = salePrice - sellCosts - loanBalanceRemaining;
  final exitCashflow = netSale;

  if (monthlyCashflows.isNotEmpty) {
    monthlyCashflows[monthlyCashflows.length - 1] += exitCashflow;
  }
  if (annualCashflows.isNotEmpty) {
    annualCashflows[annualCashflows.length - 1] += exitCashflow;
  }

  return ProformaComputation(
    proformaMonths: months,
    proformaYears: years,
    amortizationSchedule: amortization.schedule,
    monthlyCashflows: monthlyCashflows,
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

double _powAnnual(double annualRate, int monthsElapsed) =>
    math.pow(1 + annualRate, monthsElapsed / 12).toDouble();

double _resolveStabilizedNoi({
  required List<DerivedProformaMonth> months,
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

  final monthsUsed = math.min(12, months.length);
  if (monthsUsed <= 0) {
    return 0;
  }
  final firstWindowNoi = months
      .take(monthsUsed)
      .fold<double>(0, (sum, month) => sum + month.noi);
  return monthsUsed == 12 ? firstWindowNoi : (firstWindowNoi / monthsUsed) * 12;
}
