import '../models/analysis_result.dart';
import '../models/inputs.dart';
import 'irr.dart';
import 'proforma.dart';

AnalysisMetrics computeMetrics({
  required NormalizedInputs normalized,
  required ProformaComputation proforma,
  required List<String> warnings,
}) {
  if (proforma.proformaYears.isEmpty) {
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

  final year1 = proforma.proformaYears.first;
  final annualCashflowYear1 = year1.cashflowBeforeTax;
  final monthlyCashflowYear1 = annualCashflowYear1 / 12;

  final capRate =
      normalized.inputs.purchasePrice <= 0
          ? 0.0
          : year1.noi / normalized.inputs.purchasePrice;

  final dscr =
      proforma.debtServiceYear1 <= 0
          ? null
          : year1.noi / proforma.debtServiceYear1;

  final cashOnCash =
      proforma.totalCashInvested <= 0
          ? 0.0
          : annualCashflowYear1 / proforma.totalCashInvested;

  final irrCashflows = <double>[
    -proforma.totalCashInvested,
    ...proforma.annualCashflows,
  ];
  final irr = computeIrr(irrCashflows);
  if (irr == null) {
    warnings.add('IRR did not converge.');
  }

  final annualWithoutInitial = proforma.annualCashflows.fold<double>(
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
    noiYear1: year1.noi,
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

  var cumulative = 0.0;
  for (var i = 0; i < annualCashflows.length; i++) {
    cumulative += annualCashflows[i];
    if (cumulative >= totalCashInvested) {
      return i + 1;
    }
  }

  return null;
}
