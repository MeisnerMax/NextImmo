import '../../../core/models/documents.dart';
import '../../../data/repositories/document_types_repo.dart';
import '../../../data/repositories/documents_repo.dart';
import '../../../data/repositories/required_documents_repo.dart';
import '../application/document_repository.dart';
import '../domain/document_dto.dart';

/// Read-only projection of the legacy local `documents` / `document_metadata` /
/// `document_types` / `required_documents` tables onto the canonical
/// documents_compliance contract (P2-D03, mirroring the P2-D02 party adapter).
///
/// The legacy store keeps a single file per document row (`file_path`), so each
/// legacy row projects onto exactly one document, one synthetic content version
/// (`versionNo` 1, empty [legacyStorageBucket] — the DEBT-007 gap: there is no
/// cloud object yet) and at most one synthetic link. A legacy `entity_type`
/// string with no [DocumentLinkEntityType] counterpart (`tenant`, ...) degrades
/// to an unlinked document instead of throwing (DEBT-006).
///
/// All mutations are blocked with
/// [DocumentRepositoryFailureKind.dependencyConflict] — the local schema has no
/// version token, no immutable version history, no storage object and no
/// audited command envelope.
abstract interface class LegacyDocumentReadSource {
  Future<List<DocumentRecord>> listDocuments();

  Future<List<DocumentMetadataRecord>> listMetadata(String documentId);

  Future<List<DocumentTypeRecord>> listDocumentTypes();

  Future<List<RequiredDocumentRecord>> listRequiredDocuments();
}

/// [LegacyDocumentReadSource] backed by the concrete local repositories.
class RepositoryLegacyDocumentReadSource implements LegacyDocumentReadSource {
  const RepositoryLegacyDocumentReadSource({
    required DocumentsRepo documentsRepo,
    required DocumentTypesRepo documentTypesRepo,
    required RequiredDocumentsRepo requiredDocumentsRepo,
  }) : _documentsRepo = documentsRepo,
       _documentTypesRepo = documentTypesRepo,
       _requiredDocumentsRepo = requiredDocumentsRepo;

  final DocumentsRepo _documentsRepo;
  final DocumentTypesRepo _documentTypesRepo;
  final RequiredDocumentsRepo _requiredDocumentsRepo;

  @override
  Future<List<DocumentRecord>> listDocuments() =>
      _documentsRepo.listDocuments();

  @override
  Future<List<DocumentMetadataRecord>> listMetadata(String documentId) =>
      _documentsRepo.listMetadata(documentId);

  @override
  Future<List<DocumentTypeRecord>> listDocumentTypes() =>
      _documentTypesRepo.list();

  @override
  Future<List<RequiredDocumentRecord>> listRequiredDocuments() =>
      _requiredDocumentsRepo.list();
}

