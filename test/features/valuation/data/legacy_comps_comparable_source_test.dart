import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/comps.dart';
import 'package:neximmo_app/data/repositories/comps_repo.dart';
import 'package:neximmo_app/features/valuation/data/legacy_comps_comparable_source.dart';
import 'package:neximmo_app/features/valuation/domain/methods/comparison_approach_method.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

CompSale _sale({
  String id = 'comp-1',
  String address = 'Musterweg 1',
  double price = 300000,
  double? sqft = 100,
  bool selected = true,
  double weight = 1,
  String? source,
}) => CompSale(
  id: id,
  propertyId: 'prop-1',
  address: address,
  price: price,
  sqft: sqft,
  selected: selected,
  weight: weight,
  source: source,
  createdAt: 1750000000000,
);

/// Stands in for the legacy repository: the mapping is what is under test, not
/// SQLite.
class _StubCompsRepository implements CompsRepository {
  _StubCompsRepository(this.sales);

  final List<CompSale> sales;

  @override
  Future<List<CompSale>> listSales(String propertyId) async => sales;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();

  Future<List<ComparableSale>> map(List<CompSale> sales) async {
    final source = LegacyCompsComparableSource(_StubCompsRepository(sales));
    return source.listForProperty('prop-1');
  }

  test('maps a selected comp onto its adjusted price per square metre',
      () async {
    final comparables = await map(<CompSale>[_sale()]);

    expect(comparables, hasLength(1));
    final comparable = comparables.single;
    expect(comparable.adjustedPricePerSqm, closeTo(3000, 1e-9));
    expect(comparable.label, 'Musterweg 1');
  });

  test('skips comps the user did not select', () async {
    // The legacy list doubles as a research collection; feeding the unselected
    // rows would move a valuation behind the user's back.
    final comparables = await map(<CompSale>[_sale(selected: false)]);

    expect(comparables, isEmpty);
  });

  test('skips a comp without an area', () async {
    // The method values €/m²; guessing an area from the price would be
    // circular.
    final comparables = await map(<CompSale>[_sale(sqft: null)]);

    expect(comparables, isEmpty);
  });

  test('skips a comp without a price', () async {
    final comparables = await map(<CompSale>[_sale(price: 0)]);

    expect(comparables, isEmpty);
  });

  test('carries the legacy weight as the price adjustment', () async {
    final comparables = await map(<CompSale>[_sale(weight: 0.95)]);

    final comparable = comparables.single;
    expect(comparable.priceAdjustment, closeTo(0.95, 1e-9));
    expect(comparable.adjustedPricePerSqm, closeTo(2850, 1e-9));
  });

  test('an absurd or unset weight leaves the comp at face value', () async {
    final comparables = await map(<CompSale>[
      _sale(id: 'a', weight: 0),
      _sale(id: 'b', weight: 12),
    ]);

    final adjustments = comparables
        .map((entry) => entry.priceAdjustment)
        .toList();
    expect(adjustments.first, 1.0);
    expect(adjustments.last, LegacyCompsComparableSource.maxAdjustment);
  });
}
