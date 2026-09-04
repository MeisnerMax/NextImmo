import 'dart:async';
import 'dart:typed_data';

import 'package:neximmo_app/features/documents_compliance/application/document_repository.dart';
import 'package:neximmo_app/features/documents_compliance/domain/document_dto.dart';

/// One fake serving all seven documents_compliance ports, the way a real
/// backend binds them (one adapter instance per domain). Shared by the
/// DOCUMENTS-V2 host, register, registry and compliance tests.
///
/// Registry mutations are real upserts here, mirroring
/// `upsert_document_type` / `upsert_required_document`: an existing key or an
/// existing live rule identity is updated in place, never rejected.
class FakeDocumentBackend
    implements
        DocumentRepository,
        DocumentContentPort,
        DocumentLinkPort,
        RequirementPolicyRepository,
        DocumentVerificationPort,
        SignedUrlPort,
        DocumentUploadPort {
  FakeDocumentBackend({
    List<DocumentDto> documents = const <DocumentDto>[],
    this.versions = const <DocumentVersionDto>[],
    this.links = const <DocumentLinkDto>[],
    List<DocumentTypeDto>? types,
    List<RequiredDocumentDto> requirements = const <RequiredDocumentDto>[],
    this.workspaceRequirements = const WorkspaceDocumentRequirements(
      requirements: <DocumentRequirementProjection>[],
      scopedRuleCount: 0,
    ),
    this.searchFailure,
    this.transitionFailure,
    this.verifyFailure,
    this.listTypesFailure,
    this.listRequirementsFailure,
    this.upsertTypeFailure,
    this.upsertRequirementFailure,
    this.signedUrlFailure,
    this.confirmResult,
    this.pageSize,
  }) : documents = List<DocumentDto>.of(documents),
       types = List<DocumentTypeDto>.of(types ?? defaultTypes),
       requirements = List<RequiredDocumentDto>.of(requirements);

  static const String workspace = 'ws-1';

  static const List<DocumentTypeDto> defaultTypes = <DocumentTypeDto>[
    DocumentTypeDto(
      id: 'type-1',
      workspaceId: workspace,
      key: 'purchase_contract',
      name: 'Vertragsunterlage',
      entityType: DocumentLinkEntityType.property,
      isActive: true,
      version: 1,
      defaultValidityMonths: 12,
    ),
    DocumentTypeDto(
      id: 'type-2',
      workspaceId: workspace,
      key: 'party_file',
      name: 'Parteiunterlage',
      entityType: DocumentLinkEntityType.party,
      isActive: true,
      version: 1,
    ),
    DocumentTypeDto(
      id: 'type-3',
      workspaceId: workspace,
      key: 'old_energy',
      name: 'Alter Energieausweis',
      entityType: DocumentLinkEntityType.property,
      isActive: false,
      version: 2,
    ),
  ];

  final List<DocumentDto> documents;
  final List<DocumentVersionDto> versions;
  final List<DocumentLinkDto> links;
  final List<DocumentTypeDto> types;
  final List<RequiredDocumentDto> requirements;
  final WorkspaceDocumentRequirements workspaceRequirements;
  final DocumentRepositoryFailure<DocumentPageResult>? searchFailure;
  final DocumentRepositoryFailure<DocumentDto>? transitionFailure;
  final DocumentRepositoryFailure<DocumentVersionDto>? verifyFailure;
  final DocumentRepositoryFailure<List<DocumentTypeDto>>? listTypesFailure;
  final DocumentRepositoryFailure<List<RequiredDocumentDto>>?
  listRequirementsFailure;
  final DocumentRepositoryFailure<DocumentTypeDto>? upsertTypeFailure;
  final DocumentRepositoryFailure<RequiredDocumentDto>?
  upsertRequirementFailure;
  final DocumentRepositoryFailure<SignedDocumentUrl>? signedUrlFailure;
  final DocumentDto? confirmResult;

  /// When set, `search` pages the document list with this size and hands out
  /// cursors, so keyset load-more can be exercised.
  final int? pageSize;

  int createCalls = 0;
  int uploadCalls = 0;
  int transitionCalls = 0;
  int verifyCalls = 0;
  int confirmCalls = 0;
  int addVersionCalls = 0;
  int linkCalls = 0;
  int signedUrlCalls = 0;
  int listTypesCalls = 0;
  bool? lastListTypesActiveOnly;
  int listRequirementsCalls = 0;
  int evaluateWorkspaceCalls = 0;
  final List<DocumentListQuery> queries = <DocumentListQuery>[];
  final List<UpsertDocumentTypeCommand> typeCommands =
      <UpsertDocumentTypeCommand>[];
  final List<UpsertRequiredDocumentCommand> requirementCommands =
      <UpsertRequiredDocumentCommand>[];
  final List<VerifyDocumentVersionCommand> verifyCommands =
      <VerifyDocumentVersionCommand>[];
  final List<TransitionDocumentStatusCommand> transitionCommands =
      <TransitionDocumentStatusCommand>[];
  WorkspaceDocumentRequirementQuery? lastWorkspaceQuery;
  Completer<void>? _searchGate;

  DocumentListQuery? get lastQuery => queries.isEmpty ? null : queries.last;

  void holdSearch() => _searchGate = Completer<void>();

  void releaseSearch() => _searchGate?.complete();

  DocumentDto get _anyDocument =>
      documents.isNotEmpty
          ? documents.first
          : const DocumentDto(
            id: 'generated',
            workspaceId: workspace,
            title: 'Neuer Nachweis',
            status: DocumentStatus.uploaded,
            currentVersionNo: 1,
            version: 1,
          );

  @override
  Future<DocumentRepositoryResult<DocumentPageResult>> search(
    DocumentListQuery query,
  ) async {
    queries.add(query);
    await _searchGate?.future;
    final failure = searchFailure;
    if (failure != null) {
      return failure;
    }
    final filtered = documents
        .where((document) {
          if (query.documentTypeId != null &&
              document.documentTypeId != query.documentTypeId) {
            return false;
          }
          if (!query.includeInactive && !document.status.isActive) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    final size = pageSize;
    if (size == null) {
      return DocumentRepositorySuccess<DocumentPageResult>(
        DocumentPageResult(items: filtered),
      );
    }
    final start = int.tryParse(query.page.cursor ?? '0') ?? 0;
    final end = (start + size).clamp(0, filtered.length);
    return DocumentRepositorySuccess<DocumentPageResult>(
      DocumentPageResult(
        items: filtered.sublist(start, end),
        nextCursor: end < filtered.length ? '$end' : null,
      ),
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentDto>> getById({
    required String workspaceId,
    required String documentId,
  }) async {
    for (final document in documents) {
      if (document.id == documentId) {
        return DocumentRepositorySuccess<DocumentDto>(document);
      }
    }
    return const DocumentRepositoryFailure<DocumentDto>(
      kind: DocumentRepositoryFailureKind.notFound,
      message: 'not found',
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentDto>> create(
    CreateDocumentCommand command,
  ) async {
    createCalls++;
    return DocumentRepositorySuccess<DocumentDto>(_anyDocument);
  }

  @override
  Future<DocumentRepositoryResult<DocumentDto>> transitionStatus(
    TransitionDocumentStatusCommand command,
  ) async {
    transitionCalls++;
    transitionCommands.add(command);
    final failure = transitionFailure;
    if (failure != null) {
      return failure;
    }
    return DocumentRepositorySuccess<DocumentDto>(_anyDocument);
  }

  @override
  Future<DocumentRepositoryResult<List<DocumentVersionDto>>> listVersions({
    required String workspaceId,
    required String documentId,
  }) async {
    return DocumentRepositorySuccess<List<DocumentVersionDto>>(
      versions
          .where((version) => version.documentId == documentId)
          .toList(growable: false),
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentVersionDto>> addVersion(
    AddDocumentVersionCommand command,
  ) async {
    addVersionCalls++;
    return DocumentRepositorySuccess<DocumentVersionDto>(
      versions.isNotEmpty
          ? versions.first
          : DocumentVersionDto(
            id: 'v-generated',
            workspaceId: workspace,
            documentId: command.documentId,
            versionNo: 2,
            storageBucket: 'documents',
            storageObjectPath: command.content.storageObjectPath,
            contentHash: command.content.contentHash,
            byteSize: command.content.byteSize,
            mimeType: command.content.mimeType,
            verificationStatus: DocumentVerificationStatus.pending,
            version: 1,
          ),
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentDto>> confirmContent(
    ConfirmDocumentContentCommand command,
  ) async {
    confirmCalls++;
    return DocumentRepositorySuccess<DocumentDto>(
      confirmResult ?? _anyDocument,
    );
  }

  @override
  Future<DocumentRepositoryResult<List<DocumentLinkDto>>> listLinks({
    required String workspaceId,
    required String documentId,
  }) async {
    return DocumentRepositorySuccess<List<DocumentLinkDto>>(
      links
          .where((link) => link.documentId == documentId)
          .toList(growable: false),
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentLinkDto>> link(
    LinkDocumentCommand command,
  ) async {
    linkCalls++;
    return DocumentRepositorySuccess<DocumentLinkDto>(
      DocumentLinkDto(
        id: 'link-1',
        workspaceId: command.context.workspaceId,
        documentId: command.documentId,
        entityType: command.entityType,
        entityId: command.entityId,
      ),
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentLinkDto>> unlink(
    UnlinkDocumentCommand command,
  ) async {
    return const DocumentRepositoryFailure<DocumentLinkDto>(
      kind: DocumentRepositoryFailureKind.notFound,
      message: 'not found',
    );
  }

  @override
  Future<DocumentRepositoryResult<List<DocumentTypeDto>>> listTypes({
    required String workspaceId,
    bool activeOnly = true,
  }) async {
    listTypesCalls++;
    lastListTypesActiveOnly = activeOnly;
    final failure = listTypesFailure;
    if (failure != null) {
      return failure;
    }
    return DocumentRepositorySuccess<List<DocumentTypeDto>>(
      types
          .where((type) => !activeOnly || type.isActive)
          .toList(growable: false),
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentTypeDto>> upsertType(
    UpsertDocumentTypeCommand command,
  ) async {
    typeCommands.add(command);
    final failure = upsertTypeFailure;
    if (failure != null) {
      return failure;
    }
    final draft = command.draft;
    final index = types.indexWhere((type) => type.key == draft.key);
    final existing = index < 0 ? null : types[index];
    final saved = DocumentTypeDto(
      id: existing?.id ?? 'type-${types.length + 1}',
      workspaceId: workspace,
      key: draft.key,
      name: draft.name,
      entityType: draft.entityType,
      isActive: draft.isActive,
      version: (existing?.version ?? 0) + 1,
      defaultValidityMonths: draft.defaultValidityMonths,
    );
    if (index < 0) {
      types.add(saved);
    } else {
      types[index] = saved;
    }
    return DocumentRepositorySuccess<DocumentTypeDto>(saved);
  }

  @override
  Future<DocumentRepositoryResult<List<RequiredDocumentDto>>> listRequirements({
    required String workspaceId,
    required DocumentLinkEntityType entityType,
    String? entityId,
  }) async {
    listRequirementsCalls++;
    final failure = listRequirementsFailure;
    if (failure != null) {
      return failure;
    }
    return DocumentRepositorySuccess<List<RequiredDocumentDto>>(
      requirements
          .where(
            (rule) =>
                rule.entityType == entityType &&
                !rule.isRetired &&
                (entityId == null || rule.entityId == entityId),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<DocumentRepositoryResult<RequiredDocumentDto>> upsertRequirement(
    UpsertRequiredDocumentCommand command,
  ) async {
    requirementCommands.add(command);
    final failure = upsertRequirementFailure;
    if (failure != null) {
      return failure;
    }
    final draft = command.draft;
    final now = DateTime.utc(2026, 9, 4);
    final index = requirements.indexWhere(
      (rule) =>
          !rule.isRetired &&
          rule.entityType == draft.entityType &&
          rule.entityId == draft.entityId &&
          rule.scopeKey == draft.scopeKey &&
          rule.documentTypeId == draft.documentTypeId,
    );
    final existing = index < 0 ? null : requirements[index];
    final saved = RequiredDocumentDto(
      id: existing?.id ?? 'rule-${requirements.length + 1}',
      workspaceId: workspace,
      entityType: draft.entityType,
      documentTypeId: draft.documentTypeId,
      isMandatory: draft.isMandatory,
      version: (existing?.version ?? 0) + 1,
      entityId: draft.entityId,
      scopeKey: draft.scopeKey,
      dueAt: draft.dueAt,
      validityMonths: draft.validityMonths,
      note: draft.note,
      requestedAt: draft.requested ? now : null,
      waivedAt: draft.waived ? now : null,
      waiverReason: draft.waived ? draft.waiverReason : null,
      retiredAt: draft.retired ? now : null,
    );
    if (index < 0) {
      requirements.add(saved);
    } else {
      requirements[index] = saved;
    }
    return DocumentRepositorySuccess<RequiredDocumentDto>(saved);
  }

  @override
  Future<DocumentRepositoryResult<List<DocumentRequirementProjection>>>
  evaluate(DocumentRequirementQuery query) async {
    return const DocumentRepositorySuccess<List<DocumentRequirementProjection>>(
      <DocumentRequirementProjection>[],
    );
  }

  @override
  Future<DocumentRepositoryResult<WorkspaceDocumentRequirements>>
  evaluateWorkspace(WorkspaceDocumentRequirementQuery query) async {
    evaluateWorkspaceCalls++;
    lastWorkspaceQuery = query;
    if (!query.onlyUnmet) {
      return DocumentRepositorySuccess<WorkspaceDocumentRequirements>(
        workspaceRequirements,
      );
    }
    return DocumentRepositorySuccess<WorkspaceDocumentRequirements>(
      WorkspaceDocumentRequirements(
        requirements: workspaceRequirements.requirements
            .where(
              (row) =>
                  row.state != DocumentRequirementState.satisfied &&
                  row.state != DocumentRequirementState.waived,
            )
            .toList(growable: false),
        scopedRuleCount: workspaceRequirements.scopedRuleCount,
      ),
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentVersionDto>> verify(
    VerifyDocumentVersionCommand command,
  ) async {
    verifyCalls++;
    verifyCommands.add(command);
    final failure = verifyFailure;
    if (failure != null) {
      return failure;
    }
    return DocumentRepositorySuccess<DocumentVersionDto>(
      versions.isNotEmpty
          ? versions.first
          : DocumentVersionDto(
            id: 'v-generated',
            workspaceId: workspace,
            documentId: command.documentId,
            versionNo: command.versionNo,
            storageBucket: 'documents',
            storageObjectPath: 'ws-1/x.pdf',
            contentHash: 'c' * 64,
            byteSize: 1,
            mimeType: 'application/pdf',
            verificationStatus: DocumentVerificationStatus.verified,
            version: 1,
          ),
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentContentRef>> resolveContentRef({
    required String workspaceId,
    required String documentId,
    int? versionNo,
  }) async {
    return DocumentRepositorySuccess<DocumentContentRef>(
      _contentRef(documentId),
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentContentDraft>> upload({
    required String workspaceId,
    required String scopeId,
    required int versionNo,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    uploadCalls++;
    final path = DocumentUploadPort.storageObjectPath(
      workspaceId: workspaceId,
      scopeId: scopeId,
      versionNo: versionNo,
      filename: filename,
    );
    return DocumentRepositorySuccess<DocumentContentDraft>(
      DocumentContentDraft(
        storageObjectPath: path,
        contentHash: DocumentUploadPort.contentHashOf(bytes),
        byteSize: bytes.length,
        mimeType: mimeType,
        originalFilename: filename,
      ),
    );
  }

  /// The minted URL carries a marker that must never show up in any widget:
  /// tests grep the tree for it.
  static String signedUrlFor(String documentId, int? versionNo) =>
      'https://storage.test/signed/$documentId/${versionNo ?? 'current'}'
      '?token=SECRET-SIGNATURE';

  @override
  Future<DocumentRepositoryResult<SignedDocumentUrl>> createSignedUrl({
    required String workspaceId,
    required String documentId,
    int? versionNo,
    Duration? ttl,
  }) async {
    signedUrlCalls++;
    final failure = signedUrlFailure;
    if (failure != null) {
      return failure;
    }
    final applied = SignedUrlPort.clampTtl(ttl);
    return DocumentRepositorySuccess<SignedDocumentUrl>(
      SignedDocumentUrl(
        url: signedUrlFor(documentId, versionNo),
        expiresAt: DateTime.utc(2026, 7, 29, 12).add(applied),
        appliedTtl: applied,
        contentRef: _contentRef(documentId),
      ),
    );
  }

  DocumentContentRef _contentRef(String documentId) {
    return DocumentContentRef(
      documentId: documentId,
      workspaceId: workspace,
      versionNo: 1,
      storageBucket: 'documents',
      storageObjectPath: 'ws-1/$documentId/1.pdf',
      contentHash: 'a' * 64,
      byteSize: 20480,
      mimeType: 'application/pdf',
      verificationStatus: DocumentVerificationStatus.pending,
    );
  }
}