class LegacySqliteDocumentRepositoryAdapter
    implements
        DocumentRepository,
        DocumentContentPort,
        DocumentLinkPort,
        RequirementPolicyRepository,
        DocumentVerificationPort,
        SignedUrlPort {
  LegacySqliteDocumentRepositoryAdapter({
    required LegacyDocumentReadSource source,
    required String legacyWorkspaceId,
  }) : _source = source,
       _legacyWorkspaceId = legacyWorkspaceId;

  /// Legacy rows carry no optimistic-concurrency token and no version history,
  /// so every projected aggregate reports the one version it can honestly have.
  static const int legacyVersion = 1;

  /// The single synthetic content version of a legacy document.
  static const int legacyVersionNo = 1;

  /// There is no cloud Storage object behind a legacy `file_path` (DEBT-007).
  static const String legacyStorageBucket = '';

  static const String defaultMimeType = 'application/octet-stream';

  /// Carried over verbatim from `DocumentsRepo._resolveDocumentStatus`.
  static const Duration expiringWindow = Duration(days: 45);

  static const String _fallbackTypeKey = 'document_type';

  static const Map<String, String> _transliterations = <String, String>{
    'ä': 'ae',
    'ö': 'oe',
    'ü': 'ue',
    'ß': 'ss',
    'á': 'a',
    'à': 'a',
    'é': 'e',
    'è': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ñ': 'n',
    'ç': 'c',
  };

  final LegacyDocumentReadSource _source;
  final String _legacyWorkspaceId;

  // --- DocumentRepository ---

  @override
  Future<DocumentRepositoryResult<DocumentDto>> getById({
    required String workspaceId,
    required String documentId,
  }) async {
    final scopeFailure = _scopeFailure<DocumentDto>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final entry = await _findDocument(documentId);
      if (entry == null) {
        return _notFound<DocumentDto>();
      }
      return DocumentRepositorySuccess<DocumentDto>(entry.document);
    } catch (_) {
      return _loadFailure<DocumentDto>();
    }
  }

  @override
  Future<DocumentRepositoryResult<DocumentPageResult>> search(
    DocumentListQuery query,
  ) async {
    final scopeFailure = _scopeFailure<DocumentPageResult>(query.workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final documents = await _loadAll();
      final filtered =
          documents.where((entry) {
              if (!query.includeInactive && !entry.document.status.isActive) {
                return false;
              }
              if (query.documentTypeId != null &&
                  entry.document.documentTypeId != query.documentTypeId) {
                return false;
              }
              if (query.entityType == null) {
                return true;
              }
              final link = entry.link;
              return link != null &&
                  link.entityType == query.entityType &&
                  link.entityId == query.entityId;
            }).toList(growable: false)
            ..sort((a, b) => a.document.id.compareTo(b.document.id));

      final cursor = query.page.cursor;
      final page = <DocumentDto>[];
      var reachedCursor = cursor == null;
      String? nextCursor;
      for (final entry in filtered) {
        if (!reachedCursor) {
          if (entry.document.id == cursor) {
            reachedCursor = true;
          }
          continue;
        }
        if (page.length == query.page.limit) {
          nextCursor = page.last.id;
          break;
        }
        page.add(entry.document);
      }
      return DocumentRepositorySuccess<DocumentPageResult>(
        DocumentPageResult(items: page, nextCursor: nextCursor),
      );
    } catch (_) {
      return _loadFailure<DocumentPageResult>();
    }
  }

  @override
  Future<DocumentRepositoryResult<DocumentDto>> create(
    CreateDocumentCommand command,
  ) => _blockedMutation<DocumentDto>(command.context.workspaceId);

  @override
  Future<DocumentRepositoryResult<DocumentDto>> transitionStatus(
    TransitionDocumentStatusCommand command,
  ) => _blockedMutation<DocumentDto>(command.context.workspaceId);

  // --- DocumentContentPort ---

  @override
  Future<DocumentRepositoryResult<List<DocumentVersionDto>>> listVersions({
    required String workspaceId,
    required String documentId,
  }) async {
    final scopeFailure = _scopeFailure<List<DocumentVersionDto>>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final entry = await _findDocument(documentId);
      if (entry == null) {
        return _notFound<List<DocumentVersionDto>>();
      }
      return DocumentRepositorySuccess<List<DocumentVersionDto>>(
        <DocumentVersionDto>[entry.version],
      );
    } catch (_) {
      return _loadFailure<List<DocumentVersionDto>>();
    }
  }

  @override
  Future<DocumentRepositoryResult<DocumentVersionDto>> addVersion(
    AddDocumentVersionCommand command,
  ) => _blockedMutation<DocumentVersionDto>(command.context.workspaceId);

  @override
  Future<DocumentRepositoryResult<DocumentDto>> confirmContent(
    ConfirmDocumentContentCommand command,
  ) => _blockedMutation<DocumentDto>(command.context.workspaceId);

  // --- DocumentLinkPort ---

  @override
  Future<DocumentRepositoryResult<List<DocumentLinkDto>>> listLinks({
    required String workspaceId,
    required String documentId,
  }) async {
    final scopeFailure = _scopeFailure<List<DocumentLinkDto>>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final entry = await _findDocument(documentId);
      if (entry == null) {
        return _notFound<List<DocumentLinkDto>>();
      }
      final link = entry.link;
      return DocumentRepositorySuccess<List<DocumentLinkDto>>(
        link == null ? const <DocumentLinkDto>[] : <DocumentLinkDto>[link],
      );
    } catch (_) {
      return _loadFailure<List<DocumentLinkDto>>();
    }
  }

  @override
  Future<DocumentRepositoryResult<DocumentLinkDto>> link(
    LinkDocumentCommand command,
  ) => _blockedMutation<DocumentLinkDto>(command.context.workspaceId);

  @override
  Future<DocumentRepositoryResult<DocumentLinkDto>> unlink(
    UnlinkDocumentCommand command,
  ) => _blockedMutation<DocumentLinkDto>(command.context.workspaceId);

  // --- RequirementPolicyRepository ---

  @override
  Future<DocumentRepositoryResult<List<DocumentTypeDto>>> listTypes({
    required String workspaceId,
    bool activeOnly = true,
  }) async {
    final scopeFailure = _scopeFailure<List<DocumentTypeDto>>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final records = await _source.listDocumentTypes();
      final types = <DocumentTypeDto>[];
      for (final record in records) {
        final entityType = DocumentLinkEntityType.fromWire(record.entityType);
        if (entityType == null) {
          // Legacy free-text entity type without a controlled counterpart:
          // degrade instead of inventing a domain (DEBT-006).
          continue;
        }
        types.add(
          DocumentTypeDto(
            id: record.id,
            workspaceId: _legacyWorkspaceId,
            key: typeKeyFor(record.name),
            name: record.name,
            entityType: entityType,
            isActive: true,
            version: legacyVersion,
          ),
        );
      }
      types.sort((a, b) => a.id.compareTo(b.id));
      return DocumentRepositorySuccess<List<DocumentTypeDto>>(types);
    } catch (_) {
      return _loadFailure<List<DocumentTypeDto>>();
    }
  }

  @override
  Future<DocumentRepositoryResult<DocumentTypeDto>> upsertType(
    UpsertDocumentTypeCommand command,
  ) => _blockedMutation<DocumentTypeDto>(command.context.workspaceId);

  @override
  Future<DocumentRepositoryResult<List<RequiredDocumentDto>>>
  listRequirements({
    required String workspaceId,
    required DocumentLinkEntityType entityType,
    String? entityId,
  }) async {
    final scopeFailure = _scopeFailure<List<RequiredDocumentDto>>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final records = await _source.listRequiredDocuments();
      final requirements = <RequiredDocumentDto>[];
      for (final record in records) {
        if (DocumentLinkEntityType.fromWire(record.entityType) != entityType) {
          continue;
        }
        // Legacy rules are always type-level, so an instance filter never
        // narrows them further — they apply to every instance of the type.
        requirements.add(_requirement(record, entityType));
      }
      requirements.sort((a, b) => a.id.compareTo(b.id));
      return DocumentRepositorySuccess<List<RequiredDocumentDto>>(requirements);
    } catch (_) {
      return _loadFailure<List<RequiredDocumentDto>>();
    }
  }

  @override
  Future<DocumentRepositoryResult<RequiredDocumentDto>> upsertRequirement(
    UpsertRequiredDocumentCommand command,
  ) => _blockedMutation<RequiredDocumentDto>(command.context.workspaceId);

  @override
  Future<DocumentRepositoryResult<List<DocumentRequirementProjection>>>
  evaluate(DocumentRequirementQuery query) async {
    final scopeFailure = _scopeFailure<List<DocumentRequirementProjection>>(
      query.workspaceId,
    );
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final context = await _loadProjectionContext();
      final rows = _projectForEntity(
        context: context,
        entityType: query.entityType,
        entityId: query.entityId,
        scopeKey: query.scopeKey,
        scopeAgnosticOnly: false,
      );
      rows.sort((a, b) => a.requirementId.compareTo(b.requirementId));
      return DocumentRepositorySuccess<List<DocumentRequirementProjection>>(
        rows,
      );
    } catch (_) {
      return _loadFailure<List<DocumentRequirementProjection>>();
    }
  }

  /// The workspace-wide counterpart, mirroring
  /// `evaluate_workspace_document_requirements`.
  ///
  /// Locally every rule is type-level (the legacy schema has no instance
  /// rules), so the evaluated entity set is the linked entities plus whatever
  /// the caller supplied — the same union the cloud RPC forms, minus the
  /// instance-rule branch that cannot occur here. Scoped rules are skipped and
  /// counted exactly as server-side, so both backends report the same coverage.
  @override
  Future<DocumentRepositoryResult<WorkspaceDocumentRequirements>>
  evaluateWorkspace(WorkspaceDocumentRequirementQuery query) async {
    final scopeFailure = _scopeFailure<WorkspaceDocumentRequirements>(
      query.workspaceId,
    );
    if (scopeFailure != null) {
      return scopeFailure;
    }

    final requestedType = query.entityType;
    if (query.entityIds.isNotEmpty && requestedType == null) {
      // Same refusal the RPC gives: ids without a type would silently evaluate
      // nothing, which reads like "everything is fine".
      return const DocumentRepositoryFailure<WorkspaceDocumentRequirements>(
        kind: DocumentRepositoryFailureKind.validationFailed,
        message: 'Entity ids require an entity type.',
      );
    }

    try {
      final context = await _loadProjectionContext();

      final targets = <_ProjectionTarget>{};
      for (final entry in context.documents) {
        final link = entry.link;
        if (link == null) {
          continue;
        }
        if (requestedType != null && link.entityType != requestedType) {
          continue;
        }
        targets.add(
          _ProjectionTarget(entityType: link.entityType, entityId: link.entityId),
        );
      }
      if (requestedType != null) {
        for (final entityId in query.entityIds) {
          targets.add(
            _ProjectionTarget(entityType: requestedType, entityId: entityId),
          );
        }
      }

      final rows = <DocumentRequirementProjection>[];
      for (final target in targets) {
        rows.addAll(
          _projectForEntity(
            context: context,
            entityType: target.entityType,
            entityId: target.entityId,
            scopeKey: null,
            scopeAgnosticOnly: true,
          ),
        );
      }
      rows.sort((a, b) {
        final byEntity = a.entityId.compareTo(b.entityId);
        return byEntity != 0
            ? byEntity
            : a.requirementId.compareTo(b.requirementId);
      });

      final visible =
          query.onlyUnmet
              ? rows
                  .where(
                    (requirement) =>
                        requirement.state !=
                            DocumentRequirementState.satisfied &&
                        requirement.state != DocumentRequirementState.waived,
                  )
                  .toList(growable: false)
              : rows;

      var scopedRuleCount = 0;
      for (final record in context.requirementRecords) {
        if (requestedType != null &&
            DocumentLinkEntityType.fromWire(record.entityType) !=
                requestedType) {
          continue;
        }
        final scope = record.propertyType?.trim();
        if (scope != null && scope.isNotEmpty) {
          scopedRuleCount++;
        }
      }

      return DocumentRepositorySuccess<WorkspaceDocumentRequirements>(
        WorkspaceDocumentRequirements(
          requirements: visible,
          scopedRuleCount: scopedRuleCount,
        ),
      );
    } catch (_) {
      return _loadFailure<WorkspaceDocumentRequirements>();
    }
  }

  Future<_ProjectionContext> _loadProjectionContext() async {
    final requirementRecords = await _source.listRequiredDocuments();
    final typeRecords = await _source.listDocumentTypes();
    final documents = await _loadAll();
    return _ProjectionContext(
      requirementRecords: requirementRecords,
      typesById: <String, DocumentTypeRecord>{
        for (final record in typeRecords) record.id: record,
      },
      documents: documents,
    );
  }

  /// One entity's requirement rows. Shared by both entry points so the derived
  /// state cannot differ between the per-entity and the workspace-wide view —
  /// the same guarantee `private.document_requirement_state` gives server-side.
  List<DocumentRequirementProjection> _projectForEntity({
    required _ProjectionContext context,
    required DocumentLinkEntityType entityType,
    required String entityId,
    required String? scopeKey,
    required bool scopeAgnosticOnly,
  }) {
    final linked =
        context.documents.where((entry) {
          final link = entry.link;
          return link != null &&
              link.entityType == entityType &&
              link.entityId == entityId;
        }).toList(growable: false)..sort(
          (a, b) => b.record.createdAt.compareTo(a.record.createdAt),
        );

    final now = DateTime.now();
    final typesById = context.typesById;
    final rows = <DocumentRequirementProjection>[];
    for (final record in context.requirementRecords) {
      if (DocumentLinkEntityType.fromWire(record.entityType) != entityType) {
        continue;
      }
      if (scopeAgnosticOnly) {
        final scope = record.propertyType?.trim();
        if (scope != null && scope.isNotEmpty) {
          continue;
        }
      } else if (!_matchesScope(record.propertyType, scopeKey)) {
        continue;
      }

      // `listDocuments` orders newest first; keep that reduction explicit.
      _LegacyDocument? candidate;
      for (final entry in linked) {
        if (entry.record.typeId == record.typeId) {
          candidate = entry;
          break;
        }
      }

      final type = typesById[record.typeId];
      DateTime? validUntil;
      DocumentRequirementState state;
      if (candidate == null) {
        state = DocumentRequirementState.missing;
      } else {
        validUntil = _expiryOf(candidate, record.expiresFieldKey);
        if (validUntil != null && validUntil.isBefore(now)) {
          state = DocumentRequirementState.expired;
        } else if (validUntil != null &&
            !validUntil.isAfter(now.add(expiringWindow))) {
          state = DocumentRequirementState.expiring;
        } else if (_isVerified(candidate.metadata)) {
          state = DocumentRequirementState.satisfied;
        } else {
          state = DocumentRequirementState.pendingVerification;
        }
      }

      rows.add(
        DocumentRequirementProjection(
          requirementId: record.id,
          documentTypeId: record.typeId,
          documentTypeKey:
              type == null ? record.typeId : typeKeyFor(type.name),
          documentTypeName: type?.name ?? record.typeId,
          entityType: entityType,
          entityId: entityId,
          isMandatory: record.required,
          isInstanceRule: false,
          state: state,
          scopeKey: record.propertyType,
          documentId: candidate?.document.id,
          documentStatus: candidate?.document.status,
          documentValidUntil: validUntil,
        ),
      );
    }
    return rows;
  }

  // --- DocumentVerificationPort ---

  @override
  Future<DocumentRepositoryResult<DocumentVersionDto>> verify(
    VerifyDocumentVersionCommand command,
  ) => _blockedMutation<DocumentVersionDto>(command.context.workspaceId);

  // --- SignedUrlPort ---

  @override
  Future<DocumentRepositoryResult<DocumentContentRef>> resolveContentRef({
    required String workspaceId,
    required String documentId,
    int? versionNo,
  }) async {
    final scopeFailure = _scopeFailure<DocumentContentRef>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final entry = await _findDocument(documentId);
      if (entry == null) {
        return _notFound<DocumentContentRef>();
      }
      if (versionNo != null && versionNo != legacyVersionNo) {
        return const DocumentRepositoryFailure<DocumentContentRef>(
          kind: DocumentRepositoryFailureKind.notFound,
          message:
              'The legacy SQLite store keeps a single file per document, so '
              'only version $legacyVersionNo exists.',
        );
      }
      final version = entry.version;
      return DocumentRepositorySuccess<DocumentContentRef>(
        DocumentContentRef(
          documentId: version.documentId,
          workspaceId: _legacyWorkspaceId,
          versionNo: version.versionNo,
          storageBucket: version.storageBucket,
          storageObjectPath: version.storageObjectPath,
          contentHash: version.contentHash,
          byteSize: version.byteSize,
          mimeType: version.mimeType,
          verificationStatus: version.verificationStatus,
          originalFilename: version.originalFilename,
        ),
      );
    } catch (_) {
      return _loadFailure<DocumentContentRef>();
    }
  }

  @override
  Future<DocumentRepositoryResult<SignedDocumentUrl>> createSignedUrl({
    required String workspaceId,
    required String documentId,
    int? versionNo,
    Duration? ttl,
  }) async {
    final scopeFailure = _scopeFailure<SignedDocumentUrl>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }
    return const DocumentRepositoryFailure<SignedDocumentUrl>(
      kind: DocumentRepositoryFailureKind.dependencyConflict,
      message:
          'Legacy SQLite documents are plain local files: there is no private '
          'Storage bucket and no signing authority, so no signed URL can be '
          'minted. Use the resolved local path instead.',
    );
  }

  // --- projection ---

  Future<_LegacyDocument?> _findDocument(String documentId) async {
    final documents = await _loadAll();
    for (final entry in documents) {
      if (entry.document.id == documentId) {
        return entry;
      }
    }
    return null;
  }

  Future<List<_LegacyDocument>> _loadAll() async {
    final records = await _source.listDocuments();
    final metadata = await Future.wait(
      records.map((record) => _source.listMetadata(record.id)),
    );
    final documents = <_LegacyDocument>[];
    for (var index = 0; index < records.length; index++) {
      documents.add(
        _mapDocument(records[index], <String, String>{
          for (final row in metadata[index]) row.key: row.value,
        }),
      );
    }
    return List<_LegacyDocument>.unmodifiable(documents);
  }

  _LegacyDocument _mapDocument(
    DocumentRecord record,
    Map<String, String> metadata,
  ) {
    final verified = _isVerified(metadata);
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      record.createdAt,
      isUtc: true,
    );
    final version = DocumentVersionDto(
      id: '${record.id}:$legacyVersionNo',
      workspaceId: _legacyWorkspaceId,
      documentId: record.id,
      versionNo: legacyVersionNo,
      // DEBT-007: the legacy file lives on the local disk, not in a bucket.
      storageBucket: legacyStorageBucket,
      storageObjectPath: record.filePath,
      contentHash: record.sha256 ?? '',
      byteSize: record.sizeBytes ?? 0,
      mimeType: record.mimeType ?? defaultMimeType,
      verificationStatus: verified
          ? DocumentVerificationStatus.verified
          : DocumentVerificationStatus.pending,
      version: legacyVersion,
      originalFilename: record.fileName,
    );
    final linkEntityType = DocumentLinkEntityType.fromWire(record.entityType);
    final document = DocumentDto(
      id: record.id,
      workspaceId: _legacyWorkspaceId,
      title: record.fileName,
      // Legacy rows always point at an existing file, so they are never
      // `uploaded`/`processing`; verification metadata is the only lift.
      status: verified ? DocumentStatus.verified : DocumentStatus.available,
      currentVersionNo: legacyVersionNo,
      version: legacyVersion,
      documentTypeId: record.typeId,
      createdAt: createdAt,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        record.updatedAt,
        isUtc: true,
      ),
      createdBy: record.createdBy,
      currentVersion: version,
    );
    return _LegacyDocument(
      record: record,
      metadata: metadata,
      document: document,
      version: version,
      link: linkEntityType == null
          ? null
          : DocumentLinkDto(
              id: '${record.id}:${linkEntityType.wireName}',
              workspaceId: _legacyWorkspaceId,
              documentId: record.id,
              entityType: linkEntityType,
              entityId: record.entityId,
              createdAt: createdAt,
              createdBy: record.createdBy,
            ),
    );
  }

  RequiredDocumentDto _requirement(
    RequiredDocumentRecord record,
    DocumentLinkEntityType entityType,
  ) {
    return RequiredDocumentDto(
      id: record.id,
      workspaceId: _legacyWorkspaceId,
      entityType: entityType,
      documentTypeId: record.typeId,
      isMandatory: record.required,
      version: legacyVersion,
      // Legacy requirement rules are type-level only, never instance-level.
      scopeKey: record.propertyType,
    );
  }

  DateTime? _expiryOf(_LegacyDocument entry, String? expiresFieldKey) {
    final key = expiresFieldKey?.trim();
    if (key == null || key.isEmpty) {
      return null;
    }
    return tryParseLegacyDate(entry.metadata[key]);
  }

  /// Mirrors `RequiredDocumentsRepo.list`: a rule without a property type
  /// applies to every scope, and an unscoped query keeps every rule.
  static bool _matchesScope(String? rulePropertyType, String? scopeKey) {
    final scope = scopeKey?.trim();
    if (scope == null || scope.isEmpty) {
      return true;
    }
    final ruleScope = rulePropertyType?.trim();
    return ruleScope == null || ruleScope.isEmpty || ruleScope == scope;
  }

  /// Mirrors `DocumentsRepo._resolveDocumentStatus`: verification is recorded
  /// as free-text metadata under one of three keys.
  static bool _isVerified(Map<String, String> metadata) {
    final raw =
        metadata['verified'] ??
        metadata['verified_at'] ??
        metadata['checked_at'];
    return raw != null && raw.trim().isNotEmpty;
  }

  /// Mirrors `DocumentsRepo._tryParseDate` / `DocComplianceEngine`: an expiry is
  /// stored either as epoch millis or as an ISO date string.
  static DateTime? tryParseLegacyDate(String? rawValue) {
    final raw = rawValue?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final epoch = int.tryParse(raw);
    if (epoch != null) {
      return DateTime.fromMillisecondsSinceEpoch(epoch);
    }
    return DateTime.tryParse(raw);
  }

  /// Slugifies a legacy type name onto the cloud `document_types.key` shape
  /// `^[a-z0-9]+([._-][a-z0-9]+)*$`.
  static String typeKeyFor(String name) {
    var value = name.trim().toLowerCase();
    for (final entry in _transliterations.entries) {
      value = value.replaceAll(entry.key, entry.value);
    }
    final slug = value
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'[._-]{2,}'), '_')
        .replaceAll(RegExp(r'^[._-]+'), '')
        .replaceAll(RegExp(r'[._-]+$'), '');
    return slug.isEmpty ? _fallbackTypeKey : slug;
  }

  Future<DocumentRepositoryResult<T>> _blockedMutation<T>(
    String workspaceId,
  ) async {
    final scopeFailure = _scopeFailure<T>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }
    return DocumentRepositoryFailure<T>(
      kind: DocumentRepositoryFailureKind.dependencyConflict,
      message:
          'The local SQLite backend is read-only for the documents_compliance '
          'contract: it has no document version token, no immutable version '
          'history, no private Storage object and no audited command envelope.',
    );
  }

  DocumentRepositoryFailure<T>? _scopeFailure<T>(String workspaceId) {
    if (workspaceId == _legacyWorkspaceId) {
      return null;
    }
    return DocumentRepositoryFailure<T>(
      kind: DocumentRepositoryFailureKind.forbidden,
      message: 'The legacy SQLite database is bound to another workspace.',
    );
  }

  DocumentRepositoryFailure<T> _notFound<T>() {
    return DocumentRepositoryFailure<T>(
      kind: DocumentRepositoryFailureKind.notFound,
      message: 'Document not found in the local store.',
    );
  }

  DocumentRepositoryFailure<T> _loadFailure<T>() {
    return DocumentRepositoryFailure<T>(
      kind: DocumentRepositoryFailureKind.infrastructureFailure,
      message: 'Legacy SQLite documents could not be loaded.',
    );
  }
}

/// Everything both requirement projections read, loaded once. Without this the
/// workspace-wide pass would re-read the whole legacy store per entity — the
/// N+1 the cloud increment exists to remove, just moved into the adapter.
class _ProjectionContext {
  const _ProjectionContext({
    required this.requirementRecords,
    required this.typesById,
    required this.documents,
  });

  final List<RequiredDocumentRecord> requirementRecords;
  final Map<String, DocumentTypeRecord> typesById;
  final List<_LegacyDocument> documents;
}

class _ProjectionTarget {
  const _ProjectionTarget({required this.entityType, required this.entityId});

  final DocumentLinkEntityType entityType;
  final String entityId;

  @override
  bool operator ==(Object other) =>
      other is _ProjectionTarget &&
      other.entityType == entityType &&
      other.entityId == entityId;

  @override
  int get hashCode => Object.hash(entityType, entityId);
}

class _LegacyDocument {
  const _LegacyDocument({
    required this.record,
    required this.metadata,
    required this.document,
    required this.version,
    this.link,
  });

  final DocumentRecord record;
  final Map<String, String> metadata;
  final DocumentDto document;
  final DocumentVersionDto version;
  final DocumentLinkDto? link;
}
