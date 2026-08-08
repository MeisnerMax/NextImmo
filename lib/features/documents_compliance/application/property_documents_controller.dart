/// Screen-facing orchestration over the documents_compliance contract for one
/// property (P2-D03 / Wave 2, Arbeitspaket 3), following the pattern proven by
/// `PartiesController`: explicit phases per zone, a generation guard against
/// out-of-order responses, and every mandatory screen state of
/// `03_design_system.md` represented as data rather than as a widget branch.
///
/// Three domain specifics drive the shape:
///
/// * **`confirmContent` succeeds in both outcomes.** The server drives the
///   STM-008 error path to `rejected` when the declared object does not match
///   what really landed in the bucket (MIG-BND-003), and returns success with
///   that status. So the result is inspected and surfaced as its own visible
///   outcome instead of being reported as a failure or silently swallowed.
/// * **Verification is a separate capability** (`document.verify`) from editing
///   (`document.manage`), so the two affordances are gated independently.
/// * **There is no delete path.** `OPN-DOM-005` is still open and the shipped
///   default is that `archived` is terminal.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/authorization_port.dart';
import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/document_dto.dart';
import 'document_providers.dart';
import 'document_query_invalidation_source.dart';
import 'document_repository.dart';

const Object _unchanged = Object();

enum PropertyDocumentsListPhase { idle, loading, ready, empty, forbidden, error }

enum PropertyDocumentsRequirementPhase {
  idle,
  loading,
  ready,
  empty,
  forbidden,
  error,
}

enum PropertyDocumentsActionPhase {
  idle,
  submitting,
  succeeded,
  conflict,
  forbidden,

  /// The bound backend cannot mutate yet (legacy SQLite adapter is read-only by
  /// design). Rendered as the mandatory "read-only until migrated" notice.
  readOnly,

  /// MIG-BND-003: the upload confirmation ran, and the declared object did not
  /// match the stored one, so the document went to `rejected`. A visible
  /// outcome, not an infrastructure error.
  contentRejected,
  failed,
}

class PropertyDocumentsState {
  const PropertyDocumentsState({
    required this.listPhase,
    required this.requirementPhase,
    this.actionPhase = PropertyDocumentsActionPhase.idle,
    this.documents = const <DocumentDto>[],
    this.requirements = const <DocumentRequirementProjection>[],
    this.versions = const <DocumentVersionDto>[],
    this.nextCursor,
    this.loadingMore = false,
    this.includeInactive = false,
    this.selectedDocumentId,
    this.versionConflict,
    this.message,
    this.actionMessage,
  });

  const PropertyDocumentsState.loading()
    : this(
        listPhase: PropertyDocumentsListPhase.loading,
        requirementPhase: PropertyDocumentsRequirementPhase.loading,
      );

  final PropertyDocumentsListPhase listPhase;
  final PropertyDocumentsRequirementPhase requirementPhase;
  final PropertyDocumentsActionPhase actionPhase;
  final List<DocumentDto> documents;
  final List<DocumentRequirementProjection> requirements;
  final List<DocumentVersionDto> versions;
  final String? nextCursor;
  final bool loadingMore;
  final bool includeInactive;
  final String? selectedDocumentId;
  final DocumentVersionConflict? versionConflict;
  final String? message;
  final String? actionMessage;

  bool get hasMore => nextCursor != null;

  /// Mandatory requirements that are not met — what the compliance surfaces
  /// count. Derived server-side; this only filters the projection.
  List<DocumentRequirementProjection> get blockingRequirements =>
      requirements
          .where((requirement) => requirement.isBlocking)
          .toList(growable: false);

