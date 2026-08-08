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
/// [currentParty]/[currentRole] is set, matching the entity the failed command
/// targeted.
class PartyVersionConflict {
  const PartyVersionConflict({
    required this.expectedVersion,
    required this.actualVersion,
    this.currentParty,
    this.currentRole,
  }) : assert((currentParty != null) != (currentRole != null));

  final int expectedVersion;
  final int actualVersion;
  final PartyDto? currentParty;
  final PartyRoleDto? currentRole;
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

  Future<PartyRepositoryResult<PartyRoleDto>> end(EndPartyRoleCommand command);
}

/// Read-only duplicate detection over normalized email / phone / display name.
abstract interface class DuplicateDetectionPort {
  Future<PartyRepositoryResult<List<PartyDuplicateCandidate>>> detect(
    PartyDuplicateQuery query,
  );
}
