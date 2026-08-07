/// Backend-agnostic maintenance_capex contract (P2-D06, DOM-007).
///
/// Four ports mirror the module contract: [MaintenanceTicketRepository] /
/// [MaintenanceTicketSearchPort] and [CapexProjectRepository] /
/// [CapexProjectSearchPort]. All mutations are workspace-scoped,
/// permission-gated server-side (`maintenance.read`/`maintenance.manage`,
/// `capex.read`/`capex.manage`, plus the separate `capex.approve` required
/// only to transition a project into [CapexProjectStatus.approved]), no AAL2
/// (ordinary business data), idempotent (`mutationId`), versioned
/// (`expectedVersion`) and audited append-only — the same envelope as the
/// property, party, document and leasing contracts.
///
/// Two shapes here differ from `leasing_operations`, both because the server
/// does:
///
///   * There is no delete anywhere. `OPN-DOM-005` is open, so no aggregate in
///     this domain has a delete path, not even a tombstone.
///   * The list RPCs (`public.maintenance_tickets`, `public.capex_projects`)
///     require a [propertyId] and return every matching row unpaginated —
///     there is no `expectedVersion`-style cursor. [MaintenanceTicketSearchPort]
///     and [CapexProjectSearchPort] return a plain `List`, not a page result;
///     inventing pagination the server does not offer would misrepresent it.
library;

import '../domain/capex_project_dto.dart';
import '../domain/maintenance_ticket_dto.dart';

class MaintenanceCapexCommandContext {
  const MaintenanceCapexCommandContext({
    required this.workspaceId,
    required this.actorId,
    required this.mutationId,
    required this.correlationId,
    this.reason,
  });

  final String workspaceId;
  final String actorId;
  final String mutationId;
  final String correlationId;
  final String? reason;
}

// --- Queries -----------------------------------------------------------

/// Lists tickets of exactly one property — `public.maintenance_tickets`
/// requires [propertyId], it is not optional server-side.
class MaintenanceTicketListQuery {
  const MaintenanceTicketListQuery({
    required this.workspaceId,
    required this.propertyId,
    this.unitId,
    this.status,
    this.priority,
  });

  final String workspaceId;
  final String propertyId;
  final String? unitId;
  final MaintenanceTicketStatus? status;
  final MaintenanceTicketPriority? priority;
}

/// Lists projects of exactly one property — `public.capex_projects` requires
/// [propertyId], it is not optional server-side.
class CapexProjectListQuery {
  const CapexProjectListQuery({
    required this.workspaceId,
    required this.propertyId,
    this.status,
  });

  final String workspaceId;
  final String propertyId;
  final CapexProjectStatus? status;
}

// --- Commands ------------------------------------------------------------

class CreateMaintenanceTicketCommand {
  const CreateMaintenanceTicketCommand({
    required this.context,
    required this.draft,
  });

  final MaintenanceCapexCommandContext context;
  final MaintenanceTicketDraft draft;
}

class UpdateMaintenanceTicketCommand {
  const UpdateMaintenanceTicketCommand({
    required this.context,
    required this.ticketId,
    required this.expectedVersion,
    required this.changes,
  });

  final MaintenanceCapexCommandContext context;
  final String ticketId;
  final int expectedVersion;
  final MaintenanceTicketUpdateDto changes;
}

/// STM-006. [costActual] is accepted on any target — the server does not
/// restrict it to a particular status — but is only meaningful once work is
/// actually done, typically entering `resolved` or `invoiced`.
class TransitionMaintenanceTicketStatusCommand {
  const TransitionMaintenanceTicketStatusCommand({
    required this.context,
    required this.ticketId,
    required this.expectedVersion,
    required this.targetStatus,
    this.costActual,
  });

  final MaintenanceCapexCommandContext context;
  final String ticketId;
  final int expectedVersion;
  final MaintenanceTicketStatus targetStatus;
  final double? costActual;
}

class CreateCapexProjectCommand {
  const CreateCapexProjectCommand({required this.context, required this.draft});

  final MaintenanceCapexCommandContext context;
  final CapexProjectDraft draft;
}

class UpdateCapexProjectCommand {
  const UpdateCapexProjectCommand({
    required this.context,
    required this.projectId,
    required this.expectedVersion,
    required this.changes,
  });

  final MaintenanceCapexCommandContext context;
  final String projectId;
  final int expectedVersion;
  final CapexProjectUpdateDto changes;
}

