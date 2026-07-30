/// Backend-agnostic leasing_operations contract (P2-D05, DOM-004).
///
/// Seven ports mirror the module contract: [UnitRepository] / [UnitSearchPort],
/// [LeaseRepository] / [LeaseSearchPort], [LeasingCaseRepository] /
/// [LeasingCaseSearchPort], and [RentRollPort]. All mutations are
/// workspace-scoped, permission-gated server-side (`lease.read`/`lease.manage`,
/// no AAL2 — units, leases, cases and rent rolls are ordinary business data),
/// idempotent (`mutationId`), versioned (`expectedVersion` where a row is
/// edited) and audited append-only — the same envelope as the property, party
/// and document contracts.
///
/// Two shapes here differ from the other domains, both because the server does:
///
///   * There is no delete anywhere. `OPN-DOM-005` is open, so no aggregate in
///     this domain has a delete path, not even a tombstone.
///   * [RentRollPort.createSnapshot] has no update or transition counterpart.
///     AGG-007 makes a snapshot immutable; the only lawful operation on one is
///     creating another.
library;

import '../domain/lease_dto.dart';
import '../domain/leasing_case_dto.dart';
import '../domain/rent_roll_dto.dart';
import '../domain/unit_dto.dart';

class LeasingCommandContext {
  const LeasingCommandContext({
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

class LeasingPageRequest {
  const LeasingPageRequest({this.limit = 50, this.cursor})
    : assert(limit > 0 && limit <= 100);

  final int limit;
  final String? cursor;
}

class LeasingPageResult<T> {
  const LeasingPageResult({required this.items, this.nextCursor});

  final List<T> items;
  final String? nextCursor;
}

// --- Queries ---------------------------------------------------------------

class UnitListQuery {
  const UnitListQuery({
    required this.workspaceId,
    this.propertyId,
    this.status,
    this.page = const LeasingPageRequest(),
  });

  final String workspaceId;
  final String? propertyId;
  final UnitStatus? status;
  final LeasingPageRequest page;
}

/// A lease search. [unitId] returns **every** lease of that unit, not one —
/// OPN-DOM-001 allows several concurrently effective leases per unit.
class LeaseListQuery {
  const LeaseListQuery({
    required this.workspaceId,
    this.propertyId,
    this.unitId,
    this.tenantPartyId,
    this.status,
    this.effectiveOnly = false,
    this.page = const LeasingPageRequest(),
  });

  final String workspaceId;
  final String? propertyId;
  final String? unitId;
  final String? tenantPartyId;
  final LeaseStatus? status;

  /// Restrict to leases that count for occupancy (status `active`). Distinct
  /// from a date filter — see [LeaseSummaryDto.coversDate].
  final bool effectiveOnly;
  final LeasingPageRequest page;
}

class LeasingCaseListQuery {
  const LeasingCaseListQuery({
    required this.workspaceId,
    this.propertyId,
    this.unitId,
    this.status,
    this.openOnly = false,
    this.page = const LeasingPageRequest(),
  });

  final String workspaceId;
  final String? propertyId;
  final String? unitId;
  final LeasingCaseStatus? status;

  /// Exclude terminal cases — the pipeline-board read.
  final bool openOnly;
  final LeasingPageRequest page;
}

class RentRollSnapshotListQuery {
  const RentRollSnapshotListQuery({
    required this.workspaceId,
    required this.propertyId,
    this.page = const LeasingPageRequest(),
  });

  final String workspaceId;
  final String propertyId;
  final LeasingPageRequest page;
}

// --- Commands --------------------------------------------------------------

class CreateUnitCommand {
  const CreateUnitCommand({required this.context, required this.draft});

  final LeasingCommandContext context;
  final UnitDraft draft;
}

class UpdateUnitCommand {
  const UpdateUnitCommand({
    required this.context,
    required this.unitId,
    required this.expectedVersion,
    required this.changes,
  });

  final LeasingCommandContext context;
  final String unitId;
  final int expectedVersion;
  final UnitUpdateDto changes;
}

/// STM-003. Only [UnitStatus.offline] and the return from it are caller-driven:
/// `vacant`/`occupied` are derived from the effective leases, and asking for
/// them directly is refused with `validationFailed`.
///
/// Entering `offline` requires a [LeasingCommandContext.reason] — the server
/// records the count of effective leases at that moment in the audit entry, so
/// STM-003's "only after checking the lease situation" is evidenced rather than
/// asserted. Leaving `offline` recomputes the status from the leases effective
/// then.
///
/// There is deliberately no separate `offlineReason` field: for a transition
/// into `offline` the command reason **is** the unit's offline reason — the
/// server stores `reason` into `units.offline_reason` and into the audit entry
/// from the one value. Two fields would let them disagree about the same fact.
class TransitionUnitStatusCommand {
  const TransitionUnitStatusCommand({
    required this.context,
    required this.unitId,
    required this.expectedVersion,
    required this.targetStatus,
  });

  final LeasingCommandContext context;
  final String unitId;
  final int expectedVersion;
  final UnitStatus targetStatus;
}

class CreateLeaseCommand {
  const CreateLeaseCommand({required this.context, required this.draft});

  final LeasingCommandContext context;
  final LeaseDraft draft;
}

class UpdateLeaseCommand {
  const UpdateLeaseCommand({
    required this.context,
    required this.leaseId,
    required this.expectedVersion,
    required this.changes,
  });

  final LeasingCommandContext context;
  final String leaseId;
  final int expectedVersion;
  final LeaseUpdateDto changes;
}

/// STM-005. Cancelling requires a [LeasingCommandContext.reason].
/// [moveOutDate] belongs only to ending a lease and is refused otherwise.
class TransitionLeaseStatusCommand {
  const TransitionLeaseStatusCommand({
    required this.context,
    required this.leaseId,
    required this.expectedVersion,
    required this.targetStatus,
    this.moveOutDate,
  });

  final LeasingCommandContext context;
  final String leaseId;
  final int expectedVersion;
  final LeaseStatus targetStatus;
  final DateTime? moveOutDate;
}

class CreateLeasingCaseCommand {
  const CreateLeasingCaseCommand({required this.context, required this.draft});

  final LeasingCommandContext context;
  final LeasingCaseDraft draft;
}

class UpdateLeasingCaseCommand {
  const UpdateLeasingCaseCommand({
    required this.context,
    required this.caseId,
    required this.expectedVersion,
    required this.changes,
  });

  final LeasingCommandContext context;
  final String caseId;
  final int expectedVersion;
  final LeasingCaseUpdateDto changes;
}

/// STM-004: one step forward, or cancel. Cancelling requires a
/// [LeasingCommandContext.reason]; moving to [LeasingCaseStatus.signed]
/// requires [leaseId] unless the case already names one.
class TransitionLeasingCaseStatusCommand {
  const TransitionLeasingCaseStatusCommand({
    required this.context,
    required this.caseId,
    required this.expectedVersion,
    required this.targetStatus,
    this.leaseId,
  });

  final LeasingCommandContext context;
  final String caseId;
  final int expectedVersion;
  final LeasingCaseStatus targetStatus;
  final String? leaseId;
}

/// Freeze the rent roll of one property as of a date (AGG-007).
///
/// [currencyCode] is required exactly when it cannot be derived — i.e. when no
/// lease contributes at all, which is the legitimate case of a fully vacant
/// property that still deserves a rent roll of zeros. When leases do
/// contribute, their shared currency wins and passing a conflicting one is
/// refused. Guessing would invent data.
class CreateRentRollSnapshotCommand {
  const CreateRentRollSnapshotCommand({
    required this.context,
    required this.propertyId,
    required this.asOfDate,
    this.currencyCode,
  });

  final LeasingCommandContext context;
  final String propertyId;
  final DateTime asOfDate;
  final String? currencyCode;
}

// --- Results ---------------------------------------------------------------

enum LeasingRepositoryFailureKind {
  notFound,
  forbidden,
  validationFailed,
  versionConflict,
  mutationConflict,
  mutationInProgress,
  dependencyConflict,

  /// The leases contributing to a rent roll do not share one currency, or the
  /// requested currency contradicts them (DEC-011). Its own kind rather than a
  /// [validationFailed] because it is the one failure that carries the
  /// information needed to fix it — see [RentRollCurrencyMismatch].
  currencyMismatch,

  infrastructureFailure,
}

/// Structured optimistic-concurrency conflict. Exactly one of the `current*`
/// fields is set, matching the entity the failed command targeted.
class LeasingVersionConflict {
  const LeasingVersionConflict({
    required this.expectedVersion,
    required this.actualVersion,
    this.currentUnit,
    this.currentLease,
    this.currentCase,
  }) : assert(
         (currentUnit != null ? 1 : 0) +
                 (currentLease != null ? 1 : 0) +
                 (currentCase != null ? 1 : 0) ==
             1,
         'Exactly one current entity belongs to a version conflict.',
       );

  final int expectedVersion;
  final int actualVersion;
  final UnitDto? currentUnit;
  final LeaseDto? currentLease;
  final LeasingCaseDto? currentCase;
}

/// The currencies actually found among the contributing leases. Carrying them
/// is the point: "these leases are in CHF and EUR" is actionable, "invalid
/// currency" is not.
class RentRollCurrencyMismatch {
  const RentRollCurrencyMismatch({required this.currencies});

  final List<String> currencies;
}

sealed class LeasingRepositoryResult<T> {
  const LeasingRepositoryResult();
}

class LeasingRepositorySuccess<T> extends LeasingRepositoryResult<T> {
  const LeasingRepositorySuccess(this.value);

  final T value;
}

class LeasingRepositoryFailure<T> extends LeasingRepositoryResult<T> {
  const LeasingRepositoryFailure({
    required this.kind,
    required this.message,
    this.versionConflict,
    this.currencyMismatch,
  }) : assert(
         kind == LeasingRepositoryFailureKind.versionConflict
             ? versionConflict != null
             : versionConflict == null,
       ),
       assert(
         kind == LeasingRepositoryFailureKind.currencyMismatch
             ? currencyMismatch != null
             : currencyMismatch == null,
       );

  final LeasingRepositoryFailureKind kind;
  final String message;
  final LeasingVersionConflict? versionConflict;
  final RentRollCurrencyMismatch? currencyMismatch;
}

// --- Ports -----------------------------------------------------------------

/// Unit lifecycle. Reads are server-authorized on `lease.read`; mutations run
/// through the audited RPC envelope only.
abstract interface class UnitRepository {
  Future<LeasingRepositoryResult<UnitDto>> getById({
    required String workspaceId,
    required String unitId,
  });

  Future<LeasingRepositoryResult<UnitDto>> create(CreateUnitCommand command);

  Future<LeasingRepositoryResult<UnitDto>> update(UpdateUnitCommand command);

  Future<LeasingRepositoryResult<UnitDto>> transitionStatus(
    TransitionUnitStatusCommand command,
  );
}

abstract interface class UnitSearchPort {
  Future<LeasingRepositoryResult<LeasingPageResult<UnitSummaryDto>>> search(
    UnitListQuery query,
  );
}

/// Lease lifecycle. Activation and ending are transitions rather than updates,
/// because those are the writes that change a unit's occupancy.
abstract interface class LeaseRepository {
  Future<LeasingRepositoryResult<LeaseDto>> getById({
    required String workspaceId,
    required String leaseId,
  });

  Future<LeasingRepositoryResult<LeaseDto>> create(CreateLeaseCommand command);

  Future<LeasingRepositoryResult<LeaseDto>> update(UpdateLeaseCommand command);

  Future<LeasingRepositoryResult<LeaseDto>> transitionStatus(
    TransitionLeaseStatusCommand command,
  );
}

abstract interface class LeaseSearchPort {
  Future<LeasingRepositoryResult<LeasingPageResult<LeaseSummaryDto>>> search(
    LeaseListQuery query,
  );
}

/// STM-004 pipeline lifecycle.
abstract interface class LeasingCaseRepository {
  Future<LeasingRepositoryResult<LeasingCaseDto>> getById({
    required String workspaceId,
    required String caseId,
  });

  Future<LeasingRepositoryResult<LeasingCaseDto>> create(
    CreateLeasingCaseCommand command,
  );

  Future<LeasingRepositoryResult<LeasingCaseDto>> update(
    UpdateLeasingCaseCommand command,
  );

  Future<LeasingRepositoryResult<LeasingCaseDto>> transitionStatus(
    TransitionLeasingCaseStatusCommand command,
  );
}

abstract interface class LeasingCaseSearchPort {
  Future<LeasingRepositoryResult<LeasingPageResult<LeasingCaseSummaryDto>>>
  search(LeasingCaseListQuery query);
}

/// Rent-roll snapshots (AGG-007). Create and read only — a frozen snapshot has
/// no update, transition or delete path by design.
abstract interface class RentRollPort {
  /// The full frozen document, lines included.
  Future<LeasingRepositoryResult<RentRollSnapshotDto>> getSnapshot({
    required String workspaceId,
    required String snapshotId,
  });

  /// Header-only projections, newest first. Several snapshots may share an
  /// `asOfDate`; they are ordered by `generatedAt`.
  Future<LeasingRepositoryResult<LeasingPageResult<RentRollSnapshotDto>>>
  listSnapshots(RentRollSnapshotListQuery query);

  Future<LeasingRepositoryResult<RentRollSnapshotDto>> createSnapshot(
    CreateRentRollSnapshotCommand command,
  );
}
