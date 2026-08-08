import '../../../core/models/comps.dart';
import '../../../data/repositories/comps_repo.dart';
import '../application/valuation_comparable_source.dart';
import '../domain/methods/comparison_approach_method.dart';

/// Maps the legacy `comps_sales` rows onto the engine's [ComparableSale]
/// (Welle 5, AP7).
///
/// Three decisions the mapping makes, each of them a place where inventing
/// something would have been easy:
///
/// * **Only selected comps count.** The legacy list doubles as a research
///   collection; `selected` is the user's statement that a row is comparable.
///   Feeding the unselected ones would move a valuation behind the user's back.
/// * **A comp without an area is dropped.** The method values €/m², so a row
///   without `sqft` cannot contribute — and guessing an area from the price
///   would be circular.
/// * **The legacy `weight` becomes the price adjustment**, because that is what
///   it does arithmetically: it scales the comparable's contribution. It is
///   clamped to a sane band and defaults to 1.0, so an unset or absurd weight
///   leaves the comp at face value rather than distorting it.
class LegacyCompsComparableSource implements ValuationComparableSource {
  const LegacyCompsComparableSource(this._compsRepo);

  /// Legacy weights are free-form doubles. Outside this band a weight is more
  /// likely a data error than an intended adjustment.
  static const double minAdjustment = 0.5;
  static const double maxAdjustment = 1.5;

  final CompsRepository _compsRepo;

  @override
  Future<List<ComparableSale>> listForProperty(String propertyId) async {
    final sales = await _compsRepo.listSales(propertyId);
    return sales
        .where((sale) => sale.selected && (sale.sqft ?? 0) > 0 && sale.price > 0)
        .map(_toComparable)
        .toList(growable: false);
  }

  static ComparableSale _toComparable(CompSale sale) => ComparableSale(
    id: sale.id,
    label: sale.address,
    price: sale.price,
    areaSqm: sale.sqft!,
    priceAdjustment: _adjustmentFor(sale.weight),
    note: sale.source,
  );

  static double _adjustmentFor(double weight) {
    if (weight <= 0) return 1;
    return weight.clamp(minAdjustment, maxAdjustment);
  }
}