/// STM-007. Entering [CapexProjectStatus.approved] requires the caller to
/// hold `capex.approve`, not just `capex.manage` — the server checks this by
/// branching on [targetStatus], and a caller without it gets `forbidden`
/// rather than a silently ignored approval. [actualAmount] is refused with
/// `validationFailed` if the project has no `currencyCode` yet — an actual
/// spend cannot be recorded without a currency to record it in.
class TransitionCapexProjectStatusCommand {
  const TransitionCapexProjectStatusCommand({
    required this.context,
    required this.projectId,
    required this.expectedVersion,
    required this.targetStatus,
    this.actualAmount,
  });

  final MaintenanceCapexCommandContext context;
  final String projectId;
  final int expectedVersion;
  final CapexProjectStatus targetStatus;
  final double? actualAmount;
}

// --- Results ---------------------------------------------------------------

enum MaintenanceCapexRepositoryFailureKind {
  notFound,
  forbidden,
  validationFailed,
  versionConflict,
  mutationConflict,
  mutationInProgress,

  /// Also returned when a `contractorPartyId` does not hold an open
  /// `contractor` party role (`private.maintenance_contractor_party_valid`).
  dependencyConflict,

  infrastructureFailure,
}

/// Structured optimistic-concurrency conflict. Exactly one of the `current*`
/// fields is set, matching the entity the failed command targeted.
class MaintenanceCapexVersionConflict {
  const MaintenanceCapexVersionConflict({
    required this.expectedVersion,
    required this.actualVersion,
    this.currentTicket,
    this.currentProject,
  }) : assert(
         (currentTicket != null ? 1 : 0) + (currentProject != null ? 1 : 0) ==
             1,
         'Exactly one current entity belongs to a version conflict.',
       );

  final int expectedVersion;
  final int actualVersion;
  final MaintenanceTicketDto? currentTicket;
  final CapexProjectDto? currentProject;
}

sealed class MaintenanceCapexRepositoryResult<T> {
  const MaintenanceCapexRepositoryResult();
}

class MaintenanceCapexRepositorySuccess<T>
    extends MaintenanceCapexRepositoryResult<T> {
  const MaintenanceCapexRepositorySuccess(this.value);

  final T value;
}

class MaintenanceCapexRepositoryFailure<T>
    extends MaintenanceCapexRepositoryResult<T> {
  const MaintenanceCapexRepositoryFailure({
    required this.kind,
    required this.message,
    this.versionConflict,
  }) : assert(
         kind == MaintenanceCapexRepositoryFailureKind.versionConflict
             ? versionConflict != null
             : versionConflict == null,
       );

  final MaintenanceCapexRepositoryFailureKind kind;
  final String message;
  final MaintenanceCapexVersionConflict? versionConflict;
}

// --- Ports -----------------------------------------------------------------

/// Ticket lifecycle. Reads are server-authorized on `maintenance.read`;
/// mutations run through the audited RPC envelope only.
abstract interface class MaintenanceTicketRepository {
  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> getById({
    required String workspaceId,
    required String ticketId,
  });

  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> create(
    CreateMaintenanceTicketCommand command,
  );

  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>> update(
    UpdateMaintenanceTicketCommand command,
  );

  Future<MaintenanceCapexRepositoryResult<MaintenanceTicketDto>>
  transitionStatus(TransitionMaintenanceTicketStatusCommand command);
}

abstract interface class MaintenanceTicketSearchPort {
  Future<MaintenanceCapexRepositoryResult<List<MaintenanceTicketSummaryDto>>>
  search(MaintenanceTicketListQuery query);
}

/// Project lifecycle. Reads are server-authorized on `capex.read`; mutations
/// run through the audited RPC envelope only.
abstract interface class CapexProjectRepository {
  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> getById({
    required String workspaceId,
    required String projectId,
  });

  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> create(
    CreateCapexProjectCommand command,
  );

  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> update(
    UpdateCapexProjectCommand command,
  );

  Future<MaintenanceCapexRepositoryResult<CapexProjectDto>> transitionStatus(
    TransitionCapexProjectStatusCommand command,
  );
}

abstract interface class CapexProjectSearchPort {
  Future<MaintenanceCapexRepositoryResult<List<CapexProjectSummaryDto>>>
  search(CapexProjectListQuery query);
}
