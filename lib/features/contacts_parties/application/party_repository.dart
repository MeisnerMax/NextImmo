/// Backend-agnostic contacts_parties contract (P2-D02, DOM-003).
///
/// Four ports mirror the module contract: [PartyRepository] (identity
/// lifecycle + merge), [PartySearchPort] (keyset search / role-scoped reads),
/// [PartyRoleRepository] (time-boundable roles + contractor satellite) and
/// [DuplicateDetectionPort]. All mutations are workspace-scoped, permission-
/// gated server-side (`party.read`/`party.manage`, no AAL2 — parties are
/// ordinary business data), idempotent (`mutationId`), versioned
/// (`expectedVersion` where a row is edited) and audited append-only — the
/// same envelope as the property contract.
library;

import '../domain/party_dto.dart';
import '../domain/supplier_contract_dto.dart';

class PartyCommandContext {
  const PartyCommandContext({
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

class PartyPageRequest {
  const PartyPageRequest({this.limit = 50, this.cursor})
    : assert(limit > 0 && limit <= 100);

  final int limit;
  final String? cursor;
}

/// A workspace-scoped party search. [roleType] restricts to parties holding an
/// open role of that type (the role-scoped read); [includeMerged] surfaces
/// tombstoned/merged parties for an audit view.
class PartyListQuery {
  const PartyListQuery({
    required this.workspaceId,
    this.roleType,
    this.page = const PartyPageRequest(),
    this.includeMerged = false,
  });

  final String workspaceId;
  final PartyRoleType? roleType;
  final PartyPageRequest page;
  final bool includeMerged;
}

class PartyPageResult {
  const PartyPageResult({required this.items, this.nextCursor});

  final List<PartySummaryDto> items;
  final String? nextCursor;
}

class CreatePartyCommand {
  const CreatePartyCommand({required this.context, required this.draft});

  final PartyCommandContext context;
  final PartyDraft draft;
}

class UpdatePartyCommand {
  const UpdatePartyCommand({
    required this.context,
    required this.partyId,
    required this.expectedVersion,
    required this.changes,
  });

  final PartyCommandContext context;
  final String partyId;
  final int expectedVersion;
  final PartyUpdateDto changes;
}

class MergePartiesCommand {
  const MergePartiesCommand({
    required this.context,
    required this.targetPartyId,
    required this.sourcePartyId,
    required this.expectedTargetVersion,
    required this.expectedSourceVersion,
  });

  final PartyCommandContext context;
  final String targetPartyId;
  final String sourcePartyId;
  final int expectedTargetVersion;
  final int expectedSourceVersion;
}

class AssignPartyRoleCommand {
  const AssignPartyRoleCommand({
    required this.context,
    required this.partyId,
    required this.roleType,
    this.validFrom,
    this.validUntil,
    this.contractorDetails,
  }) : assert(
         contractorDetails == null || roleType == PartyRoleType.contractor,
         'Role details apply to the contractor role only.',
       );

  final PartyCommandContext context;
  final String partyId;
  final PartyRoleType roleType;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final ContractorDetailsInput? contractorDetails;
}

/// Corrects a contractor's details (`SUPPLIER-DETAILS-01`, P-3).
///
/// A patch, not a replacement: only the fields present in [changes] are
/// written, and a field mapped to null is *cleared*. That distinction is the
/// reason this is a map rather than a `ContractorDetailsInput` — "no agreed
/// rate any more" and "leave the rate as it is" are different intents, and a
/// nullable field on an input object cannot express both.
///
/// Separate from [AssignPartyRoleCommand] because correcting a rate is not
/// granting a role. Sending it through the assignment would put
/// `party.role.assign` in the audit trail, which is a statement about who this
/// company is to the workspace rather than about a typo in a number.
class UpdateContractorDetailsCommand {
  const UpdateContractorDetailsCommand({
    required this.context,
    required this.partyId,
    required this.expectedVersion,
    required this.changes,
  }) : assert(changes.length > 0, 'an empty change set is not a command');

  final PartyCommandContext context;
  final String partyId;

  /// The satellite's own version, which the role-assignment path never checked.
  final int expectedVersion;

  /// Server field names to values. Use [contractorDetailChanges] to build one
  /// rather than spelling the keys at a call site.
  final Map<String, Object?> changes;
}

/// Builds a change set without spelling server field names at a call site.
///
/// Every parameter takes a sentinel default so "not mentioned" and "set to
/// null" stay distinguishable — the whole point of a patch. Passing
/// `hourlyRate: null` clears the rate; omitting it leaves the rate alone.
const Object unchangedContractorField = Object();

Map<String, Object?> contractorDetailChanges({
  Object? tradeCategory = unchangedContractorField,
  Object? hourlyRate = unchangedContractorField,
  Object? serviceArea = unchangedContractorField,
  Object? ratingPrice = unchangedContractorField,
  Object? ratingQuality = unchangedContractorField,
  Object? ratingSpeed = unchangedContractorField,
  Object? ratingCommunication = unchangedContractorField,
  Object? ratingPunctuality = unchangedContractorField,
  Object? insuranceCertExpiry = unchangedContractorField,
  Object? isActive = unchangedContractorField,
}) {
  final changes = <String, Object?>{};
  void put(String key, Object? value) {
    if (!identical(value, unchangedContractorField)) {
      changes[key] = value;
    }
  }

  put('trade_category', tradeCategory);
  put('hourly_rate', hourlyRate);
  put('service_area', serviceArea);
  put('rating_price', ratingPrice);
  put('rating_quality', ratingQuality);
  put('rating_speed', ratingSpeed);
  put('rating_communication', ratingCommunication);
  put('rating_punctuality', ratingPunctuality);
  put('insurance_cert_expiry', insuranceCertExpiry);
  put('is_active', isActive);
  return Map<String, Object?>.unmodifiable(changes);
}

class EndPartyRoleCommand {
  const EndPartyRoleCommand({
    required this.context,
    required this.partyRoleId,
    required this.expectedVersion,
    this.validUntil,
  });

  final PartyCommandContext context;
  final String partyRoleId;
  final int expectedVersion;
  final DateTime? validUntil;
}

class PartyDuplicateQuery {
  const PartyDuplicateQuery({
    required this.workspaceId,
    this.displayName,
    this.email,
    this.phone,
  }) : assert(
         displayName != null || email != null || phone != null,
         'At least one probe attribute is required.',
       );

  final String workspaceId;
  final String? displayName;
  final String? email;
  final String? phone;
}

enum PartyRepositoryFailureKind {
  notFound,
  forbidden,
  validationFailed,
  versionConflict,
  mutationConflict,
  mutationInProgress,
  dependencyConflict,
  infrastructureFailure,
}

/// Structured optimistic-concurrency conflict. Exactly one of
/// [currentParty]/[currentRole]/[currentContractorDetails] is set, matching the
/// entity the failed command targeted.
///
/// The third slot exists because `SUPPLIER-DETAILS-01` conflicts on the
/// contractor satellite, which is neither a party nor a role. Without it the
/// conflict could only say that the form was stale, not what it would have
/// overwritten -- and a form that cannot show the other value leaves the
/// reader to guess whether their edit still applies.
class PartyVersionConflict {
  const PartyVersionConflict({
    required this.expectedVersion,
    required this.actualVersion,
    this.currentParty,
    this.currentRole,
    this.currentContractorDetails,
  }) : assert(
         (currentParty != null ? 1 : 0) +
                 (currentRole != null ? 1 : 0) +
                 (currentContractorDetails != null ? 1 : 0) ==
             1,
       );

  final int expectedVersion;
  final int actualVersion;
  final PartyDto? currentParty;
  final PartyRoleDto? currentRole;
  final ContractorDetailsDto? currentContractorDetails;
}

sealed class PartyRepositoryResult<T> {
  const PartyRepositoryResult();
}

class PartyRepositorySuccess<T> extends PartyRepositoryResult<T> {
  const PartyRepositorySuccess(this.value);

  final T value;
}

class PartyRepositoryFailure<T> extends PartyRepositoryResult<T> {
  const PartyRepositoryFailure({
    required this.kind,
    required this.message,
    this.versionConflict,
  }) : assert(
         kind == PartyRepositoryFailureKind.versionConflict
             ? versionConflict != null
             : versionConflict == null,
       );

  final PartyRepositoryFailureKind kind;
  final String message;
  final PartyVersionConflict? versionConflict;
}

/// Canonical party identity lifecycle: create, edit and merge. Reads are
/// server-authorized on `party.read`; mutations run through the audited RPC
/// envelope only.
abstract interface class PartyRepository {
  Future<PartyRepositoryResult<PartyDto>> getById({
    required String workspaceId,
    required String partyId,
  });

  Future<PartyRepositoryResult<PartyDto>> create(CreatePartyCommand command);

  Future<PartyRepositoryResult<PartyDto>> update(UpdatePartyCommand command);

  /// Fold [MergePartiesCommand.sourcePartyId] into the target, keeping the
  /// source's roles (re-pointed and closed), alias and audit history. Returns
  /// the surviving target.
  Future<PartyRepositoryResult<PartyDto>> merge(MergePartiesCommand command);
}

/// Keyset-paginated, optionally role-scoped party search.
abstract interface class PartySearchPort {
  Future<PartyRepositoryResult<PartyPageResult>> search(PartyListQuery query);
}

/// Time-boundable functional roles and the contractor satellite.
/// Supplier and utility contracts (`SUPPLIER-CONTRACTS-01`, P-3).
///
/// Its own port beside [PartyRoleRepository] rather than more methods on it: a
/// role says what a party *is* to the workspace, and a contract is a thing
/// agreed *with* them. They have different lifecycles and only share a
/// counterparty.
class SupplierContractsQuery {
  const SupplierContractsQuery({
    required this.workspaceId,
    this.asOfDate,
    this.partyId,
    this.propertyId,
    this.includeEnded = false,
  });

  final String workspaceId;

  /// The date the deadlines are computed against. Null lets the server use its
  /// own today, and the answer states which date it used.
  final DateTime? asOfDate;

  final String? partyId;
  final String? propertyId;

  /// Ended contracts are out by default. "What did we agree with them before"
  /// is a real question, just not the one a worklist asks.
  final bool includeEnded;
}

class CreateSupplierContractCommand {
  const CreateSupplierContractCommand({
    required this.context,
    required this.partyId,
    required this.title,
    required this.contractType,
    required this.startDate,
    this.propertyId,
    this.scopeNote,
    this.endDate,
    this.noticePeriodDays,
    this.autoRenew = false,
    this.renewalTermMonths,
    this.annualValue,
    this.currencyCode,
  });

  final PartyCommandContext context;
  final String partyId;
  final String? propertyId;
  final String title;
  final String contractType;
  final String? scopeNote;
  final DateTime startDate;
  final DateTime? endDate;
  final int? noticePeriodDays;
  final bool autoRenew;
  final int? renewalTermMonths;
  final double? annualValue;
  final String? currencyCode;
}

/// A patch, like the contractor details command: a field not mentioned keeps
/// its value, one mapped to null is cleared.
///
/// `status` may move between `draft` and `active` and nothing else. Ending has
/// its own command, which demands a reason and stamps the date — and a
/// terminal state reachable through a field edit is how "why did we drop them"
/// becomes unanswerable.
class UpdateSupplierContractCommand {
  const UpdateSupplierContractCommand({
    required this.context,
    required this.contractId,
    required this.expectedVersion,
    required this.changes,
  }) : assert(changes.length > 0, 'an empty change set is not a command');

  final PartyCommandContext context;
  final String contractId;
  final int expectedVersion;
  final Map<String, Object?> changes;
}

class EndSupplierContractCommand {
  const EndSupplierContractCommand({
    required this.context,
    required this.contractId,
    required this.expectedVersion,
    required this.endedReason,
  });

  final PartyCommandContext context;
  final String contractId;
  final int expectedVersion;

  /// Required, unlike the optional command reason. Why a supplier relationship
  /// ended is what somebody wants to know in two years.
  final String endedReason;
}

/// The methods carry `Contract` in their names rather than being `create`,
/// `update` and `end`.
///
/// Not decoration: the Supabase adapter implements four of these ports on one
/// class, and `PartyRepository` and `PartyRoleRepository` already own those
/// three verbs. Generic names would have collided, and the collision does not
/// surface as a naming complaint — it surfaces as `CreatePartyCommand` no
/// longer being assignable, in files that have nothing to do with contracts.
abstract interface class SupplierContractsPort {
  Future<PartyRepositoryResult<SupplierContractSetDto>> listContracts(
    SupplierContractsQuery query,
  );

  Future<PartyRepositoryResult<SupplierContractDto>> createContract(
    CreateSupplierContractCommand command,
  );

  Future<PartyRepositoryResult<SupplierContractDto>> updateContract(
    UpdateSupplierContractCommand command,
  );

  Future<PartyRepositoryResult<SupplierContractDto>> endContract(
    EndSupplierContractCommand command,
  );
}

abstract interface class PartyRoleRepository {
  Future<PartyRepositoryResult<List<PartyRoleDto>>> listForParty({
    required String workspaceId,
    required String partyId,
  });

  /// The contractor satellite for [partyId], or a success carrying `null` when
  /// the party holds no contractor details.
  Future<PartyRepositoryResult<ContractorDetailsDto?>> getContractorDetails({
    required String workspaceId,
    required String partyId,
  });

  Future<PartyRepositoryResult<PartyRoleDto>> assign(
    AssignPartyRoleCommand command,
  );

  /// Corrects the contractor satellite (`SUPPLIER-DETAILS-01`).
  ///
  /// Optimistic concurrency on the satellite's own version, which [assign]
  /// cannot check: the caller there is granting a role, and demanding the
  /// satellite's version for that would be asking about the wrong thing.
  Future<PartyRepositoryResult<ContractorDetailsDto>> updateContractorDetails(
    UpdateContractorDetailsCommand command,
  );

  Future<PartyRepositoryResult<PartyRoleDto>> end(EndPartyRoleCommand command);
}

/// Read-only duplicate detection over normalized email / phone / display name.
abstract interface class DuplicateDetectionPort {
  Future<PartyRepositoryResult<List<PartyDuplicateCandidate>>> detect(
    PartyDuplicateQuery query,
  );
}
