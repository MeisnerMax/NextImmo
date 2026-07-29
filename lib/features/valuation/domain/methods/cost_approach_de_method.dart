import '../valuation_factor.dart';
import '../valuation_factor_ids.dart';
import '../valuation_math.dart';
import '../valuation_method.dart';
import 'land_value.dart';

/// Sachwertverfahren (ImmoWertV 2021 §§35–39):
///
///   Herstellungskosten = NHK × BGF × Baupreisindex × Regionalfaktor
///   Gebäudesachwert    = Herstellungskosten × (1 − Alter / GND)
///   vorläufiger Sachwert = Bodenwert + Gebäudesachwert + Außenanlagen
///   Sachwert           = vorläufiger Sachwert × Sachwertfaktor (± boM)
///
/// Außenanlagen and boM are optional; every other factor is required and an
/// absent or unconfirmed one yields [MethodUnavailable] instead of a number.
class CostApproachDeMethod implements ValuationMethod {
  const CostApproachDeMethod();

  @override
  ValuationMethodKind get kind => ValuationMethodKind.costApproachDe;

  @override
  String get name => 'Sachwertverfahren';

  @override
  MethodResult evaluate(FactorSet factors) {
    const requiredIds = [
      ValuationFactorIds.grossFloorAreaSqm,
      ValuationFactorIds.normalHerstellungskostenPerSqm,
      ValuationFactorIds.constructionPriceIndex,
      ValuationFactorIds.regionalFactor,
      ValuationFactorIds.buildingAgeYears,
      ValuationFactorIds.totalUsefulLifeYears,
      ValuationFactorIds.sachwertfaktor,
    ];

    final missing = factors.missingAmong(requiredIds);
    final land = resolveLandValue(factors);
    missing.addAll(land.missing);
    if (missing.isNotEmpty) {
      return MethodUnavailable(missingFactors: missing);
    }

    final used = <ValuationFactor>[
      ...land.used,
      ...requiredIds.map((id) => factors[id]!),
    ];

    final bgf = factors.value(ValuationFactorIds.grossFloorAreaSqm)!;
    final nhk = factors.value(
      ValuationFactorIds.normalHerstellungskostenPerSqm,
    )!;
    final index = factors.value(ValuationFactorIds.constructionPriceIndex)!;
    final regional = factors.value(ValuationFactorIds.regionalFactor)!;
    final age = factors.value(ValuationFactorIds.buildingAgeYears)!.round();
    final gnd = factors.value(ValuationFactorIds.totalUsefulLifeYears)!.round();
    final swf = factors.value(ValuationFactorIds.sachwertfaktor)!;

    final remainingShare = linearRemainingValueFactor(
      age: age,
      totalUsefulLife: gnd,
    );
    if (remainingShare == null) {
      return const MethodUnavailable(
        missingFactors: [],
        reasons: [
          'Alterswertminderung nicht berechenbar (Alter oder '
              'Gesamtnutzungsdauer unzulässig).',
        ],
      );
    }

    final herstellungskosten = nhk * bgf * index * regional;
    final gebaeudesachwert = herstellungskosten * remainingShare;
    final bodenwert = land.value!;

    final outdoor = factors.value(ValuationFactorIds.outdoorFacilitiesValue);
    if (outdoor != null) {
      used.add(factors[ValuationFactorIds.outdoorFacilitiesValue]!);
    }

    final vorlaeufigerSachwert =
        bodenwert + gebaeudesachwert + (outdoor ?? 0);
    var sachwert = vorlaeufigerSachwert * swf;

    final breakdown = <MethodBreakdownLine>[
      MethodBreakdownLine(
        label: 'Herstellungskosten',
        amount: herstellungskosten,
        unit: '€',
        formula: 'NHK × BGF × Baupreisindex × Regionalfaktor',
      ),
      MethodBreakdownLine(
        label: 'Alterswertminderung (Restwertanteil)',
        amount: remainingShare,
        formula: '1 − Alter / Gesamtnutzungsdauer ($age / $gnd Jahre)',
      ),
      MethodBreakdownLine(
        label: 'Gebäudesachwert',
        amount: gebaeudesachwert,
        unit: '€',
        formula: 'Herstellungskosten × Restwertanteil',
      ),
      MethodBreakdownLine(
        label: 'Bodenwert',
        amount: bodenwert,
        unit: '€',
        formula: land.derived ? 'Grundstücksfläche × Bodenrichtwert' : null,
      ),
      if (outdoor != null)
        MethodBreakdownLine(
          label: 'Außenanlagen',
          amount: outdoor,
          unit: '€',
        ),
      MethodBreakdownLine(
        label: 'Vorläufiger Sachwert',
        amount: vorlaeufigerSachwert,
        unit: '€',
        formula: 'Bodenwert + Gebäudesachwert + Außenanlagen',
      ),
    ];

    final boM = factors.value(ValuationFactorIds.otherValueAdjustment);
    if (boM != null) {
      sachwert += boM;
      used.add(factors[ValuationFactorIds.otherValueAdjustment]!);
      breakdown.add(
        MethodBreakdownLine(
          label: 'Besondere objektspezifische Grundstücksmerkmale',
          amount: boM,
          unit: '€',
        ),
      );
    }

    breakdown.add(
      MethodBreakdownLine(
        label: 'Sachwert',
        amount: sachwert,
        unit: '€',
        formula:
            'Vorläufiger Sachwert × Sachwertfaktor${boM != null ? ' ± boM' : ''}',
      ),
    );

    return MethodValue(
      amount: sachwert,
      confidence: combineConfidence(used),
      breakdown: breakdown,
      assumptions:
          used.map(ValuationAssumption.fromFactor).toList(growable: false),
    );
  }
}
