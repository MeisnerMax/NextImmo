/// Case-kind templates (Welle 5, AP5) — the "real valuation scenarios".
///
/// A template decides which methods a case starts with and how they are
/// weighted, and it can seed reference values. What it deliberately does not do
/// is *set* anything as fact: every reference value it produces is a
/// [FactorProvenance.suggestedDefault] and stays uncounted until somebody
/// confirms it. A template is a starting point, not an assertion.
///
/// The weights are a proposal too. [ValuationReconciler] renormalizes over the
/// methods that are actually available, so a template can never mis-weight a
/// result — at worst it expresses a preference that the data does not support,
/// and the rationale then says which methods carried the value.
library;

import 'cash_flow_projection.dart';
import 'reference_data.dart';
import 'valuation_case.dart';
import 'valuation_factor.dart';
import 'valuation_factor_ids.dart';
import 'valuation_method.dart';

class ValuationCaseTemplate {
  const ValuationCaseTemplate({
    required this.kind,
    required this.headline,
    required this.description,
    required this.enabledMethods,
    required this.weights,
    this.dcfTerminal = DcfTerminalMethod.exitCap,
  });

  final ValuationCaseKind kind;

  /// Short label for the picker — the user's words, not the enum's.
  final String headline;

  /// What this case kind is for, in one sentence.
  final String description;

  final Set<ValuationMethodKind> enabledMethods;
  final Map<ValuationMethodKind, double> weights;
  final DcfTerminalMethod dcfTerminal;
}

abstract final class ValuationCaseTemplates {
  static const List<ValuationCaseTemplate> all = <ValuationCaseTemplate>[
    ValuationCaseTemplate(
      kind: ValuationCaseKind.acquisition,
      headline: 'Ankauf',
      description:
          'Vollständige Prüfung vor dem Kauf: alle Verfahren, Investment- und '
          'Renditekennzahlen.',
      enabledMethods: <ValuationMethodKind>{
        ValuationMethodKind.comparisonApproach,
        ValuationMethodKind.incomeApproachDe,
        ValuationMethodKind.discountedCashFlow,
        ValuationMethodKind.costApproachDe,
        ValuationMethodKind.directCapitalization,
      },
      weights: <ValuationMethodKind, double>{
        ValuationMethodKind.comparisonApproach: 0.35,
        ValuationMethodKind.incomeApproachDe: 0.30,
        ValuationMethodKind.discountedCashFlow: 0.20,
        ValuationMethodKind.costApproachDe: 0.10,
        ValuationMethodKind.directCapitalization: 0.05,
      },
    ),
    ValuationCaseTemplate(
      kind: ValuationCaseKind.holding,
      headline: 'Bestand',
      description:
          'Turnusmäßige Bewertung im Bestand — Ertrags- und Sachwert, ohne '
          'Exit-Annahmen.',
      enabledMethods: <ValuationMethodKind>{
        ValuationMethodKind.incomeApproachDe,
        ValuationMethodKind.costApproachDe,
        ValuationMethodKind.directCapitalization,
      },
      weights: <ValuationMethodKind, double>{
        ValuationMethodKind.incomeApproachDe: 0.55,
        ValuationMethodKind.costApproachDe: 0.25,
        ValuationMethodKind.directCapitalization: 0.20,
      },
    ),
    ValuationCaseTemplate(
      kind: ValuationCaseKind.renovation,
      headline: 'Sanierung',
      description:
          'Wertwirkung einer Maßnahme: Substanz über den Sachwert, Wirkung '
          'über Ertragswert und Cashflow.',
      enabledMethods: <ValuationMethodKind>{
        ValuationMethodKind.incomeApproachDe,
        ValuationMethodKind.costApproachDe,
        ValuationMethodKind.discountedCashFlow,
      },
      weights: <ValuationMethodKind, double>{
        ValuationMethodKind.incomeApproachDe: 0.40,
        ValuationMethodKind.costApproachDe: 0.35,
        ValuationMethodKind.discountedCashFlow: 0.25,
      },
    ),
    ValuationCaseTemplate(
      kind: ValuationCaseKind.disposition,
      headline: 'Verkauf',
      description:
          'Preisfindung und Exit: Vergleichspreise, Cashflow bis zum Verkauf, '
          'Schnellkennzahlen.',
      enabledMethods: <ValuationMethodKind>{
        ValuationMethodKind.comparisonApproach,
        ValuationMethodKind.discountedCashFlow,
        ValuationMethodKind.directCapitalization,
      },
      weights: <ValuationMethodKind, double>{
        ValuationMethodKind.comparisonApproach: 0.45,
        ValuationMethodKind.discountedCashFlow: 0.35,
        ValuationMethodKind.directCapitalization: 0.20,
      },
    ),
  ];

  static ValuationCaseTemplate forKind(ValuationCaseKind kind) =>
      all.firstWhere((template) => template.kind == kind);

  /// Reference values the wizard can offer once the user has said what kind of
  /// object this is. Everything here is a **suggestion**: it carries its source
  /// and does not count until confirmed, which is why a template may seed a
  /// factor at all.
  ///
  /// Only values that follow from the two menu answers are produced — the
  /// Liegenschaftszinssatz from the asset class, Gesamtnutzungsdauer and
  /// Normalherstellungskosten from the building type. Anything region-specific
  /// (Bodenrichtwert, Sachwertfaktor) is left out on purpose: without an
  /// external source there is nothing to propose that would not be a guess
  /// dressed up as reference data.
  static List<ValuationFactor> suggestedFactors({
    required ValuationCaseTemplate template,
    AssetClass? assetClass,
    ReferenceBuildingType? buildingType,
    BuildingQualityStandard standard = BuildingQualityStandard.mittel,
    ReferenceDataProvider reference = const SeedReferenceDataProvider(),
  }) {
    final factors = <ValuationFactor>[];

    if (assetClass != null &&
        template.enabledMethods.contains(
          ValuationMethodKind.incomeApproachDe,
        )) {
      final range = reference.liegenschaftszinssatz(assetClass);
      if (range != null) {
        factors.add(
          ValuationFactor.suggested(
            id: ValuationFactorIds.liegenschaftszinssatz,
            label: 'Liegenschaftszinssatz',
            value: range.typical,
            source: range.source,
            confidence: range.confidence,
          ),
        );
      }
    }

    if (buildingType != null &&
        template.enabledMethods.contains(ValuationMethodKind.costApproachDe)) {
      final cost = reference.buildingCost(buildingType, standard);
      if (cost != null) {
        factors.add(
          ValuationFactor.suggested(
            id: ValuationFactorIds.normalHerstellungskostenPerSqm,
            label: 'Normalherstellungskosten',
            value: cost.normalHerstellungskostenPerSqm,
            unit: '€/m²',
            source: cost.source,
            confidence: cost.confidence,
          ),
        );
        factors.add(
          ValuationFactor.suggested(
            id: ValuationFactorIds.totalUsefulLifeYears,
            label: 'Gesamtnutzungsdauer',
            value: cost.gesamtnutzungsdauerYears.toDouble(),
            unit: 'Jahre',
            source: cost.source,
            confidence: cost.confidence,
          ),
        );
      }
    }

    return List<ValuationFactor>.unmodifiable(factors);
  }
}