  PropertyDocumentsState copyWith({
    PropertyDocumentsListPhase? listPhase,
    PropertyDocumentsRequirementPhase? requirementPhase,
    PropertyDocumentsActionPhase? actionPhase,
    List<DocumentDto>? documents,
    List<DocumentRequirementProjection>? requirements,
    List<DocumentVersionDto>? versions,
    Object? nextCursor = _unchanged,
    bool? loadingMore,
    bool? includeInactive,
    Object? selectedDocumentId = _unchanged,
    Object? versionConflict = _unchanged,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
  }) {
    return PropertyDocumentsState(
      listPhase: listPhase ?? this.listPhase,
      requirementPhase: requirementPhase ?? this.requirementPhase,
      actionPhase: actionPhase ?? this.actionPhase,
      documents: documents ?? this.documents,
      requirements: requirements ?? this.requirements,
      versions: versions ?? this.versions,
      nextCursor:
          identical(nextCursor, _unchanged)
              ? this.nextCursor
              : nextCursor as String?,
      loadingMore: loadingMore ?? this.loadingMore,
      includeInactive: includeInactive ?? this.includeInactive,
      selectedDocumentId:
          identical(selectedDocumentId, _unchanged)
              ? this.selectedDocumentId
              : selectedDocumentId as String?,
      versionConflict:
          identical(versionConflict, _unchanged)
              ? this.versionConflict
              : versionConflict as DocumentVersionConflict?,
      message:
          identical(message, _unchanged) ? this.message : message as String?,
      actionMessage:
          identical(actionMessage, _unchanged)
              ? this.actionMessage
              : actionMessage as String?,
    );
  }
}

typedef DocumentIdFactory = String Function();

