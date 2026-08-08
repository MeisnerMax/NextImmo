/// The single status vocabulary of the valuation UI.
///
/// `03_design_system.md` requires one consistent badge mapping per workflow
/// status — not a per-screen chip. Every valuation screen renders lifecycle,
/// provenance and confidence through these helpers, and every badge carries
/// text, so nothing is signalled by colour alone.
library;

import 'package:flutter/material.dart';

import '../../../../../features/valuation/domain/valuation_case.dart';
import '../../../../../features/valuation/domain/valuation_factor.dart';
import '../../../../components/nx_status_badge.dart';

/// Lifecycle of a valuation case (`draft → in_review → approved → archived`).
class ValuationStatusBadge extends StatelessWidget {
  const ValuationStatusBadge({super.key, required this.status});

  final ValuationCaseStatus status;

  static String labelFor(ValuationCaseStatus status) => switch (status) {
    ValuationCaseStatus.draft => 'Entwurf',
    ValuationCaseStatus.inReview => 'In Prüfung',
    ValuationCaseStatus.approved => 'Freigegeben',
    ValuationCaseStatus.archived => 'Archiviert',
  };

  static NxBadgeKind kindFor(ValuationCaseStatus status) => switch (status) {
    ValuationCaseStatus.draft => NxBadgeKind.neutral,
    ValuationCaseStatus.inReview => NxBadgeKind.info,
    ValuationCaseStatus.approved => NxBadgeKind.success,
    ValuationCaseStatus.archived => NxBadgeKind.neutral,
  };

  @override
  Widget build(BuildContext context) =>
      NxStatusBadge(label: labelFor(status), kind: kindFor(status));
}

/// Where a factor's value came from. The unconfirmed suggestion is deliberately
/// a *warning*: it looks like a value but does not count yet, and that is the
/// distinction the whole rewrite turns on.
class FactorProvenanceBadge extends StatelessWidget {
  const FactorProvenanceBadge({super.key, required this.provenance});

  final FactorProvenance provenance;

  static String labelFor(FactorProvenance provenance) => switch (provenance) {
    FactorProvenance.userProvided => 'Eigene Eingabe',
    FactorProvenance.derived => 'Systemberechnet',
    FactorProvenance.suggestedDefault => 'Vorschlag – unbestätigt',
    FactorProvenance.accepted => 'Vorschlag bestätigt',
    FactorProvenance.missing => 'Fehlt',
  };

  static NxBadgeKind kindFor(FactorProvenance provenance) => switch (provenance) {
    FactorProvenance.userProvided => NxBadgeKind.success,
    FactorProvenance.derived => NxBadgeKind.info,
    FactorProvenance.suggestedDefault => NxBadgeKind.warning,
    FactorProvenance.accepted => NxBadgeKind.info,
    FactorProvenance.missing => NxBadgeKind.error,
  };

  @override
  Widget build(BuildContext context) => NxStatusBadge(
    label: labelFor(provenance),
    kind: kindFor(provenance),
  );
}

/// Result confidence, derived from the provenance of the factors a method
/// actually used.
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({super.key, required this.confidence});

  final ConfidenceBand confidence;

  static String labelFor(ConfidenceBand confidence) => switch (confidence) {
    ConfidenceBand.high => 'Konfidenz hoch',
    ConfidenceBand.medium => 'Konfidenz mittel',
    ConfidenceBand.low => 'Konfidenz niedrig',
    ConfidenceBand.unknown => 'Konfidenz unbekannt',
  };

  static NxBadgeKind kindFor(ConfidenceBand confidence) => switch (confidence) {
    ConfidenceBand.high => NxBadgeKind.success,
    ConfidenceBand.medium => NxBadgeKind.info,
    ConfidenceBand.low => NxBadgeKind.warning,
    ConfidenceBand.unknown => NxBadgeKind.neutral,
  };

  @override
  Widget build(BuildContext context) => NxStatusBadge(
    label: labelFor(confidence),
    kind: kindFor(confidence),
  );
}
