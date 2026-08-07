import '../valuation_factor.dart';
import '../valuation_factor_ids.dart';
import '../valuation_math.dart';
import '../valuation_method.dart';
import 'land_value.dart';

/// Ertragswertverfahren (ImmoWertV 2021 §§27–34), allgemeines Verfahren:
///
///   Reinertrag        = Rohertrag − Bewirtschaftungskosten
///   Bodenwertverzinsung = Bodenwert × Liegenschaftszinssatz
///   Gebäudereinertrag = Reinertrag − Bodenwertverzinsung
///   Gebäudeertragswert = Gebäudereinertrag × Vervielfältiger(LZ, RND)
///   Ertragswert       = Bodenwert + Gebäudeertragswert (± boM)
///
/// The Restnutzungsdauer is taken directly when supplied, otherwise derived from
/// Gesamtnutzungsdauer − Alter. Any required factor that is absent or an
/// unconfirmed suggestion makes the method return [MethodUnavailable].
class IncomeApproachDeMethod implements ValuationMethod {
  const IncomeApproachDeMethod();

  @override
  ValuationMethodKind get kind => ValuationMethodKind.incomeApproachDe;

  @override
  String get name => 'Ertragswertverfahren';

  @override
  MethodResult evaluate(FactorSet factors) {
    final used = <ValuationFactor>[];
    final missing = <MissingFactor>[];

    // Reinertrag: explicit, else Rohertrag − Bewirtschaftungskosten.
    double? reinertrag;
    if (factors.has(ValuationFactorIds.stabilizedNoiAnnual)) {
      reinertrag = factors.value(ValuationFactorIds.stabilizedNoiAnnual);
      used.add(factors[ValuationFactorIds.stabilizedNoiAnnual]!);
    } else {
      const componentIds = [
        ValuationFactorIds.grossRentAnnual,
        ValuationFactorIds.operatingExpensesAnnual,
      ];
      final componentMissing = factors.missingAmong(componentIds);
      if (componentMissing.isEmpty) {
        reinertrag =
            factors.value(ValuationFactorIds.grossRentAnnual)! -
            factors.value(ValuationFactorIds.operatingExpensesAnnual)!;
        used.addAll(componentIds.map((id) => factors[id]!));
      } else {
        missing.add(
          const MissingFactor(
            factorId: ValuationFactorIds.stabilizedNoiAnnual,
            label: 'Reinertrag p.a.',
            reason: MissingFactorReason.notEntered,
            message:
                'Reinertrag p.a. fehlt (direkt oder aus Rohertrag und '
                'Bewirtschaftungskosten).',
          ),
        );
      }
    }

    final land = resolveLandValue(factors);
    used.addAll(land.used);
    missing.addAll(land.missing);

    missing.addAll(
      factors.missingAmong([ValuationFactorIds.liegenschaftszinssatz]),
    );

    // Restnutzungsdauer: explicit, else Gesamtnutzungsdauer − Alter.
    int? rnd;
    if (factors.has(ValuationFactorIds.remainingUsefulLifeYears)) {
      rnd = factors.value(ValuationFactorIds.remainingUsefulLifeYears)!.round();
      used.add(factors[ValuationFactorIds.remainingUsefulLifeYears]!);
    } else {
      const componentIds = [
        ValuationFactorIds.totalUsefulLifeYears,
        ValuationFactorIds.buildingAgeYears,
      ];
      final componentMissing = factors.missingAmong(componentIds);
      if (componentMissing.isEmpty) {
        rnd = remainingUsefulLife(
          totalUsefulLife:
              factors.value(ValuationFactorIds.totalUsefulLifeYears)!.round(),
          age: factors.value(ValuationFactorIds.buildingAgeYears)!.round(),
        );
        used.addAll(componentIds.map((id) => factors[id]!));
      }
      if (rnd == null) {
        missing.add(
          const MissingFactor(
            factorId: ValuationFactorIds.remainingUsefulLifeYears,
            label: 'Restnutzungsdauer',
            reason: MissingFactorReason.notEntered,
            message:
                'Restnutzungsdauer fehlt (direkt oder aus Gesamtnutzungsdauer '
                'und Alter).',
          ),
        );
      }
    }

    if (missing.isNotEmpty) {
      return MethodUnavailable(missingFactors: missing);
    }

    final liegenschaftszins = factors.value(
      ValuationFactorIds.liegenschaftszinssatz,
    )!;
    used.add(factors[ValuationFactorIds.liegenschaftszinssatz]!);

    final bodenwert = land.value!;
    final bodenwertverzinsung = bodenwert * liegenschaftszins;
    final gebaeudereinertrag = reinertrag! - bodenwertverzinsung;

    final vervielfaeltiger = presentValueAnnuityFactor(
      rate: liegenschaftszins,
      years: rnd!,
    );
    if (vervielfaeltiger == null) {
      return const MethodUnavailable(
        missingFactors: [],
        reasons: [
          'Vervielfältiger nicht berechenbar (Restnutzungsdauer ≤ 0 oder '
              'unzulässiger Liegenschaftszinssatz).',
        ],
      );
    }

    final gebaeudeertragswert = gebaeudereinertrag * vervielfaeltiger;
    var ertragswert = bodenwert + gebaeudeertragswert;

    final breakdown = <MethodBreakdownLine>[
      MethodBreakdownLine(label: 'Reinertrag p.a.', amount: reinertrag, unit: '€'),
      MethodBreakdownLine(
        label: 'Bodenwert',
        amount: bodenwert,
        unit: '€',
        formula:
            land.derived ? 'Grundstücksfläche × Bodenrichtwert' : null,
      ),
      MethodBreakdownLine(
        label: 'Bodenwertverzinsung',
        amount: bodenwertverzinsung,
        unit: '€',
        formula: 'Bodenwert × Liegenschaftszinssatz',
      ),
      MethodBreakdownLine(
        label: 'Gebäudereinertrag',
        amount: gebaeudereinertrag,
        unit: '€',
        formula: 'Reinertrag − Bodenwertverzinsung',
      ),
      MethodBreakdownLine(
        label: 'Vervielfältiger',
        amount: vervielfaeltiger,
        formula: 'V = (qⁿ − 1) / (qⁿ · (q − 1)), n = $rnd Jahre',
      ),
      MethodBreakdownLine(
        label: 'Gebäudeertragswert',
        amount: gebaeudeertragswert,
        unit: '€',
        formula: 'Gebäudereinertrag × Vervielfältiger',
      ),
    ];

    final boM = factors.value(ValuationFactorIds.otherValueAdjustment);
    if (boM != null) {
      ertragswert += boM;
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
        label: 'Ertragswert',
        amount: ertragswert,
        unit: '€',
        formula: 'Bodenwert + Gebäudeertragswert${boM != null ? ' ± boM' : ''}',
      ),
    );

    return MethodValue(
      amount: ertragswert,
      confidence: combineConfidence(used),
      breakdown: breakdown,
      assumptions:
          used.map(ValuationAssumption.fromFactor).toList(growable: false),
    );
  }
}
