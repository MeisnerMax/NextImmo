/// documents_compliance DTOs (P2-D03, DOM-006).
///
/// These mirror the cloud contract one-to-one and carry no SDK types. Content
/// bytes never appear here: a document version references a private Storage
/// object by bucket and path, and access is minted as a short-lived signed URL
/// (`SignedUrlPort`), replacing the legacy local `file_path` (DEBT-007).
library;

/// STM-008. `processing` is part of the contract vocabulary but no server
/// command produces it yet — it is reserved for an asynchronous scan/extract
/// pipeline, and that gap is documented rather than faked.
enum DocumentStatus {
  uploaded('uploaded'),
  processing('processing'),
  available('available'),
  verified('verified'),
  superseded('superseded'),
  archived('archived'),
  rejected('rejected');

  const DocumentStatus(this.wireName);

  final String wireName;

  static DocumentStatus? fromWire(String? value) {
    for (final status in DocumentStatus.values) {
      if (status.wireName == value) return status;
    }
    return null;
  }

  /// Whether the document still participates in active reads and requirement
  /// fulfilment. Mirrors the server-side exclusion in
  /// `evaluate_document_requirements`.
  bool get isActive =>
      this != DocumentStatus.superseded && this != DocumentStatus.archived;
}

/// Verification is tracked per immutable version and is deliberately separate
/// from validity/expiry ("Ablauf und Verifikation sind getrennt").
enum DocumentVerificationStatus {
  pending('pending'),
  verified('verified'),
  rejected('rejected');

  const DocumentVerificationStatus(this.wireName);

  final String wireName;

  static DocumentVerificationStatus? fromWire(String? value) {
    for (final status in DocumentVerificationStatus.values) {
      if (status.wireName == value) return status;
    }
    return null;
  }
}

/// The controlled `EntityRef` registry replacing the legacy polymorphic
/// `entity_type` free text (DEBT-006). Values whose owning domain has not been
/// migrated yet are rejected server-side with `dependencyConflict`.
enum DocumentLinkEntityType {
  workspace('workspace'),
  property('property'),
  portfolio('portfolio'),
  unit('unit'),
  lease('lease'),
  party('party'),
  maintenanceTicket('maintenance_ticket'),
  capexProject('capex_project'),
  scenario('scenario');

  const DocumentLinkEntityType(this.wireName);

  final String wireName;

  static DocumentLinkEntityType? fromWire(String? value) {
    for (final type in DocumentLinkEntityType.values) {
      if (type.wireName == value) return type;
    }
    return null;
  }

  /// Domains that already exist in the cloud schema. The server is the
  /// authority; this only lets callers avoid an obviously doomed round trip.
  bool get isMigratedDomain =>
      this == DocumentLinkEntityType.workspace ||
      this == DocumentLinkEntityType.property ||
      this == DocumentLinkEntityType.party;
}

/// The derived requirement state (DUP-011 projection). Never stored — the
/// server computes it per read from requirement rules plus linked documents.
/// The vocabulary is the lossless union of the legacy compliance model
/// (`available`/`expiring`/`verified`) and the legacy property onboarding
/// checklist (`vorhanden`/`fehlt`/`angefordert`/`nicht_relevant`).
enum DocumentRequirementState {
  /// A linked, verified, unexpired document exists.
  satisfied('satisfied'),

  /// Content is confirmed but nobody has verified it yet.
  pendingVerification('pending_verification'),

  /// A version exists but its upload has not been confirmed yet.
  pendingContent('pending_content'),

  /// Valid, but within 45 days of its validity end (legacy window, carried
  /// over verbatim from `DocumentsRepo._resolveDocumentStatus`).
  expiring('expiring'),

  /// Past its validity end.
  expired('expired'),

  /// The satisfying document was rejected.
  rejected('rejected'),

  /// Legacy checklist "angefordert": requested but not delivered.
  requested('requested'),

  /// Legacy checklist "nicht_relevant": an explicit, audited waiver.
  waived('waived'),

  /// Legacy checklist "fehlt".
  missing('missing');

  const DocumentRequirementState(this.wireName);

  final String wireName;

  static DocumentRequirementState? fromWire(String? value) {
    for (final state in DocumentRequirementState.values) {
      if (state.wireName == value) return state;
    }
    return null;
  }

  /// Whether this state leaves a mandatory requirement unmet.
  bool get isOutstanding =>
      this == DocumentRequirementState.missing ||
      this == DocumentRequirementState.requested ||
      this == DocumentRequirementState.expired ||
      this == DocumentRequirementState.rejected;
}

/// A workspace-scoped document type. Mirrors the legacy `document_types`
/// registry (a user-maintained table, not a fixed catalogue).
class DocumentTypeDto {
  const DocumentTypeDto({
    required this.id,
    required this.workspaceId,
    required this.key,
    required this.name,
    required this.entityType,
    required this.isActive,
    required this.version,
    this.defaultValidityMonths,
  });

