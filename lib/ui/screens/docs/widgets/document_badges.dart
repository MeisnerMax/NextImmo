import 'package:flutter/material.dart';

import '../../../../features/documents_compliance/domain/document_dto.dart';
import '../../../components/nx_status_badge.dart';

/// The single status vocabulary for the documents_compliance domain
/// (`03_design_system.md`: one badge mapping per status enum, never a
/// per-screen chip).
///
/// Shared on purpose — this is the `DUP-007` foundation. The property-scoped
/// documents screen (SCR-020), the global documents workplace (SCR-051) and the
/// compliance dashboard (SCR-052) all render STM-008 document status,
/// verification status and the derived requirement state through these
/// helpers, so a state can never mean two different things in two places.
///
/// Severity mapping follows the design system: semantic colour is reserved for
/// states that actually demand attention, and every badge pairs colour with a
/// text label so nothing is signalled by colour alone.

String documentStatusLabel(DocumentStatus status) {
  return switch (status) {
    DocumentStatus.uploaded => 'Hochgeladen',
    DocumentStatus.processing => 'In Verarbeitung',
    DocumentStatus.available => 'Verfügbar',
    DocumentStatus.verified => 'Verifiziert',
    DocumentStatus.superseded => 'Ersetzt',
    DocumentStatus.archived => 'Archiviert',
    DocumentStatus.rejected => 'Abgelehnt',
  };
}

NxBadgeKind documentStatusKind(DocumentStatus status) {
  return switch (status) {
    DocumentStatus.verified => NxBadgeKind.success,
    DocumentStatus.available => NxBadgeKind.info,
    DocumentStatus.uploaded || DocumentStatus.processing => NxBadgeKind.warning,
    DocumentStatus.rejected => NxBadgeKind.error,
    DocumentStatus.superseded || DocumentStatus.archived => NxBadgeKind.neutral,
  };
}

String documentVerificationLabel(DocumentVerificationStatus status) {
  return switch (status) {
    DocumentVerificationStatus.pending => 'Prüfung offen',
    DocumentVerificationStatus.verified => 'Verifiziert',
    DocumentVerificationStatus.rejected => 'Abgelehnt',
  };
}

NxBadgeKind documentVerificationKind(DocumentVerificationStatus status) {
  return switch (status) {
    DocumentVerificationStatus.pending => NxBadgeKind.warning,
    DocumentVerificationStatus.verified => NxBadgeKind.success,
    DocumentVerificationStatus.rejected => NxBadgeKind.error,
  };
}

/// The controlled `EntityRef` vocabulary (DEBT-006). Used by the workspace-wide
/// workplace (SCR-051) for its level filter and for naming a document's links,
/// so the registry reads the same everywhere and no screen ever prints the raw
/// wire name.
String documentEntityTypeLabel(DocumentLinkEntityType entityType) {
  return switch (entityType) {
    DocumentLinkEntityType.workspace => 'Arbeitsbereich',
    DocumentLinkEntityType.property => 'Objekt',
    DocumentLinkEntityType.portfolio => 'Portfolio',
    DocumentLinkEntityType.unit => 'Einheit',
    DocumentLinkEntityType.lease => 'Mietvertrag',
    DocumentLinkEntityType.party => 'Partei',
    DocumentLinkEntityType.maintenanceTicket => 'Instandhaltung',
    DocumentLinkEntityType.capexProject => 'CapEx-Projekt',
    DocumentLinkEntityType.scenario => 'Szenario',
    DocumentLinkEntityType.task => 'Aufgabe',
  };
}

String documentRequirementLabel(DocumentRequirementState state) {
  return switch (state) {
    DocumentRequirementState.satisfied => 'Erfüllt',
    DocumentRequirementState.pendingVerification => 'Prüfung offen',
    DocumentRequirementState.pendingContent => 'Upload offen',
    DocumentRequirementState.expiring => 'Läuft ab',
    DocumentRequirementState.expired => 'Abgelaufen',
    DocumentRequirementState.rejected => 'Abgelehnt',
    DocumentRequirementState.requested => 'Angefordert',
    DocumentRequirementState.waived => 'Nicht relevant',
    DocumentRequirementState.missing => 'Fehlt',
  };
}

NxBadgeKind documentRequirementKind(DocumentRequirementState state) {
  return switch (state) {
    DocumentRequirementState.satisfied => NxBadgeKind.success,
    DocumentRequirementState.expiring ||
    DocumentRequirementState.pendingVerification ||
    DocumentRequirementState.pendingContent ||
    DocumentRequirementState.requested => NxBadgeKind.warning,
    DocumentRequirementState.expired ||
    DocumentRequirementState.rejected ||
    DocumentRequirementState.missing => NxBadgeKind.error,
    DocumentRequirementState.waived => NxBadgeKind.neutral,
  };
}

class DocumentStatusBadge extends StatelessWidget {
  const DocumentStatusBadge({super.key, required this.status});

  final DocumentStatus status;

  @override
  Widget build(BuildContext context) {
    return NxStatusBadge(
      label: documentStatusLabel(status),
      kind: documentStatusKind(status),
    );
  }
}

class DocumentVerificationBadge extends StatelessWidget {
  const DocumentVerificationBadge({super.key, required this.status});

  final DocumentVerificationStatus status;

  @override
  Widget build(BuildContext context) {
    return NxStatusBadge(
      label: documentVerificationLabel(status),
      kind: documentVerificationKind(status),
    );
  }
}

/// The derived `DUP-011` projection state. `isMandatory` is surfaced in the
/// label rather than by colour, because an optional missing document is not an
/// alarm — the same state means different things for different rules.
class DocumentRequirementBadge extends StatelessWidget {
  const DocumentRequirementBadge({
    super.key,
    required this.state,
    this.isMandatory = true,
  });

  final DocumentRequirementState state;
  final bool isMandatory;

  @override
  Widget build(BuildContext context) {
    final label = documentRequirementLabel(state);
    return NxStatusBadge(
      label: isMandatory ? label : '$label (optional)',
      kind:
          isMandatory
              ? documentRequirementKind(state)
              : NxBadgeKind.neutral,
    );
  }
}
