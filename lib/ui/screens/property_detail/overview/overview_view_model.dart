import '../../../../core/engine/financing.dart';
import '../../../../core/engine/normalize.dart';
import '../../../../core/models/property.dart';
import '../../../state/analysis_state.dart';

/// Presentation view model of the deal summary shown on the overview screen
/// (BIG-010 split). Pure derivation from [ScenarioAnalysisState] — no new
/// aggregations beyond what the legacy screen already computed.
class OverviewDealSummary {
  const OverviewDealSummary({
    required this.purchasePrice,
    required this.sizeM2,
    required this.pricePerM2,
    required this.monthlyRent,
    required this.rentPerM2,
    required this.rehabBudget,
    required this.closingCostsBuy,
    required this.totalAcquisitionCost,
    required this.totalEquityInvested,
    required this.loanAmount,
    required this.ltv,
    required this.holdPeriodLabel,
    required this.exitAssumptionMode,
  });

  final double purchasePrice;
  final double? sizeM2;
  final double? pricePerM2;
  final double monthlyRent;
  final double? rentPerM2;
  final double rehabBudget;
  final double closingCostsBuy;
  final double totalAcquisitionCost;
  final double totalEquityInvested;
  final double loanAmount;
  final double? ltv;
  final String holdPeriodLabel;
  final String exitAssumptionMode;

  factory OverviewDealSummary.fromState({
    required ScenarioAnalysisState state,
    required PropertyRecord? property,
  }) {
    final normalized = normalizeInputs(
      inputs: state.inputs,
      settings: state.settings,
      incomeLines: state.incomeLines,
      expenseLines: state.expenseLines,
    );
    final inputs = normalized.inputs;
    final financing = resolveFinancing(inputs);
    final ltv =
        financing.totalAcquisitionCost <= 0
            ? null
            : financing.loanPrincipal / financing.totalAcquisitionCost;

    final sizeM2 = property?.sqft == null ? null : property!.sqft! * 0.092903;
    final monthlyRent = inputs.rentOverride ?? inputs.rentMonthlyTotal;
    final pricePerM2 =
        sizeM2 == null || sizeM2 <= 0 ? null : inputs.purchasePrice / sizeM2;
    final rentPerM2 =
        sizeM2 == null || sizeM2 <= 0 ? null : monthlyRent / sizeM2;

    return OverviewDealSummary(
      purchasePrice: inputs.purchasePrice,
      sizeM2: sizeM2,
      pricePerM2: pricePerM2,
      monthlyRent: monthlyRent,
      rentPerM2: rentPerM2,
      rehabBudget: inputs.rehabBudget,
      closingCostsBuy: financing.buyClosingCosts,
      totalAcquisitionCost: financing.totalAcquisitionCost,
      totalEquityInvested: financing.totalCashInvested,
      loanAmount: financing.loanPrincipal,
      ltv: ltv,
      holdPeriodLabel: '${normalized.horizonMonths}m',
      exitAssumptionMode:
          state.valuation.valuationMode == 'exit_cap'
              ? 'Exit Cap'
              : 'Appreciation',
    );
  }
}

/// The onboarding guidance replaces the data sections only while the property
/// carries nothing but the creation basics (unchanged legacy condition).
bool overviewShouldShowOnboarding(
  OverviewDealSummary summary,
  PropertyRecord? property,
) {
  final propertyHasOnlyBasics =
      property != null &&
      (property.sqft == null || property.sqft == 0) &&
      property.yearBuilt == null &&
      (property.notes == null || property.notes!.trim().isEmpty);
  final assumptionsMissing =
      summary.purchasePrice <= 0 &&
      summary.monthlyRent <= 0 &&
      summary.rehabBudget <= 0;
  return propertyHasOnlyBasics && assumptionsMissing;
}

String formatOverviewNumber(double value) => value.toStringAsFixed(2);

String formatOverviewDate(int? millis) {
  if (millis == null) {
    return 'N/A';
  }
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  final day = dt.day.toString().padLeft(2, '0');
  final month = dt.month.toString().padLeft(2, '0');
  final year = dt.year;
  return '$day.$month.$year';
}

String overviewPropertyAddress(PropertyRecord? property) {
  if (property == null) {
    return 'N/A';
  }
  final parts = <String>[
    property.addressLine1,
    if (property.addressLine2 != null &&
        property.addressLine2!.trim().isNotEmpty)
      property.addressLine2!,
    property.city,
    property.country,
  ].where((part) => part.trim().isNotEmpty).toList(growable: false);
  return parts.isEmpty ? 'N/A' : parts.join(', ');
}
