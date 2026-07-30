/// What each valuation factor *is*: its label, unit, how it is entered, and
/// which method needs it.
///
/// The methods themselves declare their requirements by asking a [FactorSet]
/// for values — that stays the authority on availability. This catalogue is the
/// other half the UI needs: a stable, ordered description of the input surface,
/// so the entry form can group factors by method and say "4 of 6" without
/// re-deriving the vocabulary from each method's implementation.
///
/// Optional factors are listed too, marked as such: a Sachwert case without
/// Außenanlagen is complete, and a form that demanded them would be wrong.
library;

import 'valuation_factor_ids.dart';
import 'valuation_method.dart';

/// How a factor is typed in — decides the field widget and the formatting.
enum FactorInputKind {
  /// Money, entered in euro.
  money,

  /// A rate stored as a fraction and entered as a percentage (`0.035` ⇄ `3,5`).
  percent,

  /// Whole years.
  years,

  /// Area in m².
  area,

  /// A plain multiplier/factor (Sachwertfaktor, Baupreisindex).
  factor,
}

class ValuationFactorSpec {
  const ValuationFactorSpec({
    required this.id,
    required this.label,
    required this.kind,
    this.unit,
    this.isOptional = false,
    this.hint,
  });

  final String id;
  final String label;
  final FactorInputKind kind;

  /// Display unit; null for [FactorInputKind.percent] and
  /// [FactorInputKind.factor], whose fields carry their own affordance.
  final String? unit;

  /// An optional factor never blocks a method — it only refines the result.
  final bool isOptional;

  /// Short explanation for the field, where the term is not self-evident.
  final String? hint;
}

/// A requirement that can be met in more than one way — the shape several
/// methods actually have. The Bodenwert is the clearest case: entered directly,
/// or derived from Fläche × Bodenrichtwert. Flattening that into "everything is
/// required" would demand inputs the engine never needs; flattening it into
/// "everything is optional" would let the form claim completeness it does not
/// have. Hence the explicit alternative.
class FactorAlternative {
  const FactorAlternative({
    required this.key,
    required this.label,
    required this.options,
  });

  final String key;
  final String label;

  /// Each option is a set of factor ids that together satisfy the requirement.
  final List<List<String>> options;

  bool isSatisfied(bool Function(String factorId) has) =>
      options.any((option) => option.every(has));
}

/// One method's input surface, in the order the form shows it.
class ValuationFactorGroup {
  const ValuationFactorGroup({
    required this.method,
    required this.factors,
    this.alternatives = const <FactorAlternative>[],
    this.note,
  });

  final ValuationMethodKind method;
  final List<ValuationFactorSpec> factors;

  /// Requirements of this method that have more than one input path.
  final List<FactorAlternative> alternatives;

  /// Something the user needs to know about this group as a whole.
  final String? note;

  /// Factors that are needed outright — alternatives are counted separately,
  /// and their members are marked optional so they never appear here.
  List<ValuationFactorSpec> get requiredFactors =>
      factors.where((f) => !f.isOptional).toList(growable: false);

  /// How many of this method's requirements are met, and how many there are —
  /// the "4 von 6" the form shows per group.
  ({int satisfied, int total}) progress(bool Function(String factorId) has) {
    var satisfied = requiredFactors.where((spec) => has(spec.id)).length;
    satisfied += alternatives.where((alt) => alt.isSatisfied(has)).length;
    return (
      satisfied: satisfied,
      total: requiredFactors.length + alternatives.length,
    );
  }

  bool isComplete(bool Function(String factorId) has) {
    final state = progress(has);
    return state.satisfied == state.total;
  }
}

