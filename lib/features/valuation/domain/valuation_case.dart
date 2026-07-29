import 'cash_flow_projection.dart';
import 'investment_metrics.dart';
import 'methods/comparison_approach_method.dart';
import 'methods/cost_approach_de_method.dart';
import 'methods/dcf_method.dart';
import 'methods/direct_capitalization_method.dart';
import 'methods/income_approach_de_method.dart';
import 'reconciliation.dart';
import 'valuation_factor.dart';
import 'valuation_factor_ids.dart';
import 'valuation_method.dart';
import 'valuation_report.dart';

/// What the case is being valued for. Replaces the three separate legacy module
/// services (acquisition / renovation / disposition), which each carried their
/// own inputs, metrics and persistence for what is one valuation subject.
enum ValuationCaseKind {
  acquisition('acquisition'),
  holding('holding'),
  renovation('renovation'),
  disposition('disposition');

  const ValuationCaseKind(this.wireName);

  final String wireName;

  static ValuationCaseKind? fromWire(String? value) {
    for (final kind in ValuationCaseKind.values) {
      if (kind.wireName == value) return kind;
    }
    return null;
  }
}

extension ValuationCaseKindX on ValuationCaseKind {
  String get labelDe => switch (this) {
    ValuationCaseKind.acquisition => 'Ankauf',
    ValuationCaseKind.holding => 'Bestand',
    ValuationCaseKind.renovation => 'Sanierung',
    ValuationCaseKind.disposition => 'Verkauf',
  };
}

/// Lifecycle of a valuation case (guardrail: every workflow entity has explicit
/// status logic): `draft → inReview → approved → archived`, with `draft` and
/// `inReview` also archivable directly and no path back out of `archived`.
///
/// An [approved] case is immutable — edits must create a new version; the
/// Supabase layer enforces the same rule server-side (`AGG-014`), so
/// [canTransitionTo] is an affordance mirror, not the authority.
enum ValuationCaseStatus {
  draft('draft'),
  inReview('in_review'),
  approved('approved'),
  archived('archived');

  const ValuationCaseStatus(this.wireName);

  final String wireName;

  static ValuationCaseStatus? fromWire(String? value) {
    for (final status in ValuationCaseStatus.values) {
      if (status.wireName == value) return status;
    }
    return null;
  }

  bool canTransitionTo(ValuationCaseStatus target) => switch (this) {
    ValuationCaseStatus.draft =>
      target == ValuationCaseStatus.inReview ||
          target == ValuationCaseStatus.archived,
    ValuationCaseStatus.inReview =>
      target == ValuationCaseStatus.draft ||
          target == ValuationCaseStatus.approved ||
          target == ValuationCaseStatus.archived,
    ValuationCaseStatus.approved => target == ValuationCaseStatus.archived,
    ValuationCaseStatus.archived => false,
  };

  bool get isTerminal => this == ValuationCaseStatus.archived;
}

/// The valuation subject: its factors (each with provenance), its comparables
/// and the method configuration to evaluate it with.
class ValuationCase {
  ValuationCase({
    required this.id,
    required this.propertyId,
    required this.title,
    required this.kind,
    required this.factors,
    this.scenarioId,
    this.status = ValuationCaseStatus.draft,
    this.comparables = const [],
    this.dcfTerminal = DcfTerminalMethod.exitCap,
    this.enabledMethods = allMethodKinds,
    this.weightOverrides = const {},
    this.minimumComparables = 3,
  });

  static const Set<ValuationMethodKind> allMethodKinds = {
    ValuationMethodKind.incomeApproachDe,
    ValuationMethodKind.costApproachDe,
    ValuationMethodKind.comparisonApproach,
    ValuationMethodKind.discountedCashFlow,
    ValuationMethodKind.directCapitalization,
  };

  final String id;
  final String propertyId;
  final String? scenarioId;
  final String title;
  final ValuationCaseKind kind;
  final ValuationCaseStatus status;
  final FactorSet factors;
  final List<ComparableSale> comparables;
  final DcfTerminalMethod dcfTerminal;

  /// Which methods to run. Disabling a method is a documented decision; a method
  /// that runs but lacks inputs reports "nicht ermittelbar" instead.
  final Set<ValuationMethodKind> enabledMethods;

  /// Optional appraiser weighting for the Verkehrswert-Abgleich.
  final Map<ValuationMethodKind, double> weightOverrides;

  final int minimumComparables;

  /// Whether factors may still be changed in place.
  bool get isEditable =>
      status == ValuationCaseStatus.draft ||
      status == ValuationCaseStatus.inReview;

