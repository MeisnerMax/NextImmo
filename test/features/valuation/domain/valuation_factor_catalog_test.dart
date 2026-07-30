import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/domain/methods/comparison_approach_method.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_catalog.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';

/// A plausible value per input kind — availability is what is under test, not
/// the arithmetic, so only the shapes have to be sane (age below the useful
/// life, positive rates).
double _valueFor(ValuationFactorSpec spec) {
  if (spec.id == ValuationFactorIds.buildingAgeYears) return 20;
  if (spec.id == ValuationFactorIds.totalUsefulLifeYears) return 80;
  return switch (spec.kind) {
    FactorInputKind.percent => 0.035,
    FactorInputKind.years => 50,
    FactorInputKind.area => 400,
    FactorInputKind.factor => 1.1,
    FactorInputKind.money => 60000,
  };
}

/// Everything the form offers: all required factors plus the first option of
/// every alternative. Purely optional extras stay out — a complete case must
/// not depend on them.
FactorSet _completeFactorSet() {
  final ids = <String>{};
  for (final group in ValuationFactorCatalog.groups) {
    ids.addAll(group.requiredFactors.map((spec) => spec.id));
    for (final alternative in group.alternatives) {
      ids.addAll(alternative.options.first);
    }
  }
  return FactorSet(
    ids.map((id) {
      final spec = ValuationFactorCatalog.specFor(id)!;
      return ValuationFactor.user(
        id: spec.id,
        label: spec.label,
        value: _valueFor(spec),
        unit: spec.unit,
      );
    }),
  );
}

const _comparables = <ComparableSale>[
  ComparableSale(id: 'a', label: 'A', price: 900000, areaSqm: 300),
  ComparableSale(id: 'b', label: 'B', price: 930000, areaSqm: 310),
  ComparableSale(id: 'c', label: 'C', price: 880000, areaSqm: 295),
];

void main() {
  group('ValuationFactorCatalog', () {
    test('covers every method with a group', () {
      for (final kind in ValuationMethodKind.values) {
        expect(
          ValuationFactorCatalog.groupFor(kind),
          isNotNull,
          reason: '${kind.labelDe} hat keine Faktorgruppe',
        );
      }
    });

    test('every spec has a distinct, resolvable id', () {
      final ids = ValuationFactorCatalog.allFactors
          .map((spec) => spec.id)
          .toList();

      expect(ids, ids.toSet().toList(), reason: 'keine Doppelungen');
      for (final id in ids) {
        expect(ValuationFactorCatalog.specFor(id)?.id, id);
      }
    });

    test('an unknown id resolves to null instead of a stand-in', () {
      expect(ValuationFactorCatalog.specFor('gibtEsNicht'), isNull);
    });

    // The catalogue is the form's contract with the engine: filling in what the
    // form asks for must actually make every method available. If a method
    // gains a requirement the form does not offer, this fails — which is the
    // whole point of pinning it.
    test('the full input surface makes every method available', () {
      final factors = _completeFactorSet();
      final valuationCase = ValuationCase(
        id: 'case-1',
        propertyId: 'prop-1',
        title: 'Katalog-Musterfall',
        kind: ValuationCaseKind.holding,
        factors: factors,
        comparables: _comparables,
      );

      final report = const ValuationEngine().run(valuationCase);

      for (final kind in ValuationMethodKind.values) {
        expect(
          report.methodResults[kind],
          isA<MethodValue>(),
          reason: '${kind.labelDe} ist mit dem vollen Katalog nicht verfügbar',
        );
      }
    });

    test('every group reports itself complete for that input surface', () {
      final factors = _completeFactorSet();

      for (final group in ValuationFactorCatalog.groups) {
        expect(
          group.isComplete(factors.has),
          isTrue,
          reason: '${group.method.labelDe} zählt sich nicht als vollständig',
        );
      }
    });

    test('progress counts an alternative once, whichever path is used', () {
      final group = ValuationFactorCatalog.groupFor(
        ValuationMethodKind.incomeApproachDe,
      )!;

      final viaLandValue = FactorSet(<ValuationFactor>[
        ValuationFactor.user(
          id: ValuationFactorIds.landValue,
          label: 'Bodenwert',
          value: 200000,
        ),
      ]);
      final viaAreaAndRate = FactorSet(<ValuationFactor>[
        ValuationFactor.user(
          id: ValuationFactorIds.landAreaSqm,
          label: 'Fläche',
          value: 500,
        ),
        ValuationFactor.user(
          id: ValuationFactorIds.landValuePerSqm,
          label: 'Bodenrichtwert',
          value: 400,
        ),
      ]);
      final halfWay = FactorSet(<ValuationFactor>[
        ValuationFactor.user(
          id: ValuationFactorIds.landAreaSqm,
          label: 'Fläche',
          value: 500,
        ),
      ]);

      expect(group.progress(viaLandValue.has).satisfied, 1);
      expect(group.progress(viaAreaAndRate.has).satisfied, 1);
      // Half of a two-part path satisfies nothing — the form must not claim it.
      expect(group.progress(halfWay.has).satisfied, 0);
    });

    test('optional factors are excluded from the required set', () {
      final incomeGroup = ValuationFactorCatalog.groupFor(
        ValuationMethodKind.incomeApproachDe,
      )!;

      expect(
        incomeGroup.requiredFactors.map((spec) => spec.id),
        isNot(contains(ValuationFactorIds.otherValueAdjustment)),
      );
      expect(
        incomeGroup.requiredFactors.map((spec) => spec.id),
        contains(ValuationFactorIds.grossRentAnnual),
      );
    });

    test('rates are percent inputs and money is money', () {
      expect(
        ValuationFactorCatalog.specFor(
          ValuationFactorIds.liegenschaftszinssatz,
        )!.kind,
        FactorInputKind.percent,
      );
      expect(
        ValuationFactorCatalog.specFor(ValuationFactorIds.grossRentAnnual)!.kind,
        FactorInputKind.money,
      );
      expect(
        ValuationFactorCatalog.specFor(
          ValuationFactorIds.remainingUsefulLifeYears,
        )!.kind,
        FactorInputKind.years,
      );
    });
  });
}
