import 'dart:math' as math;

import '../models/analysis_result.dart';
import '../models/inputs.dart';
import 'irr.dart';
import 'proforma.dart';

AnalysisMetrics computeMetrics({
  required NormalizedInputs normalized,
  required ProformaComputation proforma,
  required List<String> warnings,
}) {
  if (proforma.proformaMonths.isEmpty) {
    return const AnalysisMetrics(
      monthlyCashflowYear1: 0.0,
      annualCashflowYear1: 0.0,
      noiYear1: 0.0,
      capRate: 0.0,
      cashOnCash: 0.0,
      irr: null,
      roi: 0.0,
      dscr: null,
      breakEvenYear: null,
      totalCashInvested: 0.0,
      exitCashflow: 0.0,
      exitSalePrice: 0.0,
      exitSaleCosts: 0.0,
      exitLoanPayoff: 0.0,
      exitNetSale: 0.0,
      exitStabilizedNoi: null,
      valuationMode: 'appreciation',
    );
  }

  final year1Months = proforma.proformaMonths.take(
    math.min(12, proforma.proformaMonths.length),
  );
  final annualCashflowYear1 = year1Months.fold<double>(
    0,
    (sum, month) => sum + month.cashflowBeforeTax,
  );
  final monthlyCashflowYear1 =
      year1Months.isEmpty ? 0.0 : annualCashflowYear1 / year1Months.length;
  final noiYear1 = year1Months.fold<double>(0, (sum, month) => sum + month.noi);

  final capRate =
      normalized.inputs.purchasePrice <= 0
          ? 0.0
          : noiYear1 / normalized.inputs.purchasePrice;

  final dscr =
      proforma.debtServiceYear1 <= 0
          ? null
          : noiYear1 / proforma.debtServiceYear1;

  final cashOnCash =
      proforma.totalCashInvested <= 0
          ? 0.0
          : annualCashflowYear1 / proforma.totalCashInvested;

  double? irr;
  if (proforma.totalCashInvested <= 0) {
    warnings.add('IRR unavailable because total cash invested is zero.');
  } else {
    final irrCashflows = <double>[
      -proforma.totalCashInvested,
      ...proforma.monthlyCashflows,
    ];
    final monthlyIrr = computeIrr(irrCashflows);
    if (monthlyIrr == null) {
      final hasPositive = irrCashflows.any((value) => value > 0);
      final hasNegative = irrCashflows.any((value) => value < 0);
      warnings.add(
        hasPositive && hasNegative
            ? 'IRR did not converge.'
            : 'IRR unavailable because cashflows do not change sign.',
      );
    } else {
      irr = math.pow(1 + monthlyIrr, 12).toDouble() - 1;
    }
  }

  final annualWithoutInitial = proforma.monthlyCashflows.fold<double>(
    0,
    (sum, value) => sum + value,
  );
  final totalProfit = annualWithoutInitial - proforma.totalCashInvested;
  final roi =
      proforma.totalCashInvested <= 0
          ? 0.0
          : totalProfit / proforma.totalCashInvested;

  final breakEvenYear = _computeBreakEvenYear(
    annualCashflows: proforma.annualCashflows,
    totalCashInvested: proforma.totalCashInvested,
  );

  return AnalysisMetrics(
    monthlyCashflowYear1: monthlyCashflowYear1,
    annualCashflowYear1: annualCashflowYear1,
    noiYear1: noiYear1,
    capRate: capRate,
    cashOnCash: cashOnCash,
    irr: irr,
    roi: roi,
    dscr: dscr,
    breakEvenYear: breakEvenYear,
    totalCashInvested: proforma.totalCashInvested,
    exitCashflow: proforma.exitCashflow,
    exitSalePrice: proforma.exitSalePrice,
    exitSaleCosts: proforma.exitSaleCosts,
    exitLoanPayoff: proforma.exitLoanPayoff,
    exitNetSale: proforma.exitNetSale,
    exitStabilizedNoi: proforma.exitStabilizedNoi,
    valuationMode: proforma.valuationMode,
  );
}

int? _computeBreakEvenYear({
  required List<double> annualCashflows,
  required double totalCashInvested,
}) {
  if (totalCashInvested <= 0) {
    return 0;
  }

  for (var i = 0; i < annualCashflows.length; i++) {
    final cumulative = annualCashflows
        .take(i + 1)
        .fold<double>(0, (sum, value) => sum + value);
    if (cumulative >= totalCashInvested) {
      return i + 1;
    }
  }

  return null;
}
