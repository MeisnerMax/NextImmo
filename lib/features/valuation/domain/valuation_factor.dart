/// Core primitive of the enterprise valuation engine: a single valuation
/// factor carrying both a value *and* where that value came from.
///
/// The provenance is what lets the engine be honest about missing inputs
/// instead of fabricating plausible-but-wrong numbers (the behaviour this
/// rewrite replaces). Only [FactorProvenance.userProvided],
/// [FactorProvenance.derived] and [FactorProvenance.accepted] factors may feed
/// a valuation method; an unconfirmed [FactorProvenance.suggestedDefault] or a
/// [FactorProvenance.missing] factor makes the dependent method report
/// "nicht ermittelbar" rather than a value.
library;

/// Where a factor's value came from.
enum FactorProvenance {
  /// Entered directly by the user.
  userProvided('user_provided'),

  /// Computed by the system from other usable factors / reference data.
  derived('derived'),

  /// A typical value proposed by the system. NOT yet usable — the user must
  /// confirm it (which turns it into [accepted]).
  suggestedDefault('suggested_default'),

  /// A [suggestedDefault] the user has explicitly confirmed.
  accepted('accepted'),

  /// No value is available.
  missing('missing');

  const FactorProvenance(this.wireName);

  final String wireName;

  static FactorProvenance? fromWire(String? value) {
    for (final provenance in FactorProvenance.values) {
      if (provenance.wireName == value) return provenance;
    }
    return null;
  }
}

extension FactorProvenanceX on FactorProvenance {
  /// Whether a factor with this provenance may be used in a calculation.
  bool get isUsable =>
      this == FactorProvenance.userProvided ||
      this == FactorProvenance.derived ||
      this == FactorProvenance.accepted;
}

/// Qualitative confidence attached to a factor or a method result.
enum ConfidenceBand {
  high('high'),
  medium('medium'),
  low('low'),
  unknown('unknown');

  const ConfidenceBand(this.wireName);

  final String wireName;

  static ConfidenceBand? fromWire(String? value) {
    for (final band in ConfidenceBand.values) {
      if (band.wireName == value) return band;
    }
    return null;
  }
}

/// A single numeric valuation factor with provenance.
///
/// Quantitative factors (money, rates, areas, years) are numeric; categorical
/// selections (e.g. a building type in a menu) resolve to numeric reference
/// values that themselves become factors, so a numeric value is the right core.
class ValuationFactor {
  const ValuationFactor({
    required this.id,
    required this.label,
    required this.provenance,
    this.value,
    this.unit,
    this.source,
    this.note,
    this.confidence = ConfidenceBand.unknown,
  });

  /// Stable identifier used by methods to request the factor (e.g. `rohertrag`).
  final String id;

  /// Human-readable label (German), used in UI and the assumption ledger.
  final String label;

  final FactorProvenance provenance;

  /// The numeric value; `null` when [provenance] is [FactorProvenance.missing].
  final double? value;

  /// Unit label for display (e.g. `€`, `€/m²`, `%`, `Jahre`).
  final String? unit;

  /// Where a derived/suggested value originated (reference table, formula, …).
  final String? source;

  /// Optional free-text note (e.g. why a value was overridden).
  final String? note;

  final ConfidenceBand confidence;

  /// Whether this factor may feed a calculation right now.
  bool get isUsable => value != null && provenance.isUsable;

  /// The value if [isUsable], otherwise `null` — never a substitute number.
  double? get usableValue => isUsable ? value : null;

  factory ValuationFactor.user({
    required String id,
    required String label,
    required double value,
    String? unit,
    String? note,
  }) => ValuationFactor(
    id: id,
    label: label,
    provenance: FactorProvenance.userProvided,
    value: value,
    unit: unit,
    note: note,
    confidence: ConfidenceBand.high,
  );

  factory ValuationFactor.derived({
    required String id,
    required String label,
    required double value,
    String? unit,
    String? source,
    ConfidenceBand confidence = ConfidenceBand.medium,
  }) => ValuationFactor(
    id: id,
    label: label,
    provenance: FactorProvenance.derived,
    value: value,
    unit: unit,
    source: source,
    confidence: confidence,
  );

  factory ValuationFactor.suggested({
    required String id,
    required String label,
    required double value,
    String? unit,
    String? source,
    ConfidenceBand confidence = ConfidenceBand.low,
  }) => ValuationFactor(
    id: id,
    label: label,
    provenance: FactorProvenance.suggestedDefault,
    value: value,
    unit: unit,
    source: source,
    confidence: confidence,
  );

