/// Computed financial figures and the definitions behind them (FINANCE-01b).
///
/// The one thing that makes this DTO different from an ordinary numbers-object:
/// [FinanceKpiValue.definitionVersion] is **not optional**. A computed figure
/// that cannot say which definition produced it is exactly what
/// `PROPERTY_PERFORMANCE_V2.md` §7 forbids, so there is no way to construct one
/// here. A surface that renders a value without its version is then a choice
/// somebody made, not an accident the type allowed.
///
/// Values are per currency, like everything else in this feature. Adding EUR to
/// CHF produces a number that is wrong in both, and there is no field for it.
library;

/// One figure, in one currency, computed under one definition version.
class FinanceKpiValue {
  const FinanceKpiValue({
    required this.kpiKey,
    required this.definitionId,
    required this.definitionVersion,
    required this.name,
    required this.currencyCode,
    required this.value,
    required this.entries,
  });

  /// Stable server key — `noi` stays `noi` across revisions of its meaning.
  final String kpiKey;

  final String definitionId;

  /// Which revision of the definition produced this number. Required, because
  /// a figure that cannot name its own meaning is not reproducible.
  final int definitionVersion;

  /// The human name the definition was published under.
  final String name;

  final String currencyCode;
  final num value;

  /// How many bookings the figure rests on. Excluded entries are not counted:
  /// they are not part of it.
  final int entries;
}

class PropertyFinanceKpisDto {
  const PropertyFinanceKpisDto({
    required this.asOf,
    required this.values,
    required this.isProvisional,
    required this.openPeriods,
    required this.coveredPeriods,
    required this.activeDefinitions,
  });

  final DateTime asOf;

  /// Server-ordered by key, then currency.
  final List<FinanceKpiValue> values;

  /// True while any period the figures drew on is still open.
  final bool isProvisional;

  final int openPeriods;
  final int coveredPeriods;

  /// How many definitions are active in this workspace at all.
  ///
  /// This is what separates two answers a surface must never conflate: no
  /// values with no active definitions means nobody has told this workspace
  /// what to compute; no values *with* active definitions means the definitions
  /// matched nothing booked. Rendering both as an empty panel would hide a
  /// setup step behind what looks like an absence of data.
  final int activeDefinitions;

  bool get hasDefinitions => activeDefinitions > 0;

  bool get isEmpty => values.isEmpty;

  /// The currencies present, in the order the server's rows introduced them.
  List<String> get currencies {
    final seen = <String>[];
    for (final value in values) {
      if (!seen.contains(value.currencyCode)) {
        seen.add(value.currencyCode);
      }
    }
    return seen;
  }

  List<FinanceKpiValue> valuesIn(String currencyCode) => values
      .where((value) => value.currencyCode == currencyCode)
      .toList(growable: false);
}
