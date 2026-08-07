import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/domain/methods/direct_capitalization_method.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';


void main() {
  group('DirectCapitalizationMethod', () {
    const method = DirectCapitalizationMethod();

    test('capitalizes an explicit stabilized NOI', () {
      final result = method.evaluate(
        FactorSet([
          ValuationFactor.user(id: ValuationFactorIds.stabilizedNoiAnnual, label: 'RE', value: 70000),
          ValuationFactor.user(id: ValuationFactorIds.capRate, label: 'Kap', value: 0.05),
        ]),
      );
      expect(result, isA<MethodValue>());
      expect((result as MethodValue).amount, closeTo(1400000, 1e-6));
    });

    test('derives NOI from Rohertrag, Leerstand and Bewirtschaftungskosten', () {
      final result = method.evaluate(
        FactorSet([
          ValuationFactor.user(id: ValuationFactorIds.grossRentAnnual, label: 'Rohertrag', value: 100000),
          ValuationFactor.user(id: ValuationFactorIds.vacancyRate, label: 'Leerstand', value: 0.05),
          ValuationFactor.user(id: ValuationFactorIds.operatingExpensesAnnual, label: 'BK', value: 25000),
          ValuationFactor.user(id: ValuationFactorIds.capRate, label: 'Kap', value: 0.05),
        ]),
      );
      // NOI = 100000*0.95 - 25000 = 70000 -> 70000/0.05 = 1,400,000.
      expect((result as MethodValue).amount, closeTo(1400000, 1e-6));
    });

    test('is unavailable when the cap rate is missing', () {
      final result = method.evaluate(
        FactorSet([
          ValuationFactor.user(id: ValuationFactorIds.stabilizedNoiAnnual, label: 'RE', value: 70000),
        ]),
      );
      expect(result, isA<MethodUnavailable>());
      expect(
        (result as MethodUnavailable).missingFactors.map((m) => m.factorId),
        contains(ValuationFactorIds.capRate),
      );
    });

    test('is unavailable when neither NOI nor its components are present', () {
      final result = method.evaluate(
        FactorSet([
          ValuationFactor.user(id: ValuationFactorIds.capRate, label: 'Kap', value: 0.05),
        ]),
      );
      expect(result, isA<MethodUnavailable>());
      expect(
        (result as MethodUnavailable).missingFactors.map((m) => m.factorId),
        contains(ValuationFactorIds.stabilizedNoiAnnual),
      );
    });

    test('adds quick ratios when a purchase price is present', () {
      final result =
          method.evaluate(
                FactorSet([
                  ValuationFactor.user(id: ValuationFactorIds.grossRentAnnual, label: 'Rohertrag', value: 100000),
                  ValuationFactor.user(id: ValuationFactorIds.vacancyRate, label: 'Leerstand', value: 0.05),
                  ValuationFactor.user(id: ValuationFactorIds.operatingExpensesAnnual, label: 'BK', value: 25000),
                  ValuationFactor.user(id: ValuationFactorIds.capRate, label: 'Kap', value: 0.05),
                  ValuationFactor.user(id: ValuationFactorIds.purchasePrice, label: 'Kaufpreis', value: 1250000),
                ]),
              )
              as MethodValue;
      final labels = result.breakdown.map((b) => b.label).toList();
      expect(labels, contains('Bruttoanfangsrendite'));
      expect(labels, contains('Nettoanfangsrendite'));
      expect(labels.any((l) => l.startsWith('Faktor')), isTrue);
    });
  });
}
