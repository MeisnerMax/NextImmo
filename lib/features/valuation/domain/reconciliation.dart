import 'valuation_factor.dart';
import 'valuation_method.dart';
import 'valuation_report.dart';

/// Weights the *available* method results into a single Verkehrswert and
/// documents how it got there.
///
/// Unavailable methods are never substituted or silently dropped from the
/// reasoning: they carry no weight but are listed in the rationale, and if no
/// method is available at all the result is [MarketValueUnavailable] rather than
/// a number.
class ValuationReconciler {
  const ValuationReconciler({
    this.baseWeights = defaultBaseWeights,
    this.spreadDowngradeThreshold = 0.20,
  });

  /// Relative weight per method before renormalization over the available ones.
  /// Market-derived approaches lead, the cost approach supports.
  static const Map<ValuationMethodKind, double> defaultBaseWeights = {
    ValuationMethodKind.comparisonApproach: 0.30,
    ValuationMethodKind.incomeApproachDe: 0.30,
    ValuationMethodKind.discountedCashFlow: 0.20,
    ValuationMethodKind.costApproachDe: 0.10,
    ValuationMethodKind.directCapitalization: 0.10,
  };

  final Map<ValuationMethodKind, double> baseWeights;

  /// Relative spread between the highest and lowest method value above which
  /// the overall confidence is downgraded one band.
  final double spreadDowngradeThreshold;

  /// Reconciles [methodResults]. [weightOverrides] lets a case pin an explicit
  /// weighting (e.g. an appraiser's judgement); overrides are renormalized the
  /// same way as the base weights.
  MarketValueOpinion reconcile(
    Map<ValuationMethodKind, MethodResult> methodResults, {
    Map<ValuationMethodKind, double> weightOverrides = const {},
  }) {
    final available = <ValuationMethodKind, MethodValue>{
      for (final entry in methodResults.entries)
        if (entry.value is MethodValue) entry.key: entry.value as MethodValue,
    };
    final unavailable =
        methodResults.entries
            .where((e) => e.value is MethodUnavailable)
            .map((e) => e.key)
            .toList(growable: false);

    if (available.isEmpty) {
      return MarketValueUnavailable(
        reason:
            'Verkehrswert nicht ermittelbar: kein Verfahren lieferte ein '
            'Ergebnis (${_methodList(unavailable)}).',
        unavailableMethods: unavailable,
      );
    }

    final raw = <ValuationMethodKind, double>{
      for (final kind in available.keys)
        kind: weightOverrides[kind] ?? baseWeights[kind] ?? 0.0,
    };
    final rawTotal = raw.values.fold<double>(0, (sum, w) => sum + w);
    // Fall back to an equal split only when the configured weights carry no
    // information for the available set — that is a weighting decision, not a
    // substituted value.
    final weights = <ValuationMethodKind, double>{
      for (final kind in available.keys)
        kind: rawTotal > 0 ? raw[kind]! / rawTotal : 1 / available.length,
    };

    var amount = 0.0;
    for (final entry in available.entries) {
      amount += entry.value.amount * weights[entry.key]!;
    }

    final values = available.values.map((v) => v.amount).toList(growable: false);
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final spread = amount != 0 ? (max - min).abs() / amount.abs() : null;

    var confidence = _weakest(available.values.map((v) => v.confidence));
    final downgraded =
        spread != null && spread > spreadDowngradeThreshold && available.length > 1;
    if (downgraded) confidence = _downgrade(confidence);

    return MarketValue(
      amount: amount,
      confidence: confidence,
      weights: weights,
      rationale: _rationale(
        available: available,
        weights: weights,
        unavailable: unavailable,
        spread: spread,
        downgraded: downgraded,
      ),
    );
  }

  String _rationale({
    required Map<ValuationMethodKind, MethodValue> available,
    required Map<ValuationMethodKind, double> weights,
    required List<ValuationMethodKind> unavailable,
    required double? spread,
    required bool downgraded,
  }) {
    final parts = <String>[
      'Verfahrensabgleich über ${available.length} verfügbare(s) Verfahren: '
          '${available.entries.map((e) => '${e.key.labelDe} '
              '${_percent(weights[e.key]!)} (${_euro(e.value.amount)})').join(', ')}.',
    ];
    if (spread != null) {
      parts.add('Streuung der Verfahrenswerte: ${_percent(spread)}.');
    }
    if (downgraded) {
      parts.add(
        'Konfidenz um eine Stufe herabgesetzt, da die Streuung über '
        '${_percent(spreadDowngradeThreshold)} liegt.',
      );
    }
    if (unavailable.isNotEmpty) {
      parts.add(
        'Nicht verfügbar und daher ohne Gewicht: ${_methodList(unavailable)}.',
      );
    }
    return parts.join(' ');
  }

  static String _methodList(List<ValuationMethodKind> kinds) =>
      kinds.map((k) => k.labelDe).join(', ');

  static ConfidenceBand _weakest(Iterable<ConfidenceBand> bands) {
    int rank(ConfidenceBand b) => switch (b) {
      ConfidenceBand.high => 3,
      ConfidenceBand.medium => 2,
      ConfidenceBand.low => 1,
      ConfidenceBand.unknown => 0,
    };
    var weakest = ConfidenceBand.high;
    for (final band in bands) {
      if (rank(band) < rank(weakest)) weakest = band;
    }
    return weakest;
  }

  static ConfidenceBand _downgrade(ConfidenceBand band) => switch (band) {
    ConfidenceBand.high => ConfidenceBand.medium,
    ConfidenceBand.medium => ConfidenceBand.low,
    ConfidenceBand.low => ConfidenceBand.low,
    ConfidenceBand.unknown => ConfidenceBand.unknown,
  };
}

String _percent(double fraction) =>
    '${(fraction * 100).toStringAsFixed(0)} %';

/// Deterministic euro formatting for rationale text (no intl dependency).
String _euro(double amount) {
  final rounded = amount.round().abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < rounded.length; i++) {
    if (i > 0 && (rounded.length - i) % 3 == 0) buffer.write('.');
    buffer.write(rounded[i]);
  }
  return '${amount < 0 ? '−' : ''}$buffer €';
}
