import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/domain/methods/comparison_approach_method.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_report.dart';

/// Musterfall: ein vollständig belegter Bestandsfall, in dem alle fünf
/// Verfahren rechnen können.
List<ValuationFactor> _fullFactors() => [
  // Ertrag / Betrieb.
  ValuationFactor.user(id: ValuationFactorIds.grossRentAnnual, label: 'Rohertrag', value: 60000),
  ValuationFactor.user(id: ValuationFactorIds.operatingExpensesAnnual, label: 'Bewirtschaftungskosten', value: 15000),
  ValuationFactor.user(id: ValuationFactorIds.vacancyRate, label: 'Leerstand', value: 0.03),
  // Boden / Ertragswert.
  ValuationFactor.user(id: ValuationFactorIds.landAreaSqm, label: 'Grundstücksfläche', value: 500),
  ValuationFactor.user(id: ValuationFactorIds.landValuePerSqm, label: 'Bodenrichtwert', value: 400),
  ValuationFactor.user(id: ValuationFactorIds.liegenschaftszinssatz, label: 'Liegenschaftszinssatz', value: 0.035),
  ValuationFactor.user(id: ValuationFactorIds.remainingUsefulLifeYears, label: 'Restnutzungsdauer', value: 50),
  // Sachwert.
  ValuationFactor.user(id: ValuationFactorIds.grossFloorAreaSqm, label: 'BGF', value: 400),
  ValuationFactor.user(id: ValuationFactorIds.normalHerstellungskostenPerSqm, label: 'NHK', value: 1230),
  ValuationFactor.user(id: ValuationFactorIds.constructionPriceIndex, label: 'Baupreisindex', value: 1.25),
  ValuationFactor.user(id: ValuationFactorIds.regionalFactor, label: 'Regionalfaktor', value: 1.0),
  ValuationFactor.user(id: ValuationFactorIds.buildingAgeYears, label: 'Alter', value: 20),
  ValuationFactor.user(id: ValuationFactorIds.totalUsefulLifeYears, label: 'Gesamtnutzungsdauer', value: 80),
  ValuationFactor.user(id: ValuationFactorIds.sachwertfaktor, label: 'Sachwertfaktor', value: 1.1),
  // Vergleich.
  ValuationFactor.user(id: ValuationFactorIds.subjectLivingAreaSqm, label: 'Wohnfläche', value: 300),
  // DCF / Direktkapitalisierung.
  ValuationFactor.user(id: ValuationFactorIds.rentGrowthRate, label: 'Mietwachstum', value: 0.02),
  ValuationFactor.user(id: ValuationFactorIds.expenseGrowthRate, label: 'Kostenwachstum', value: 0.02),
  ValuationFactor.user(id: ValuationFactorIds.holdYears, label: 'Haltedauer', value: 10),
  ValuationFactor.user(id: ValuationFactorIds.discountRate, label: 'Kalkulationszins', value: 0.06),
  ValuationFactor.user(id: ValuationFactorIds.saleCostRate, label: 'Verkaufskosten', value: 0.03),
  ValuationFactor.user(id: ValuationFactorIds.exitCapRate, label: 'Exit-Cap', value: 0.05),
  ValuationFactor.user(id: ValuationFactorIds.capRate, label: 'Kapitalisierungszins', value: 0.05),
  ValuationFactor.user(id: ValuationFactorIds.purchasePrice, label: 'Kaufpreis', value: 900000),
];

const _comparables = [
  ComparableSale(id: 'a', label: 'A', price: 900000, areaSqm: 300),
  ComparableSale(id: 'b', label: 'B', price: 930000, areaSqm: 310),
  ComparableSale(id: 'c', label: 'C', price: 880000, areaSqm: 295),
];

ValuationCase _case({
  List<ValuationFactor>? factors,
  ValuationCaseStatus status = ValuationCaseStatus.draft,
  Set<ValuationMethodKind>? enabledMethods,
  List<ComparableSale> comparables = _comparables,
}) => ValuationCase(
  id: 'case-1',
  propertyId: 'prop-1',
  title: 'Musterfall MFH',
  kind: ValuationCaseKind.holding,
  status: status,
  factors: FactorSet(factors ?? _fullFactors()),
  comparables: comparables,
  enabledMethods: enabledMethods ?? ValuationCase.allMethodKinds,
);

