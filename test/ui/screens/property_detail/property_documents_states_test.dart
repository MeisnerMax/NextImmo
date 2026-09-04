import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_providers.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_repository.dart';
import 'package:neximmo_app/features/documents_compliance/application/property_documents_controller.dart';
import 'package:neximmo_app/features/documents_compliance/domain/document_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/ui/screens/docs/widgets/document_content_opener.dart';
import 'package:neximmo_app/ui/screens/property_detail/property_documents_panel.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Mandatory-state coverage for the rebuilt property documents surface
/// (SCR-020, Phase 2, Wave 2, Arbeitspaket 3). Mirrors
/// `test/ui/screens/parties/parties_screen_states_test.dart`, the pattern proof
/// of this wave, and adds the three states that only the documents domain has:
/// the MIG-BND-003 `rejected` outcome, the separate `document.verify`
/// capability, and the archive confirmation that stands in for the delete path
/// `OPN-DOM-005` deliberately does not offer.
///
/// The panel is tested, not the tab host: the host only routes three
/// `PropertyDetailPage` values into the same frame and reaches into legacy,
/// `dart:io`-bound screens, while the panel is the whole Wave 2 rebuild and the
/// unit the additive cloud route mounts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String workspace = 'ws-1';
  const String propertyId = 'prop-1';

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
    DateTime? validUntil,
  }) {
    return DocumentDto(
      id: id,
      workspaceId: workspace,
      title: title,
      status: status,
      currentVersionNo: 1,
      version: documentVersion,
      documentTypeId: 'type-1',
      validUntil: validUntil,
      updatedAt: DateTime.utc(2026, 6, 1),
    );
  }

  DocumentRequirementProjection requirement({
    DocumentRequirementState state = DocumentRequirementState.missing,
    bool isMandatory = true,
    String name = 'Energieausweis',
  }) {
    return DocumentRequirementProjection(
      requirementId: 'req-1',
      documentTypeId: 'type-1',
      documentTypeKey: 'energy_certificate',
      documentTypeName: name,
      entityType: DocumentLinkEntityType.property,
      entityId: propertyId,
      isMandatory: isMandatory,
      isInstanceRule: false,
      state: state,
      dueAt: DateTime.utc(2026, 9, 1),
    );
  }

  Future<ProviderContainer> pumpPanel(
    WidgetTester tester, {
    required _FakeDocumentBackend backend,
    WorkspaceSessionScope? scope,
    DocumentUrlLauncher? launcher,
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
          documentUploadProvider.overrideWithValue(backend),
          documentUrlLauncherProvider.overrideWithValue(
            launcher ?? (_) async => true,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(densityMode: density),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: PropertyDocumentsPanel(propertyId: propertyId),
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
    return ProviderScope.containerOf(
      tester.element(find.byType(PropertyDocumentsPanel)),
    );
  }

  PropertyDocumentsController controllerOf(ProviderContainer container) {
    return container.read(
      propertyDocumentsControllerProvider(propertyId).notifier,
    );
  }

  testWidgets('loading shows section skeletons, not a full-page spinner', (
    tester,
  ) async {
    final backend = _FakeDocumentBackend()..holdSearch();
    await pumpPanel(tester, backend: backend, settle: false);
    await tester.pump();

    expect(find.byKey(const Key('property-documents-loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // The header and its actions stay usable while the zones load.
    expect(find.text('Dokumente'), findsOneWidget);
    expect(find.text('Vorhandene Dokumente'), findsOneWidget);

    backend.releaseSearch();
    await tester.pumpAndSettle();
  });

  testWidgets('empty archive names the next concrete action', (tester) async {
    await pumpPanel(tester, backend: _FakeDocumentBackend());

    expect(find.text('Noch keine Dokumente'), findsOneWidget);
    expect(buttonWithText<FilledButton>('Dokument hinzufügen'), findsWidgets);
  });

  testWidgets(
    'infrastructure failure offers retry without raw exception text',
    (tester) async {
      await pumpPanel(
        tester,
        backend: _FakeDocumentBackend(
          searchFailure: const DocumentRepositoryFailure<DocumentPageResult>(
            kind: DocumentRepositoryFailureKind.infrastructureFailure,
            message: 'Exception: socket closed',
          ),
        ),
      );

      expect(
        find.text('Dokumente konnten nicht geladen werden'),
        findsOneWidget,
      );
      expect(find.text('Erneut versuchen'), findsWidgets);
      expect(find.textContaining('Exception'), findsNothing);
    },
  );

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

  testWidgets('the requirement zone has its own forbidden state', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      backend: _FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
        evaluateFailure: const DocumentRepositoryFailure<
          List<DocumentRequirementProjection>
        >(kind: DocumentRepositoryFailureKind.forbidden, message: 'no access'),
      ),
    );

    expect(find.text('Kein Zugriff auf Anforderungen'), findsOneWidget);
    // The documents themselves still render — the zones fail independently.
    expect(find.text('Kaufvertrag'), findsOneWidget);
  });

  testWidgets('an unmet mandatory requirement is shown as a labelled state', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      backend: _FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
        requirements: <DocumentRequirementProjection>[requirement()],
      ),
    );

    expect(find.text('Energieausweis'), findsOneWidget);
    expect(find.text('Fehlt'), findsOneWidget);
  });

  testWidgets('an optional requirement is not signalled as an alarm', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      backend: _FakeDocumentBackend(
        requirements: <DocumentRequirementProjection>[
          requirement(isMandatory: false),
        ],
      ),
    );

    expect(find.text('Fehlt (optional)'), findsOneWidget);
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

    expect(find.text('Schreibgeschützt'), findsOneWidget);
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

      await controllerOf(
        container,
      ).createDocument(title: 'Neuer Nachweis', file: _selection());
      await tester.pumpAndSettle();

      expect(backend.createCalls, 0);
      expect(find.textContaining('schreibgeschützt'), findsOneWidget);
    },
  );

  testWidgets(
    'a version conflict keeps the dialog open with the server state',
    (tester) async {
      final current = document('d1', 'Kaufvertrag');
      final backend = _FakeDocumentBackend(
        documents: <DocumentDto>[current],
        versions: <DocumentVersionDto>[version('d1')],
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
      await pumpPanel(tester, backend: backend);

      await tester.tap(find.text('Kaufvertrag'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('documents-detail-archive')),
      );
      await tester.tap(find.byKey(const Key('documents-detail-archive')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('documents-dialog-submit')));
      await tester.pumpAndSettle();

      // Foundation §10: input is never thrown away — the dialog stays open,
      // names the server version and offers reload/retry.
      expect(
        find.byKey(const Key('documents-dialog-conflict')),
        findsOneWidget,
      );
      expect(find.text('Zwischenzeitlich geändert'), findsOneWidget);
      expect(find.textContaining('Version 5'), findsOneWidget);
      expect(find.text('Neu laden'), findsOneWidget);
      expect(find.text('Erneut speichern'), findsOneWidget);
      expect(find.text('Aktuellen Stand laden'), findsNothing);
      expect(backend.transitionCalls, 1);
    },
  );

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

    await controllerOf(
      container,
    ).createDocument(title: 'Neuer Nachweis', file: _selection());
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

      await controllerOf(
        container,
      ).confirmContent(documentId: 'd1', versionNo: 1, expectedVersion: 3);
      await tester.pumpAndSettle();

      expect(backend.confirmCalls, 1);
      expect(find.text('Upload abgelehnt'), findsOneWidget);
      expect(find.textContaining('Upload bestätigt.'), findsNothing);
    },
  );

  testWidgets('archiving requires an explicit confirmation', (tester) async {
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
    expect(find.textContaining('Delete'), findsNothing);
    expect(buttonWithText<OutlinedButton>('Archivieren'), findsOneWidget);
  });

  testWidgets('creating a document links it to this property', (tester) async {
    final backend = _FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
    );
    final container = await pumpPanel(tester, backend: backend);

    await controllerOf(
      container,
    ).createDocument(title: 'Neuer Nachweis', file: _selection());
    await tester.pumpAndSettle();

    expect(backend.createCalls, 1);
    expect(backend.linkCalls, 1);
    expect(backend.lastLinkedEntityId, propertyId);
    expect(backend.lastLinkedEntityType, DocumentLinkEntityType.property);
  });

  testWidgets('the bytes reach the bucket before the document is registered', (
    tester,
  ) async {
    final backend = _FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
    );
    final container = await pumpPanel(tester, backend: backend);

    await controllerOf(
      container,
    ).createDocument(title: 'Neuer Nachweis', file: _selection());
    await tester.pumpAndSettle();

    expect(backend.uploadCalls, 1);
    expect(backend.createCalls, 1);
    // Version 1 of a document that does not exist yet, so the path carries a
    // generated scope id rather than the (not yet minted) document id.
    expect(backend.lastUploadPath, endsWith('/1/nachweis.pdf'));
    expect(backend.lastUploadPath, startsWith('$workspace/'));
  });

  testWidgets('a failed upload stops before any document is registered', (
    tester,
  ) async {
    final backend = _FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      )
      ..uploadFailure = const DocumentRepositoryFailure<DocumentContentDraft>(
        kind: DocumentRepositoryFailureKind.infrastructureFailure,
        message: 'Die Datei konnte nicht geladen werden.',
      );
    final container = await pumpPanel(tester, backend: backend);

    await controllerOf(
      container,
    ).createDocument(title: 'Neuer Nachweis', file: _selection());
    await tester.pumpAndSettle();

    // Registering an aggregate whose content never arrived would leave a
    // document that can never be confirmed.
    expect(backend.uploadCalls, 1);
    expect(backend.createCalls, 0);
    expect(backend.linkCalls, 0);
    expect(find.textContaining('nicht geladen werden'), findsOneWidget);
  });

  testWidgets('a read-only backend refuses before reading any bytes', (
    tester,
  ) async {
    final backend = _FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
    );
    final container = await pumpPanel(
      tester,
      backend: backend,
      scope: localScope(),
    );

    await controllerOf(
      container,
    ).createDocument(title: 'Neuer Nachweis', file: _selection());
    await tester.pumpAndSettle();

    expect(backend.uploadCalls, 0);
    expect(backend.createCalls, 0);
  });

  testWidgets(
    'a created but unlinked document is reported, not shown as done',
    (tester) async {
      final backend = _FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
        linkFailure: const DocumentRepositoryFailure<DocumentLinkDto>(
          kind: DocumentRepositoryFailureKind.dependencyConflict,
          message: 'entity not migrated',
        ),
      );
      final container = await pumpPanel(tester, backend: backend);

      await controllerOf(
        container,
      ).createDocument(title: 'Neuer Nachweis', file: _selection());
      await tester.pumpAndSettle();

      expect(backend.createCalls, 1);
      expect(
        find.textContaining('nicht mit diesem Objekt verknüpft'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'content opens through a freshly minted signed URL, never shown',
    (tester) async {
      final backend = _FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
        versions: <DocumentVersionDto>[version('d1')],
      );
      final launched = <Uri>[];
      await pumpPanel(
        tester,
        backend: backend,
        launcher: (uri) async {
          launched.add(uri);
          return true;
        },
      );

      await tester.tap(find.text('Kaufvertrag'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('documents-detail-open')),
      );
      await tester.tap(find.byKey(const Key('documents-detail-open')));
      await tester.pumpAndSettle();

      // Same flow and the same security as the workspace register (§6.7).
      expect(launched, <Uri>[Uri.parse('https://storage.test/signed/d1')]);
      expect(find.text('Download-Link'), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      expect(find.textContaining('storage.test'), findsNothing);
      expect(find.text('Link kopieren'), findsNothing);
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
              requirements: <DocumentRequirementProjection>[requirement()],
            ),
            size: entry.value,
            density: density,
          );

          expect(tester.takeException(), isNull);
          expect(find.text('Kaufvertrag'), findsOneWidget);
          expect(find.text('Energieausweis'), findsOneWidget);
        });
      }
    }
  });
}