  final String id;
  final String workspaceId;
  final String key;
  final String name;
  final DocumentLinkEntityType entityType;
  final bool isActive;
  final int version;
  final int? defaultValidityMonths;
}

class DocumentDto {
  const DocumentDto({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.status,
    required this.currentVersionNo,
    required this.version,
    this.documentTypeId,
    this.validFrom,
    this.validUntil,
    this.retentionUntil,
    this.supersededByDocumentId,
    this.archivedAt,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
    this.currentVersion,
  });

  final String id;
  final String workspaceId;
  final String title;
  final DocumentStatus status;

  /// 0 only in the impossible pre-version state; every created document ships
  /// with version 1 of its content.
  final int currentVersionNo;
  final int version;
  final String? documentTypeId;
  final DateTime? validFrom;
  final DateTime? validUntil;

  /// Informational only. Per the OPN-DOM-005 default there is no automatic
  /// deletion and no delete path — blocking access means archiving.
  final DateTime? retentionUntil;
  final String? supersededByDocumentId;
  final DateTime? archivedAt;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  /// Present on command results that carry the affected version inline.
  final DocumentVersionDto? currentVersion;

  bool get isExpired =>
      validUntil != null && validUntil!.isBefore(DateTime.now());
}

/// One immutable content version. Path, hash, size, mime type and filename are
/// locked server-side; only verification and supersede state ever change.
class DocumentVersionDto {
  const DocumentVersionDto({
    required this.id,
    required this.workspaceId,
    required this.documentId,
    required this.versionNo,
    required this.storageBucket,
    required this.storageObjectPath,
    required this.contentHash,
    required this.byteSize,
    required this.mimeType,
    required this.verificationStatus,
    required this.version,
    this.originalFilename,
    this.contentConfirmedAt,
    this.verifiedAt,
    this.verifiedBy,
    this.verificationNote,
    this.supersededAt,
    this.supersededByVersionNo,
  });

  final String id;
  final String workspaceId;
  final String documentId;
  final int versionNo;
  final String storageBucket;
  final String storageObjectPath;

  /// Lowercase hex sha256 of the stored bytes.
  final String contentHash;
  final int byteSize;
  final String mimeType;
  final DocumentVerificationStatus verificationStatus;
  final int version;
  final String? originalFilename;

  /// Set once the server has confirmed the object really exists in the private
  /// bucket with the declared size (MIG-BND-003).
  final DateTime? contentConfirmedAt;
  final DateTime? verifiedAt;
  final String? verifiedBy;
  final String? verificationNote;
  final DateTime? supersededAt;
  final int? supersededByVersionNo;

  bool get isContentConfirmed => contentConfirmedAt != null;

  bool get isSuperseded => supersededAt != null;
}

class DocumentLinkDto {
  const DocumentLinkDto({
    required this.id,
    required this.workspaceId,
    required this.documentId,
    required this.entityType,
    required this.entityId,
    this.linkRole,
    this.createdAt,
    this.createdBy,
  });

  final String id;
  final String workspaceId;
  final String documentId;
  final DocumentLinkEntityType entityType;
  final String entityId;
  final String? linkRole;
  final DateTime? createdAt;
  final String? createdBy;
}

/// A requirement rule. [entityId] null means a workspace-wide rule for the
/// entity type; set means an instance-level requirement — the consolidated
/// DUP-011 model, where both live in one table.
class RequiredDocumentDto {
  const RequiredDocumentDto({
    required this.id,
    required this.workspaceId,
    required this.entityType,
    required this.documentTypeId,
    required this.isMandatory,
    required this.version,
    this.entityId,
    this.scopeKey,
    this.dueAt,
    this.validityMonths,
    this.ownerUserId,
    this.note,
    this.requestedAt,
    this.waivedAt,
    this.waivedBy,
    this.waiverReason,
    this.retiredAt,
  });

  final String id;
  final String workspaceId;
  final DocumentLinkEntityType entityType;
  final String documentTypeId;
  final bool isMandatory;
  final int version;
  final String? entityId;

  /// Generalises the legacy `required_documents.property_type` column without
  /// importing portfolio vocabulary into DOM-006. Null applies to every scope.
  final String? scopeKey;
  final DateTime? dueAt;
  final int? validityMonths;
  final String? ownerUserId;
  final String? note;

  /// Legacy checklist "angefordert".
  final DateTime? requestedAt;

  /// Legacy checklist "nicht_relevant", as an audited waiver.
  final DateTime? waivedAt;
  final String? waivedBy;
  final String? waiverReason;
  final DateTime? retiredAt;

  bool get isWorkspaceRule => entityId == null;

  bool get isRetired => retiredAt != null;
}