class PropertyDocumentsController
    extends StateNotifier<PropertyDocumentsState> {
  PropertyDocumentsController({
    required DocumentRepository repository,
    required DocumentContentPort content,
    required DocumentUploadPort upload,
    required DocumentLinkPort links,
    required RequirementPolicyRepository requirements,
    required DocumentVerificationPort verification,
    required SignedUrlPort signedUrls,
    required WorkspaceSessionScope scope,
    required String propertyId,
    DocumentQueryInvalidationSource? invalidationSource,
    DocumentIdFactory? idFactory,
  }) : _repository = repository,
       _content = content,
       _upload = upload,
       _links = links,
       _requirements = requirements,
       _verification = verification,
       _signedUrls = signedUrls,
       _scope = scope,
       _propertyId = propertyId,
       _invalidationSource = invalidationSource,
       _idFactory = idFactory ?? const Uuid().v4,
       super(const PropertyDocumentsState.loading());

  static const String readPermission = 'document.read';

  /// The cloud vocabulary (`document.read` / `document.manage` /
  /// `document.verify`, per the contract library docs and the P2-D03 RPCs).
  ///
  /// The local RBAC catalogue in `lib/core/security/rbac.dart` spells editing
  /// differently (`document.create` / `document.update`). That divergence is
  /// deliberately not papered over here: local mode is read-only until this
  /// domain is migrated, so `mutationsSupported` already denies every mutation
  /// before a permission is ever consulted, and the only vocabulary that can
  /// reach a capability check is the cloud one.
  static const String managePermission = 'document.manage';
  static const String verifyPermission = 'document.verify';
  static const int pageSize = 50;
  static const DocumentLinkEntityType entityType =
      DocumentLinkEntityType.property;

  final DocumentRepository _repository;
  final DocumentContentPort _content;
  final DocumentUploadPort _upload;
  final DocumentLinkPort _links;
  final RequirementPolicyRepository _requirements;
  final DocumentVerificationPort _verification;
  final SignedUrlPort _signedUrls;
  final WorkspaceSessionScope _scope;
  final String _propertyId;
  final DocumentQueryInvalidationSource? _invalidationSource;
  final DocumentIdFactory _idFactory;

  StreamSubscription<DocumentQueryInvalidation>? _invalidationSubscription;
  int _generation = 0;
  int _detailGeneration = 0;

  AuthorizationPort get _authorization => _scope.authorization;

  /// True exactly when the backend itself blocks mutations, which is what the
  /// "read-only until migrated" notice reports — as opposed to a rights issue.
  bool get isReadOnlyBackend => !_scope.mutationsSupported;

  bool get canMutate =>
      _scope.mutationsSupported &&
      _scope.isResolved &&
      _authorization.can(managePermission);

  bool get canVerify =>
      _scope.mutationsSupported &&
      _scope.isResolved &&
      _authorization.can(verifyPermission);

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        listPhase: PropertyDocumentsListPhase.idle,
        requirementPhase: PropertyDocumentsRequirementPhase.idle,
        documents: const <DocumentDto>[],
        requirements: const <DocumentRequirementProjection>[],
        nextCursor: null,
        message: null,
      );
      return;
    }
    _subscribeToInvalidation(workspaceId);
    final generation = ++_generation;
    state = state.copyWith(
      listPhase: PropertyDocumentsListPhase.loading,
      requirementPhase: PropertyDocumentsRequirementPhase.loading,
      message: null,
    );
    await Future.wait(<Future<void>>[
      _loadDocuments(generation, workspaceId),
      _loadRequirements(generation, workspaceId),
    ]);
  }

  Future<void> _loadDocuments(int generation, String workspaceId) async {
    final result = await _repository.search(
      DocumentListQuery(
        workspaceId: workspaceId,
        entityType: entityType,
        entityId: _propertyId,
        page: const DocumentPageRequest(limit: pageSize),
        includeInactive: state.includeInactive,
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case DocumentRepositorySuccess<DocumentPageResult>(:final value):
        state = state.copyWith(
          listPhase:
              value.items.isEmpty
                  ? PropertyDocumentsListPhase.empty
                  : PropertyDocumentsListPhase.ready,
          documents: value.items,
          nextCursor: value.nextCursor,
        );
      case DocumentRepositoryFailure<DocumentPageResult>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          listPhase:
              kind == DocumentRepositoryFailureKind.forbidden
                  ? PropertyDocumentsListPhase.forbidden
                  : PropertyDocumentsListPhase.error,
          documents: const <DocumentDto>[],
          nextCursor: null,
          message: message,
        );
    }
  }

  Future<void> _loadRequirements(int generation, String workspaceId) async {
    final result = await _requirements.evaluate(
      DocumentRequirementQuery(
        workspaceId: workspaceId,
        entityType: entityType,
        entityId: _propertyId,
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case DocumentRepositorySuccess<List<DocumentRequirementProjection>>(
        :final value,
      ):
        state = state.copyWith(
          requirementPhase:
              value.isEmpty
                  ? PropertyDocumentsRequirementPhase.empty
                  : PropertyDocumentsRequirementPhase.ready,
          requirements: value,
        );
      case DocumentRepositoryFailure<List<DocumentRequirementProjection>>(
        :final kind,
      ):
        state = state.copyWith(
          requirementPhase:
              kind == DocumentRepositoryFailureKind.forbidden
                  ? PropertyDocumentsRequirementPhase.forbidden
                  : PropertyDocumentsRequirementPhase.error,
          requirements: const <DocumentRequirementProjection>[],
        );
    }
  }

  Future<void> loadMore() async {
    final workspaceId = _scope.workspaceId;
    final cursor = state.nextCursor;
    if (workspaceId == null || cursor == null || state.loadingMore) {
      return;
    }
    final generation = _generation;
    state = state.copyWith(loadingMore: true);
    final result = await _repository.search(
      DocumentListQuery(
        workspaceId: workspaceId,
        entityType: entityType,
        entityId: _propertyId,
        page: DocumentPageRequest(limit: pageSize, cursor: cursor),
        includeInactive: state.includeInactive,
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case DocumentRepositorySuccess<DocumentPageResult>(:final value):
        state = state.copyWith(
          documents: <DocumentDto>[...state.documents, ...value.items],
          nextCursor: value.nextCursor,
          loadingMore: false,
        );
      case DocumentRepositoryFailure<DocumentPageResult>(:final message):
        state = state.copyWith(loadingMore: false, message: message);
    }
  }

  /// Superseded and archived documents are hidden by default; this is the audit
  /// view toggle, not a filter over a partially loaded page.
  Future<void> setIncludeInactive(bool includeInactive) async {
    if (includeInactive == state.includeInactive) {
      return;
    }
    state = state.copyWith(includeInactive: includeInactive);
    await load();
  }

  Future<void> selectDocument(String? documentId) async {
    final workspaceId = _scope.workspaceId;
    if (documentId == null || workspaceId == null) {
      _detailGeneration++;
      state = state.copyWith(
        selectedDocumentId: null,
        versions: const <DocumentVersionDto>[],
      );
      return;
    }
    final generation = ++_detailGeneration;
    state = state.copyWith(
      selectedDocumentId: documentId,
      versions: const <DocumentVersionDto>[],
    );
    final result = await _content.listVersions(
      workspaceId: workspaceId,
      documentId: documentId,
    );
    if (generation != _detailGeneration) {
      return;
    }
    state = state.copyWith(
      versions: switch (result) {
        DocumentRepositorySuccess<List<DocumentVersionDto>>(:final value) =>
          value,
        DocumentRepositoryFailure<List<DocumentVersionDto>>() =>
          const <DocumentVersionDto>[],
      },
    );
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: PropertyDocumentsActionPhase.idle,
      actionMessage: null,
      versionConflict: null,
    );
  }

  /// Registers the document and links it to this property. The object must
  /// already be in the private bucket; the document stays `uploaded` until
  /// [confirmContent] verifies it.
  ///
  /// `create_document` registers the aggregate only — the EntityRef link is a
  /// separate command, and without it the new document would never match this
  /// screen's entity-scoped search. The contract has no combined RPC, so the
  /// two steps are not atomic: a create that succeeds and a link that fails
  /// leaves an unlinked document, and that is reported as its own outcome
  /// instead of being shown as a plain success the list then contradicts.
  Future<void> createDocument({
    required String title,
    required DocumentFileSelection file,
    String? documentTypeId,
    DateTime? validFrom,
    DateTime? validUntil,
    String? notes,
  }) async {
    if (!_guardMutation(requiredPermission: managePermission)) {
      return;
    }
    // The bytes must be in the bucket before the aggregate can reference them.
    // `create_document` mints the real id, so the object path carries a
    // caller-generated scope id instead.
    final content = await _uploadContent(
      scopeId: _idFactory(),
      versionNo: 1,
      file: file,
    );
    if (content == null) {
      return;
    }
    final draft = DocumentDraft(
      title: title,
      content: content,
      documentTypeId: documentTypeId,
      validFrom: validFrom,
      validUntil: validUntil,
      notes: notes,
    );
    DocumentRepositoryFailure<DocumentLinkDto>? linkFailure;
    await _runMutation<DocumentDto>(
      () => _repository.create(
        CreateDocumentCommand(context: _commandContext(), draft: draft),
      ),
      permissionAlreadyChecked: true,
      onSuccess: (document) async {
        final linkResult = await _links.link(
          LinkDocumentCommand(
            context: _commandContext(),
            documentId: document.id,
            entityType: entityType,
            entityId: _propertyId,
          ),
        );
        if (linkResult is DocumentRepositoryFailure<DocumentLinkDto>) {
          linkFailure = linkResult;
        }
        await load();
      },
      successMessage: 'Dokument angelegt. Upload jetzt bestätigen.',
      outcomeOverride: (_) {
        if (linkFailure == null) {
          return null;
        }
        return (
          PropertyDocumentsActionPhase.failed,
          'Das Dokument wurde angelegt, konnte aber nicht mit diesem Objekt '
              'verknüpft werden. Es erscheint deshalb noch nicht in dieser '
              'Liste.',
        );
      },
    );
  }

  Future<void> addVersion({
    required String documentId,
    required int expectedVersion,
    required int nextVersionNo,
    required DocumentFileSelection file,
  }) async {
    if (!_guardMutation(requiredPermission: managePermission)) {
      return;
    }
    final content = await _uploadContent(
      scopeId: documentId,
      versionNo: nextVersionNo,
      file: file,
    );
    if (content == null) {
      return;
    }
    await _runMutation<DocumentVersionDto>(
      () => _content.addVersion(
        AddDocumentVersionCommand(
          context: _commandContext(),
          documentId: documentId,
          expectedVersion: expectedVersion,
          content: content,
        ),
      ),
      permissionAlreadyChecked: true,
      onSuccess: (_) async {
        await load();
        await selectDocument(documentId);
      },
      successMessage: 'Neue Version hinzugefügt.',
    );
  }

  /// MIG-BND-003. Succeeds in both outcomes, so the resulting status decides
  /// what the user is told: `rejected` is a visible outcome, never a silent
  /// success.
  Future<void> confirmContent({
    required String documentId,
    required int versionNo,
    required int expectedVersion,
  }) async {
    await _runMutation<DocumentDto>(
      () => _content.confirmContent(
        ConfirmDocumentContentCommand(
          context: _commandContext(),
          documentId: documentId,
          versionNo: versionNo,
          expectedVersion: expectedVersion,
        ),
      ),
      onSuccess: (document) async {
        await load();
        await selectDocument(documentId);
      },
      successMessage: 'Upload bestätigt.',
      outcomeOverride: (document) {
        if (document.status != DocumentStatus.rejected) {
          return null;
        }
        return (
          PropertyDocumentsActionPhase.contentRejected,
          'Der hochgeladene Inhalt stimmt nicht mit den angegebenen Daten '
              'überein. Das Dokument wurde abgelehnt und muss neu hochgeladen '
              'werden.',
        );
      },
    );
  }

  Future<void> verifyVersion({
    required String documentId,
    required int versionNo,
    required int expectedVersion,
    required DocumentVerificationOutcome outcome,
    String? note,
  }) async {
    if (!_guardMutation(requiredPermission: verifyPermission)) {
      return;
    }
    await _runMutation<DocumentVersionDto>(
      () => _verification.verify(
        VerifyDocumentVersionCommand(
          context: _commandContext(),
          documentId: documentId,
          versionNo: versionNo,
          expectedVersion: expectedVersion,
          outcome: outcome,
          note: note,
        ),
      ),
      onSuccess: (_) async {
        await load();
        await selectDocument(documentId);
      },
      successMessage:
          outcome == DocumentVerificationOutcome.verified
              ? 'Version verifiziert.'
              : 'Version abgelehnt.',
      permissionAlreadyChecked: true,
    );
  }

  /// STM-008 transitions. Archiving is terminal and there is no delete path
  /// (`OPN-DOM-005` default), so the screen confirms before calling this.
  Future<void> transitionStatus({
    required String documentId,
    required int expectedVersion,
    required DocumentStatusTransition transition,
    String? supersededByDocumentId,
  }) async {
    await _runMutation<DocumentDto>(
      () => _repository.transitionStatus(
        TransitionDocumentStatusCommand(
          context: _commandContext(),
          documentId: documentId,
          expectedVersion: expectedVersion,
          transition: transition,
          supersededByDocumentId: supersededByDocumentId,
        ),
      ),
      onSuccess: (_) => load(),
      successMessage:
          transition == DocumentStatusTransition.archive
              ? 'Dokument archiviert.'
              : 'Dokument ersetzt.',
    );
  }

  /// Content is reached only through a short-lived signed URL; the TTL clamp
  /// lives in the port and is never re-implemented here.
  Future<SignedDocumentUrl?> resolveDownloadUrl({
    required String documentId,
    int? versionNo,
  }) async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return null;
    }
    final result = await _signedUrls.createSignedUrl(
      workspaceId: workspaceId,
      documentId: documentId,
      versionNo: versionNo,
    );
    switch (result) {
      case DocumentRepositorySuccess<SignedDocumentUrl>(:final value):
        return value;
      case DocumentRepositoryFailure<SignedDocumentUrl>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          actionPhase:
              kind == DocumentRepositoryFailureKind.forbidden
                  ? PropertyDocumentsActionPhase.forbidden
                  : PropertyDocumentsActionPhase.failed,
          actionMessage: message,
        );
        return null;
    }
  }

  /// Uploads the picked bytes and reports failure in the same visible phases as
  /// any other mutation. Returns null when the upload failed, so callers stop
  /// before registering a document whose content is not there.
  Future<DocumentContentDraft?> _uploadContent({
    required String scopeId,
    required int versionNo,
    required DocumentFileSelection file,
  }) async {
    state = state.copyWith(
      actionPhase: PropertyDocumentsActionPhase.submitting,
      actionMessage: null,
      versionConflict: null,
    );
    final result = await _upload.upload(
      workspaceId: _scope.workspaceId!,
      scopeId: scopeId,
      versionNo: versionNo,
      filename: file.filename,
      mimeType: file.mimeType,
      bytes: file.bytes,
    );
    switch (result) {
      case DocumentRepositorySuccess<DocumentContentDraft>(:final value):
        return value;
      case DocumentRepositoryFailure<DocumentContentDraft>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          actionPhase: _phaseForFailure(kind),
          actionMessage: message,
        );
        return null;
    }
  }

  static PropertyDocumentsActionPhase _phaseForFailure(
    DocumentRepositoryFailureKind kind,
  ) {
    return switch (kind) {
      DocumentRepositoryFailureKind.versionConflict =>
        PropertyDocumentsActionPhase.conflict,
      DocumentRepositoryFailureKind.forbidden =>
        PropertyDocumentsActionPhase.forbidden,
      DocumentRepositoryFailureKind.dependencyConflict =>
        PropertyDocumentsActionPhase.readOnly,
      _ => PropertyDocumentsActionPhase.failed,
    };
  }

  bool _guardMutation({required String requiredPermission}) {
    if (isReadOnlyBackend) {
      state = state.copyWith(
        actionPhase: PropertyDocumentsActionPhase.readOnly,
        actionMessage:
            'Dokumente sind in der lokalen Datenbank schreibgeschützt, bis '
            'diese Domäne migriert ist.',
        versionConflict: null,
      );
      return false;
    }
    if (!_scope.isResolved || !_authorization.can(requiredPermission)) {
      state = state.copyWith(
        actionPhase: PropertyDocumentsActionPhase.forbidden,
        actionMessage: 'Für diese Aktion fehlt die Berechtigung.',
        versionConflict: null,
      );
      return false;
    }
    return true;
  }

  Future<void> _runMutation<T>(
    Future<DocumentRepositoryResult<T>> Function() command, {
    required Future<void> Function(T value) onSuccess,
    required String successMessage,
    (PropertyDocumentsActionPhase, String)? Function(T value)? outcomeOverride,
    bool permissionAlreadyChecked = false,
  }) async {
    if (!permissionAlreadyChecked &&
        !_guardMutation(requiredPermission: managePermission)) {
      return;
    }
    state = state.copyWith(
      actionPhase: PropertyDocumentsActionPhase.submitting,
      actionMessage: null,
      versionConflict: null,
    );
    final result = await command();
    switch (result) {
      case DocumentRepositorySuccess<T>(:final value):
        await onSuccess(value);
        final override = outcomeOverride?.call(value);
        state = state.copyWith(
          actionPhase: override?.$1 ?? PropertyDocumentsActionPhase.succeeded,
          actionMessage: override?.$2 ?? successMessage,
          versionConflict: null,
        );
      case DocumentRepositoryFailure<T>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        state = state.copyWith(
          actionPhase: _phaseForFailure(kind),
          actionMessage: message,
          versionConflict: versionConflict,
        );
    }
  }

  DocumentCommandContext _commandContext() {
    return DocumentCommandContext(
      workspaceId: _scope.workspaceId!,
      actorId: _scope.actorId!,
      mutationId: _idFactory(),
      correlationId: _idFactory(),
    );
  }

  void _subscribeToInvalidation(String workspaceId) {
    final source = _invalidationSource;
    if (source == null || _invalidationSubscription != null) {
      return;
    }
    _invalidationSubscription = source
        .watchWorkspace(workspaceId: workspaceId)
        .listen((invalidation) {
          if (invalidation.workspaceId != _scope.workspaceId) {
            return;
          }
          unawaited(load());
        });
  }

  @override
  void dispose() {
    unawaited(_invalidationSubscription?.cancel());
    _invalidationSubscription = null;
    super.dispose();
  }
}

final propertyDocumentsControllerProvider = StateNotifierProvider.autoDispose
    .family<PropertyDocumentsController, PropertyDocumentsState, String>((
      ref,
      propertyId,
    ) {
      final controller = PropertyDocumentsController(
        repository: ref.watch(documentRepositoryProvider),
        content: ref.watch(documentContentProvider),
        upload: ref.watch(documentUploadProvider),
        links: ref.watch(documentLinkProvider),
        requirements: ref.watch(requirementPolicyProvider),
        verification: ref.watch(documentVerificationProvider),
        signedUrls: ref.watch(signedUrlProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
        propertyId: propertyId,
        invalidationSource: ref.watch(documentQueryInvalidationSourceProvider),
      );
      unawaited(controller.load());
      return controller;
    });
