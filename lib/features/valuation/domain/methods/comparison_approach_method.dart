import '../valuation_factor.dart';
import '../valuation_factor_ids.dart';
import '../valuation_method.dart';

/// A single comparable sale feeding the Vergleichswertverfahren. [priceAdjustment]
/// is the combined Zu-/Abschlag as a multiplicative factor (`1.0` = no
/// adjustment, `0.95` = 5 % Abschlag), e.g. from Umrechnungskoeffizienten.
class ComparableSale {
  const ComparableSale({
    required this.id,
    required this.label,
    required this.price,
    required this.areaSqm,
    this.priceAdjustment = 1.0,
    this.note,
  });

  final String id;
  final String label;
  final double price;
  final double areaSqm;
  final double priceAdjustment;
  final String? note;

  /// Adjusted price per m² — `null` when the comparable carries no usable area.
  double? get adjustedPricePerSqm =>
      areaSqm > 0 ? (price * priceAdjustment) / areaSqm : null;
}

/// Vergleichswertverfahren (ImmoWertV 2021 §§24–26): the adjusted €/m² of
/// sufficiently many suitable comparables, applied to the subject's area.
///
/// Without at least [minimumComparables] usable comparables the method reports
/// "nicht ermittelbar" — it never falls back to a thinner sample.
class ComparisonApproachMethod implements ValuationMethod {
  const ComparisonApproachMethod({
    this.comparables = const [],
    this.minimumComparables = 3,
  });

  final List<ComparableSale> comparables;
  final int minimumComparables;

  @override
  ValuationMethodKind get kind => ValuationMethodKind.comparisonApproach;

  @override
  String get name => 'Vergleichswertverfahren';

  @override
  MethodResult evaluate(FactorSet factors) {
    final missing = factors.missingAmong([
      ValuationFactorIds.subjectLivingAreaSqm,
    ]);

    final usable =
        comparables
            .where((c) => c.adjustedPricePerSqm != null && c.price > 0)
            .toList(growable: false);

    final reasons = <String>[];
    if (usable.length < minimumComparables) {
      reasons.add(
        'Keine ausreichenden Vergleichsobjekte: ${usable.length} von '
        'mindestens $minimumComparables geeigneten Vergleichspreisen.',
      );
    }

    if (missing.isNotEmpty || reasons.isNotEmpty) {
      return MethodUnavailable(missingFactors: missing, reasons: reasons);
    }

    final area = factors.value(ValuationFactorIds.subjectLivingAreaSqm)!;
    final used = <ValuationFactor>[
      factors[ValuationFactorIds.subjectLivingAreaSqm]!,
    ];

    final perSqmValues =
        usable.map((c) => c.adjustedPricePerSqm!).toList(growable: false);
    final averagePerSqm =
        perSqmValues.reduce((a, b) => a + b) / perSqmValues.length;
    var value = averagePerSqm * area;

    final breakdown = <MethodBreakdownLine>[
      for (final c in usable)
        MethodBreakdownLine(
          label: 'Vergleichspreis ${c.label}',
          amount: c.adjustedPricePerSqm,
          unit: '€/m²',
          formula:
              c.priceAdjustment == 1.0
                  ? 'Kaufpreis / Fläche'
                  : 'Kaufpreis × ${c.priceAdjustment} / Fläche',
          note: c.note,
        ),
      MethodBreakdownLine(
        label: 'Mittlerer angepasster Vergleichspreis',
        amount: averagePerSqm,
        unit: '€/m²',
        formula: 'Mittelwert aus ${usable.length} Vergleichspreisen',
      ),
    ];

    final boM = factors.value(ValuationFactorIds.otherValueAdjustment);
    if (boM != null) {
      value += boM;
      used.add(factors[ValuationFactorIds.otherValueAdjustment]!);
      breakdown.add(
        MethodBreakdownLine(
          label: 'Besondere objektspezifische Grundstücksmerkmale',
          amount: boM,
          unit: '€',
        ),
      );
    }

    breakdown.add(
      MethodBreakdownLine(
        label: 'Vergleichswert',
        amount: value,
        unit: '€',
        formula:
            'Mittlerer Vergleichspreis × Fläche${boM != null ? ' ± boM' : ''}',
      ),
    );

    return MethodValue(
      amount: value,
      // Comparables are user-supplied market evidence; the band is still driven
      // by the provenance of the factors the method itself consumed.
      confidence: combineConfidence(used),
      breakdown: breakdown,
      assumptions:
          used.map(ValuationAssumption.fromFactor).toList(growable: false),
    );
  }
}
