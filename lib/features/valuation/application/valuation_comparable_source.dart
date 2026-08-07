/// Where the Vergleichswertverfahren gets its comparables (Welle 5, AP7).
///
/// The comps aggregate of P2-D07 has not been migrated yet, so the only source
/// that exists is the legacy `comps_sales` store. Naming the port anyway keeps
/// the engine free of that fact: when the aggregate ships, a second
/// implementation replaces the adapter and nothing above this line changes.
library;

import '../domain/methods/comparison_approach_method.dart';

abstract interface class ValuationComparableSource {
  /// Comparables for one property, already mapped onto the engine's own type.
  ///
  /// Only entries the user marked as selected are returned: an unselected comp
  /// stays in the list for reference and must not silently move a valuation.
  Future<List<ComparableSale>> listForProperty(String propertyId);
}
