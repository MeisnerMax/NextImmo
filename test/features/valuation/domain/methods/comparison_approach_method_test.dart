import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/domain/methods/comparison_approach_method.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';

void main() {
  group('ComparisonApproachMethod', () {
    const comparables = [
      ComparableSale(id: 'a', label: 'A', price: 300000, areaSqm: 100),
      ComparableSale(id: 'b', label: 'B', price: 330000, areaSqm: 110),
      ComparableSale(
        id: 'c',
        label: 'C',
        price: 280000,
        areaSqm: 95,
        priceAdjustment: 0.95,
      ),
    ];

    final subjectArea = ValuationFactor.user(
      id: ValuationFactorIds.subjectLivingAreaSqm,
      label: 'Wohnfläche',
      value: 120,
    );

    // Musterfall: 3.000 + 3.000 + 2.800 €/m² -> Mittel 2.933,33 €/m²
    // × 120 m² = 352.000 €.
    test('averages the adjusted comparable prices per m²', () {
      const method = ComparisonApproachMethod(comparables: comparables);

      final result = method.evaluate(FactorSet([subjectArea]));

      expect(result, isA<MethodValue>());
      final value = result as MethodValue;
      expect(value.amount, closeTo(352000, 1e-6));
      expect(value.breakdown.first.unit, '€/m²');
    });

    test('is unavailable with too few suitable comparables', () {
      final method = ComparisonApproachMethod(
        comparables: [comparables[0], comparables[1]],
      );

      final result = method.evaluate(FactorSet([subjectArea]));

      expect(result, isA<MethodUnavailable>());
      expect((result as MethodUnavailable).reasons.single, contains('2 von'));
    });

    test('ignores comparables without a usable area', () {
      const method = ComparisonApproachMethod(
        comparables: [
          ...comparables,
          ComparableSale(id: 'd', label: 'D', price: 400000, areaSqm: 0),
        ],
      );

      final result = method.evaluate(FactorSet([subjectArea]));

      expect((result as MethodValue).amount, closeTo(352000, 1e-6));
    });

    test('is unavailable when the subject area is missing', () {
      const method = ComparisonApproachMethod(comparables: comparables);

      final result = method.evaluate(FactorSet(const []));

      expect(result, isA<MethodUnavailable>());
      expect(
        (result as MethodUnavailable).missingFactors.single.factorId,
        ValuationFactorIds.subjectLivingAreaSqm,
      );
    });

    test('applies besondere objektspezifische Grundstücksmerkmale', () {
      const method = ComparisonApproachMethod(comparables: comparables);

      final result = method.evaluate(
        FactorSet([
          subjectArea,
          ValuationFactor.user(
            id: ValuationFactorIds.otherValueAdjustment,
            label: 'boM',
            value: 12000,
          ),
        ]),
      );

      expect((result as MethodValue).amount, closeTo(364000, 1e-6));
    });
  });
}