  factory ValuationFactor.missing({
    required String id,
    required String label,
    String? unit,
    String? note,
  }) => ValuationFactor(
    id: id,
    label: label,
    provenance: FactorProvenance.missing,
    unit: unit,
    note: note,
  );

  /// Confirms a [FactorProvenance.suggestedDefault] value, turning it into an
  /// [FactorProvenance.accepted] (and therefore usable) factor. No-op for any
  /// other provenance.
  ValuationFactor accept({String? note}) {
    if (provenance != FactorProvenance.suggestedDefault) return this;
    return copyWith(
      provenance: FactorProvenance.accepted,
      note: note ?? this.note,
    );
  }

  ValuationFactor copyWith({
    String? id,
    String? label,
    FactorProvenance? provenance,
    double? value,
    bool clearValue = false,
    String? unit,
    String? source,
    String? note,
    ConfidenceBand? confidence,
  }) => ValuationFactor(
    id: id ?? this.id,
    label: label ?? this.label,
    provenance: provenance ?? this.provenance,
    value: clearValue ? null : (value ?? this.value),
    unit: unit ?? this.unit,
    source: source ?? this.source,
    note: note ?? this.note,
    confidence: confidence ?? this.confidence,
  );
}

/// Why a required factor could not be used.
enum MissingFactorReason {
  /// No value was entered at all.
  notEntered,

  /// A system suggestion exists but has not been confirmed by the user.
  suggestionNotConfirmed,
}

/// A required factor that is absent or not yet usable — the structured reason a
/// method returns instead of a number.
class MissingFactor {
  const MissingFactor({
    required this.factorId,
    required this.label,
    required this.reason,
    required this.message,
  });

  final String factorId;
  final String label;
  final MissingFactorReason reason;

  /// Human-readable German explanation for the UI.
  final String message;
}

/// An immutable, id-keyed collection of factors handed to a method.
class FactorSet {
  FactorSet(Iterable<ValuationFactor> factors)
    : _byId = {for (final f in factors) f.id: f};

  final Map<String, ValuationFactor> _byId;

  ValuationFactor? operator [](String id) => _byId[id];

  /// The usable value for [id], or `null` if absent / not usable.
  double? value(String id) => _byId[id]?.usableValue;

  /// Whether [id] is present and usable.
  bool has(String id) => _byId[id]?.isUsable ?? false;

  Iterable<ValuationFactor> get all => _byId.values;

  /// Returns a [MissingFactor] for every [requiredIds] entry that is absent or
  /// not usable, so a method can short-circuit to [MethodUnavailable].
  List<MissingFactor> missingAmong(Iterable<String> requiredIds) {
    final result = <MissingFactor>[];
    for (final id in requiredIds) {
      final factor = _byId[id];
      if (factor != null && factor.isUsable) continue;
      final reason =
          factor?.provenance == FactorProvenance.suggestedDefault
              ? MissingFactorReason.suggestionNotConfirmed
              : MissingFactorReason.notEntered;
      final label = factor?.label ?? id;
      result.add(
        MissingFactor(
          factorId: id,
          label: label,
          reason: reason,
          message:
              reason == MissingFactorReason.suggestionNotConfirmed
                  ? 'Systemvorschlag für „$label" muss bestätigt werden.'
                  : 'Pflichtwert „$label" fehlt.',
        ),
      );
    }
    return result;
  }

  /// Returns a new set with [factor] added or replacing any existing factor of
  /// the same id.
  FactorSet withFactor(ValuationFactor factor) =>
      FactorSet([..._byId.values.where((f) => f.id != factor.id), factor]);
}

/// Result-level confidence derived purely from the provenance of the factors a
/// method actually used: user data → high, derived/confirmed suggestion →
/// medium, anything weaker → low. The overall band is the weakest contributor.
ConfidenceBand combineConfidence(Iterable<ValuationFactor> factors) {
  int rank(FactorProvenance p) => switch (p) {
    FactorProvenance.userProvided => 3,
    FactorProvenance.derived => 2,
    FactorProvenance.accepted => 2,
    FactorProvenance.suggestedDefault => 1,
    FactorProvenance.missing => 1,
  };
  var min = 3;
  for (final f in factors) {
    final r = rank(f.provenance);
    if (r < min) min = r;
  }
  return switch (min) {
    3 => ConfidenceBand.high,
    2 => ConfidenceBand.medium,
    _ => ConfidenceBand.low,
  };
}
