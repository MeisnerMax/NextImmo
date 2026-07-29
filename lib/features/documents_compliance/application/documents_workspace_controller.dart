/// Screen-facing orchestration over the documents_compliance contract for the
/// whole workspace (SCR-051, Wave 2, Arbeitspaket 4).
///
/// This is [PropertyDocumentsController] generalised from one property to the
/// workspace: same shape (explicit phases per zone, a generation guard against
/// out-of-order responses, every mandatory screen state of
/// `03_design_system.md` as data rather than as a widget branch), same three
/// domain specifics (the MIG-BND-003 `rejected` outcome of `confirmContent`,
/// the separate `document.verify` capability, no delete path), and four
/// deliberate differences that the wider scope forces:
///
/// * **No entity pinning.** The list query carries no EntityRef, so the search
///   returns every document of the workspace.
/// * **The server-side filter is the document type.** `DocumentListQuery`
///   accepts an entity filter only as a *pair* (`assert((entityType == null) ==
///   (entityId == null))`), and a workspace-wide screen has no controlled
///   source of entity ids — so the contract-backed filter this controller
///   offers is `documentTypeId`. The document-type registry carries the level
///   (`DocumentTypeDto.entityType`), which is what lets the screen offer a
///   level filter on top without inventing a backend read. See the AP4 notes in
///   `04b_wave2_contacts_documents.md`.
/// * **Creating does not link.** `create_document` registers the aggregate; the
///   EntityRef link is a separate command that needs an entity id this scope
///   does not have. A workspace-wide document is complete without one, so this
///   controller creates and says so, instead of guessing an owner.
/// * **The selection loads its links.** One `listLinks` read per selected
///   document (never per row) answers "what does this document belong to",
///   which the property-scoped screen never has to ask.
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

enum DocumentsWorkspaceListPhase {
  idle,
  loading,
  ready,
  empty,
  forbidden,
  error,
}

enum DocumentsWorkspaceActionPhase {
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

class DocumentsWorkspaceState {
  const DocumentsWorkspaceState({
    required this.listPhase,
    this.actionPhase = DocumentsWorkspaceActionPhase.idle,
    this.documents = const <DocumentDto>[],
    this.versions = const <DocumentVersionDto>[],
    this.links = const <DocumentLinkDto>[],
    this.nextCursor,
    this.loadingMore = false,
    this.includeInactive = false,
    this.documentTypeFilter,
    this.selectedDocumentId,
    this.versionConflict,
    this.message,
    this.actionMessage,
  });

  const DocumentsWorkspaceState.loading()
    : this(listPhase: DocumentsWorkspaceListPhase.loading);

  final DocumentsWorkspaceListPhase listPhase;
  final DocumentsWorkspaceActionPhase actionPhase;
  final List<DocumentDto> documents;

  /// Versions of the selected document only.
  final List<DocumentVersionDto> versions;

  /// EntityRef links of the selected document only.
  final List<DocumentLinkDto> links;
  final String? nextCursor;
  final bool loadingMore;
  final bool includeInactive;

  /// Server-side filter, passed straight into `DocumentListQuery`.
  final String? documentTypeFilter;
  final String? selectedDocumentId;
  final DocumentVersionConflict? versionConflict;
  final String? message;
  final String? actionMessage;

  bool get hasMore => nextCursor != null;

  DocumentDto? get selectedDocument {
    final id = selectedDocumentId;
    if (id == null) {
      return null;
    }
    for (final document in documents) {
      if (document.id == id) {
        return document;
      }
    }
    return null;
  }