  /// Adds or replaces a factor. Throws [StateError] on an approved/archived
  /// case — an approved valuation is a record, not a scratchpad.
  ValuationCase withFactor(ValuationFactor factor) {
    if (!isEditable) {
      throw StateError(
        'Bewertungsfall "$title" ist ${status.name} und kann nicht mehr '
        'geändert werden — neue Version anlegen.',
      );
    }
    return copyWith(factors: factors.withFactor(factor));
  }

  /// Confirms a system suggestion, making it usable by the methods.
  ValuationCase acceptSuggestion(String factorId, {String? note}) {
    final factor = factors[factorId];
    if (factor == null) return this;
    return withFactor(factor.accept(note: note));
  }

  /// The method instances for [enabledMethods], configured from this case.
  List<ValuationMethod> buildMethods() => <ValuationMethod>[
    if (enabledMethods.contains(ValuationMethodKind.incomeApproachDe))
      const IncomeApproachDeMethod(),
    if (enabledMethods.contains(ValuationMethodKind.costApproachDe))
      const CostApproachDeMethod(),
    if (enabledMethods.contains(ValuationMethodKind.comparisonApproach))
      ComparisonApproachMethod(
        comparables: comparables,
        minimumComparables: minimumComparables,
      ),
    if (enabledMethods.contains(ValuationMethodKind.discountedCashFlow))
      DiscountedCashFlowMethod(terminal: dcfTerminal),
    if (enabledMethods.contains(ValuationMethodKind.directCapitalization))
      const DirectCapitalizationMethod(),
  ];

  ValuationCase copyWith({
    String? id,
    String? propertyId,
    String? scenarioId,
    String? title,
    ValuationCaseKind? kind,
    ValuationCaseStatus? status,
    FactorSet? factors,
    List<ComparableSale>? comparables,
    DcfTerminalMethod? dcfTerminal,
    Set<ValuationMethodKind>? enabledMethods,
    Map<ValuationMethodKind, double>? weightOverrides,
    int? minimumComparables,
  }) => ValuationCase(
    id: id ?? this.id,
    propertyId: propertyId ?? this.propertyId,
    scenarioId: scenarioId ?? this.scenarioId,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    factors: factors ?? this.factors,
    comparables: comparables ?? this.comparables,
    dcfTerminal: dcfTerminal ?? this.dcfTerminal,
    enabledMethods: enabledMethods ?? this.enabledMethods,
    weightOverrides: weightOverrides ?? this.weightOverrides,
    minimumComparables: minimumComparables ?? this.minimumComparables,
  );
}

/// Runs every enabled method over a case, reconciles the available results to a
/// Verkehrswert and assembles the assumption ledger.
class ValuationEngine {
  const ValuationEngine({this.reconciler = const ValuationReconciler()});

  final ValuationReconciler reconciler;

  ValuationReport run(ValuationCase valuationCase) {
    final methodResults = <ValuationMethodKind, MethodResult>{
      for (final method in valuationCase.buildMethods())
        method.kind: method.evaluate(valuationCase.factors),
    };

    final opinion = reconciler.reconcile(
      methodResults,
      weightOverrides: valuationCase.weightOverrides,
    );

    return ValuationReport(
      methodResults: methodResults,
      opinion: opinion,
      assumptionLedger: _ledger(methodResults),
      investment: _investmentMetrics(valuationCase),
    );
  }

  /// Every factor any method actually used, once, ordered by factor id so the
  /// audit trail and PDF are deterministic.
  List<ValuationAssumption> _ledger(
    Map<ValuationMethodKind, MethodResult> methodResults,
  ) {
    final byId = <String, ValuationAssumption>{};
    for (final result in methodResults.values) {
      if (result is! MethodValue) continue;
      for (final assumption in result.assumptions) {
        byId.putIfAbsent(assumption.factorId, () => assumption);
      }
    }
    final ledger = byId.values.toList()
      ..sort((a, b) => a.factorId.compareTo(b.factorId));
    return List.unmodifiable(ledger);
  }

  InvestmentMetrics _investmentMetrics(ValuationCase valuationCase) {
    final factors = valuationCase.factors;
    final price = factors.value(ValuationFactorIds.purchasePrice);
    final dcf = dcfValuationFromFactors(
      factors,
      terminal: valuationCase.dcfTerminal,
    );
    if (price == null || dcf == null) return const InvestmentMetrics();

    final flows = unleveredCashFlows(dcf: dcf, price: price);
    if (flows == null) return const InvestmentMetrics();

    final discountRate = factors.value(ValuationFactorIds.discountRate);
    return InvestmentMetrics(
      irr: internalRateOfReturn(cashFlows: flows),
      npvAtDiscountRate:
          discountRate == null
              ? null
              : netPresentValue(cashFlows: flows, rate: discountRate),
      equityMultiple: equityMultiple(
        investedAmount: price,
        distributions: flows.skip(1).toList(growable: false),
      ),
      discountRate: discountRate,
    );
  }
}