/// A picked file, not a storage declaration: since the upload port exists, the
/// controller is what turns bytes into coordinates.
DocumentFileSelection _selection() {
  return DocumentFileSelection(
    bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    filename: 'nachweis.pdf',
    mimeType: 'application/pdf',
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
        SignedUrlPort,
        DocumentUploadPort {
  _FakeDocumentBackend({
    this.documents = const <DocumentDto>[],
    this.versions = const <DocumentVersionDto>[],
    this.requirements = const <DocumentRequirementProjection>[],
    this.searchFailure,
    this.evaluateFailure,
    this.transitionFailure,
    this.linkFailure,
    this.confirmResult,
  });

  final List<DocumentDto> documents;
  final List<DocumentVersionDto> versions;
  final List<DocumentRequirementProjection> requirements;
  final DocumentRepositoryFailure<DocumentPageResult>? searchFailure;
  final DocumentRepositoryFailure<List<DocumentRequirementProjection>>?
  evaluateFailure;
  final DocumentRepositoryFailure<DocumentDto>? transitionFailure;
  final DocumentRepositoryFailure<DocumentLinkDto>? linkFailure;
  final DocumentDto? confirmResult;

  int createCalls = 0;
  int uploadCalls = 0;
  String? lastUploadPath;
  DocumentRepositoryFailure<DocumentContentDraft>? uploadFailure;
  int linkCalls = 0;
  int transitionCalls = 0;
  int verifyCalls = 0;
  int confirmCalls = 0;
  int addVersionCalls = 0;
  String? lastLinkedEntityId;
  DocumentLinkEntityType? lastLinkedEntityType;
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
    await _searchGate?.future;
    final failure = searchFailure;
    if (failure != null) {
      return failure;
    }
    return DocumentRepositorySuccess<DocumentPageResult>(
      DocumentPageResult(items: documents),
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
    return const DocumentRepositorySuccess<List<DocumentLinkDto>>(
      <DocumentLinkDto>[],
    );
  }

  @override
  Future<DocumentRepositoryResult<DocumentLinkDto>> link(
    LinkDocumentCommand command,
  ) async {
    linkCalls++;
    lastLinkedEntityId = command.entityId;
    lastLinkedEntityType = command.entityType;
    final failure = linkFailure;
    if (failure != null) {
      return failure;
    }
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
  Future<DocumentRepositoryResult<List<DocumentRequirementProjection>>>
  evaluate(DocumentRequirementQuery query) async {
    final failure = evaluateFailure;
    if (failure != null) {
      return failure;
    }
    return DocumentRepositorySuccess<List<DocumentRequirementProjection>>(
      requirements,
    );
  }

  @override
  Future<DocumentRepositoryResult<WorkspaceDocumentRequirements>>
  evaluateWorkspace(WorkspaceDocumentRequirementQuery query) async {
    // Not used by the property-scoped surface, which always has an entity.
    return DocumentRepositorySuccess<WorkspaceDocumentRequirements>(
      WorkspaceDocumentRequirements(
        requirements: requirements,
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
  Future<DocumentRepositoryResult<DocumentContentDraft>> upload({
    required String workspaceId,
    required String scopeId,
    required int versionNo,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    uploadCalls++;
    lastUploadPath = DocumentUploadPort.storageObjectPath(
      workspaceId: workspaceId,
      scopeId: scopeId,
      versionNo: versionNo,
      filename: filename,
    );
    final failure = uploadFailure;
    if (failure != null) {
      return failure;
    }
    return DocumentRepositorySuccess<DocumentContentDraft>(
      DocumentContentDraft(
        storageObjectPath: lastUploadPath!,
        contentHash: DocumentUploadPort.contentHashOf(bytes),
        byteSize: bytes.length,
        mimeType: mimeType,
        originalFilename: filename,
      ),
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
