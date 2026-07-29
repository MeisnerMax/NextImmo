import 'valuation_factor.dart';

/// The valuation methods the engine supports. The three German statutory
/// Normverfahren (ImmoWertV 2021) plus two investment methods, reconciled to a
/// single Verkehrswert.
enum ValuationMethodKind {
  /// Ertragswertverfahren (ImmoWertV §§27–34).
  incomeApproachDe('income_approach_de'),

  /// Sachwertverfahren (ImmoWertV §§35–39).
  costApproachDe('cost_approach_de'),

  /// Vergleichswertverfahren (ImmoWertV §§24–26).
  comparisonApproach('comparison_approach'),

  /// Discounted cash flow (investment).
  discountedCashFlow('discounted_cash_flow'),

  /// Direktkapitalisierung / Schnellkennzahlen.
  directCapitalization('direct_capitalization');

  const ValuationMethodKind(this.wireName);

  final String wireName;

  static ValuationMethodKind? fromWire(String? value) {
    for (final kind in ValuationMethodKind.values) {
      if (kind.wireName == value) return kind;
    }
    return null;
  }
}

extension ValuationMethodKindX on ValuationMethodKind {
  String get labelDe => switch (this) {
    ValuationMethodKind.incomeApproachDe => 'Ertragswertverfahren',
    ValuationMethodKind.costApproachDe => 'Sachwertverfahren',
    ValuationMethodKind.comparisonApproach => 'Vergleichswertverfahren',
    ValuationMethodKind.discountedCashFlow => 'DCF-Verfahren',
    ValuationMethodKind.directCapitalization => 'Direktkapitalisierung',
  };
}

/// One line of a method's transparent calculation trail (for UI + PDF).
class MethodBreakdownLine {
  const MethodBreakdownLine({
    required this.label,
    this.amount,
    this.unit,
    this.formula,
    this.note,
  });

  final String label;
  final double? amount;
  final String? unit;

  /// Optional human-readable formula, e.g. `Reinertrag − Bodenwertverzinsung`.
  final String? formula;
  final String? note;
}

/// A factor as it was actually used in a result — the audit/PDF ledger entry.
class ValuationAssumption {
  const ValuationAssumption({
    required this.factorId,
    required this.label,
    required this.provenance,
    this.value,
    this.unit,
    this.source,
  });

  final String factorId;
  final String label;
  final FactorProvenance provenance;
  final double? value;
  final String? unit;
  final String? source;

  factory ValuationAssumption.fromFactor(ValuationFactor factor) =>
      ValuationAssumption(
        factorId: factor.id,
        label: factor.label,
        provenance: factor.provenance,
        value: factor.value,
        unit: factor.unit,
        source: factor.source,
      );
}

/// Result of evaluating a single method: either a value with its trail, or an
/// explicit "not determinable" with the reasons why. There is no third,
/// silently-substituted option.
sealed class MethodResult {
  const MethodResult();
}

class MethodValue extends MethodResult {
  const MethodValue({
    required this.amount,
    required this.confidence,
    this.breakdown = const [],
    this.assumptions = const [],
  });

  final double amount;
  final ConfidenceBand confidence;
  final List<MethodBreakdownLine> breakdown;
  final List<ValuationAssumption> assumptions;
}

class MethodUnavailable extends MethodResult {
  const MethodUnavailable({required this.missingFactors, this.reasons = const []});

  /// Required factors that were absent or unconfirmed.
  final List<MissingFactor> missingFactors;

  /// Additional non-factor reasons (e.g. "keine ausreichenden Vergleichsobjekte").
  final List<String> reasons;
}

/// Backend-agnostic, deterministic valuation method contract. Each method
/// declares what it needs by inspecting the [FactorSet] and returns a
/// [MethodResult]; it never mutates inputs and never reaches for a fallback.
abstract interface class ValuationMethod {
  ValuationMethodKind get kind;

  String get name;

  MethodResult evaluate(FactorSet factors);
}
