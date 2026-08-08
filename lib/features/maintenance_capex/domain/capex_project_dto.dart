/// Domain DTOs for the CapExProject aggregate (P2-D06, DOM-007, STM-007,
/// AGG-009).
///
/// Unlike the `leasing_operations` aggregates this migrates real local data —
/// see `legacy_sqlite_maintenance_capex_repository_adapter.dart` for how the
/// pre-existing `renovation_projects` SQLite table (German free-text status,
/// no party FK) is projected into this shape.
library;

/// STM-007, exactly as `private.capex_project_status_transition_allowed`
/// implements it: strictly linear, no back-edges and no abort/cancel state at
/// all (unlike [MaintenanceTicketStatus] or the leasing aggregates).
enum CapexProjectStatus {
  idea,
  planned,
  quoteRequested,
  approved,
  inProgress,
  completed,
  invoiced,
  archived;

  bool get isTerminal => this == CapexProjectStatus.archived;

  /// The single lawful forward step, or null once terminal.
  CapexProjectStatus? get nextStatus => switch (this) {
    CapexProjectStatus.idea => CapexProjectStatus.planned,
    CapexProjectStatus.planned => CapexProjectStatus.quoteRequested,
    CapexProjectStatus.quoteRequested => CapexProjectStatus.approved,
    CapexProjectStatus.approved => CapexProjectStatus.inProgress,
    CapexProjectStatus.inProgress => CapexProjectStatus.completed,
    CapexProjectStatus.completed => CapexProjectStatus.invoiced,
    CapexProjectStatus.invoiced => CapexProjectStatus.archived,
    CapexProjectStatus.archived => null,
  };

  /// Local mirror of `private.capex_project_status_transition_allowed`, for
  /// offering only the move the server will accept. The server remains the
  /// authority — this never decides, it only avoids proposing a refused step.
  bool canTransitionTo(CapexProjectStatus target) => target == nextStatus;

  /// Entering [approved] requires the separate `capex.approve` permission
  /// server-side (`transition_capex_project_status`), unlike every other
  /// target which only requires `capex.manage`.
  bool get requiresApprovalPermission => this == CapexProjectStatus.approved;
}

/// Compact projection used by list results.
///
/// The list/read RPCs (`public.capex_projects`) return the identical full
/// snapshot used for a single read — there is no lighter server-side
/// projection for this aggregate. The Summary/Full split is kept anyway, for
/// consistency with every other aggregate contract in this codebase, and
/// built by discarding fields client-side ([CapexProjectDto.toSummary]).
class CapexProjectSummaryDto {
  const CapexProjectSummaryDto({
    required this.id,
    required this.workspaceId,
    required this.propertyId,
    required this.projectCode,
    required this.status,
    required this.version,
    this.currencyCode,
    this.budgetAmount,
    this.forecastAmount,
    this.actualAmount,
    this.plannedEndDate,
    this.contractorPartyId,
  });

  final String id;
  final String workspaceId;
  final String propertyId;
  final String projectCode;
  final CapexProjectStatus status;
  final int version;

  /// DEC-011: present whenever a money amount is.
  final String? currencyCode;
  final double? budgetAmount;
  final double? forecastAmount;
  final double? actualAmount;
  final DateTime? plannedEndDate;

  /// The contractor is a Party role (AGG-005 / P2-D02), not a separate vendor
  /// master. Null while unassigned, validated server-side on write.
  final String? contractorPartyId;
}

class CapexProjectDto extends CapexProjectSummaryDto {
  const CapexProjectDto({
    required super.id,
    required super.workspaceId,
    required super.propertyId,
    required super.projectCode,
    required super.status,
    required super.version,
    super.currencyCode,
    super.budgetAmount,
    super.forecastAmount,
    super.actualAmount,
    super.plannedEndDate,
    super.contractorPartyId,
    this.category,
    this.measure,
    this.startDate,
    this.actualEndDate,
    this.owner,
    this.nextStep,
    this.approvedBy,
    this.approvedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  final String? category;
  final String? measure;
  final DateTime? startDate;

  /// Auto-stamped to today the first time [status] enters `completed`, if not
  /// already set (`transition_capex_project_status`).
  final DateTime? actualEndDate;
  final String? owner;
  final String? nextStep;

  /// Stamped the first time [status] moves beyond `quoteRequested` and
  /// preserved on every subsequent forward move. Neither field is settable
  /// via create/update — they only ever come from the `approved` transition.
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;

  CapexProjectSummaryDto toSummary() => CapexProjectSummaryDto(
    id: id,
    workspaceId: workspaceId,
    propertyId: propertyId,
    projectCode: projectCode,
    status: status,
    version: version,
    currencyCode: currencyCode,
    budgetAmount: budgetAmount,
    forecastAmount: forecastAmount,
    actualAmount: actualAmount,
    plannedEndDate: plannedEndDate,
    contractorPartyId: contractorPartyId,
  );
}

/// Input for creating a project. A new project always starts
/// [CapexProjectStatus.idea]; advancing is a separate audited transition.
class CapexProjectDraft {
  const CapexProjectDraft({
    required this.propertyId,
    required this.projectCode,
    this.category,
    this.measure,
    this.startDate,
    this.plannedEndDate,
    this.budgetAmount,
    this.forecastAmount,
    this.currencyCode,
    this.contractorPartyId,
    this.owner,
    this.nextStep,
  });

  final String propertyId;
  final String projectCode;
  final String? category;
  final String? measure;
  final DateTime? startDate;
  final DateTime? plannedEndDate;
  final double? budgetAmount;
  final double? forecastAmount;
  final String? currencyCode;
  final String? contractorPartyId;
  final String? owner;
  final String? nextStep;
}

/// Attribute-only patch. Mirrors `update_capex_project`'s actual semantics:
/// every field is `coalesce(param, existing)` server-side, so a null here
/// leaves the current value untouched rather than clearing it — there is no
/// way to clear these fields back to null via update at all. `status`,
/// `approvedBy` and `approvedAt` are deliberately absent: status only moves
/// through [CapexProjectStatus] transitions, and the approval stamp only
/// comes from the `approved` transition.
class CapexProjectUpdateDto {
  const CapexProjectUpdateDto({
    this.projectCode,
    this.category,
    this.measure,
    this.startDate,
    this.plannedEndDate,
    this.actualEndDate,
    this.budgetAmount,
    this.forecastAmount,
    this.actualAmount,
    this.currencyCode,
    this.contractorPartyId,
    this.owner,
    this.nextStep,
  });

  final String? projectCode;
  final String? category;
  final String? measure;
  final DateTime? startDate;
  final DateTime? plannedEndDate;
  final DateTime? actualEndDate;
  final double? budgetAmount;
  final double? forecastAmount;
  final double? actualAmount;
  final String? currencyCode;
  final String? contractorPartyId;
  final String? owner;
  final String? nextStep;
}
