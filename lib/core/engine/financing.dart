import 'dart:math' as math;

import '../models/inputs.dart';

class FinancingSnapshot {
  const FinancingSnapshot({
    required this.buyClosingCosts,
    required this.totalAcquisitionCost,
    required this.downPaymentAmount,
    required this.requestedLoanPrincipal,
    required this.loanPrincipal,
    required this.totalCashInvested,
    required this.wasLoanPrincipalCapped,
  });

  final double buyClosingCosts;
  final double totalAcquisitionCost;
  final double downPaymentAmount;
  final double requestedLoanPrincipal;
  final double loanPrincipal;
  final double totalCashInvested;
  final bool wasLoanPrincipalCapped;
}

FinancingSnapshot resolveFinancing(ScenarioInputs inputs) {
  final buyClosingCosts =
      (inputs.purchasePrice * inputs.closingCostBuyPercent) +
      inputs.closingCostBuyFixed;
  final totalAcquisitionCost =
      inputs.purchasePrice + inputs.rehabBudget + buyClosingCosts;
  final downPaymentAmount = totalAcquisitionCost * inputs.downPaymentPercent;
  final autoLoanPrincipal = math.max(
    0,
    totalAcquisitionCost - downPaymentAmount,
  ).toDouble();
  final requestedLoanPrincipal =
      inputs.financingMode == 'loan'
          ? (inputs.loanAmount > 0 ? inputs.loanAmount : autoLoanPrincipal)
          : 0.0;
  final loanPrincipal = requestedLoanPrincipal
      .clamp(0, totalAcquisitionCost)
      .toDouble();
  final totalCashInvested =
      inputs.financingMode == 'loan'
          ? math.max(0, totalAcquisitionCost - loanPrincipal).toDouble()
          : totalAcquisitionCost;

  return FinancingSnapshot(
    buyClosingCosts: buyClosingCosts,
    totalAcquisitionCost: totalAcquisitionCost,
    downPaymentAmount: downPaymentAmount,
    requestedLoanPrincipal: requestedLoanPrincipal,
    loanPrincipal: loanPrincipal,
    totalCashInvested: totalCashInvested,
    wasLoanPrincipalCapped: requestedLoanPrincipal > loanPrincipal,
  );
}
