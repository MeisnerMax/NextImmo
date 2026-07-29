import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_providers.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_repository.dart';
import 'package:neximmo_app/features/documents_compliance/application/documents_workspace_controller.dart';
import 'package:neximmo_app/features/documents_compliance/domain/document_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/ui/screens/docs/documents_screen.dart';
import 'package:neximmo_app/ui/screens/docs/documents_workspace_panel.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Mandatory-state coverage for the rebuilt workspace-wide documents workplace
/// (SCR-051, Phase 2, Wave 2, Arbeitspaket 4). Mirrors
/// `test/ui/screens/property_detail/property_documents_states_test.dart` — the
/// property-scoped surface this one generalises — and adds the states that only
/// exist once the scope is the whole workspace: the two distinct empty
/// conditions, the level/type filters, and a create that deliberately does not
/// invent an entity link.
///
/// The panel is tested, not `DocumentsScreen`: that file is the local four-tab
/// host whose remaining tabs still read the legacy document registries, while
/// the panel is the whole Wave 2 rebuild and the unit the additive cloud route
/// mounts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String workspace = 'ws-1';

  /// `find.byType` matches the exact runtime type, so the private `*.icon`
  /// button subclasses would slip through. Match by `is` instead.
  Finder buttonWithText<T extends Widget>(String text) {
    return find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate((widget) => widget is T),
    );
  }

  WorkspaceSessionScope cloudScope({
    Set<String> permissions = const <String>{
      'document.read',
      'document.manage',
      'document.verify',
    },
  }) {
    return WorkspaceSessionScope(
      workspaceId: workspace,
      actorId: 'actor-1',
      permissions: permissions,
      mutationsSupported: true,
    );
  }

  WorkspaceSessionScope localScope() {
    return WorkspaceSessionScope(
      workspaceId: workspace,
      actorId: 'actor-1',
      permissions: const <String>{},
      mutationsSupported: false,
    );
  }

  DocumentVersionDto version(
    String documentId, {
    int versionNo = 1,
    DocumentVerificationStatus verificationStatus =
        DocumentVerificationStatus.pending,
    DateTime? contentConfirmedAt,
  }) {
    return DocumentVersionDto(
      id: '$documentId-v$versionNo',
      workspaceId: workspace,
      documentId: documentId,
      versionNo: versionNo,
      storageBucket: 'documents',
      storageObjectPath: '$workspace/$documentId/$versionNo.pdf',
      contentHash: 'a' * 64,
      byteSize: 20480,
      mimeType: 'application/pdf',
      verificationStatus: verificationStatus,
      version: 1,
      originalFilename: 'nachweis.pdf',
      contentConfirmedAt: contentConfirmedAt,
    );
  }

  DocumentDto document(
    String id,
    String title, {
    DocumentStatus status = DocumentStatus.available,
    int documentVersion = 3,
    String? documentTypeId = 'type-1',
    DateTime? validUntil,
  }) {
    return DocumentDto(
      id: id,
      workspaceId: workspace,
      title: title,
      status: status,
      currentVersionNo: 1,
      version: documentVersion,
      documentTypeId: documentTypeId,
      validUntil: validUntil,
      updatedAt: DateTime.utc(2026, 6, 1),
    );
  }

  DocumentLinkDto link(
    String documentId, {
    DocumentLinkEntityType entityType = DocumentLinkEntityType.property,
  }) {
    return DocumentLinkDto(
      id: '$documentId-link',
      workspaceId: workspace,
      documentId: documentId,
      entityType: entityType,
      entityId: 'entity-1',
    );
  }

  Future<ProviderContainer> pumpPanel(
    WidgetTester tester, {
    required _FakeDocumentBackend backend,
    WorkspaceSessionScope? scope,
    Size size = const Size(1440, 900),
    AppDensityModeSetting density = AppDensityModeSetting.comfort,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          workspaceSessionScopeProvider.overrideWithValue(
            scope ?? cloudScope(),
          ),
          documentRepositoryProvider.overrideWithValue(backend),
          documentContentProvider.overrideWithValue(backend),
          documentLinkProvider.overrideWithValue(backend),
          requirementPolicyProvider.overrideWithValue(backend),
          documentVerificationProvider.overrideWithValue(backend),
          signedUrlProvider.overrideWithValue(backend),
        ],
        child: MaterialApp(
          theme: AppTheme.light(densityMode: density),
          home: const Scaffold(body: DocumentsWorkspacePanel()),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
    return ProviderScope.containerOf(
      tester.element(find.byType(DocumentsWorkspacePanel)),
    );
  }

  DocumentsWorkspaceController controllerOf(ProviderContainer container) {
    return container.read(documentsWorkspaceControllerProvider.notifier);
  }

  testWidgets('loading shows a table skeleton, not a full-page spinner', (
    tester,
  ) async {
    final backend = _FakeDocumentBackend()..holdSearch();
    await pumpPanel(tester, backend: backend, settle: false);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    // Header and filters stay usable while the table loads.
    expect(find.text('Dokumente'), findsOneWidget);
    expect(find.text('Dokumente durchsuchen'), findsOneWidget);

    backend.releaseSearch();
    await tester.pumpAndSettle();
  });

  testWidgets('an empty workspace names the next concrete action', (
    tester,
  ) async {
    await pumpPanel(tester, backend: _FakeDocumentBackend());

    expect(find.text('Noch keine Dokumente'), findsOneWidget);
    expect(buttonWithText<FilledButton>('Dokument hinzufügen'), findsWidgets);
    expect(find.text('Keine Dokumente für diesen Filter'), findsNothing);
  });

  testWidgets('a search without hits is its own state, not "no documents yet"', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      backend: _FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('Keine Dokumente für diesen Filter'), findsOneWidget);
    expect(find.text('Noch keine Dokumente'), findsNothing);
    expect(find.text('Filter zurücksetzen'), findsOneWidget);
  });

  testWidgets('resetting the filters brings the documents back', (tester) async {
    await pumpPanel(
      tester,
      backend: _FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filter zurücksetzen'));
    await tester.pumpAndSettle();

    expect(find.text('Kaufvertrag'), findsOneWidget);
  });

  testWidgets(
    'a backend-side type filter without hits also reads as a filter state',
    (tester) async {
      final backend = _FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      );
      final container = await pumpPanel(tester, backend: backend);

      // type-2 exists in the registry but no document carries it.
      await controllerOf(container).setDocumentTypeFilter('type-2');
      await tester.pumpAndSettle();

      expect(backend.lastQuery?.documentTypeId, 'type-2');
      expect(find.text('Keine Dokumente für diesen Filter'), findsOneWidget);
      expect(find.text('Noch keine Dokumente'), findsNothing);
    },
  );

  testWidgets('the workspace search carries no entity filter', (tester) async {
    final backend = _FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
    );
    await pumpPanel(tester, backend: backend);

    expect(backend.lastQuery?.workspaceId, workspace);
    expect(backend.lastQuery?.entityType, isNull);
    expect(backend.lastQuery?.entityId, isNull);
  });

  testWidgets('the level filter narrows to the level of the document type', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      backend: _FakeDocumentBackend(
        documents: <DocumentDto>[
          document('d1', 'Kaufvertrag'),
          document('d2', 'Mieterakte', documentTypeId: 'type-2'),
        ],
      ),
    );

    expect(find.text('Kaufvertrag'), findsOneWidget);
    expect(find.text('Mieterakte'), findsOneWidget);

    await tester.tap(find.text('Alle Ebenen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partei').last);
    await tester.pumpAndSettle();

    expect(find.text('Mieterakte'), findsOneWidget);
    expect(find.text('Kaufvertrag'), findsNothing);
  });

  testWidgets('infrastructure failure offers retry without raw exception text', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      backend: _FakeDocumentBackend(
        searchFailure: const DocumentRepositoryFailure<DocumentPageResult>(
          kind: DocumentRepositoryFailureKind.infrastructureFailure,
          message: 'Exception: socket closed',
        ),
      ),
    );

    expect(find.text('Dokumente konnten nicht geladen werden'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsWidgets);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('forbidden is its own state, distinct from empty and error', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      backend: _FakeDocumentBackend(
        searchFailure: const DocumentRepositoryFailure<DocumentPageResult>(
          kind: DocumentRepositoryFailureKind.forbidden,
          message: 'document.read missing',
        ),
      ),
    );

    expect(find.text('Kein Zugriff auf Dokumente'), findsOneWidget);
    expect(find.text('Noch keine Dokumente'), findsNothing);
    expect(find.text('Dokumente konnten nicht geladen werden'), findsNothing);
  });

  testWidgets('read-only backend explains itself and disables creating', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      backend: _FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      ),
      scope: localScope(),
    );

    expect(find.text('Schreibgeschützt bis zur Migration'), findsOneWidget);
    final createButton =
        tester
            .widgetList<FilledButton>(
              buttonWithText<FilledButton>('Dokument hinzufügen'),
            )
            .first;
    expect(createButton.onPressed, isNull);
  });

  testWidgets(
    'a mutation on the read-only backend reports it instead of silently '
    'no-opping',
    (tester) async {
      final backend = _FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      );
      final container = await pumpPanel(
        tester,
        backend: backend,
        scope: localScope(),
      );

      await controllerOf(container).createDocument(_draft());
      await tester.pumpAndSettle();

      expect(backend.createCalls, 0);
      expect(find.textContaining('schreibgeschützt'), findsOneWidget);
    },
  );

  testWidgets('version conflict shows both versions and a resolve action', (
    tester,
  ) async {
    final current = document('d1', 'Kaufvertrag');
    final backend = _FakeDocumentBackend(
      documents: <DocumentDto>[current],
      transitionFailure: DocumentRepositoryFailure<DocumentDto>(
        kind: DocumentRepositoryFailureKind.versionConflict,
        message: 'stale',
        versionConflict: DocumentVersionConflict(
          expectedVersion: 3,
          actualVersion: 5,
          currentDocument: current,
        ),
      ),
    );
    final container = await pumpPanel(tester, backend: backend);

    await controllerOf(container).transitionStatus(
      documentId: 'd1',
      expectedVersion: 3,
      transition: DocumentStatusTransition.archive,
    );
    await tester.pumpAndSettle();

    expect(find.text('Zwischenzeitlich geändert'), findsOneWidget);
    expect(find.textContaining('Deine Version: 3'), findsOneWidget);
    expect(find.textContaining('Aktuelle Version: 5'), findsOneWidget);
    expect(find.text('Aktuellen Stand laden'), findsOneWidget);
  });

  testWidgets('missing document.manage forbids mutations without pretending', (
    tester,
  ) async {
    final backend = _FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
    );
    final container = await pumpPanel(
      tester,
      backend: backend,
      scope: cloudScope(permissions: const <String>{'document.read'}),
    );

    await controllerOf(container).createDocument(_draft());
    await tester.pumpAndSettle();

    expect(backend.createCalls, 0);
    expect(find.textContaining('fehlt die Berechtigung'), findsOneWidget);
  });

  testWidgets('document.verify is gated separately from document.manage', (
    tester,
  ) async {
    final backend = _FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
    );
    final container = await pumpPanel(
      tester,
      backend: backend,
      scope: cloudScope(
        permissions: const <String>{'document.read', 'document.manage'},
      ),
    );
    final controller = controllerOf(container);
    expect(controller.canMutate, isTrue);
    expect(controller.canVerify, isFalse);

    await controller.verifyVersion(
      documentId: 'd1',
      versionNo: 1,
      expectedVersion: 3,
      outcome: DocumentVerificationOutcome.verified,
    );
    await tester.pumpAndSettle();

    expect(backend.verifyCalls, 0);
    expect(find.textContaining('fehlt die Berechtigung'), findsOneWidget);
  });

  testWidgets(
    'a rejected upload confirmation is a visible outcome, not a silent success',
    (tester) async {
      final backend = _FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
        confirmResult: document(
          'd1',
          'Kaufvertrag',
          status: DocumentStatus.rejected,
        ),
      );
      final container = await pumpPanel(tester, backend: backend);

      await controllerOf(container).confirmContent(
        documentId: 'd1',
        versionNo: 1,
        expectedVersion: 3,
      );
      await tester.pumpAndSettle();

      expect(backend.confirmCalls, 1);
      expect(find.text('Upload abgelehnt'), findsOneWidget);
      expect(find.textContaining('Upload bestätigt.'), findsNothing);
    },
  );

  testWidgets('a cancelled archive confirmation does not run the mutation', (
    tester,
  ) async {
    final backend = _FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      versions: <DocumentVersionDto>[version('d1')],
    );
    await pumpPanel(tester, backend: backend);

    await tester.tap(find.text('Kaufvertrag'));
    await tester.pumpAndSettle();
    await tester.tap(buttonWithText<OutlinedButton>('Archivieren'));
    await tester.pumpAndSettle();

    expect(find.text('Dokument archivieren'), findsOneWidget);
    expect(backend.transitionCalls, 0);

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect(backend.transitionCalls, 0);
    expect(find.text('Dokument archivieren'), findsNothing);
  });

  testWidgets('there is no delete affordance (OPN-DOM-005 stays open)', (
    tester,
  ) async {
    final backend = _FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      versions: <DocumentVersionDto>[version('d1')],
    );
    await pumpPanel(tester, backend: backend);

    await tester.tap(find.text('Kaufvertrag'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Löschen'), findsNothing);
    expect(find.textContaining('Loeschen'), findsNothing);
    expect(find.textContaining('Delete'), findsNothing);
    expect(buttonWithText<OutlinedButton>('Archivieren'), findsOneWidget);
  });

  testWidgets('creating in workspace scope does not invent an entity link', (
    tester,
  ) async {
    final backend = _FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
    );
    final container = await pumpPanel(tester, backend: backend);

    await controllerOf(container).createDocument(_draft());
    await tester.pumpAndSettle();

    expect(backend.createCalls, 1);
    expect(backend.linkCalls, 0);
  });

  testWidgets('the detail names the levels a document is linked to', (
    tester,
  ) async {
    final backend = _FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      versions: <DocumentVersionDto>[version('d1')],
      links: <DocumentLinkDto>[link('d1')],
    );
    await pumpPanel(tester, backend: backend);

    await tester.tap(find.text('Kaufvertrag'));
    await tester.pumpAndSettle();

    expect(find.text('Verknüpft mit: Objekt'), findsOneWidget);
  });

  testWidgets('an unlinked document says so instead of showing nothing', (
    tester,
  ) async {
    final backend = _FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      versions: <DocumentVersionDto>[version('d1')],
    );
    await pumpPanel(tester, backend: backend);

    await tester.tap(find.text('Kaufvertrag'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Noch keiner Entität zugeordnet'), findsOneWidget);
  });

  testWidgets('content is reached through a signed URL with its expiry', (
    tester,
  ) async {
    final backend = _FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      versions: <DocumentVersionDto>[version('d1')],
    );
    await pumpPanel(tester, backend: backend);

    await tester.tap(find.text('Kaufvertrag'));
    await tester.pumpAndSettle();
    await tester.tap(buttonWithText<OutlinedButton>('Inhalt öffnen'));
    await tester.pumpAndSettle();

    expect(find.text('Download-Link'), findsOneWidget);
    expect(find.textContaining('5 Minuten'), findsOneWidget);
  });

  testWidgets(
    'the local host keeps all four document surfaces and opens the rebuilt '
    'workplace first',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final backend = _FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            workspaceSessionScopeProvider.overrideWithValue(cloudScope()),
            documentRepositoryProvider.overrideWithValue(backend),
            documentContentProvider.overrideWithValue(backend),
            documentLinkProvider.overrideWithValue(backend),
            requirementPolicyProvider.overrideWithValue(backend),
            documentVerificationProvider.overrideWithValue(backend),
            signedUrlProvider.overrideWithValue(backend),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: DocumentsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The tab that `navigation_actions.dart` jumps into (Compliance, index 3)
      // and the two legacy registries stay reachable.
      expect(find.text('Typen'), findsOneWidget);
      expect(find.text('Pflichtregeln'), findsOneWidget);
      expect(find.text('Compliance'), findsOneWidget);
      // Tab 0 is the rebuild, and only tab 0 is built up front — so the host
      // reaches no legacy repository for the surface it shows first.
      expect(find.byType(DocumentsWorkspacePanel), findsOneWidget);
      expect(find.text('Kaufvertrag'), findsOneWidget);
    },
  );

  group('responsive', () {
    const sizes = <String, Size>{
      'phone 390x844': Size(390, 844),
      'tablet 1024x768': Size(1024, 768),
      'desktop 1440x900': Size(1440, 900),
    };

    for (final density in AppDensityModeSetting.values) {
      for (final entry in sizes.entries) {
        testWidgets('${entry.key} renders in ${density.name} density', (
          tester,
        ) async {
          await pumpPanel(
            tester,
            backend: _FakeDocumentBackend(
              documents: <DocumentDto>[
                document('d1', 'Kaufvertrag'),
                document('d2', 'Energieausweis 2026'),
              ],
            ),
            size: entry.value,
            density: density,
          );

          expect(tester.takeException(), isNull);
          expect(find.text('Kaufvertrag'), findsOneWidget);
          expect(find.text('Energieausweis 2026'), findsOneWidget);
        });
      }
    }
  });
}