/// The factor groups of the entry form, one per method.
///
/// Deliberately not derived from the method classes: those resolve alternatives
/// at runtime (an explicit Bodenwert *or* Fläche × Bodenrichtwert), and a form
/// has to offer both paths explicitly rather than guess which one the user
/// means.
abstract final class ValuationFactorCatalog {
  static const List<ValuationFactorGroup> groups = <ValuationFactorGroup>[
    ValuationFactorGroup(
      method: ValuationMethodKind.incomeApproachDe,
      note:
          'Bodenwert entweder direkt eintragen oder aus Grundstücksfläche × '
          'Bodenrichtwert ableiten lassen.',
      alternatives: <FactorAlternative>[
        FactorAlternative(
          key: 'bodenwert',
          label: 'Bodenwert',
          options: <List<String>>[
            <String>[ValuationFactorIds.landValue],
            <String>[
              ValuationFactorIds.landAreaSqm,
              ValuationFactorIds.landValuePerSqm,
            ],
          ],
        ),
        FactorAlternative(
          key: 'restnutzungsdauer',
          label: 'Restnutzungsdauer',
          options: <List<String>>[
            <String>[ValuationFactorIds.remainingUsefulLifeYears],
            <String>[
              ValuationFactorIds.totalUsefulLifeYears,
              ValuationFactorIds.buildingAgeYears,
            ],
          ],
        ),
      ],
      factors: <ValuationFactorSpec>[
        ValuationFactorSpec(
          id: ValuationFactorIds.grossRentAnnual,
          label: 'Rohertrag p.a.',
          kind: FactorInputKind.money,
          unit: '€',
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.operatingExpensesAnnual,
          label: 'Bewirtschaftungskosten p.a.',
          kind: FactorInputKind.money,
          unit: '€',
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.landValue,
          label: 'Bodenwert',
          kind: FactorInputKind.money,
          unit: '€',
          isOptional: true,
          hint: 'Alternativ aus Fläche und Bodenrichtwert.',
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.landAreaSqm,
          label: 'Grundstücksfläche',
          kind: FactorInputKind.area,
          unit: 'm²',
          isOptional: true,
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.landValuePerSqm,
          label: 'Bodenrichtwert',
          kind: FactorInputKind.money,
          unit: '€/m²',
          isOptional: true,
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.liegenschaftszinssatz,
          label: 'Liegenschaftszinssatz',
          kind: FactorInputKind.percent,
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.remainingUsefulLifeYears,
          label: 'Restnutzungsdauer',
          kind: FactorInputKind.years,
          unit: 'Jahre',
          isOptional: true,
          hint: 'Alternativ aus Gesamtnutzungsdauer und Alter.',
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.otherValueAdjustment,
          label: 'Besondere objektspezifische Merkmale',
          kind: FactorInputKind.money,
          unit: '€',
          isOptional: true,
        ),
      ],
    ),
    ValuationFactorGroup(
      method: ValuationMethodKind.costApproachDe,
      alternatives: <FactorAlternative>[
        FactorAlternative(
          key: 'bodenwert',
          label: 'Bodenwert',
          options: <List<String>>[
            <String>[ValuationFactorIds.landValue],
            <String>[
              ValuationFactorIds.landAreaSqm,
              ValuationFactorIds.landValuePerSqm,
            ],
          ],
        ),
      ],
      factors: <ValuationFactorSpec>[
        ValuationFactorSpec(
          id: ValuationFactorIds.grossFloorAreaSqm,
          label: 'Bruttogrundfläche (BGF)',
          kind: FactorInputKind.area,
          unit: 'm²',
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.normalHerstellungskostenPerSqm,
          label: 'Normalherstellungskosten',
          kind: FactorInputKind.money,
          unit: '€/m²',
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.constructionPriceIndex,
          label: 'Baupreisindex',
          kind: FactorInputKind.factor,
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.regionalFactor,
          label: 'Regionalfaktor',
          kind: FactorInputKind.factor,
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.buildingAgeYears,
          label: 'Alter des Gebäudes',
          kind: FactorInputKind.years,
          unit: 'Jahre',
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.totalUsefulLifeYears,
          label: 'Gesamtnutzungsdauer',
          kind: FactorInputKind.years,
          unit: 'Jahre',
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.sachwertfaktor,
          label: 'Sachwertfaktor',
          kind: FactorInputKind.factor,
          hint: 'Marktanpassungsfaktor des Gutachterausschusses.',
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.outdoorFacilitiesValue,
          label: 'Außenanlagen',
          kind: FactorInputKind.money,
          unit: '€',
          isOptional: true,
        ),
      ],
    ),
    ValuationFactorGroup(
      method: ValuationMethodKind.comparisonApproach,
      note:
          'Vergleichspreise kommen aus den Vergleichsobjekten des Objekts, '
          'nicht aus diesem Formular.',
      factors: <ValuationFactorSpec>[
        ValuationFactorSpec(
          id: ValuationFactorIds.subjectLivingAreaSqm,
          label: 'Wohn-/Nutzfläche',
          kind: FactorInputKind.area,
          unit: 'm²',
        ),
      ],
    ),
    ValuationFactorGroup(
      method: ValuationMethodKind.discountedCashFlow,
      note:
          'Rohertrag und Bewirtschaftungskosten kommen aus dem '
          'Ertragswertverfahren — hier nur die Prognoseannahmen.',
      alternatives: <FactorAlternative>[
        FactorAlternative(
          key: 'terminal',
          label: 'Terminalwert-Methode',
          options: <List<String>>[
            <String>[ValuationFactorIds.exitCapRate],
            <String>[ValuationFactorIds.terminalGrowthRate],
          ],
        ),
      ],
      factors: <ValuationFactorSpec>[
        ValuationFactorSpec(
          id: ValuationFactorIds.vacancyRate,
          label: 'Mietausfall-/Leerstandsquote',
          kind: FactorInputKind.percent,
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.rentGrowthRate,
          label: 'Mietwachstum p.a.',
          kind: FactorInputKind.percent,
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.expenseGrowthRate,
          label: 'Kostenwachstum p.a.',
          kind: FactorInputKind.percent,
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.holdYears,
          label: 'Betrachtungszeitraum',
          kind: FactorInputKind.years,
          unit: 'Jahre',
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.discountRate,
          label: 'Kalkulationszins',
          kind: FactorInputKind.percent,
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.saleCostRate,
          label: 'Verkaufskostenquote',
          kind: FactorInputKind.percent,
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.exitCapRate,
          label: 'Exit-Cap-Rate',
          kind: FactorInputKind.percent,
          isOptional: true,
          hint: 'Alternativ Terminal-Wachstum (Gordon Growth).',
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.terminalGrowthRate,
          label: 'Terminal-Wachstum',
          kind: FactorInputKind.percent,
          isOptional: true,
        ),
      ],
    ),
    ValuationFactorGroup(
      method: ValuationMethodKind.directCapitalization,
      alternatives: <FactorAlternative>[
        FactorAlternative(
          key: 'reinertrag',
          label: 'Reinertrag',
          options: <List<String>>[
            <String>[ValuationFactorIds.stabilizedNoiAnnual],
            <String>[
              ValuationFactorIds.grossRentAnnual,
              ValuationFactorIds.vacancyRate,
              ValuationFactorIds.operatingExpensesAnnual,
            ],
          ],
        ),
      ],
      factors: <ValuationFactorSpec>[
        ValuationFactorSpec(
          id: ValuationFactorIds.capRate,
          label: 'Kapitalisierungszins',
          kind: FactorInputKind.percent,
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.stabilizedNoiAnnual,
          label: 'Reinertrag p.a.',
          kind: FactorInputKind.money,
          unit: '€',
          isOptional: true,
          hint: 'Sonst aus Rohertrag, Leerstand und Kosten abgeleitet.',
        ),
        ValuationFactorSpec(
          id: ValuationFactorIds.purchasePrice,
          label: 'Kaufpreis',
          kind: FactorInputKind.money,
          unit: '€',
          isOptional: true,
          hint: 'Nur für Kennzahlen (Rendite, Faktor, IRR).',
        ),
      ],
    ),
  ];

  /// Every factor the form knows, deduplicated — a factor may appear in more
  /// than one group (the Rohertrag feeds both the Ertragswert and the DCF).
  static List<ValuationFactorSpec> get allFactors {
    final byId = <String, ValuationFactorSpec>{};
    for (final group in groups) {
      for (final spec in group.factors) {
        byId.putIfAbsent(spec.id, () => spec);
      }
    }
    final all = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(all);
  }

  static ValuationFactorSpec? specFor(String factorId) {
    for (final group in groups) {
      for (final spec in group.factors) {
        if (spec.id == factorId) return spec;
      }
    }
    return null;
  }

  static ValuationFactorGroup? groupFor(ValuationMethodKind method) {
    for (final group in groups) {
      if (group.method == method) return group;
    }
    return null;
  }
}
