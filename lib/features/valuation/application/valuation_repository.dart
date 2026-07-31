/// Backend-agnostic valuation contract (P2-D07, Welle 5).
///
/// Three ports: [ValuationCaseRepository] (the aggregate and its lifecycle),
/// [ValuationFactorPort] (the provenance-tagged factors) and
/// [ValuationReportPort] (the computed method results plus the reconciled
/// Verkehrswert).
///
/// Every mutation carries the same audited envelope as the property, party,
/// document and platform contracts: workspace-scoped, bound to the acting user,
/// idempotent (`mutationId`), versioned (`expectedVersion`) and audited
/// (`correlationId`, `reason`). Two rules are specific to valuations:
///
/// 1. **An approved case is a record.** Any factor or configuration change on an
///    `approved` case fails with
///    [ValuationRepositoryFailureKind.approvedImmutable] (`AGG-014`); a revision
///    is a new case, not an edit.
/// 2. **Unavailability is stored, not swallowed.** A method that concluded
///    "nicht ermittelbar" is persisted as such with its missing factors — the
///    report path has no way to write a substituted amount.
library;

import '../domain/cash_flow_projection.dart';
import '../domain/methods/comparison_approach_method.dart';
import '../domain/valuation_case.dart';
import '../domain/valuation_case_dto.dart';
import '../domain/valuation_method.dart';
import '../domain/valuation_report.dart';