/// One row of the derived requirement projection — the cloud replacement for
/// both the legacy compliance issue list and the property onboarding checklist.
class DocumentRequirementProjection {
  const DocumentRequirementProjection({
    required this.requirementId,
    required this.documentTypeId,
    required this.documentTypeKey,
    required this.documentTypeName,
    required this.entityType,
    required this.entityId,
    required this.isMandatory,
    required this.isInstanceRule,
    required this.state,
    this.scopeKey,
    this.dueAt,
    this.ownerUserId,
    this.note,
    this.documentId,
    this.documentStatus,
    this.documentValidUntil,
  });

  final String requirementId;
  final String documentTypeId;
  final String documentTypeKey;
  final String documentTypeName;
  final DocumentLinkEntityType entityType;
  final String entityId;
  final bool isMandatory;

  /// False for a workspace-wide rule, true for an instance requirement.
  final bool isInstanceRule;
  final DocumentRequirementState state;
  final String? scopeKey;
  final DateTime? dueAt;
  final String? ownerUserId;
  final String? note;
  final String? documentId;
  final DocumentStatus? documentStatus;
  final DateTime? documentValidUntil;

  /// A mandatory requirement that is not met — the cloud equivalent of the
  /// legacy `missing_required_document` / `expired_document` issue codes.
  bool get isBlocking => isMandatory && state.isOutstanding;
}

/// Storage coordinates for one version, resolved server-side after a
/// permission check. Input to [SignedUrlPort]; never a URL itself.
class DocumentContentRef {
  const DocumentContentRef({
    required this.documentId,
    required this.workspaceId,
    required this.versionNo,
    required this.storageBucket,
    required this.storageObjectPath,
    required this.contentHash,
    required this.byteSize,
    required this.mimeType,
    required this.verificationStatus,
    this.originalFilename,
    this.contentConfirmedAt,
  });

  final String documentId;
  final String workspaceId;
  final int versionNo;
  final String storageBucket;
  final String storageObjectPath;
  final String contentHash;
  final int byteSize;
  final String mimeType;
  final DocumentVerificationStatus verificationStatus;
  final String? originalFilename;
  final DateTime? contentConfirmedAt;
}

/// A minted, short-lived download URL. [expiresAt] is computed from the TTL the
/// port actually applied after clamping, not from the TTL that was requested.
class SignedDocumentUrl {
  const SignedDocumentUrl({
    required this.url,
    required this.expiresAt,
    required this.appliedTtl,
    required this.contentRef,
  });

  final String url;
  final DateTime expiresAt;
  final Duration appliedTtl;
  final DocumentContentRef contentRef;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// The client-declared facts about an object already uploaded to the private
/// bucket. The server verifies them against the real object before the document
/// becomes available (MIG-BND-003).
class DocumentContentDraft {
  const DocumentContentDraft({
    required this.storageObjectPath,
    required this.contentHash,
    required this.byteSize,
    required this.mimeType,
    this.originalFilename,
  }) : assert(byteSize >= 0);

  final String storageObjectPath;

  /// Lowercase hex sha256.
  final String contentHash;
  final int byteSize;
  final String mimeType;
  final String? originalFilename;
}

class DocumentDraft {
  const DocumentDraft({
    required this.title,
    required this.content,
    this.documentTypeId,
    this.validFrom,
    this.validUntil,
    this.retentionUntil,
    this.notes,
  });

  final String title;
  final DocumentContentDraft content;
  final String? documentTypeId;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime? retentionUntil;
  final String? notes;
}

class DocumentTypeDraft {
  const DocumentTypeDraft({
    required this.key,
    required this.name,
    required this.entityType,
    this.defaultValidityMonths,
    this.isActive = true,
  });

  final String key;
  final String name;
  final DocumentLinkEntityType entityType;
  final int? defaultValidityMonths;
  final bool isActive;
}

/// Upsert payload for a requirement rule. [requested], [waived] and [retired]
/// carry the legacy checklist states; a waiver requires [waiverReason].
class RequiredDocumentDraft {
  const RequiredDocumentDraft({
    required this.entityType,
    required this.documentTypeId,
    this.entityId,
    this.scopeKey,
    this.isMandatory = true,
    this.dueAt,
    this.validityMonths,
    this.ownerUserId,
    this.note,
    this.requested = false,
    this.waived = false,
    this.waiverReason,
    this.retired = false,
  }) : assert(
         !waived || waiverReason != null,
         'A waiver requires a reason (audited decision).',
       );

  final DocumentLinkEntityType entityType;
  final String documentTypeId;
  final String? entityId;
  final String? scopeKey;
  final bool isMandatory;
  final DateTime? dueAt;
  final int? validityMonths;
  final String? ownerUserId;
  final String? note;
  final bool requested;
  final bool waived;
  final String? waiverReason;
  final bool retired;
}
