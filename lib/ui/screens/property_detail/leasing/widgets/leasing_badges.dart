/// The one status-badge mapping for the leasing domain (Welle 3).
///
/// `03_design_system.md` requires a single consistent colour/shape mapping per
/// `STM-*` state across all screens rather than per-screen chips. Every Welle-3
/// screen reads its badges from here; nothing re-derives a colour inline.
library;

import 'package:flutter/material.dart';

import '../../../../components/nx_status_badge.dart';
import '../../../../../features/leasing_operations/domain/lease_dto.dart';
import '../../../../../features/leasing_operations/domain/leasing_case_dto.dart';
import '../../../../../features/leasing_operations/domain/unit_dto.dart';

/// STM-003. `vacant`/`occupied` are derived from the effective leases and only
/// `offline` is caller-driven — the colours say the same thing: occupied is the
/// settled state, vacant is the one asking for attention, offline is the one
/// somebody decided.
String unitStatusLabel(UnitStatus status) => switch (status) {
  UnitStatus.vacant => 'Leer',
  UnitStatus.occupied => 'Vermietet',
  UnitStatus.offline => 'Offline',
};

NxBadgeKind unitStatusKind(UnitStatus status) => switch (status) {
  UnitStatus.vacant => NxBadgeKind.warning,
  UnitStatus.occupied => NxBadgeKind.success,
  UnitStatus.offline => NxBadgeKind.error,
};

class UnitStatusBadge extends StatelessWidget {
  const UnitStatusBadge({super.key, required this.status});

  final UnitStatus status;

  @override
  Widget build(BuildContext context) {
    return NxStatusBadge(
      label: unitStatusLabel(status),
      kind: unitStatusKind(status),
    );
  }
}

/// STM-005. The lifecycle reads as one movement: everything between the draft
/// and the signature is in flight (`info`), `active` is the settled state that
/// makes the lease effective, `ended` is a finished fact rather than a problem,
/// and `cancelled` is the one status that says something went wrong.
String leaseStatusLabel(LeaseStatus status) => switch (status) {
  LeaseStatus.draft => 'Entwurf',
  LeaseStatus.reviewed => 'Geprüft',
  LeaseStatus.sent => 'Versendet',
  LeaseStatus.tenantSigned => 'Mieter unterschrieben',
  LeaseStatus.landlordSigned => 'Vermieter unterschrieben',
  LeaseStatus.active => 'Aktiv',
  LeaseStatus.ended => 'Beendet',
  LeaseStatus.cancelled => 'Abgebrochen',
};

NxBadgeKind leaseStatusKind(LeaseStatus status) => switch (status) {
  LeaseStatus.draft => NxBadgeKind.neutral,
  LeaseStatus.reviewed ||
  LeaseStatus.sent ||
  LeaseStatus.tenantSigned ||
  LeaseStatus.landlordSigned => NxBadgeKind.info,
  LeaseStatus.active => NxBadgeKind.success,
  LeaseStatus.ended => NxBadgeKind.neutral,
  LeaseStatus.cancelled => NxBadgeKind.error,
};

class LeaseStatusBadge extends StatelessWidget {
  const LeaseStatusBadge({super.key, required this.status});

  final LeaseStatus status;

  @override
  Widget build(BuildContext context) {
    return NxStatusBadge(
      label: leaseStatusLabel(status),
      kind: leaseStatusKind(status),
    );
  }
}

/// STM-004. Ten stages plus the abort — the colours mark the three things a
/// reader needs at a glance: the case is running (`info`), it reached its goal
/// (`success`), or it died (`error`). `signed` is already `success` because
/// that is the stage at which a lease exists; handover and completion are the
/// remaining formalities.
String leasingCaseStatusLabel(LeasingCaseStatus status) => switch (status) {
  LeasingCaseStatus.inquiry => 'Anfrage',
  LeasingCaseStatus.contact => 'Kontakt',
  LeasingCaseStatus.viewing => 'Besichtigung',
  LeasingCaseStatus.documentsPending => 'Unterlagen offen',
  LeasingCaseStatus.screening => 'Prüfung',
  LeasingCaseStatus.offer => 'Angebot',
  LeasingCaseStatus.contractDraft => 'Vertragsentwurf',
  LeasingCaseStatus.signed => 'Unterschrieben',
  LeasingCaseStatus.handover => 'Übergabe',
  LeasingCaseStatus.completed => 'Abgeschlossen',
  LeasingCaseStatus.cancelled => 'Abgebrochen',
};

NxBadgeKind leasingCaseStatusKind(LeasingCaseStatus status) => switch (status) {
  LeasingCaseStatus.signed ||
  LeasingCaseStatus.handover ||
  LeasingCaseStatus.completed => NxBadgeKind.success,
  LeasingCaseStatus.cancelled => NxBadgeKind.error,
  _ => NxBadgeKind.info,
};

class LeasingCaseStatusBadge extends StatelessWidget {
  const LeasingCaseStatusBadge({super.key, required this.status});

  final LeasingCaseStatus status;

  @override
  Widget build(BuildContext context) {
    return NxStatusBadge(
      label: leasingCaseStatusLabel(status),
      kind: leasingCaseStatusKind(status),
    );
  }
}

String leasingCaseSourceLabel(LeasingCaseSource source) => switch (source) {
  LeasingCaseSource.portal => 'Portal',
  LeasingCaseSource.email => 'E-Mail',
  LeasingCaseSource.phone => 'Telefon',
  LeasingCaseSource.walkIn => 'Vor Ort',
  LeasingCaseSource.referral => 'Empfehlung',
  LeasingCaseSource.other => 'Sonstige',
};

/// The precondition the server checks before the next stage, in the words of
/// the surface the user would have to visit to satisfy it.
String leasingCaseBlockedReasonLabel(LeasingCaseBlockedReason reason) =>
    switch (reason) {
      LeasingCaseBlockedReason.prospectRequired =>
        'Ab der Prüfung braucht der Fall einen benannten Interessenten.',
      LeasingCaseBlockedReason.unitRequired =>
        'Ab dem Angebot braucht der Fall eine Einheit.',
      LeasingCaseBlockedReason.leaseRequired =>
        'Ab „Unterschrieben" braucht der Fall den Vertrag, den er erzeugt hat.',
    };
