import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/documents_compliance/application/compliance_dashboard_controller.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_providers.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_repository.dart';
import 'package:neximmo_app/features/documents_compliance/application/documents_workspace_controller.dart';
import 'package:neximmo_app/features/documents_compliance/domain/document_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/ui/components/nx_kpi_tile.dart';
import 'package:neximmo_app/ui/components/nx_list_skeleton.dart';
import 'package:neximmo_app/ui/navigation/app_navigation.dart';
import 'package:neximmo_app/ui/navigation/cloud_route_request.dart';
import 'package:neximmo_app/ui/screens/docs/documents_host_screen.dart';
import 'package:neximmo_app/ui/screens/docs/widgets/document_content_opener.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

import 'fake_document_backend.dart';

/// DOCUMENTS-V2 increment A: the one documents destination (host + workspace
/// register), the signed-URL open flow and the state-first compliance jump.
/// Keys, never copy (Foundation §17); the register is served by the contract
/// only (no client search, no client sort, keyset load-more).
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

  DocumentVersionDto version(
    String documentId, {
    int versionNo = 1,
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
      verificationStatus: DocumentVerificationStatus.pending,
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

  DocumentRequirementProjection finding({
    required String entityId,
    DocumentRequirementState state = DocumentRequirementState.missing,
    String name = 'Energieausweis',
  }) {
    return DocumentRequirementProjection(
      requirementId: 'req-$entityId-$name',
      documentTypeId: 'type-1',
      documentTypeKey: 'energy_certificate',
      documentTypeName: name,
      entityType: DocumentLinkEntityType.property,
      entityId: entityId,
      isMandatory: true,
      isInstanceRule: false,
      state: state,
    );
  }

  Future<ProviderContainer> pumpHost(
    WidgetTester tester, {
    required FakeDocumentBackend backend,
    WorkspaceSessionScope? scope,
    DocumentsHostTab initialTab = DocumentsHostTab.documents,
    bool requiresStepUp = false,
    _RecordingLauncher? launcher,
    Size size = const Size(1440, 900),
    AppDensityModeSetting density = AppDensityModeSetting.comfort,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final recorder = launcher ?? _RecordingLauncher();
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
          complianceObjectDirectoryProvider.overrideWithValue(null),
          documentUrlLauncherProvider.overrideWithValue(recorder.launch),
        ],
        child: MaterialApp(
          theme: AppTheme.light(densityMode: density),
          home: Scaffold(
            body: DocumentsHostScreen(
              initialTab: initialTab,
              requiresStepUp: requiresStepUp,
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
    return ProviderScope.containerOf(
      tester.element(find.byType(DocumentsHostScreen)),
    );
  }

  Future<void> openTab(WidgetTester tester, DocumentsHostTab tab) async {
    final tabFinder = find.byKey(Key('documents-tab-${tab.name}'));
    await tester.ensureVisible(tabFinder);
    await tester.tap(tabFinder);
    await tester.pumpAndSettle();
  }

  group('host', () {
    test('the cloud surfaces map onto the tabs', () {
      expect(
        documentsHostTabForSurface(CloudRouteSurface.compliance),
        DocumentsHostTab.compliance,
      );
      expect(
        documentsHostTabForSurface(CloudRouteSurface.documentsWorkspace),
        DocumentsHostTab.documents,
      );
      expect(
        documentsHostTabForSurface(CloudRouteSurface.page),
        DocumentsHostTab.documents,
      );
    });

    testWidgets('the destination hosts the four approved tabs', (tester) async {
      await pumpHost(tester, backend: FakeDocumentBackend());

      expect(find.byKey(const Key('documents-host')), findsOneWidget);
      for (final tab in DocumentsHostTab.values) {
        expect(find.byKey(Key('documents-tab-${tab.name}')), findsOneWidget);
      }
      expect(implementedDocumentsHostTabs, DocumentsHostTab.values);
    });

    testWidgets('the compliance surface opens on the compliance tab', (
      tester,
    ) async {
      await pumpHost(
        tester,
        backend: FakeDocumentBackend(),
        initialTab: DocumentsHostTab.compliance,
      );

      expect(find.byKey(const Key('documents-compliance')), findsOneWidget);
      expect(find.byKey(const Key('documents-register')), findsNothing);
    });

    testWidgets('the primary action follows the active tab', (tester) async {
      await pumpHost(tester, backend: FakeDocumentBackend());
      final primary = find.byKey(const Key('documents-primary-action'));

      expect(
        find.descendant(
          of: primary,
          matching: find.text('Dokument hinzufügen'),
        ),
        findsOneWidget,
      );
      await openTab(tester, DocumentsHostTab.types);
      expect(
        find.descendant(
          of: primary,
          matching: find.text('Dokumenttyp anlegen'),
        ),
        findsOneWidget,
      );
      await openTab(tester, DocumentsHostTab.requirements);
      expect(
        find.descendant(
          of: primary,
          matching: find.text('Pflichtregel anlegen'),
        ),
        findsOneWidget,
      );
      await openTab(tester, DocumentsHostTab.compliance);
      expect(primary, findsNothing);
      // Only ever one filled button in the header (Foundation §5).
      expect(
        find.descendant(
          of: find.byKey(const Key('documents-host-header')),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'a session below AAL2 gets the step-up state and reads nothing',
      (tester) async {
        final backend = FakeDocumentBackend(
          documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
        );
        await pumpHost(tester, backend: backend, requiresStepUp: true);

        expect(
          find.byKey(const Key('documents-step-up-required')),
          findsOneWidget,
        );
        expect(find.textContaining('AAL2'), findsWidgets);
        expect(find.text('Kaufvertrag'), findsNothing);
        expect(backend.queries, isEmpty);
        expect(backend.listTypesCalls, 0);
        expect(backend.evaluateWorkspaceCalls, 0);
      },
    );
  });

  group('register', () {
    testWidgets('loading shows a list skeleton, not a spinner', (tester) async {
      final backend = FakeDocumentBackend()..holdSearch();
      await pumpHost(tester, backend: backend, settle: false);
      await tester.pump();

      expect(
        find.byKey(const Key('documents-register-loading')),
        findsOneWidget,
      );
      expect(find.byType(NxListSkeleton), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      backend.releaseSearch();
      await tester.pumpAndSettle();
    });

    testWidgets('an empty workspace names the next action', (tester) async {
      await pumpHost(tester, backend: FakeDocumentBackend());

      expect(find.byKey(const Key('documents-register-empty')), findsOneWidget);
      expect(find.text('Noch keine Dokumente'), findsOneWidget);
    });

    testWidgets('infrastructure failure offers the one retry style', (
      tester,
    ) async {
      final backend = FakeDocumentBackend(
        searchFailure: const DocumentRepositoryFailure<DocumentPageResult>(
          kind: DocumentRepositoryFailureKind.infrastructureFailure,
          message: 'PostgrestException: relation missing',
        ),
      );
      await pumpHost(tester, backend: backend);

      expect(find.byKey(const Key('documents-register-error')), findsOneWidget);
      expect(find.textContaining('PostgrestException'), findsNothing);
      final retry = buttonWithText<FilledButton>('Erneut versuchen');
      expect(retry, findsOneWidget);
      final before = backend.queries.length;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(backend.queries.length, before + 1);
    });

    testWidgets('forbidden names the capability', (tester) async {
      await pumpHost(
        tester,
        backend: FakeDocumentBackend(
          searchFailure: const DocumentRepositoryFailure<DocumentPageResult>(
            kind: DocumentRepositoryFailureKind.forbidden,
            message: 'forbidden',
          ),
        ),
      );

      expect(
        find.byKey(const Key('documents-register-forbidden')),
        findsOneWidget,
      );
      expect(find.textContaining('(document.read)'), findsOneWidget);
      expect(find.byKey(const Key('documents-register-empty')), findsNothing);
    });

    testWidgets(
      'data renders the rows and the query carries no client filter',
      (tester) async {
        final backend = FakeDocumentBackend(
          documents: <DocumentDto>[
            document('d1', 'Kaufvertrag'),
            document('d2', 'Energieausweis 2026', documentTypeId: 'type-2'),
          ],
        );
        await pumpHost(tester, backend: backend);

        expect(find.text('Kaufvertrag'), findsOneWidget);
        expect(find.text('Energieausweis 2026'), findsOneWidget);
        expect(backend.lastQuery?.entityType, isNull);
        expect(backend.lastQuery?.documentTypeId, isNull);
        expect(backend.lastQuery?.includeInactive, isFalse);
      },
    );

    testWidgets('the register offers no search control', (tester) async {
      await pumpHost(
        tester,
        backend: FakeDocumentBackend(
          documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
        ),
      );

      final register = find.byKey(const Key('documents-register'));
      expect(register, findsOneWidget);
      expect(
        find.descendant(of: register, matching: find.byType(TextField)),
        findsNothing,
      );
      expect(find.text('Dokumente durchsuchen'), findsNothing);
      expect(find.byIcon(Icons.search), findsNothing);
      expect(find.text('Alle Ebenen'), findsNothing);
    });

    testWidgets('keyset load more asks the server for the next page', (
      tester,
    ) async {
      final backend = FakeDocumentBackend(
        pageSize: 2,
        documents: <DocumentDto>[
          document('d1', 'Kaufvertrag'),
          document('d2', 'Grundbuchauszug'),
          document('d3', 'Energieausweis 2026'),
        ],
      );
      await pumpHost(tester, backend: backend);

      expect(find.text('Energieausweis 2026'), findsNothing);
      final loadMore = find.byKey(const Key('documents-register-load-more'));
      expect(loadMore, findsOneWidget);
      await tester.tap(loadMore);
      await tester.pumpAndSettle();

      expect(backend.lastQuery?.page.cursor, '2');
      expect(find.text('Energieausweis 2026'), findsOneWidget);
      expect(loadMore, findsNothing);
    });

    testWidgets('the type filter is served by the query', (tester) async {
      final backend = FakeDocumentBackend(
        documents: <DocumentDto>[
          document('d1', 'Kaufvertrag'),
          document('d2', 'Parteiakte', documentTypeId: 'type-2'),
        ],
      );
      await pumpHost(tester, backend: backend);

      await tester.tap(find.byKey(const Key('documents-register-type-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Parteiunterlage').last);
      await tester.pumpAndSettle();

      expect(backend.lastQuery?.documentTypeId, 'type-2');
      expect(find.text('Parteiakte'), findsOneWidget);
      expect(find.text('Kaufvertrag'), findsNothing);
    });

    testWidgets('no-match is its own state after a server-empty filter', (
      tester,
    ) async {
      final backend = FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
      );
      await pumpHost(tester, backend: backend);

      await tester.tap(find.byKey(const Key('documents-register-type-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Parteiunterlage').last);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('documents-register-no-match')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('documents-register-empty')), findsNothing);
      await tester.tap(find.text('Filter zurücksetzen'));
      await tester.pumpAndSettle();
      expect(backend.lastQuery?.documentTypeId, isNull);
      expect(find.text('Kaufvertrag'), findsOneWidget);
    });

    testWidgets('selecting a row opens the detail', (tester) async {
      await pumpHost(
        tester,
        backend: FakeDocumentBackend(
          documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
          versions: <DocumentVersionDto>[version('d1')],
        ),
      );

      await tester.tap(find.text('Kaufvertrag'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('documents-register-detail')),
        findsOneWidget,
      );
      expect(find.text('Versionen'), findsOneWidget);
    });

    testWidgets('narrow viewports replace the list with the detail', (
      tester,
    ) async {
      await pumpHost(
        tester,
        backend: FakeDocumentBackend(
          documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
          versions: <DocumentVersionDto>[version('d1')],
        ),
        size: const Size(390, 844),
      );

      await tester.tap(find.text('Kaufvertrag'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('documents-register-detail')),
        findsOneWidget,
      );
      expect(find.text('Zur Liste'), findsOneWidget);
      await tester.tap(find.text('Zur Liste'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('documents-register-detail')), findsNothing);
      expect(find.text('Kaufvertrag'), findsOneWidget);
    });
  });

  group('signed url', () {
    testWidgets(
      'opening mints on the click and hands the URL to the launcher',
      (tester) async {
        final backend = FakeDocumentBackend(
          documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
          versions: <DocumentVersionDto>[version('d1')],
        );
        final launcher = _RecordingLauncher();
        await pumpHost(tester, backend: backend, launcher: launcher);
        await tester.tap(find.text('Kaufvertrag'));
        await tester.pumpAndSettle();
        expect(backend.signedUrlCalls, 0);

        await tester.tap(find.byKey(const Key('documents-detail-open')));
        await tester.pumpAndSettle();

        expect(backend.signedUrlCalls, 1);
        expect(launcher.launched, <Uri>[
          Uri.parse(FakeDocumentBackend.signedUrlFor('d1', 1)),
        ]);
        expect(find.textContaining('SECRET-SIGNATURE'), findsNothing);
        expect(find.textContaining('storage.test'), findsNothing);
        expect(find.byType(SelectableText), findsNothing);
        expect(find.text('Download-Link'), findsNothing);
        expect(find.text('Link kopieren'), findsNothing);
        expect(find.byIcon(Icons.copy), findsNothing);
        expect(find.byIcon(Icons.copy_outlined), findsNothing);

        // No cached URL: the next open mints again.
        await tester.tap(find.byKey(const Key('documents-detail-open')));
        await tester.pumpAndSettle();
        expect(backend.signedUrlCalls, 2);
        expect(launcher.launched.length, 2);
      },
    );

    testWidgets('a failed launch is reported without the URL', (tester) async {
      final backend = FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
        versions: <DocumentVersionDto>[version('d1')],
      );
      final launcher = _RecordingLauncher(result: false);
      await pumpHost(tester, backend: backend, launcher: launcher);
      await tester.tap(find.text('Kaufvertrag'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('documents-detail-open')));
      await tester.pumpAndSettle();

      expect(
        find.text('Der Inhalt konnte nicht geöffnet werden.'),
        findsOneWidget,
      );
      expect(find.textContaining('storage.test'), findsNothing);
    });

    testWidgets('a version row opens with a labelled action', (tester) async {
      final backend = FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
        versions: <DocumentVersionDto>[version('d1')],
      );
      final launcher = _RecordingLauncher();
      await pumpHost(tester, backend: backend, launcher: launcher);
      await tester.tap(find.text('Kaufvertrag'));
      await tester.pumpAndSettle();

      // The version list sits at the bottom of the detail pane: scroll that
      // pane (never `ensureVisible`, which would page the TabBarView).
      await tester.drag(
        find.byKey(const Key('documents-register-detail')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('documents-version-open-1')));
      await tester.pumpAndSettle();

      expect(launcher.launched.single.pathSegments.last, '1');
      expect(find.text('Öffnen', skipOffstage: false), findsWidgets);
    });
  });

  group('actions', () {
    testWidgets('document.verify is gated separately with a tooltip', (
      tester,
    ) async {
      await pumpHost(
        tester,
        backend: FakeDocumentBackend(
          documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
          versions: <DocumentVersionDto>[
            version('d1', contentConfirmedAt: DateTime.utc(2026, 6, 1)),
          ],
        ),
        scope: cloudScope(
          permissions: const <String>{'document.read', 'document.manage'},
        ),
      );
      await tester.tap(find.text('Kaufvertrag'));
      await tester.pumpAndSettle();

      final verify = find.byKey(const Key('documents-detail-verify'));
      expect(verify, findsOneWidget);
      final button = tester.widget<OutlinedButton>(verify);
      expect(button.onPressed, isNull);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: verify, matching: find.byType(Tooltip)).first,
      );
      expect(tooltip.message, contains('(document.verify)'));
      // manage is present: adding a version stays enabled.
      final addVersion = tester.widget<FilledButton>(
        find.byKey(const Key('documents-detail-add-version')),
      );
      expect(addVersion.onPressed, isNotNull);
    });

    testWidgets('a version conflict keeps the dialog input', (tester) async {
      final backend = FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
        versions: <DocumentVersionDto>[
          version('d1', contentConfirmedAt: DateTime.utc(2026, 6, 1)),
        ],
        verifyFailure: DocumentRepositoryFailure<DocumentVersionDto>(
          kind: DocumentRepositoryFailureKind.versionConflict,
          message: 'conflict',
          versionConflict: DocumentVersionConflict(
            expectedVersion: 3,
            actualVersion: 7,
            currentDocument: document('d1', 'Kaufvertrag', documentVersion: 7),
          ),
        ),
      );
      await pumpHost(tester, backend: backend);
      await tester.tap(find.text('Kaufvertrag'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('documents-detail-verify')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('documents-dialog-note')),
        'Stempel fehlt',
      );
      await tester.tap(find.byKey(const Key('documents-dialog-submit')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('documents-dialog-conflict')),
        findsOneWidget,
      );
      expect(find.textContaining('Version 7'), findsOneWidget);
      expect(find.text('Stempel fehlt'), findsOneWidget);
      expect(find.text('Zwischenzeitlich geändert'), findsOneWidget);
      expect(find.text('Aktuellen Stand laden'), findsNothing);

      await tester.tap(find.byKey(const Key('documents-dialog-retry')));
      await tester.pumpAndSettle();
      expect(backend.verifyCommands.last.expectedVersion, 7);
      expect(backend.verifyCommands.last.note, 'Stempel fehlt');
    });

    testWidgets('archiving confirms by name with a reason that is audited', (
      tester,
    ) async {
      final backend = FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
        versions: <DocumentVersionDto>[version('d1')],
      );
      await pumpHost(tester, backend: backend);
      await tester.tap(find.text('Kaufvertrag'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('documents-detail-archive')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Gelöscht wird nichts'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('documents-dialog-reason')),
        'Doppelt erfasst',
      );
      await tester.tap(find.byKey(const Key('documents-dialog-submit')));
      await tester.pumpAndSettle();

      expect(
        backend.transitionCommands.single.context.reason,
        'Doppelt erfasst',
      );
      expect(
        backend.transitionCommands.single.transition,
        DocumentStatusTransition.archive,
      );
    });

    testWidgets('archiving without a reason is still a complete decision', (
      tester,
    ) async {
      final backend = FakeDocumentBackend(
        documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
        versions: <DocumentVersionDto>[version('d1')],
      );
      await pumpHost(tester, backend: backend);
      await tester.tap(find.text('Kaufvertrag'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('documents-detail-archive')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('documents-dialog-submit')));
      await tester.pumpAndSettle();

      expect(backend.transitionCommands.single.context.reason, isNull);
      expect(find.byKey(const Key('documents-archive-dialog')), findsNothing);
    });

    testWidgets('there is no delete, share or processing trigger', (
      tester,
    ) async {
      await pumpHost(
        tester,
        backend: FakeDocumentBackend(
          documents: <DocumentDto>[document('d1', 'Kaufvertrag')],
          versions: <DocumentVersionDto>[version('d1')],
        ),
      );
      await tester.tap(find.text('Kaufvertrag'));
      await tester.pumpAndSettle();

      expect(find.text('Löschen'), findsNothing);
      expect(find.text('Loeschen'), findsNothing);
      expect(find.text('Teilen'), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('missing document.manage disables creating with a tooltip', (
      tester,
    ) async {
      await pumpHost(
        tester,
        backend: FakeDocumentBackend(),
        scope: cloudScope(permissions: const <String>{'document.read'}),
      );

      final primary = find.byKey(const Key('documents-primary-action'));
      final button = tester.widget<FilledButton>(
        find.descendant(
          of: primary,
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: primary, matching: find.byType(Tooltip)).first,
      );
      expect(tooltip.message, contains('(document.manage)'));
    });
  });

  group('compliance tab', () {
    testWidgets(
      'a finding navigates state-first through the cloud route request',
      (tester) async {
        final backend = FakeDocumentBackend(
          workspaceRequirements: WorkspaceDocumentRequirements(
            requirements: <DocumentRequirementProjection>[
              finding(entityId: 'prop-1'),
            ],
            scopedRuleCount: 0,
          ),
        );
        final container = await pumpHost(
          tester,
          backend: backend,
          initialTab: DocumentsHostTab.compliance,
        );

        await tester.tap(find.text('Energieausweis'));
        await tester.pumpAndSettle();

        final request = container.read(cloudRouteRequestProvider);
        expect(request, isNotNull);
        expect(request!.page, GlobalPage.documents);
        expect(request.surface, CloudRouteSurface.propertyDocuments);
        expect(request.propertyId, 'prop-1');
        expect(find.byType(DocumentsHostScreen), findsOneWidget);
      },
    );

    testWidgets('KPIs ride the shared tiles and offer no reminder', (
      tester,
    ) async {
      await pumpHost(
        tester,
        backend: FakeDocumentBackend(
          workspaceRequirements: WorkspaceDocumentRequirements(
            requirements: <DocumentRequirementProjection>[
              finding(entityId: 'prop-1'),
              finding(
                entityId: 'prop-2',
                state: DocumentRequirementState.expiring,
                name: 'Brandschutz',
              ),
            ],
            scopedRuleCount: 2,
          ),
        ),
        initialTab: DocumentsHostTab.compliance,
      );

      expect(find.byType(NxKpiTile), findsNWidgets(4));
      expect(find.byType(NxKpiRow), findsOneWidget);
      expect(find.text('Nicht vollständig ausgewertet'), findsOneWidget);
      expect(find.textContaining('Erinner'), findsNothing);
      expect(
        find.byKey(const Key('documents-compliance-only-unmet')),
        findsOneWidget,
      );
    });
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
        testWidgets('${entry.key} renders every tab in ${density.name}', (
          tester,
        ) async {
          final container = await pumpHost(
            tester,
            backend: FakeDocumentBackend(
              documents: <DocumentDto>[
                document('d1', 'Kaufvertrag'),
                document('d2', 'Energieausweis 2026'),
              ],
              versions: <DocumentVersionDto>[version('d1')],
              requirements: <RequiredDocumentDto>[
                const RequiredDocumentDto(
                  id: 'rule-1',
                  workspaceId: workspace,
                  entityType: DocumentLinkEntityType.property,
                  documentTypeId: 'type-1',
                  isMandatory: true,
                  version: 1,
                ),
              ],
              workspaceRequirements: WorkspaceDocumentRequirements(
                requirements: <DocumentRequirementProjection>[
                  finding(entityId: 'prop-1'),
                ],
                scopedRuleCount: 1,
              ),
            ),
            size: entry.value,
            density: density,
          );

          expect(tester.takeException(), isNull);
          expect(find.text('Kaufvertrag'), findsOneWidget);
          // Selected through the controller: at the 320 floor the row sits
          // below the fold and a missed tap would test nothing.
          await container
              .read(documentsWorkspaceControllerProvider.notifier)
              .selectDocument('d1');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('documents-register-detail')),
            findsOneWidget,
          );
          for (final tab in <DocumentsHostTab>[
            DocumentsHostTab.types,
            DocumentsHostTab.requirements,
            DocumentsHostTab.compliance,
          ]) {
            await openTab(tester, tab);
            expect(tester.takeException(), isNull, reason: tab.name);
          }
        });
      }
    }
  });
}

class _RecordingLauncher {
  _RecordingLauncher({this.result = true});

  final bool result;
  final List<Uri> launched = <Uri>[];

  Future<bool> launch(Uri uri) async {
    launched.add(uri);
    return result;
  }
}