  DocumentsWorkspaceState copyWith({
    DocumentsWorkspaceListPhase? listPhase,
    DocumentsWorkspaceActionPhase? actionPhase,
    List<DocumentDto>? documents,
    List<DocumentVersionDto>? versions,
    List<DocumentLinkDto>? links,
    Object? nextCursor = _unchanged,
    bool? loadingMore,
    bool? includeInactive,
    Object? documentTypeFilter = _unchanged,
    Object? selectedDocumentId = _unchanged,
    Object? versionConflict = _unchanged,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
  }) {
    return DocumentsWorkspaceState(
      listPhase: listPhase ?? this.listPhase,
      actionPhase: actionPhase ?? this.actionPhase,
      documents: documents ?? this.documents,
      versions: versions ?? this.versions,
      links: links ?? this.links,
      nextCursor:
          identical(nextCursor, _unchanged)
              ? this.nextCursor
              : nextCursor as String?,
      loadingMore: loadingMore ?? this.loadingMore,
      includeInactive: includeInactive ?? this.includeInactive,
      documentTypeFilter:
          identical(documentTypeFilter, _unchanged)
              ? this.documentTypeFilter
              : documentTypeFilter as String?,
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

typedef DocumentsWorkspaceIdFactory = String Function();

class DocumentsWorkspaceController
    extends StateNotifier<DocumentsWorkspaceState> {
  DocumentsWorkspaceController({
    required DocumentRepository repository,
    required DocumentContentPort content,
    required DocumentLinkPort links,
    required DocumentVerificationPort verification,
    required SignedUrlPort signedUrls,
    required WorkspaceSessionScope scope,
    DocumentQueryInvalidationSource? invalidationSource,
    DocumentsWorkspaceIdFactory? idFactory,
  }) : _repository = repository,
       _content = content,
       _links = links,
       _verification = verification,
       _signedUrls = signedUrls,
       _scope = scope,
       _invalidationSource = invalidationSource,
       _idFactory = idFactory ?? const Uuid().v4,
       super(const DocumentsWorkspaceState.loading());

  static const String readPermission = 'document.read';

  /// The cloud vocabulary, as in [PropertyDocumentsController]: the local RBAC
  /// catalogue spells editing differently (`document.create`/`document.update`)
  /// and that divergence stays harmless because local mode is read-only until
  /// this domain is migrated — `isReadOnlyBackend` denies every mutation before
  /// a permission is ever consulted.
  static const String managePermission = 'document.manage';
  static const String verifyPermission = 'document.verify';
  static const int pageSize = 50;

  final DocumentRepository _repository;
  final DocumentContentPort _content;
  final DocumentLinkPort _links;
  final DocumentVerificationPort _verification;
  final SignedUrlPort _signedUrls;
  final WorkspaceSessionScope _scope;
  final DocumentQueryInvalidationSource? _invalidationSource;
  final DocumentsWorkspaceIdFactory _idFactory;

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
        listPhase: DocumentsWorkspaceListPhase.idle,
        documents: const <DocumentDto>[],
        nextCursor: null,
        message: null,
      );
      return;
    }
    _subscribeToInvalidation(workspaceId);
    final generation = ++_generation;
    state = state.copyWith(
      listPhase: DocumentsWorkspaceListPhase.loading,
      message: null,
    );
    final result = await _repository.search(
      DocumentListQuery(
        workspaceId: workspaceId,
        documentTypeId: state.documentTypeFilter,
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
                  ? DocumentsWorkspaceListPhase.empty
                  : DocumentsWorkspaceListPhase.ready,
          documents: value.items,
          nextCursor: value.nextCursor,
          message: null,
        );
      case DocumentRepositoryFailure<DocumentPageResult>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          listPhase:
              kind == DocumentRepositoryFailureKind.forbidden
                  ? DocumentsWorkspaceListPhase.forbidden
                  : DocumentsWorkspaceListPhase.error,
          documents: const <DocumentDto>[],
          nextCursor: null,
          message: message,
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
        documentTypeId: state.documentTypeFilter,
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

  /// The one contract-backed list filter of this screen. Passing null clears it.
  /// Re-runs the keyset search from the first page, because a cursor is only
  /// valid for the query that produced it.
  Future<void> setDocumentTypeFilter(String? documentTypeId) async {
    if (documentTypeId == state.documentTypeFilter) {
      return;
    }
    state = state.copyWith(documentTypeFilter: documentTypeId);
    await load();
  }

  Future<void> selectDocument(String? documentId) async {
    final workspaceId = _scope.workspaceId;
    if (documentId == null || workspaceId == null) {
      _detailGeneration++;
      state = state.copyWith(
        selectedDocumentId: null,
        versions: const <DocumentVersionDto>[],
        links: const <DocumentLinkDto>[],
      );
      return;
    }
    final generation = ++_detailGeneration;
    state = state.copyWith(
      selectedDocumentId: documentId,
      versions: const <DocumentVersionDto>[],
      links: const <DocumentLinkDto>[],
    );
    final results = await Future.wait(<Future<Object>>[
      _content.listVersions(workspaceId: workspaceId, documentId: documentId),
      _links.listLinks(workspaceId: workspaceId, documentId: documentId),
    ]);
    if (generation != _detailGeneration) {
      return;
    }
    final versionResult =
        results.first as DocumentRepositoryResult<List<DocumentVersionDto>>;
    final linkResult =
        results.last as DocumentRepositoryResult<List<DocumentLinkDto>>;
    state = state.copyWith(
      versions: switch (versionResult) {
        DocumentRepositorySuccess<List<DocumentVersionDto>>(:final value) =>
          value,
        DocumentRepositoryFailure<List<DocumentVersionDto>>() =>
          const <DocumentVersionDto>[],
      },
      links: switch (linkResult) {
        DocumentRepositorySuccess<List<DocumentLinkDto>>(:final value) => value,
        DocumentRepositoryFailure<List<DocumentLinkDto>>() =>
          const <DocumentLinkDto>[],
      },
    );
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: DocumentsWorkspaceActionPhase.idle,
      actionMessage: null,
      versionConflict: null,
    );
  }

  /// Registers the document. The object must already be in the private bucket;
  /// the document stays `uploaded` until [confirmContent] verifies it.
  ///
  /// No EntityRef link is created: this scope has no entity, and inventing one
  /// would attach the document to something the user never chose. Linking to an
  /// object happens on that object's document surface (SCR-020).
  Future<void> createDocument(DocumentDraft draft) async {
    await _runMutation<DocumentDto>(
      () => _repository.create(
        CreateDocumentCommand(context: _commandContext(), draft: draft),
      ),
      onSuccess: (_) => load(),
      successMessage:
          'Dokument angelegt. Upload jetzt bestätigen. Die Verknüpfung mit '
          'einem Objekt erfolgt im Dokumentbereich des Objekts.',
    );
  }

  Future<void> addVersion({
    required String documentId,
    required int expectedVersion,
    required DocumentContentDraft content,
  }) async {
    await _runMutation<DocumentVersionDto>(
      () => _content.addVersion(
        AddDocumentVersionCommand(
          context: _commandContext(),
          documentId: documentId,
          expectedVersion: expectedVersion,
          content: content,
        ),
      ),
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
      onSuccess: (_) async {
        await load();
        await selectDocument(documentId);
      },
      successMessage: 'Upload bestätigt.',
      outcomeOverride: (document) {
        if (document.status != DocumentStatus.rejected) {
          return null;
        }
        return (
          DocumentsWorkspaceActionPhase.contentRejected,
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
                  ? DocumentsWorkspaceActionPhase.forbidden
                  : DocumentsWorkspaceActionPhase.failed,
          actionMessage: message,
        );
        return null;
    }
  }

  bool _guardMutation({required String requiredPermission}) {
    if (isReadOnlyBackend) {
      state = state.copyWith(
        actionPhase: DocumentsWorkspaceActionPhase.readOnly,
        actionMessage:
            'Dokumente sind in der lokalen Datenbank schreibgeschützt, bis '
            'diese Domäne migriert ist.',
        versionConflict: null,
      );
      return false;
    }
    if (!_scope.isResolved || !_authorization.can(requiredPermission)) {
      state = state.copyWith(
        actionPhase: DocumentsWorkspaceActionPhase.forbidden,
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
    (DocumentsWorkspaceActionPhase, String)? Function(T value)? outcomeOverride,
    bool permissionAlreadyChecked = false,
  }) async {
    if (!permissionAlreadyChecked &&
        !_guardMutation(requiredPermission: managePermission)) {
      return;
    }
    state = state.copyWith(
      actionPhase: DocumentsWorkspaceActionPhase.submitting,
      actionMessage: null,
      versionConflict: null,
    );
    final result = await command();
    switch (result) {
      case DocumentRepositorySuccess<T>(:final value):
        await onSuccess(value);
        final override = outcomeOverride?.call(value);
        state = state.copyWith(
          actionPhase: override?.$1 ?? DocumentsWorkspaceActionPhase.succeeded,
          actionMessage: override?.$2 ?? successMessage,
          versionConflict: null,
        );
      case DocumentRepositoryFailure<T>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        state = state.copyWith(
          actionPhase: switch (kind) {
            DocumentRepositoryFailureKind.versionConflict =>
              DocumentsWorkspaceActionPhase.conflict,
            DocumentRepositoryFailureKind.forbidden =>
              DocumentsWorkspaceActionPhase.forbidden,
            DocumentRepositoryFailureKind.dependencyConflict =>
              DocumentsWorkspaceActionPhase.readOnly,
            _ => DocumentsWorkspaceActionPhase.failed,
          },
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

final documentsWorkspaceControllerProvider = StateNotifierProvider.autoDispose<
  DocumentsWorkspaceController,
  DocumentsWorkspaceState
>((ref) {
  final controller = DocumentsWorkspaceController(
    repository: ref.watch(documentRepositoryProvider),
    content: ref.watch(documentContentProvider),
    links: ref.watch(documentLinkProvider),
    verification: ref.watch(documentVerificationProvider),
    signedUrls: ref.watch(signedUrlProvider),
    scope: ref.watch(workspaceSessionScopeProvider),
    invalidationSource: ref.watch(documentQueryInvalidationSourceProvider),
  );
  unawaited(controller.load());
  return controller;
});
