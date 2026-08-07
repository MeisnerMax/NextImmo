/// Domain DTOs for the MaintenanceTicket aggregate (P2-D06, DOM-007, STM-006,
/// AGG-008).
///
/// Unlike the `leasing_operations` aggregates this migrates real local data —
/// see `legacy_sqlite_maintenance_capex_repository_adapter.dart` for how the
/// pre-existing `maintenance_tickets` SQLite table (free-text status, no party
/// FK) is projected into this shape.
library;

/// STM-006, exactly as `private.maintenance_ticket_status_transition_allowed`
/// implements it. Unlike [CapexProjectStatus] this is **not** a strict linear
/// chain: `inProgress` branches to `waiting` or `resolved`, and `resolved` has
/// the one reopen edge back to `inProgress` in addition to the forward move to
/// `invoiced`. So there is no single "next" status — [allowedNextStatuses]
/// returns every lawful target instead of one.
///
/// [newTicket] is the Dart-side name for the SQL value `new`: `new` is a
/// reserved word in Dart and cannot be an enum member. The wire mapping (in
/// the Supabase adapter) maps it explicitly, the same way every status enum in
/// this codebase maps to/from its SQL string rather than relying on `.name`.
enum MaintenanceTicketStatus {
  newTicket,
  triage,
  quoteRequested,
  commissioned,
  scheduled,
  inProgress,
  waiting,
  resolved,
  invoiced,
  archived;

  bool get isTerminal => this == MaintenanceTicketStatus.archived;

  /// Mirrors `private.maintenance_ticket_status_transition_allowed`, for
  /// offering only moves the server will accept. The server remains the
  /// authority — this never decides, it only avoids proposing a refused step.
  Set<MaintenanceTicketStatus> get allowedNextStatuses => switch (this) {
    MaintenanceTicketStatus.newTicket => const {MaintenanceTicketStatus.triage},
    MaintenanceTicketStatus.triage => const {
      MaintenanceTicketStatus.quoteRequested,
    },
    MaintenanceTicketStatus.quoteRequested => const {
      MaintenanceTicketStatus.commissioned,
    },
    MaintenanceTicketStatus.commissioned => const {
      MaintenanceTicketStatus.scheduled,
    },
    MaintenanceTicketStatus.scheduled => const {
      MaintenanceTicketStatus.inProgress,
    },
    MaintenanceTicketStatus.inProgress => const {
      MaintenanceTicketStatus.waiting,
      MaintenanceTicketStatus.resolved,
    },
    MaintenanceTicketStatus.waiting => const {
      MaintenanceTicketStatus.inProgress,
    },
    MaintenanceTicketStatus.resolved => const {
      MaintenanceTicketStatus.inProgress,
      MaintenanceTicketStatus.invoiced,
    },
    MaintenanceTicketStatus.invoiced => const {
      MaintenanceTicketStatus.archived,
    },
    MaintenanceTicketStatus.archived => const {},
  };

  bool canTransitionTo(MaintenanceTicketStatus target) =>
      allowedNextStatuses.contains(target);
}

enum MaintenanceTicketPriority { low, normal, high, urgent }

/// Compact projection used by list results.
///
/// The list/read RPCs (`public.maintenance_tickets`) return the identical
/// full snapshot used for a single read — there is no lighter server-side
/// projection for this aggregate. The Summary/Full split is kept anyway, for
/// consistency with every other aggregate contract in this codebase, and
/// built by discarding fields client-side ([MaintenanceTicketDto.toSummary]).
class MaintenanceTicketSummaryDto {
  const MaintenanceTicketSummaryDto({
    required this.id,
    required this.workspaceId,
    required this.propertyId,
    required this.title,
    required this.status,
    required this.priority,
    required this.reportedAt,
    required this.version,
    this.unitId,
    this.dueAt,
    this.costEstimate,
    this.costActual,
    this.currencyCode,
    this.contractorPartyId,
  });

  final String id;
  final String workspaceId;
  final String propertyId;
  final String title;
  final MaintenanceTicketStatus status;
  final MaintenanceTicketPriority priority;
  final DateTime reportedAt;
  final int version;

