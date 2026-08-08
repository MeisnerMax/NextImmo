import '../cash_flow_projection.dart';
import '../valuation_factor.dart';
import '../valuation_factor_ids.dart';
import '../valuation_method.dart';

/// The factors the DCF requires for a given terminal method.
List<String> dcfRequiredFactorIds(DcfTerminalMethod terminal) => <String>[
  ValuationFactorIds.grossRentAnnual,
  ValuationFactorIds.vacancyRate,
  ValuationFactorIds.operatingExpensesAnnual,
  ValuationFactorIds.rentGrowthRate,
  ValuationFactorIds.expenseGrowthRate,
  ValuationFactorIds.holdYears,
  ValuationFactorIds.discountRate,
  ValuationFactorIds.saleCostRate,
  terminal == DcfTerminalMethod.exitCap
      ? ValuationFactorIds.exitCapRate
      : ValuationFactorIds.terminalGrowthRate,
];

/// Runs the DCF projection off a [FactorSet], or returns `null` when a required
/// factor is unusable or the terminal method is infeasible. Shared by
/// [DiscountedCashFlowMethod] and the case-level investment metrics so both see
/// exactly the same cash flows.
DcfValuation? dcfValuationFromFactors(
  FactorSet factors, {
  required DcfTerminalMethod terminal,
}) {
  if (factors.missingAmong(dcfRequiredFactorIds(terminal)).isNotEmpty) {
    return null;
  }
  return computeDcfValuation(
    grossRentAnnual: factors.value(ValuationFactorIds.grossRentAnnual)!,
    vacancyRate: factors.value(ValuationFactorIds.vacancyRate)!,
    operatingExpensesAnnual:
        factors.value(ValuationFactorIds.operatingExpensesAnnual)!,
    rentGrowthRate: factors.value(ValuationFactorIds.rentGrowthRate)!,
    expenseGrowthRate: factors.value(ValuationFactorIds.expenseGrowthRate)!,
    holdYears: factors.value(ValuationFactorIds.holdYears)!.round(),
    discountRate: factors.value(ValuationFactorIds.discountRate)!,
    saleCostRate: factors.value(ValuationFactorIds.saleCostRate)!,
    terminal: terminal,
    exitCapRate: factors.value(ValuationFactorIds.exitCapRate),
    terminalGrowthRate: factors.value(ValuationFactorIds.terminalGrowthRate),
  );
}

/// DCF (investment) valuation: discounts an annual NOI projection plus the net
/// terminal value to an unlevered asset value. Reimplemented from scratch for
/// the enterprise engine (no dependency on the legacy pro-forma engine).
class DiscountedCashFlowMethod implements ValuationMethod {
  const DiscountedCashFlowMethod({this.terminal = DcfTerminalMethod.exitCap});

  final DcfTerminalMethod terminal;

  @override
  ValuationMethodKind get kind => ValuationMethodKind.discountedCashFlow;

  @override
  String get name => 'DCF-Verfahren';

  @override
  MethodResult evaluate(FactorSet factors) {
    final requiredIds = dcfRequiredFactorIds(terminal);

    final missing = factors.missingAmong(requiredIds);
    if (missing.isNotEmpty) {
      return MethodUnavailable(missingFactors: missing);
    }

    final dcf = dcfValuationFromFactors(factors, terminal: terminal);

    if (dcf == null) {
      return MethodUnavailable(
        missingFactors: const [],
        reasons: [
          terminal == DcfTerminalMethod.gordonGrowth
              ? 'Kalkulationszins muss größer als das Terminal-Wachstum sein.'
              : 'Exit-Cap-Rate fehlt oder ist nicht positiv.',
        ],
      );
    }

    final used = requiredIds.map((id) => factors[id]!).toList();
    return MethodValue(
      amount: dcf.assetValue,
      confidence: combineConfidence(used),
      breakdown: [
        MethodBreakdownLine(
          label: 'Barwert der Reinerträge',
          amount: dcf.presentValueOfIncome,
          unit: '€',
        ),
        MethodBreakdownLine(
          label: 'Terminalwert (brutto)',
          amount: dcf.terminalValue,
          unit: '€',
          formula:
              terminal == DcfTerminalMethod.exitCap
                  ? 'Forward-NOI / Exit-Cap'
                  : 'Forward-NOI / (Kalkulationszins − Wachstum)',
        ),
        MethodBreakdownLine(
          label: 'Barwert des Nettoveräußerungserlöses',
          amount: dcf.presentValueOfTerminal,
          unit: '€',
        ),
        MethodBreakdownLine(
          label: 'DCF-Wert (unbelastet)',
          amount: dcf.assetValue,
          unit: '€',
          formula: 'Barwert Reinerträge + Barwert Nettoerlös',
        ),
      ],
      assumptions:
          used.map(ValuationAssumption.fromFactor).toList(growable: false),
    );
  }
}