DocumentDraft _draft() {
  return DocumentDraft(
    title: 'Neuer Nachweis',
    content: DocumentContentDraft(
      storageObjectPath: 'ws-1/new.pdf',
      contentHash: 'b' * 64,
      byteSize: 1024,
      mimeType: 'application/pdf',
    ),
  );
}

/// One fake serving all six documents_compliance ports, matching how a real
/// backend binds them (one adapter instance per domain).
class _FakeDocumentBackend
    implements
        DocumentRepository,
        DocumentContentPort,
        DocumentLinkPort,
        RequirementPolicyRepository,
        DocumentVerificationPort,
        SignedUrlPort {
  _FakeDocumentBackend({
    this.documents = const <DocumentDto>[],
    this.versions = const <DocumentVersionDto>[],
    this.links = const <DocumentLinkDto>[],
    this.searchFailure,
    this.transitionFailure,
    this.confirmResult,
  });

  final List<DocumentDto> documents;
  final List<DocumentVersionDto> versions;
  final List<DocumentLinkDto> links;
  final DocumentRepositoryFailure<DocumentPageResult>? searchFailure;
  final DocumentRepositoryFailure<DocumentDto>? transitionFailure;
  final DocumentDto? confirmResult;

  int createCalls = 0;
  int linkCalls = 0;
  int transitionCalls = 0;
  int verifyCalls = 0;
  int confirmCalls = 0;
  int addVersionCalls = 0;
  DocumentListQuery? lastQuery;
  Completer<void>? _searchGate;

  void holdSearch() => _searchGate = Completer<void>();

  void releaseSearch() => _searchGate?.complete();

  DocumentDto get _anyDocument =>
      documents.isNotEmpty
          ? documents.first
          : DocumentDto(
            id: 'generated',
            workspaceId: 'ws-1',
            title: 'Neuer Nachweis',
            status: DocumentStatus.uploaded,
            currentVersionNo: 1,
            version: 1,
          );

  @override
  Future<DocumentRepositoryResult<DocumentPageResult>> search(
    DocumentListQuery query,
  ) async {
    lastQuery = query;
    await _searchGate?.future;
    final failure = searchFailure;
    if (failure != null) {
      return failure;
    }
    // The document-type filter is a backend filter in the contract, so the fake
    // honours it here instead of letting the screen fake it client-side.
    final items =
        query.documentTypeId == null
            ? documents
            : documents
                .where(
                  (document) =>
                      document.documentTypeId == query.documentTypeId,
                )
                .toList(growable: false);
    return DocumentRepositorySuccess<DocumentPageResult>(
      DocumentPageResult(items: items),
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
            workspaceId: 'ws-1',
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
    return const DocumentRepositorySuccess<List<DocumentTypeDto>>(
      <DocumentTypeDto>[
        DocumentTypeDto(
          id: 'type-1',
          workspaceId: 'ws-1',
          key: 'purchase_contract',
          name: 'Vertragsunterlage',
          entityType: DocumentLinkEntityType.property,
          isActive: true,
          version: 1,
        ),
        DocumentTypeDto(
          id: 'type-2',
          workspaceId: 'ws-1',
          key: 'party_file',
          name: 'Parteiunterlage',
          entityType: DocumentLinkEntityType.party,
          isActive: true,
          version: 1,
        ),
      ],
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentTypeDto>> upsertType(
    UpsertDocumentTypeCommand command,
  ) async {
    return const DocumentRepositoryFailure<DocumentTypeDto>(
      kind: DocumentRepositoryFailureKind.forbidden,
      message: 'not used by this screen',
    );
  }

  @override
  Future<DocumentRepositoryResult<List<RequiredDocumentDto>>> listRequirements({
    required String workspaceId,
    required DocumentLinkEntityType entityType,
    String? entityId,
  }) async {
    return const DocumentRepositorySuccess<List<RequiredDocumentDto>>(
      <RequiredDocumentDto>[],
    );
  }

  @override
  Future<DocumentRepositoryResult<RequiredDocumentDto>> upsertRequirement(
    UpsertRequiredDocumentCommand command,
  ) async {
    return const DocumentRepositoryFailure<RequiredDocumentDto>(
      kind: DocumentRepositoryFailureKind.forbidden,
      message: 'not used by this screen',
    );
  }

  @override
  Future<DocumentRepositoryResult<List<DocumentRequirementProjection>>> evaluate(
    DocumentRequirementQuery query,
  ) async {
    return const DocumentRepositorySuccess<List<DocumentRequirementProjection>>(
      <DocumentRequirementProjection>[],
    );
  }

  @override
  Future<DocumentRepositoryResult<WorkspaceDocumentRequirements>>
  evaluateWorkspace(WorkspaceDocumentRequirementQuery query) async {
    // SCR-051 has no requirements section; the workspace projection belongs to
    // the compliance dashboard (SCR-052).
    return const DocumentRepositorySuccess<WorkspaceDocumentRequirements>(
      WorkspaceDocumentRequirements(
        requirements: <DocumentRequirementProjection>[],
        scopedRuleCount: 0,
      ),
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentVersionDto>> verify(
    VerifyDocumentVersionCommand command,
  ) async {
    verifyCalls++;
    return DocumentRepositorySuccess<DocumentVersionDto>(
      versions.isNotEmpty
          ? versions.first
          : DocumentVersionDto(
            id: 'v-generated',
            workspaceId: 'ws-1',
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
  Future<DocumentRepositoryResult<SignedDocumentUrl>> createSignedUrl({
    required String workspaceId,
    required String documentId,
    int? versionNo,
    Duration? ttl,
  }) async {
    final applied = SignedUrlPort.clampTtl(ttl);
    return DocumentRepositorySuccess<SignedDocumentUrl>(
      SignedDocumentUrl(
        url: 'https://storage.test/signed/$documentId',
        expiresAt: DateTime.utc(2026, 7, 29, 12).add(applied),
        appliedTtl: applied,
        contentRef: _contentRef(documentId),
      ),
    );
  }

  DocumentContentRef _contentRef(String documentId) {
    return DocumentContentRef(
      documentId: documentId,
      workspaceId: 'ws-1',
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