void main() {
  const engine = ValuationEngine();

  group('ValuationCase lifecycle', () {
    test('a draft case accepts factor changes', () {
      final updated = _case().withFactor(
        ValuationFactor.user(
          id: ValuationFactorIds.grossRentAnnual,
          label: 'Rohertrag',
          value: 66000,
        ),
      );

      expect(updated.factors.value(ValuationFactorIds.grossRentAnnual), 66000);
    });

    test('an approved case is immutable', () {
      final approved = _case(status: ValuationCaseStatus.approved);

      expect(
        () => approved.withFactor(
          ValuationFactor.user(
            id: ValuationFactorIds.grossRentAnnual,
            label: 'Rohertrag',
            value: 66000,
          ),
        ),
        throwsStateError,
      );
    });

    test('acceptSuggestion makes a blocked method available', () {
      final withSuggestion = _case(
        factors: [
          ..._fullFactors().where(
            (f) => f.id != ValuationFactorIds.liegenschaftszinssatz,
          ),
          ValuationFactor.suggested(
            id: ValuationFactorIds.liegenschaftszinssatz,
            label: 'Liegenschaftszinssatz',
            value: 0.035,
            source: 'Referenztabelle',
          ),
        ],
      );

      final before = engine.run(withSuggestion);
      expect(
        before.methodResults[ValuationMethodKind.incomeApproachDe],
        isA<MethodUnavailable>(),
      );

      final after = engine.run(
        withSuggestion.acceptSuggestion(ValuationFactorIds.liegenschaftszinssatz),
      );
      expect(
        after.methodResults[ValuationMethodKind.incomeApproachDe],
        isA<MethodValue>(),
      );
    });
  });

  group('ValuationEngine', () {
    test('runs every enabled method and reconciles a Verkehrswert', () {
      final report = engine.run(_case());

      expect(report.methodResults, hasLength(5));
      expect(report.unavailableMethods, isEmpty);
      expect(report.opinion, isA<MarketValue>());

      final opinion = report.opinion as MarketValue;
      expect(opinion.weights.keys, hasLength(5));
      expect(
        opinion.weights.values.fold<double>(0, (s, w) => s + w),
        closeTo(1.0, 1e-9),
      );
      // The weighted value must sit inside the range of the method values.
      final values = report.methodResults.values
          .whereType<MethodValue>()
          .map((v) => v.amount);
      expect(opinion.amount, greaterThanOrEqualTo(values.reduce((a, b) => a < b ? a : b)));
      expect(opinion.amount, lessThanOrEqualTo(values.reduce((a, b) => a > b ? a : b)));
    });

    test('builds a deduplicated, deterministically ordered assumption ledger', () {
      final report = engine.run(_case());

      final ids = report.assumptionLedger.map((a) => a.factorId).toList();
      expect(ids, ids.toSet().toList(), reason: 'keine Doppelungen');
      expect(ids, List<String>.from(ids)..sort());
      expect(ids, contains(ValuationFactorIds.landValuePerSqm));
      expect(ids, contains(ValuationFactorIds.discountRate));
    });

    test('reports investment metrics from the case cash flows', () {
      final report = engine.run(_case());

      expect(report.investment.irr, isNotNull);
      expect(report.investment.irr, greaterThan(0));
      expect(report.investment.npvAtDiscountRate, isNotNull);
      expect(report.investment.equityMultiple, greaterThan(1));
      expect(report.investment.discountRate, 0.06);
    });

    test('leaves investment metrics empty without a purchase price', () {
      final report = engine.run(
        _case(
          factors: _fullFactors()
              .where((f) => f.id != ValuationFactorIds.purchasePrice)
              .toList(),
        ),
      );

      expect(report.investment.isEmpty, isTrue);
    });

    test('keeps unavailable methods visible instead of dropping them', () {
      final report = engine.run(_case(comparables: const []));

      expect(
        report.unavailableMethods,
        contains(ValuationMethodKind.comparisonApproach),
      );
      expect(report.opinion, isA<MarketValue>());
      expect(
        (report.opinion as MarketValue).weights.keys,
        isNot(contains(ValuationMethodKind.comparisonApproach)),
      );
    });

    test('runs only the enabled methods', () {
      final report = engine.run(
        _case(
          enabledMethods: const {
            ValuationMethodKind.incomeApproachDe,
            ValuationMethodKind.directCapitalization,
          },
        ),
      );

      expect(report.methodResults.keys, hasLength(2));
      expect(
        report.methodResults.keys,
        isNot(contains(ValuationMethodKind.costApproachDe)),
      );
    });

    test('yields "nicht ermittelbar" when no method can run', () {
      final report = engine.run(
        _case(factors: const [], comparables: const []),
      );

      expect(report.opinion, isA<MarketValueUnavailable>());
      expect(report.assumptionLedger, isEmpty);
      expect(report.investment.isEmpty, isTrue);
    });
  });
}
