import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/domain/reference_data.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case_templates.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';

void main() {
  group('templates', () {
    test('every case kind has exactly one template', () {
      for (final kind in ValuationCaseKind.values) {
        expect(
          ValuationCaseTemplates.all.where((t) => t.kind == kind),
          hasLength(1),
          reason: '${kind.labelDe} braucht genau eine Vorlage',
        );
      }
    });

    test('weights only mention methods the template enables', () {
      for (final template in ValuationCaseTemplates.all) {
        expect(
          template.weights.keys,
          everyElement(isIn(template.enabledMethods)),
          reason: '${template.headline} gewichtet ein inaktives Verfahren',
        );
        expect(
          template.weights.values.fold<double>(0, (sum, w) => sum + w),
          closeTo(1.0, 1e-9),
        );
      }
    });

    test('each template runs at least one method', () {
      for (final template in ValuationCaseTemplates.all) {
        expect(template.enabledMethods, isNotEmpty);
      }
    });

    test('the acquisition template is the broad one, holding the narrow', () {
      final acquisition = ValuationCaseTemplates.forKind(
        ValuationCaseKind.acquisition,
      );
      final holding = ValuationCaseTemplates.forKind(ValuationCaseKind.holding);

      expect(acquisition.enabledMethods, hasLength(5));
      expect(
        holding.enabledMethods,
        isNot(contains(ValuationMethodKind.discountedCashFlow)),
      );
    });
  });

  group('suggested reference values', () {
    test('are suggestions, never usable facts', () {
      final factors = ValuationCaseTemplates.suggestedFactors(
        template: ValuationCaseTemplates.forKind(ValuationCaseKind.holding),
        assetClass: AssetClass.wohnenMehrfamilien,
        buildingType: ReferenceBuildingType.mehrfamilienhaus,
      );

      expect(factors, isNotEmpty);
      for (final factor in factors) {
        expect(factor.provenance, FactorProvenance.suggestedDefault);
        expect(factor.isUsable, isFalse);
        expect(factor.source, isNotNull);
      }
    });

    test('the asset class proposes a Liegenschaftszinssatz', () {
      final factors = ValuationCaseTemplates.suggestedFactors(
        template: ValuationCaseTemplates.forKind(ValuationCaseKind.holding),
        assetClass: AssetClass.wohnenMehrfamilien,
      );

      final rate = factors.firstWhere(
        (f) => f.id == ValuationFactorIds.liegenschaftszinssatz,
      );
      expect(rate.value, closeTo(0.035, 1e-9));
    });

    test('the building type proposes NHK and Gesamtnutzungsdauer', () {
      final factors = ValuationCaseTemplates.suggestedFactors(
        template: ValuationCaseTemplates.forKind(ValuationCaseKind.holding),
        buildingType: ReferenceBuildingType.mehrfamilienhaus,
      );

      expect(
        factors.map((f) => f.id),
        containsAll(<String>[
          ValuationFactorIds.normalHerstellungskostenPerSqm,
          ValuationFactorIds.totalUsefulLifeYears,
        ]),
      );
    });

    test('proposes nothing for a method the template does not run', () {
      // The disposition template has no Sachwertverfahren, so no NHK.
      final factors = ValuationCaseTemplates.suggestedFactors(
        template: ValuationCaseTemplates.forKind(ValuationCaseKind.disposition),
        buildingType: ReferenceBuildingType.mehrfamilienhaus,
        assetClass: AssetClass.wohnenMehrfamilien,
      );

      expect(
        factors.map((f) => f.id),
        isNot(contains(ValuationFactorIds.normalHerstellungskostenPerSqm)),
      );
    });

    test('proposes nothing without the menu answers', () {
      final factors = ValuationCaseTemplates.suggestedFactors(
        template: ValuationCaseTemplates.forKind(ValuationCaseKind.acquisition),
      );

      expect(factors, isEmpty);
    });

    test('never proposes a region-specific value', () {
      final factors = ValuationCaseTemplates.suggestedFactors(
        template: ValuationCaseTemplates.forKind(ValuationCaseKind.acquisition),
        assetClass: AssetClass.buero,
        buildingType: ReferenceBuildingType.buerogebaeude,
      );

      // Bodenrichtwert and Sachwertfaktor have no offline source worth
      // proposing — guessing them would dress a guess up as reference data.
      expect(
        factors.map((f) => f.id),
        isNot(contains(ValuationFactorIds.landValuePerSqm)),
      );
      expect(
        factors.map((f) => f.id),
        isNot(contains(ValuationFactorIds.sachwertfaktor)),
      );
    });
  });
}
