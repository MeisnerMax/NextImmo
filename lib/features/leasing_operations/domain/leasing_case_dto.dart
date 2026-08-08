/// Domain DTOs for the LeasingCase aggregate (P2-D05, STM-004).
///
/// Replaces the UI-only status strings the legacy screens carried (part of
/// FTR-024) with a versioned, audited, server-validated pipeline.
library;

/// STM-004, in order. The chain moves exactly one step forward at a time, or
/// aborts to [cancelled] from any non-terminal state.
///
/// There are deliberately **no backward transitions** — STM-004 lists none. A
/// failed screening or a withdrawn offer is a cancellation with a reason, and
/// the next attempt is a new case. That is also the honest data model: a
/// reopened case would silently overwrite the record of why the first attempt
/// died. The pre-cancellation stage is preserved in the audit trail.
enum LeasingCaseStatus {
  inquiry,
  contact,
  viewing,
  documentsPending,
  screening,
  offer,
  contractDraft,
  signed,
  handover,
  completed,
  cancelled;

  /// Position in the pipeline; [cancelled] is off the chain and ranks 0.
  /// Mirrors `private.leasing_case_stage_rank`.
  int get stageRank => switch (this) {
    LeasingCaseStatus.inquiry => 1,
    LeasingCaseStatus.contact => 2,
    LeasingCaseStatus.viewing => 3,
    LeasingCaseStatus.documentsPending => 4,
    LeasingCaseStatus.screening => 5,
    LeasingCaseStatus.offer => 6,
    LeasingCaseStatus.contractDraft => 7,
    LeasingCaseStatus.signed => 8,
    LeasingCaseStatus.handover => 9,
    LeasingCaseStatus.completed => 10,
    LeasingCaseStatus.cancelled => 0,
  };

  bool get isTerminal =>
      this == LeasingCaseStatus.completed || this == LeasingCaseStatus.cancelled;

  /// Local mirror of `private.leasing_case_transition_allowed`, for disabling
  /// affordances before a round trip. The server remains the authority — this
  /// never decides, it only avoids offering a move that will be refused.
  bool canTransitionTo(LeasingCaseStatus target) {
    if (isTerminal) {
      return false;
    }
    if (target == LeasingCaseStatus.cancelled) {
      return true;
    }
    return target.stageRank == stageRank + 1;
  }

  /// The single lawful forward step, or null at the end of the chain.
  LeasingCaseStatus? get nextStage {
    if (isTerminal) {
      return null;
    }
    return LeasingCaseStatus.values
        .where((status) => status.stageRank == stageRank + 1)
        .firstOrNull;
  }
}

/// Where the enquiry came from.
enum LeasingCaseSource { portal, email, phone, walkIn, referral, other }

/// Compact projection used by the pipeline board.
class LeasingCaseSummaryDto {
  const LeasingCaseSummaryDto({
    required this.id,
    required this.workspaceId,
    required this.propertyId,
    required this.caseName,
    required this.status,
    required this.source,
    required this.openedAt,
    required this.version,
    this.unitId,
    this.prospectPartyId,
    this.leaseId,
  });

  final String id;
  final String workspaceId;
  final String propertyId;
  final String caseName;
  final LeasingCaseStatus status;
  final LeasingCaseSource source;
  final DateTime openedAt;
  final int version;

  /// Null while an enquiry predates the choice of unit. Required from
  /// [LeasingCaseStatus.offer] onward.
  final String? unitId;

  /// The interested party. Required from [LeasingCaseStatus.screening] onward.
  ///
  /// Unlike a lease tenant, a prospect is **not** required to hold the `tenant`
  /// party role: there is no `prospect` role type, and stamping an enquiry as a
  /// tenant would assert a relationship that does not exist yet. The role
  /// attaches when a lease names the party.
  final String? prospectPartyId;

  /// The lease this case produced. Required from [LeasingCaseStatus.signed].
  final String? leaseId;

  bool get isOpen => !status.isTerminal;
}

class LeasingCaseDto extends LeasingCaseSummaryDto {
  const LeasingCaseDto({
    required super.id,
    required super.workspaceId,
    required super.propertyId,
    required super.caseName,
    required super.status,
    required super.source,
    required super.openedAt,
    required super.version,
    super.unitId,
    super.prospectPartyId,
    super.leaseId,
    this.completedAt,
    this.cancelledAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  /// Exactly the terminal status carries its timestamp.
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;

  /// Which precondition, if any, blocks the next forward step. Mirrors the
  /// server's checks so a UI can explain the block instead of only reporting a
  /// rejection. Returns null when the next step is unobstructed or absent.
  LeasingCaseBlockedReason? get blockedReason {
    final next = status.nextStage;
    if (next == null) {
      return null;
    }
    if (next.stageRank >= LeasingCaseStatus.screening.stageRank &&
        prospectPartyId == null) {
      return LeasingCaseBlockedReason.prospectRequired;
    }
    if (next.stageRank >= LeasingCaseStatus.offer.stageRank && unitId == null) {
      return LeasingCaseBlockedReason.unitRequired;
    }
    if (next.stageRank >= LeasingCaseStatus.signed.stageRank && leaseId == null) {
      return LeasingCaseBlockedReason.leaseRequired;
    }
    return null;
  }

  LeasingCaseSummaryDto toSummary() => LeasingCaseSummaryDto(
    id: id,
    workspaceId: workspaceId,
    propertyId: propertyId,
    caseName: caseName,
    status: status,
    source: source,
    openedAt: openedAt,
    version: version,
    unitId: unitId,
    prospectPartyId: prospectPartyId,
    leaseId: leaseId,
  );
}

/// Why the next pipeline step is not currently available.
enum LeasingCaseBlockedReason { prospectRequired, unitRequired, leaseRequired }

/// Input for creating a case. A new case always starts
/// [LeasingCaseStatus.inquiry]; advancing is a separate audited transition.
class LeasingCaseDraft {
  const LeasingCaseDraft({
    required this.propertyId,
    required this.caseName,
    this.unitId,
    this.prospectPartyId,
    this.source = LeasingCaseSource.other,
    this.notes,
  });

  final String propertyId;
  final String caseName;
  final String? unitId;
  final String? prospectPartyId;
  final LeasingCaseSource source;
  final String? notes;
}

/// Attribute changes while a case is still open. The server refuses this once
/// the case is completed or cancelled — closed cases are history, not records
/// to be tidied up afterwards.
///
/// [unitId] and [prospectPartyId] are editable because an early enquiry
/// routinely changes the unit it is about and the prospect is often identified
/// only after first contact. They cannot be cleared back to null once a stage
/// requires them; passing null leaves the current value untouched rather than
/// walking the row into a state its own constraint forbids.
class LeasingCaseUpdateDto {
  const LeasingCaseUpdateDto({
    this.caseName,
    this.unitId,
    this.prospectPartyId,
    this.source,
    this.notes,
  });

  final String? caseName;
  final String? unitId;
  final String? prospectPartyId;
  final LeasingCaseSource? source;
  final String? notes;
}