  final String? unitId;
  final DateTime? dueAt;
  final double? costEstimate;
  final double? costActual;

  /// DEC-011: present whenever a money amount is.
  final String? currencyCode;

  /// The contractor is a Party role (AGG-005 / P2-D02), not a separate vendor
  /// master. Null while unassigned, validated server-side on write.
  final String? contractorPartyId;
}

class MaintenanceTicketDto extends MaintenanceTicketSummaryDto {
  const MaintenanceTicketDto({
    required super.id,
    required super.workspaceId,
    required super.propertyId,
    required super.title,
    required super.status,
    required super.priority,
    required super.reportedAt,
    required super.version,
    super.unitId,
    super.dueAt,
    super.costEstimate,
    super.costActual,
    super.currencyCode,
    super.contractorPartyId,
    required this.category,
    this.description,
    this.resolvedAt,
    this.damageLocation,
    required this.insuranceCase,
    this.insuranceStatus,
    this.insuranceClaimNumber,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  final String category;
  final String? description;

  /// Set exactly while [status] is `resolved`, `invoiced` or `archived` — the
  /// column describes the current state, not a history of every resolution.
  final DateTime? resolvedAt;
  final String? damageLocation;
  final bool insuranceCase;
  final String? insuranceStatus;
  final String? insuranceClaimNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;

  MaintenanceTicketSummaryDto toSummary() => MaintenanceTicketSummaryDto(
    id: id,
    workspaceId: workspaceId,
    propertyId: propertyId,
    title: title,
    status: status,
    priority: priority,
    reportedAt: reportedAt,
    version: version,
    unitId: unitId,
    dueAt: dueAt,
    costEstimate: costEstimate,
    costActual: costActual,
    currencyCode: currencyCode,
    contractorPartyId: contractorPartyId,
  );
}

/// Input for creating a ticket. A new ticket always starts
/// [MaintenanceTicketStatus.newTicket]; advancing is a separate audited
/// transition.
class MaintenanceTicketDraft {
  const MaintenanceTicketDraft({
    required this.propertyId,
    required this.title,
    this.unitId,
    this.description,
    this.category = 'general',
    this.priority = MaintenanceTicketPriority.normal,
    this.dueAt,
    this.costEstimate,
    this.currencyCode,
    this.contractorPartyId,
    this.damageLocation,
    this.insuranceCase = false,
    this.insuranceStatus,
    this.insuranceClaimNumber,
  });

  final String propertyId;
  final String title;
  final String? unitId;
  final String? description;
  final String category;
  final MaintenanceTicketPriority priority;
  final DateTime? dueAt;
  final double? costEstimate;
  final String? currencyCode;
  final String? contractorPartyId;
  final String? damageLocation;
  final bool insuranceCase;
  final String? insuranceStatus;
  final String? insuranceClaimNumber;
}

/// Attribute-only patch. Mirrors `update_maintenance_ticket`'s actual
/// semantics: every field is `coalesce(param, existing)` server-side, so a
/// null here leaves the current value untouched rather than clearing it —
/// there is no way to clear these fields back to null via update at all.
/// `status` is deliberately absent: it only moves through
/// [MaintenanceTicketStatus] transitions.
class MaintenanceTicketUpdateDto {
  const MaintenanceTicketUpdateDto({
    this.title,
    this.description,
    this.category,
    this.priority,
    this.dueAt,
    this.costEstimate,
    this.costActual,
    this.currencyCode,
    this.contractorPartyId,
    this.damageLocation,
    this.insuranceCase,
    this.insuranceStatus,
    this.insuranceClaimNumber,
  });

  final String? title;
  final String? description;
  final String? category;
  final MaintenanceTicketPriority? priority;
  final DateTime? dueAt;
  final double? costEstimate;
  final double? costActual;
  final String? currencyCode;
  final String? contractorPartyId;
  final String? damageLocation;
  final bool? insuranceCase;
  final String? insuranceStatus;
  final String? insuranceClaimNumber;
}
