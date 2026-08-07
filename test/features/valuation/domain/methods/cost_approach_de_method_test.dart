import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/domain/methods/cost_approach_de_method.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';

void main() {
  group('CostApproachDeMethod', () {
    const method = CostApproachDeMethod();

    List<ValuationFactor> baseFactors() => [
      ValuationFactor.user(
        id: ValuationFactorIds.grossFloorAreaSqm,
        label: 'BGF',
        value: 400,
      ),
      ValuationFactor.user(
        id: ValuationFactorIds.normalHerstellungskostenPerSqm,
        label: 'NHK',
        value: 1230,
      ),
      ValuationFactor.user(
        id: ValuationFactorIds.constructionPriceIndex,
        label: 'Baupreisindex',
        value: 1.25,
      ),
      ValuationFactor.user(
        id: ValuationFactorIds.regionalFactor,
        label: 'Regionalfaktor',
        value: 1.0,
      ),
      ValuationFactor.user(
        id: ValuationFactorIds.buildingAgeYears,
        label: 'Alter',
        value: 20,
      ),
      ValuationFactor.user(
        id: ValuationFactorIds.totalUsefulLifeYears,
        label: 'Gesamtnutzungsdauer',
        value: 80,
      ),
      ValuationFactor.user(
        id: ValuationFactorIds.sachwertfaktor,
        label: 'Sachwertfaktor',
        value: 1.1,
      ),
      ValuationFactor.user(
        id: ValuationFactorIds.landValue,
        label: 'Bodenwert',
        value: 200000,
      ),
      ValuationFactor.user(
        id: ValuationFactorIds.outdoorFacilitiesValue,
        label: 'Außenanlagen',
        value: 15000,
      ),
    ];

    // Musterfall: HK = 1230*400*1,25*1,0 = 615.000; Restwertanteil = 1 − 20/80
    // = 0,75 -> Gebäudesachwert 461.250; + Bodenwert 200.000 + Außenanlagen
    // 15.000 = 676.250; × Sachwertfaktor 1,1 = 743.875 €.
    test('computes the Sachwert from the reference sample case', () {
      final result = method.evaluate(FactorSet(baseFactors()));

      expect(result, isA<MethodValue>());
      final value = result as MethodValue;
      expect(value.amount, closeTo(743875, 1e-6));
      expect(value.confidence, ConfidenceBand.high);
      expect(
        value.breakdown.map((l) => l.label),
        containsAll(<String>[
          'Herstellungskosten',
          'Gebäudesachwert',
          'Vorläufiger Sachwert',
          'Sachwert',
        ]),
      );
    });

    test('adds besondere objektspezifische Grundstücksmerkmale after the factor', () {
      final result = method.evaluate(
        FactorSet([
          ...baseFactors(),
          ValuationFactor.user(
            id: ValuationFactorIds.otherValueAdjustment,
            label: 'boM',
            value: -40000,
          ),
        ]),
      );

      expect((result as MethodValue).amount, closeTo(703875, 1e-6));
    });

    test('is unavailable when the Sachwertfaktor is missing', () {
      final result = method.evaluate(
        FactorSet(
          baseFactors().where((f) => f.id != ValuationFactorIds.sachwertfaktor),
        ),
      );

      expect(result, isA<MethodUnavailable>());
      expect(
        (result as MethodUnavailable).missingFactors.single.factorId,
        ValuationFactorIds.sachwertfaktor,
      );
    });

    test('derives the Bodenwert from Fläche × Bodenrichtwert', () {
      final factors = [
        ...baseFactors().where((f) => f.id != ValuationFactorIds.landValue),
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
      ];

      final result = method.evaluate(FactorSet(factors));

      expect((result as MethodValue).amount, closeTo(743875, 1e-6));
    });

    test('an unconfirmed NHK suggestion blocks the method', () {
      final factors = [
        ...baseFactors().where(
          (f) => f.id != ValuationFactorIds.normalHerstellungskostenPerSqm,
        ),
        ValuationFactor.suggested(
          id: ValuationFactorIds.normalHerstellungskostenPerSqm,
          label: 'NHK',
          value: 1230,
          source: 'NHK-2010-Tabelle',
        ),
      ];

      final result = method.evaluate(FactorSet(factors));

      expect(result, isA<MethodUnavailable>());
      expect(
        (result as MethodUnavailable).missingFactors.single.reason,
        MissingFactorReason.suggestionNotConfirmed,
      );
    });
  });
}
