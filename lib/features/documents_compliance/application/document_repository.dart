/// Backend-agnostic documents_compliance contract (P2-D03, DOM-006).
///
/// Six ports mirror the module contract: [DocumentRepository] (aggregate
/// lifecycle and STM-008 transitions), [DocumentContentPort] (immutable
/// versions and upload confirmation), [DocumentLinkPort] (EntityRef links),
/// [RequirementPolicyRepository] (requirement rules plus the derived DUP-011
/// projection), [DocumentVerificationPort] and [SignedUrlPort].
///
/// All mutations are workspace-scoped, permission-gated server-side
/// (`document.read` / `document.manage` / `document.verify`; no AAL2 — like
/// parties and properties, documents are ordinary workspace business data),
/// idempotent (`mutationId`), versioned (`expectedVersion`) and audited
/// append-only.
///
/// Content bytes never cross this contract. A version points at an object in a
/// private Storage bucket, and download access is a short-lived signed URL.
library;

import '../domain/document_dto.dart';

class DocumentCommandContext {
  const DocumentCommandContext({
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

class DocumentPageRequest {
  const DocumentPageRequest({this.limit = 50, this.cursor})
    : assert(limit > 0 && limit <= 100);

  final int limit;
  final String? cursor;
}

/// A workspace-scoped document search. [entityType]/[entityId] restrict to
/// documents linked to that entity; [includeInactive] surfaces superseded and
/// archived documents for an audit view.
class DocumentListQuery {
  const DocumentListQuery({
    required this.workspaceId,
    this.entityType,
    this.entityId,
    this.documentTypeId,
    this.page = const DocumentPageRequest(),
    this.includeInactive = false,
  }) : assert(
         (entityType == null) == (entityId == null),
         'An entity filter needs both a type and an id.',
       );

  final String workspaceId;
  final DocumentLinkEntityType? entityType;
  final String? entityId;
  final String? documentTypeId;
  final DocumentPageRequest page;
  final bool includeInactive;
}

class DocumentPageResult {
  const DocumentPageResult({required this.items, this.nextCursor});

  final List<DocumentDto> items;
  final String? nextCursor;
}

class CreateDocumentCommand {
  const CreateDocumentCommand({required this.context, required this.draft});

  final DocumentCommandContext context;
  final DocumentDraft draft;
}

class AddDocumentVersionCommand {
  const AddDocumentVersionCommand({
    required this.context,
    required this.documentId,
    required this.expectedVersion,
    required this.content,
  });

  final DocumentCommandContext context;
  final String documentId;
  final int expectedVersion;
  final DocumentContentDraft content;
}

/// Verify that the declared object really landed in the private bucket before
/// the document is published (MIG-BND-003). A mismatch is not an error: the
/// server drives the STM-008 error path to `rejected` and returns success with
/// that status, so callers must inspect [DocumentDto.status].
class ConfirmDocumentContentCommand {
  const ConfirmDocumentContentCommand({
    required this.context,
    required this.documentId,
    required this.versionNo,
    required this.expectedVersion,
  });

  final DocumentCommandContext context;
  final String documentId;
  final int versionNo;
  final int expectedVersion;
}

enum DocumentVerificationOutcome {
  verified('verified'),
  rejected('rejected');

  const DocumentVerificationOutcome(this.wireName);

  final String wireName;
}

class VerifyDocumentVersionCommand {
  const VerifyDocumentVersionCommand({
    required this.context,
    required this.documentId,
    required this.versionNo,
    required this.expectedVersion,
    required this.outcome,
    this.note,
  });

  final DocumentCommandContext context;
  final String documentId;
  final int versionNo;
  final int expectedVersion;
  final DocumentVerificationOutcome outcome;
  final String? note;
}

/// The commandable half of STM-008. `available`/`verified`/`rejected` are
/// produced by the content and verification commands instead, and `processing`
/// by no command yet.
enum DocumentStatusTransition {
  supersede('superseded'),
  archive('archived');

  const DocumentStatusTransition(this.wireName);

  final String wireName;
}

class TransitionDocumentStatusCommand {
  const TransitionDocumentStatusCommand({
    required this.context,
    required this.documentId,
    required this.expectedVersion,
    required this.transition,
    this.supersededByDocumentId,
  }) : assert(
         (transition == DocumentStatusTransition.supersede) ==
             (supersededByDocumentId != null),
         'Superseding needs a successor; archiving takes none.',
       );

  final DocumentCommandContext context;
  final String documentId;
  final int expectedVersion;
  final DocumentStatusTransition transition;
  final String? supersededByDocumentId;
}

class LinkDocumentCommand {
  const LinkDocumentCommand({
    required this.context,
    required this.documentId,
    required this.entityType,
    required this.entityId,
    this.linkRole,
  });

  final DocumentCommandContext context;
  final String documentId;
  final DocumentLinkEntityType entityType;
  final String entityId;
  final String? linkRole;
}

class UnlinkDocumentCommand {
  const UnlinkDocumentCommand({
    required this.context,
    required this.documentLinkId,
  });

  final DocumentCommandContext context;
  final String documentLinkId;
}

class UpsertDocumentTypeCommand {
  const UpsertDocumentTypeCommand({required this.context, required this.draft});

  final DocumentCommandContext context;
  final DocumentTypeDraft draft;
}

class UpsertRequiredDocumentCommand {
  const UpsertRequiredDocumentCommand({
    required this.context,
    required this.draft,
  });

  final DocumentCommandContext context;
  final RequiredDocumentDraft draft;
}

class DocumentRequirementQuery {
  const DocumentRequirementQuery({
    required this.workspaceId,
    required this.entityType,
    required this.entityId,
    this.scopeKey,
  });

  final String workspaceId;
  final DocumentLinkEntityType entityType;
  final String entityId;
  final String? scopeKey;
}

/// Workspace-wide requirement evaluation (P2-D03 follow-up increment).
///
/// The per-entity [DocumentRequirementQuery] cannot serve a compliance view
/// over the whole workspace: fanning it out is the N+1 this wave removes, and
/// rebuilding the derivation client-side would be the second truth `DUP-011`
/// forbids. So the derivation stays server-side and gains this entry point.
///
/// [entityIds] is how the caller contributes entities this module cannot
/// discover on its own. DOM-006 declares no dependency on DOM-002, so the
/// server must not look up which properties exist; passing ids across the
/// module boundary is explicitly allowed, and they travel in **one** call.
class WorkspaceDocumentRequirementQuery {
  const WorkspaceDocumentRequirementQuery({
    required this.workspaceId,
    this.entityType,
    this.entityIds = const <String>[],
    this.onlyUnmet = false,
  });

  final String workspaceId;

  /// Restricts the evaluation to one entity type. Null evaluates every type
  /// that has rules.
  final DocumentLinkEntityType? entityType;

  /// Ids only mean something together with [entityType]; supplying them without
  /// one is rejected with [DocumentRepositoryFailureKind.validationFailed] by
  /// both backends rather than silently evaluating nothing. (Not a constructor
  /// assert: this type is constructed in `const` contexts, where a list's
  /// length cannot be inspected.)
  final List<String> entityIds;

  /// Drops requirements that are already satisfied or waived — what a
  /// compliance surface actually shows.
  final bool onlyUnmet;
}

/// The workspace-wide projection plus what it could not evaluate.
///
/// Per-entity evaluation narrows rules by `scopeKey`; workspace-wide there is
/// no per-entity scope key to match without importing portfolio vocabulary into
/// DOM-006. Scoped rules are therefore left to the per-entity projection and
/// **counted** here rather than dropped silently, so a caller can say what it
/// did not cover instead of implying full coverage.
class WorkspaceDocumentRequirements {
  const WorkspaceDocumentRequirements({
    required this.requirements,
    required this.scopedRuleCount,
  });

  final List<DocumentRequirementProjection> requirements;
  final int scopedRuleCount;

  bool get hasUnevaluatedScopedRules => scopedRuleCount > 0;

  List<DocumentRequirementProjection> get blocking =>
      requirements
          .where((requirement) => requirement.isBlocking)
          .toList(growable: false);
}

enum DocumentRepositoryFailureKind {
  notFound,
  forbidden,
  validationFailed,
  versionConflict,
  mutationConflict,
  mutationInProgress,
  dependencyConflict,
  infrastructureFailure,
}

/// Structured optimistic-concurrency conflict. Every versioned document command
/// carries the document's own `expectedVersion`, so the conflict always reports
/// the current document — unlike the party contract, versions and links are
/// never independently versioned by the caller.
class DocumentVersionConflict {
  const DocumentVersionConflict({
    required this.expectedVersion,
    required this.actualVersion,
    required this.currentDocument,
  });

  final int expectedVersion;
  final int actualVersion;
  final DocumentDto currentDocument;
}

sealed class DocumentRepositoryResult<T> {
  const DocumentRepositoryResult();
}

class DocumentRepositorySuccess<T> extends DocumentRepositoryResult<T> {
  const DocumentRepositorySuccess(this.value);

  final T value;
}

class DocumentRepositoryFailure<T> extends DocumentRepositoryResult<T> {
  const DocumentRepositoryFailure({
    required this.kind,
    required this.message,
    this.versionConflict,
  }) : assert(
         kind == DocumentRepositoryFailureKind.versionConflict
             ? versionConflict != null
             : versionConflict == null,
       );

  final DocumentRepositoryFailureKind kind;
  final String message;
  final DocumentVersionConflict? versionConflict;
}

/// Document aggregate lifecycle and the commandable STM-008 transitions. Reads
/// are server-authorized on `document.read`; mutations run through the audited
/// RPC envelope only.
abstract interface class DocumentRepository {
  Future<DocumentRepositoryResult<DocumentDto>> getById({
    required String workspaceId,
    required String documentId,
  });

  Future<DocumentRepositoryResult<DocumentPageResult>> search(
    DocumentListQuery query,
  );

  /// Register a document and its first content version. The object must already
  /// be uploaded to the private bucket; the document stays `uploaded` until
  /// [DocumentContentPort.confirmContent] verifies it.
  Future<DocumentRepositoryResult<DocumentDto>> create(
    CreateDocumentCommand command,
  );

  Future<DocumentRepositoryResult<DocumentDto>> transitionStatus(
    TransitionDocumentStatusCommand command,
  );
}

/// Immutable content versions. Adding a version never overwrites the previous
/// one — it is marked superseded in place, keeping its path, hash, size and
/// verification outcome.
abstract interface class DocumentContentPort {
  Future<DocumentRepositoryResult<List<DocumentVersionDto>>> listVersions({
    required String workspaceId,
    required String documentId,
  });

  Future<DocumentRepositoryResult<DocumentVersionDto>> addVersion(
    AddDocumentVersionCommand command,
  );

  /// Confirm the upload. Succeeds in both outcomes: inspect
  /// [DocumentDto.status] for `available` versus `rejected`.
  Future<DocumentRepositoryResult<DocumentDto>> confirmContent(
    ConfirmDocumentContentCommand command,
  );
}

/// EntityRef links. Linking to a domain that has not been migrated yet fails
/// with [DocumentRepositoryFailureKind.dependencyConflict] rather than creating
/// a dangling reference.
abstract interface class DocumentLinkPort {
  Future<DocumentRepositoryResult<List<DocumentLinkDto>>> listLinks({
    required String workspaceId,
    required String documentId,
  });

  Future<DocumentRepositoryResult<DocumentLinkDto>> link(
    LinkDocumentCommand command,
  );

  Future<DocumentRepositoryResult<DocumentLinkDto>> unlink(
    UnlinkDocumentCommand command,
  );
}

/// Requirement rules plus the derived DUP-011 projection. The workspace type
/// registry lives here too: types define which requirements can exist, and
/// DOM-006 names exactly six ports, so they do not get a seventh.
abstract interface class RequirementPolicyRepository {
  Future<DocumentRepositoryResult<List<DocumentTypeDto>>> listTypes({
    required String workspaceId,
    bool activeOnly = true,
  });

  Future<DocumentRepositoryResult<DocumentTypeDto>> upsertType(
    UpsertDocumentTypeCommand command,
  );

  Future<DocumentRepositoryResult<List<RequiredDocumentDto>>> listRequirements({
    required String workspaceId,
    required DocumentLinkEntityType entityType,
    String? entityId,
  });

  Future<DocumentRepositoryResult<RequiredDocumentDto>> upsertRequirement(
    UpsertRequiredDocumentCommand command,
  );

  /// The consolidated checklist/compliance view: one row per live rule with a
  /// derived state. Nothing here is stored.
  Future<DocumentRepositoryResult<List<DocumentRequirementProjection>>> evaluate(
    DocumentRequirementQuery query,
  );

  /// The same derivation across a whole workspace, in one call. Shares its state
  /// derivation with [evaluate] server-side, so the two can never disagree.
  Future<DocumentRepositoryResult<WorkspaceDocumentRequirements>>
  evaluateWorkspace(WorkspaceDocumentRequirementQuery query);
}

/// Verification of one immutable version, gated by the separate
/// `document.verify` permission. Verifying never touches validity: an expired
/// document can still be verified, and a verified one can still expire.
abstract interface class DocumentVerificationPort {
  Future<DocumentRepositoryResult<DocumentVersionDto>> verify(
    VerifyDocumentVersionCommand command,
  );
}

/// Short-lived download access to a private-bucket object.
///
/// Implementations MUST clamp the requested TTL into
/// [minTtl]..[maxTtl] and report what they actually applied via
/// [SignedDocumentUrl.appliedTtl], so a caller can never widen the window by
/// asking for more.
abstract interface class SignedUrlPort {
  /// Confirmed default (2026-07-23): short enough that a leaked URL is worth
  /// little, long enough to download a large file.
  static const Duration defaultTtl = Duration(minutes: 5);

  /// Confirmed server-side ceiling (2026-07-23).
  static const Duration maxTtl = Duration(hours: 1);

  static const Duration minTtl = Duration(seconds: 1);

  /// Clamp helper shared by every implementation and by the tests, so the
  /// policy lives in exactly one place.
  static Duration clampTtl(Duration? requested) {
    final ttl = requested ?? defaultTtl;
    if (ttl < minTtl) return minTtl;
    if (ttl > maxTtl) return maxTtl;
    return ttl;
  }

  /// Resolve storage coordinates for a version after a server-side permission
  /// check. Passing a null [versionNo] resolves the current version.
  Future<DocumentRepositoryResult<DocumentContentRef>> resolveContentRef({
    required String workspaceId,
    required String documentId,
    int? versionNo,
  });

  /// Mint a signed download URL. [ttl] is clamped; omit it for [defaultTtl].
  Future<DocumentRepositoryResult<SignedDocumentUrl>> createSignedUrl({
    required String workspaceId,
    required String documentId,
    int? versionNo,
    Duration? ttl,
  });
}
