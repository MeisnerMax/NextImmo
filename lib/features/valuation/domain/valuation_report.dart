import 'investment_metrics.dart';
import 'valuation_factor.dart';
import 'valuation_method.dart';

/// The reconciled market-value conclusion (Verkehrswert), or an explicit
/// statement that it could not be determined.
sealed class MarketValueOpinion {
  const MarketValueOpinion();
}

class MarketValue extends MarketValueOpinion {
  const MarketValue({
    required this.amount,
    required this.confidence,
    required this.weights,
    required this.rationale,
  });

  final double amount;
  final ConfidenceBand confidence;

  /// Weight applied to each contributing method (sums to 1.0).
  final Map<ValuationMethodKind, double> weights;

  /// Human-readable justification of the weighting/abgleich.
  final String rationale;
}

class MarketValueUnavailable extends MarketValueOpinion {
  const MarketValueUnavailable({
    required this.reason,
    this.unavailableMethods = const [],
  });

  final String reason;
  final List<ValuationMethodKind> unavailableMethods;
}

/// The full result of valuing one object/scenario: every method's result, the
/// reconciled opinion, and the complete assumption ledger for audit + PDF.
class ValuationReport {
  const ValuationReport({
    required this.methodResults,
    required this.opinion,
    this.assumptionLedger = const [],
    this.investment = const InvestmentMetrics(),
  });

  final Map<ValuationMethodKind, MethodResult> methodResults;
  final MarketValueOpinion opinion;
  final List<ValuationAssumption> assumptionLedger;

  /// Investment key figures (IRR/NPV/Equity-Multiple) for the case, each `null`
  /// when the underlying inputs do not permit an honest answer.
  final InvestmentMetrics investment;

  Iterable<ValuationMethodKind> get availableMethods => methodResults.entries
      .where((e) => e.value is MethodValue)
      .map((e) => e.key);

  Iterable<ValuationMethodKind> get unavailableMethods => methodResults.entries
      .where((e) => e.value is MethodUnavailable)
      .map((e) => e.key);
}
