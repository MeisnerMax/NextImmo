import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_providers.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_repository.dart';
import 'package:neximmo_app/features/documents_compliance/application/documents_workspace_controller.dart';
import 'package:neximmo_app/features/documents_compliance/domain/document_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/ui/screens/docs/documents_workspace_panel.dart';
import 'package:neximmo_app/ui/screens/docs/widgets/document_content_opener.dart';
import 'package:neximmo_app/ui/screens/docs/widgets/document_dialogs.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

import 'fake_document_backend.dart';

/// Mandatory-state coverage for the workspace register — tab `Dokumente` of
/// the DOCUMENTS-V2 destination — pumped on its own, without the host. The
/// host-level behaviour (tabs, primary action, step-up, signed-URL open flow,
/// conflict banners) lives in `documents_host_screen_test.dart`; this suite
/// keeps the register's own states and the controller-level gates.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String workspace = FakeDocumentBackend.workspace;

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

  /// A session that cannot mutate (below the AAL2 boundary, DEC-025).
  WorkspaceSessionScope readOnlyScope() {
    return WorkspaceSessionScope(
      workspaceId: workspace,
      actorId: 'actor-1',
      permissions: const <String>{'document.read'},
      mutationsSupported: false,
    );
  }

  DocumentVersionDto version(String documentId, {int versionNo = 1}) {
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
      verificationStatus: DocumentVerificationStatus.pending,
      version: 1,
      originalFilename: 'nachweis.pdf',
    );
  }

  DocumentDto document(
    String id,
    String title, {
    DocumentStatus status = DocumentStatus.available,
    int documentVersion = 3,
    String? documentTypeId = 'type-1',
  }) {
    return DocumentDto(
      id: id,
      workspaceId: workspace,
      title: title,
      status: status,
      currentVersionNo: 1,
      version: documentVersion,
      documentTypeId: documentTypeId,
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
    required FakeDocumentBackend backend,
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
          documentUploadProvider.overrideWithValue(backend),
          documentUrlLauncherProvider.overrideWithValue((_) async => true),
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

  testWidgets('loading shows a list skeleton, not a spinner', (tester) async {
    final backend = FakeDocumentBackend()..holdSearch();
    await pumpPanel(tester, backend: backend, settle: false);
    await tester.pump();

    expect(find.byKey(const Key('documents-register-loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // The filter bar stays usable while the table loads.
    expect(
      find.byKey(const Key('documents-register-type-filter')),
      findsOneWidget,
    );

    backend.releaseSearch();
    await tester.pumpAndSettle();
  });

  testWidgets('an empty workspace names the next concrete action', (
    tester,
  ) async {
    await pumpPanel(tester, backend: FakeDocumentBackend());

    expect(find.byKey(const Key('documents-register-empty')), findsOneWidget);
    expect(buttonWithText<FilledButton>('Dokument hinzufügen'), findsOneWidget);
    expect(find.byKey(const Key('documents-register-no-match')), findsNothing);
  });

  testWidgets('a backend-side type filter without hits reads as no-match', (
    tester,
  ) async {
    final backend = FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
    );
    final container = await pumpPanel(tester, backend: backend);

    // type-2 exists in the registry but no document carries it.
    await controllerOf(container).setDocumentTypeFilter('type-2');
    await tester.pumpAndSettle();

    expect(backend.lastQuery?.documentTypeId, 'type-2');
    expect(
      find.byKey(const Key('documents-register-no-match')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('documents-register-empty')), findsNothing);
  });

  testWidgets('the workspace query carries no entity filter', (tester) async {
    final backend = FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
    );
    await pumpPanel(tester, backend: backend);

    expect(backend.lastQuery?.workspaceId, workspace);
    expect(backend.lastQuery?.entityType, isNull);
    expect(backend.lastQuery?.entityId, isNull);
  });

  testWidgets('the register offers neither a search nor a level filter', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      backend: FakeDocumentBackend(
        documents: <DocumentDto>[
          document('d1', 'Kaufvertrag'),
          document('d2', 'Mieterakte', documentTypeId: 'type-2'),
        ],
      ),
    );

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Alle Ebenen'), findsNothing);
    expect(find.text('Dokumente durchsuchen'), findsNothing);
    // Both rows are served by the query; nothing is sieved client-side.
    expect(find.text('Kaufvertrag'), findsOneWidget);
    expect(find.text('Mieterakte'), findsOneWidget);
  });

  testWidgets(
    'infrastructure failure offers retry without raw exception text',
    (tester) async {
      await pumpPanel(
        tester,
        backend: FakeDocumentBackend(
          searchFailure: const DocumentRepositoryFailure<DocumentPageResult>(
            kind: DocumentRepositoryFailureKind.infrastructureFailure,
            message: 'Exception: socket closed',
          ),
        ),
      );

      expect(find.byKey(const Key('documents-register-error')), findsOneWidget);
      expect(buttonWithText<FilledButton>('Erneut versuchen'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    },
  );

  testWidgets('forbidden is its own state and names the capability', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      backend: FakeDocumentBackend(
        searchFailure: const DocumentRepositoryFailure<DocumentPageResult>(
          kind: DocumentRepositoryFailureKind.forbidden,
          message: 'document.read missing',
        ),
      ),
    );

    expect(
      find.byKey(const Key('documents-register-forbidden')),
      findsOneWidget,
    );
    expect(find.textContaining('(document.read)'), findsOneWidget);
    expect(find.byKey(const Key('documents-register-empty')), findsNothing);
    expect(find.byKey(const Key('documents-register-error')), findsNothing);
  });

  testWidgets('a read-only session disables creating with a reason', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      backend: FakeDocumentBackend(),
      scope: readOnlyScope(),
    );

    final create = tester.widget<FilledButton>(
      find.byKey(const Key('documents-register-empty-create')),
    );
    expect(create.onPressed, isNull);
    final tooltip = tester.widget<Tooltip>(
      find
          .ancestor(
            of: find.byKey(const Key('documents-register-empty-create')),
            matching: find.byType(Tooltip),
          )
          .first,
    );
    expect(tooltip.message, contains('AAL2'));
  });

  testWidgets('a mutation in a read-only session reports it, not silently', (
    tester,
  ) async {
    final backend = FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
    );
    final container = await pumpPanel(
      tester,
      backend: backend,
      scope: readOnlyScope(),
    );

    final outcome = await controllerOf(
      container,
    ).createDocument(title: 'Neuer Nachweis', file: _selection());
    await tester.pumpAndSettle();

    expect(outcome.succeeded, isFalse);
    expect(backend.createCalls, 0);
    expect(backend.uploadCalls, 0);
    expect(find.textContaining('schreibgeschützt'), findsOneWidget);
  });

  testWidgets('missing document.manage forbids mutations without pretending', (
    tester,
  ) async {
    final backend = FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
    );
    final container = await pumpPanel(
      tester,
      backend: backend,
      scope: cloudScope(permissions: const <String>{'document.read'}),
    );

    final outcome = await controllerOf(
      container,
    ).createDocument(title: 'Neuer Nachweis', file: _selection());
    await tester.pumpAndSettle();

    expect(outcome.succeeded, isFalse);
    expect(backend.createCalls, 0);
    expect(find.textContaining('fehlt die Berechtigung'), findsOneWidget);
  });

  testWidgets('document.verify is gated separately from document.manage', (
    tester,
  ) async {
    final backend = FakeDocumentBackend(
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

  testWidgets('a rejected upload confirmation is an outcome, not a success', (
    tester,
  ) async {
    final backend = FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      confirmResult: document(
        'd1',
        'Kaufvertrag',
        status: DocumentStatus.rejected,
      ),
    );
    final container = await pumpPanel(tester, backend: backend);

    final outcome = await controllerOf(
      container,
    ).confirmContent(documentId: 'd1', versionNo: 1, expectedVersion: 3);
    await tester.pumpAndSettle();

    expect(backend.confirmCalls, 1);
    expect(outcome.succeeded, isTrue);
    expect(
      container.read(documentsWorkspaceControllerProvider).actionPhase,
      DocumentsWorkspaceActionPhase.contentRejected,
    );
    expect(find.textContaining('Upload bestätigt.'), findsNothing);
  });

  testWidgets('a cancelled archive confirmation does not run the mutation', (
    tester,
  ) async {
    final backend = FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      versions: <DocumentVersionDto>[version('d1')],
    );
    await pumpPanel(tester, backend: backend);

    await tester.tap(find.text('Kaufvertrag'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('documents-detail-archive')),
    );
    await tester.tap(find.byKey(const Key('documents-detail-archive')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('documents-archive-dialog')), findsOneWidget);
    expect(backend.transitionCalls, 0);

    await tester.tap(find.byKey(const Key('documents-dialog-cancel')));
    await tester.pumpAndSettle();

    expect(backend.transitionCalls, 0);
    expect(find.byKey(const Key('documents-archive-dialog')), findsNothing);
  });

  testWidgets('there is no delete affordance (OPN-DOM-005 stays open)', (
    tester,
  ) async {
    final backend = FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      versions: <DocumentVersionDto>[version('d1')],
    );
    await pumpPanel(tester, backend: backend);

    await tester.tap(find.text('Kaufvertrag'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Löschen'), findsNothing);
    expect(find.textContaining('Loeschen'), findsNothing);
    expect(find.textContaining('Delete'), findsNothing);
    expect(find.byKey(const Key('documents-detail-archive')), findsOneWidget);
  });

  testWidgets('creating in workspace scope does not invent an entity link', (
    tester,
  ) async {
    final backend = FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
    );
    final container = await pumpPanel(tester, backend: backend);

    final outcome = await controllerOf(
      container,
    ).createDocument(title: 'Neuer Nachweis', file: _selection());
    await tester.pumpAndSettle();

    expect(outcome.succeeded, isTrue);
    expect(backend.uploadCalls, 1);
    expect(backend.createCalls, 1);
    expect(backend.linkCalls, 0);
  });

  testWidgets('the detail names the levels a document is linked to', (
    tester,
  ) async {
    final backend = FakeDocumentBackend(
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
    final backend = FakeDocumentBackend(
      documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      versions: <DocumentVersionDto>[version('d1')],
    );
    await pumpPanel(tester, backend: backend);

    await tester.tap(find.text('Kaufvertrag'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Noch keiner Entität zugeordnet'),
      findsOneWidget,
    );
  });

  test('the validity prefill adds whole months and clamps the day', () {
    expect(
      addDocumentValidityMonths(DateTime(2026, 1, 31), 1),
      DateTime(2026, 2, 28),
    );
    expect(
      addDocumentValidityMonths(DateTime(2026, 3, 15), 12),
      DateTime(2027, 3, 15),
    );
    expect(
      addDocumentValidityMonths(DateTime(2026, 11, 30), 3),
      DateTime(2027, 2, 28),
    );
  });

  group('responsive', () {
    const sizes = <String, Size>{
      'floor 320x568': Size(320, 568),
      'phone 390x844': Size(390, 844),
      'tablet 1024x768': Size(1024, 768),
      'desktop 1440x900': Size(1440, 900),
    };

    for (final density in AppDensityModeSetting.values) {
      for (final entry in sizes.entries) {
        testWidgets('${entry.key} renders in ${density.name} density', (
          tester,
        ) async {
          final container = await pumpPanel(
            tester,
            backend: FakeDocumentBackend(
              documents: <DocumentDto>[
                document('d1', 'Kaufvertrag'),
                document('d2', 'Energieausweis 2026'),
              ],
              versions: <DocumentVersionDto>[version('d1')],
            ),
            size: entry.value,
            density: density,
          );

          expect(tester.takeException(), isNull);
          expect(find.text('Kaufvertrag'), findsOneWidget);
          expect(find.text('Energieausweis 2026'), findsOneWidget);
          // Selected through the controller: at the 320 floor the row sits
          // below the fold and a missed tap would test nothing.
          await controllerOf(container).selectDocument('d1');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('documents-register-detail')),
            findsOneWidget,
          );
        });
      }
    }
  });
}

/// A picked file, not a storage declaration: the controller is what turns
/// bytes into coordinates.
DocumentFileSelection _selection() {
  return DocumentFileSelection(
    bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    filename: 'nachweis.pdf',
    mimeType: 'application/pdf',
  );
}