/// The audited command envelope shared by every valuation mutation.
class ValuationCommandContext {
  const ValuationCommandContext({
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

class ValuationPageRequest {
  const ValuationPageRequest({this.limit = 50, this.cursor})
    : assert(limit > 0 && limit <= 100);

  final int limit;

  /// Opaque to callers; produced by a previous page's
  /// [ValuationPageResult.nextCursor] — see [ValuationKeysetCursor].
  final String? cursor;
}

class ValuationPageResult<T> {
  const ValuationPageResult({required this.items, this.nextCursor});

  final List<T> items;
  final String? nextCursor;
}

/// `updated_at` plus the row id that breaks ties — the same composite keyset the
/// platform lists use, and for the same reason: `now()` is transaction-bound, so
/// a timestamp alone cannot order rows written by one command.
class ValuationKeysetCursor {
  const ValuationKeysetCursor({required this.timestamp, required this.id});

  final DateTime timestamp;
  final String id;

  static ValuationKeysetCursor? decode(String? value) {
    if (value == null) return null;
    final separator = value.lastIndexOf('|');
    if (separator <= 0 || separator == value.length - 1) return null;
    final timestamp = DateTime.tryParse(value.substring(0, separator));
    if (timestamp == null) return null;
    return ValuationKeysetCursor(
      timestamp: timestamp,
      id: value.substring(separator + 1),
    );
  }

  String encode() => '${timestamp.toUtc().toIso8601String()}|$id';
}

// -----------------------------------------------------------------------------
// Queries
// -----------------------------------------------------------------------------

/// Newest-first case list. Archived cases are excluded unless
/// [includeArchived] — an archived case belongs in an audit view, not a work
/// list.
class ValuationCaseListQuery {
  const ValuationCaseListQuery({
    required this.workspaceId,
    this.propertyId,
    this.scenarioId,
    this.kind,
    this.status,
    this.includeArchived = false,
    this.page = const ValuationPageRequest(),
  });

  final String workspaceId;
  final String? propertyId;
  final String? scenarioId;
  final ValuationCaseKind? kind;
  final ValuationCaseStatus? status;
  final bool includeArchived;
  final ValuationPageRequest page;
}

/// The stored projection of one computed report: what each method concluded and
/// the reconciled Verkehrswert, together with the case version they were
/// computed from. A report whose [computedFromVersion] is behind the case's
/// current version is stale — visibly so, which is the point.
class ValuationReportSnapshot {
  const ValuationReportSnapshot({
    required this.valuationCaseId,
    required this.computedFromVersion,
    required this.methodResults,
    this.opinion,
  });

  final String valuationCaseId;
  final int computedFromVersion;
  final List<ValuationMethodResultDto> methodResults;

  /// Null only when a report row exists without its opinion, which the schema
  /// does not allow — present for every report this contract can produce.
  final MarketValueOpinionDto? opinion;
}

/// A case with everything needed to rehydrate and display it: the row, its
/// factors, the last stored method results and the last Verkehrswert opinion.
class ValuationCaseDetail {
  const ValuationCaseDetail({
    required this.valuationCase,
    required this.factors,
    this.report,
  });

  final ValuationCaseDto valuationCase;
  final List<ValuationFactorDto> factors;

  /// Null when no report has been published for the case yet.
  final ValuationReportSnapshot? report;

  /// Whether the stored report predates the current factor set.
  bool get hasStaleReport =>
      report != null && report!.computedFromVersion < valuationCase.version;

  /// Rebuilds the engine aggregate from the stored factors. Comparables come
  /// from the `comps` aggregate and are supplied by the caller.
  ValuationCase toDomain({List<ComparableSale> comparables = const []}) =>
      valuationCase.toDomain(
        factors: factors.map((f) => f.toDomain()),
        comparables: comparables,
      );
}

// -----------------------------------------------------------------------------
// Commands
// -----------------------------------------------------------------------------

class CreateValuationCaseCommand {
  const CreateValuationCaseCommand({
    required this.context,
    required this.propertyId,
    required this.title,
    required this.kind,
    this.scenarioId,
    this.dcfTerminal,
    this.enabledMethods,
    this.weightOverrides = const {},
    this.minimumComparables,
    this.factors = const [],
  });

  final ValuationCommandContext context;
  final String propertyId;
  final String? scenarioId;
  final String title;
  final ValuationCaseKind kind;

  /// Null keeps the server default (`exit_cap`).
  final DcfTerminalMethod? dcfTerminal;
  final Set<ValuationMethodKind>? enabledMethods;
  final Map<ValuationMethodKind, double> weightOverrides;
  final int? minimumComparables;

  /// Optional initial factor set, written in the same transaction so a new case
  /// is never briefly half-populated.
  final List<ValuationFactorDto> factors;
}

/// Edits the configuration of a case (title, method selection, weighting).
/// Factors go through [UpsertValuationFactorsCommand] instead, so a factor edit
/// and a configuration edit never contend on the same version token by accident.
class UpdateValuationCaseCommand {
  const UpdateValuationCaseCommand({
    required this.context,
    required this.valuationCaseId,
    required this.expectedVersion,
    this.title,
    this.kind,
    this.scenarioId,
    this.clearScenarioId = false,
    this.dcfTerminal,
    this.enabledMethods,
    this.weightOverrides,
    this.minimumComparables,
  });

  final ValuationCommandContext context;
  final String valuationCaseId;
  final int expectedVersion;
  final String? title;
  final ValuationCaseKind? kind;
  final String? scenarioId;
  final bool clearScenarioId;
  final DcfTerminalMethod? dcfTerminal;
  final Set<ValuationMethodKind>? enabledMethods;
  final Map<ValuationMethodKind, double>? weightOverrides;
  final int? minimumComparables;
}

/// Adds or replaces factors by `factor_id`.
///
/// Confirming a system suggestion is *this* command with the factor's
/// provenance set to `accepted` — there is no separate "accept" endpoint,
/// because the confirmation is a factor write like any other and must be
/// audited as one.
class UpsertValuationFactorsCommand {
  const UpsertValuationFactorsCommand({
    required this.context,
    required this.valuationCaseId,
    required this.expectedVersion,
    required this.factors,
    this.removeFactorIds = const [],
  });

  final ValuationCommandContext context;
  final String valuationCaseId;
  final int expectedVersion;
  final List<ValuationFactorDto> factors;

  /// Factor ids to drop. Removing a factor makes the dependent methods report
  /// "nicht ermittelbar" again — which is the honest outcome, not a regression.
  final List<String> removeFactorIds;
}

/// Copies a case into a named sibling variant (`DEC-023`).
///
/// The command carries no factors and no report: the server copies the source's
/// configuration and factors, and deliberately leaves the report behind — a
/// variant that arrived with somebody else's published result would be a
/// borrowed number.
class CreateValuationVariantCommand {
  const CreateValuationVariantCommand({
    required this.context,
    required this.sourceValuationCaseId,
    required this.variantLabel,
    this.sourceVariantLabel = 'Basis',
    this.title,
  });

  final ValuationCommandContext context;
  final String sourceValuationCaseId;

  /// Name of the new variant inside the group.
  final String variantLabel;

  /// Name the source takes when this call is what forms the group. Ignored once
  /// the source already belongs to one.
  final String sourceVariantLabel;

  /// Null keeps the source's title.
  final String? title;
}

class TransitionValuationCaseStatusCommand {
  const TransitionValuationCaseStatusCommand({
    required this.context,
    required this.valuationCaseId,
    required this.expectedVersion,
    required this.targetStatus,
  });

  final ValuationCommandContext context;
  final String valuationCaseId;
  final int expectedVersion;
  final ValuationCaseStatus targetStatus;
}

/// Stores a computed report: one row per method plus the reconciled opinion.
///
/// The engine is deterministic, so this is a projection of the case's factors at
/// a point in time rather than an independent input. It is versioned all the
/// same, so a report published against stale factors loses to the newer write
/// instead of silently overwriting it.
class PublishValuationReportCommand {
  const PublishValuationReportCommand({
    required this.context,
    required this.valuationCaseId,
    required this.expectedVersion,
    required this.report,
  });

  final ValuationCommandContext context;
  final String valuationCaseId;
  final int expectedVersion;
  final ValuationReport report;
}

// -----------------------------------------------------------------------------
// Results
// -----------------------------------------------------------------------------

enum ValuationRepositoryFailureKind {
  notFound,
  forbidden,
  validationFailed,
  versionConflict,
  mutationConflict,
  mutationInProgress,

  /// The case is `approved` (or `archived`) and no longer accepts edits —
  /// `AGG-014`. Distinct from [forbidden]: the caller may well hold the
  /// permission; the *record* is closed.
  approvedImmutable,

  /// The selected backend cannot honour this part of the contract at all. The
  /// legacy SQLite store returns this for every mutation: it has no version
  /// token, no mutation receipt and no audited command envelope, so writing
  /// would silently drop the concurrency, idempotency and audit guarantees the
  /// contract promises. Distinct from [forbidden] and [validationFailed] —
  /// nothing about the caller or the payload is wrong.
  unsupportedByBackend,
  infrastructureFailure,
}

class ValuationVersionConflict {
  const ValuationVersionConflict({
    required this.expectedVersion,
    required this.actualVersion,
    this.currentCase,
  });

  final int expectedVersion;
  final int actualVersion;
  final ValuationCaseDto? currentCase;
}

sealed class ValuationRepositoryResult<T> {
  const ValuationRepositoryResult();
}

class ValuationRepositorySuccess<T> extends ValuationRepositoryResult<T> {
  const ValuationRepositorySuccess(this.value);

  final T value;
}

class ValuationRepositoryFailure<T> extends ValuationRepositoryResult<T> {
  const ValuationRepositoryFailure({
    required this.kind,
    required this.message,
    this.versionConflict,
  }) : assert(
         kind == ValuationRepositoryFailureKind.versionConflict
             ? versionConflict != null
             : versionConflict == null,
       );

  final ValuationRepositoryFailureKind kind;
  final String message;
  final ValuationVersionConflict? versionConflict;
}

// -----------------------------------------------------------------------------
// Ports
// -----------------------------------------------------------------------------

/// The valuation aggregate and its lifecycle. Reads are server-authorized on
/// `valuation.read`; mutations run through the audited RPC envelope only.
abstract interface class ValuationCaseRepository {
  Future<ValuationRepositoryResult<ValuationPageResult<ValuationCaseDto>>>
  searchValuationCases(ValuationCaseListQuery query);

  Future<ValuationRepositoryResult<ValuationCaseDetail>> getValuationCaseById({
    required String workspaceId,
    required String valuationCaseId,
  });

  Future<ValuationRepositoryResult<ValuationCaseDetail>> createValuationCase(
    CreateValuationCaseCommand command,
  );

  Future<ValuationRepositoryResult<ValuationCaseDetail>> updateValuationCase(
    UpdateValuationCaseCommand command,
  );

  /// Creates a sibling variant of an existing case. The returned detail is the
  /// new variant — a draft with the source's factors and no report of its own.
  Future<ValuationRepositoryResult<ValuationCaseDetail>> createValuationVariant(
    CreateValuationVariantCommand command,
  );

  /// Approving requires `valuation.approve`; the server rejects any transition
  /// that [ValuationCaseStatus.canTransitionTo] forbids with
  /// [ValuationRepositoryFailureKind.validationFailed].
  Future<ValuationRepositoryResult<ValuationCaseDto>>
  transitionValuationCaseStatus(TransitionValuationCaseStatusCommand command);
}

/// The provenance-tagged factors of a case.
abstract interface class ValuationFactorPort {
  Future<ValuationRepositoryResult<List<ValuationFactorDto>>> listFactors({
    required String workspaceId,
    required String valuationCaseId,
  });

  Future<ValuationRepositoryResult<List<ValuationFactorDto>>> upsertFactors(
    UpsertValuationFactorsCommand command,
  );
}

/// The computed method results and the reconciled Verkehrswert.
abstract interface class ValuationReportPort {
  /// The last published report of a case, or
  /// [ValuationRepositoryFailureKind.notFound] when none exists — never an
  /// empty stand-in report.
  Future<ValuationRepositoryResult<ValuationReportSnapshot>> latestReport({
    required String workspaceId,
    required String valuationCaseId,
  });

  Future<ValuationRepositoryResult<ValuationReportSnapshot>> publishReport(
    PublishValuationReportCommand command,
  );
}
