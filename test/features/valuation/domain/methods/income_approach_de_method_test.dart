import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/domain/methods/income_approach_de_method.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_math.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';

void main() {
  group('IncomeApproachDeMethod', () {
    const method = IncomeApproachDeMethod();

    List<ValuationFactor> baseFactors() => [
      ValuationFactor.user(
        id: ValuationFactorIds.grossRentAnnual,
        label: 'Rohertrag',
        value: 60000,
      ),
      ValuationFactor.user(
        id: ValuationFactorIds.operatingExpensesAnnual,
        label: 'Bewirtschaftungskosten',
        value: 15000,
      ),
      ValuationFactor.user(
        id: ValuationFactorIds.landAreaSqm,
        label: 'Grundstücksfläche',
        value: 500,
      ),
      ValuationFactor.user(
        id: ValuationFactorIds.landValuePerSqm,
        label: 'Bodenrichtwert',
        value: 400,
      ),
      ValuationFactor.user(
        id: ValuationFactorIds.liegenschaftszinssatz,
        label: 'Liegenschaftszinssatz',
        value: 0.035,
      ),
      ValuationFactor.user(
        id: ValuationFactorIds.remainingUsefulLifeYears,
        label: 'Restnutzungsdauer',
        value: 50,
      ),
    ];

    // Musterfall (Referenzbasis): Reinertrag 45.000, Bodenwert 200.000,
    // Bodenwertverzinsung 7.000, Gebäudereinertrag 38.000,
    // Vervielfältiger(3,5 %, 50 J.) ≈ 23,4556 -> Ertragswert ≈ 1.091.313 €.
    final vervielfaeltiger = presentValueAnnuityFactor(rate: 0.035, years: 50)!;
    final expected = 200000 + 38000 * vervielfaeltiger;

    test('computes the Ertragswert from the reference sample case', () {
      final result = method.evaluate(FactorSet(baseFactors()));

      expect(result, isA<MethodValue>());
      final value = result as MethodValue;
      expect(value.amount, closeTo(expected, 1e-6));
      expect(value.amount, closeTo(1091313, 5));
      expect(value.confidence, ConfidenceBand.high);
      expect(
        value.breakdown.map((l) => l.label),
        containsAll(<String>[
          'Bodenwertverzinsung',
          'Gebäudereinertrag',
          'Vervielfältiger',
          'Ertragswert',
        ]),
      );
    });

    test('derives the Restnutzungsdauer from Gesamtnutzungsdauer and age', () {
      final factors = [
        ...baseFactors().where(
          (f) => f.id != ValuationFactorIds.remainingUsefulLifeYears,
        ),
        ValuationFactor.user(
          id: ValuationFactorIds.totalUsefulLifeYears,
          label: 'Gesamtnutzungsdauer',
          value: 80,
        ),
        ValuationFactor.user(
          id: ValuationFactorIds.buildingAgeYears,
          label: 'Alter',
          value: 30,
        ),
      ];

      final result = method.evaluate(FactorSet(factors));

      expect((result as MethodValue).amount, closeTo(expected, 1e-6));
    });

    test('applies besondere objektspezifische Grundstücksmerkmale', () {
      final result = method.evaluate(
        FactorSet([
          ...baseFactors(),
          ValuationFactor.user(
            id: ValuationFactorIds.otherValueAdjustment,
            label: 'boM',
            value: -25000,
          ),
        ]),
      );

      expect((result as MethodValue).amount, closeTo(expected - 25000, 1e-6));
    });

    test('is unavailable — not zero — when the Bodenwert cannot be built', () {
      final factors = baseFactors().where(
        (f) => f.id != ValuationFactorIds.landValuePerSqm,
      );

      final result = method.evaluate(FactorSet(factors));

      expect(result, isA<MethodUnavailable>());
      expect(
        (result as MethodUnavailable).missingFactors.map((m) => m.factorId),
        contains(ValuationFactorIds.landValue),
      );
    });

    test('treats an unconfirmed suggestion as missing', () {
      final factors = [
        ...baseFactors().where(
          (f) => f.id != ValuationFactorIds.liegenschaftszinssatz,
        ),
        ValuationFactor.suggested(
          id: ValuationFactorIds.liegenschaftszinssatz,
          label: 'Liegenschaftszinssatz',
          value: 0.035,
          source: 'Referenztabelle',
        ),
      ];

      final result = method.evaluate(FactorSet(factors));

      expect(result, isA<MethodUnavailable>());
      final missing = (result as MethodUnavailable).missingFactors.single;
      expect(missing.factorId, ValuationFactorIds.liegenschaftszinssatz);
      expect(missing.reason, MissingFactorReason.suggestionNotConfirmed);
    });

    test('accepting the suggestion makes the method available again', () {
      final suggestion = ValuationFactor.suggested(
        id: ValuationFactorIds.liegenschaftszinssatz,
        label: 'Liegenschaftszinssatz',
        value: 0.035,
        source: 'Referenztabelle',
      ).accept();
      final factors = [
        ...baseFactors().where(
          (f) => f.id != ValuationFactorIds.liegenschaftszinssatz,
        ),
        suggestion,
      ];

      final result = method.evaluate(FactorSet(factors));

      expect(result, isA<MethodValue>());
      final value = result as MethodValue;
      expect(value.amount, closeTo(expected, 1e-6));
      expect(value.confidence, ConfidenceBand.medium);
    });
  });
}
