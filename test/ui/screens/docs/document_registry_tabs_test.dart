import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/documents_compliance/application/compliance_dashboard_controller.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_providers.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_repository.dart';
import 'package:neximmo_app/features/documents_compliance/domain/document_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/ui/screens/docs/documents_host_screen.dart';
import 'package:neximmo_app/ui/screens/docs/widgets/document_content_opener.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

import 'fake_document_backend.dart';

/// DOCUMENTS-V2 increment B1: the registry tabs `Typen` and `Pflichtregeln`
/// on the existing `RequirementPolicyRepository` contract — upsert semantics
/// only (deactivate, retire), never a delete; the B2 catalogue decision is not
/// pre-empted (no default types, no prefill).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String workspace = FakeDocumentBackend.workspace;

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

  const propertyRule = RequiredDocumentDto(
    id: 'rule-1',
    workspaceId: workspace,
    entityType: DocumentLinkEntityType.property,
    documentTypeId: 'type-1',
    isMandatory: true,
    version: 2,
    validityMonths: 24,
    note: 'Bei Ankauf',
  );

  const partyRule = RequiredDocumentDto(
    id: 'rule-2',
    workspaceId: workspace,
    entityType: DocumentLinkEntityType.party,
    documentTypeId: 'type-2',
    isMandatory: false,
    version: 1,
    scopeKey: 'Mieter',
  );

  const instanceRule = RequiredDocumentDto(
    id: 'rule-3',
    workspaceId: workspace,
    entityType: DocumentLinkEntityType.property,
    documentTypeId: 'type-1',
    isMandatory: true,
    version: 1,
    entityId: 'prop-1234567890',
    requestedAt: null,
  );

  Future<ProviderContainer> pumpTab(
    WidgetTester tester, {
    required FakeDocumentBackend backend,
    required DocumentsHostTab tab,
    WorkspaceSessionScope? scope,
    Size size = const Size(1440, 900),
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
          complianceObjectDirectoryProvider.overrideWithValue(null),
          documentUrlLauncherProvider.overrideWithValue((_) async => true),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: DocumentsHostScreen(initialTab: tab)),
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

  FilledButton primaryButton(WidgetTester tester) {
    return tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const Key('documents-primary-action')),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
  }

  group('Typen', () {
    testWidgets('types load completely and inactive ones are a toggle', (
      tester,
    ) async {
      final backend = FakeDocumentBackend();
      await pumpTab(tester, backend: backend, tab: DocumentsHostTab.types);

      expect(backend.lastListTypesActiveOnly, isFalse);
      expect(find.byKey(const Key('documents-types')), findsOneWidget);
      expect(find.text('Vertragsunterlage'), findsOneWidget);
      expect(find.text('Parteiunterlage'), findsOneWidget);
      expect(find.text('Alter Energieausweis'), findsNothing);
      expect(find.text('purchase_contract'), findsOneWidget);
      expect(find.text('12 Monate'), findsOneWidget);

      await tester.tap(find.byKey(const Key('documents-types-show-inactive')));
      await tester.pumpAndSettle();
      expect(find.text('Alter Energieausweis'), findsOneWidget);
      expect(find.text('Inaktiv'), findsOneWidget);
      expect(find.textContaining('nie gelöscht'), findsOneWidget);
    });

    testWidgets('search narrows by name or key over the complete list', (
      tester,
    ) async {
      await pumpTab(
        tester,
        backend: FakeDocumentBackend(),
        tab: DocumentsHostTab.types,
      );

      await tester.enterText(
        find.byKey(const Key('documents-types-search')),
        'party',
      );
      await tester.pumpAndSettle();

      expect(find.text('Parteiunterlage'), findsOneWidget);
      expect(find.text('Vertragsunterlage'), findsNothing);
    });

    testWidgets('forbidden and error are their own states', (tester) async {
      await pumpTab(
        tester,
        backend: FakeDocumentBackend(
          listTypesFailure:
              const DocumentRepositoryFailure<List<DocumentTypeDto>>(
                kind: DocumentRepositoryFailureKind.forbidden,
                message: 'forbidden',
              ),
        ),
        tab: DocumentsHostTab.types,
      );
      expect(
        find.byKey(const Key('documents-types-forbidden')),
        findsOneWidget,
      );
      expect(find.textContaining('(document.read)'), findsOneWidget);

      final backend = FakeDocumentBackend(
        listTypesFailure:
            const DocumentRepositoryFailure<List<DocumentTypeDto>>(
              kind: DocumentRepositoryFailureKind.infrastructureFailure,
              message: 'boom',
            ),
      );
      await pumpTab(tester, backend: backend, tab: DocumentsHostTab.types);
      expect(find.byKey(const Key('documents-types-error')), findsOneWidget);
      expect(find.text('boom'), findsNothing);
      expect(find.text('Erneut versuchen'), findsOneWidget);
    });

    testWidgets('creating without document.manage is disabled with a tooltip', (
      tester,
    ) async {
      await pumpTab(
        tester,
        backend: FakeDocumentBackend(),
        tab: DocumentsHostTab.types,
        scope: cloudScope(permissions: const <String>{'document.read'}),
      );

      expect(primaryButton(tester).onPressed, isNull);
      final tooltip = tester.widget<Tooltip>(
        find
            .ancestor(
              of: find.byKey(const Key('documents-primary-action')),
              matching: find.byType(Tooltip),
            )
            .first,
      );
      expect(tooltip.message, contains('(document.manage)'));
      expect(
        find.byKey(const Key('documents-types-edit-party_file')),
        findsOneWidget,
      );
      final edit = tester.widget<TextButton>(
        find.byKey(const Key('documents-types-edit-party_file')),
      );
      expect(edit.onPressed, isNull);
    });

    testWidgets('creating a type sends key, level and validity to the upsert', (
      tester,
    ) async {
      final backend = FakeDocumentBackend();
      await pumpTab(tester, backend: backend, tab: DocumentsHostTab.types);

      await tester.tap(find.byKey(const Key('documents-primary-action')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('documents-type-dialog')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('documents-type-dialog-name')),
        'Energieausweis Neu',
      );
      await tester.pumpAndSettle();
      final keyField = tester.widget<TextFormField>(
        find.byKey(const Key('documents-type-dialog-key')),
      );
      expect(keyField.controller?.text, 'energieausweis_neu');
      await tester.enterText(
        find.byKey(const Key('documents-type-dialog-validity')),
        '10',
      );
      await tester.tap(find.byKey(const Key('documents-type-dialog-submit')));
      await tester.pumpAndSettle();

      final draft = backend.typeCommands.single.draft;
      expect(draft.key, 'energieausweis_neu');
      expect(draft.name, 'Energieausweis Neu');
      expect(draft.entityType, DocumentLinkEntityType.property);
      expect(draft.defaultValidityMonths, 10);
      expect(draft.isActive, isTrue);
      expect(find.byKey(const Key('documents-type-dialog')), findsNothing);
      expect(find.text('Energieausweis Neu'), findsOneWidget);
    });

    testWidgets('an invalid or duplicate key is explained inline', (
      tester,
    ) async {
      final backend = FakeDocumentBackend();
      await pumpTab(tester, backend: backend, tab: DocumentsHostTab.types);
      await tester.tap(find.byKey(const Key('documents-primary-action')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('documents-type-dialog-name')),
        'Test',
      );
      await tester.enterText(
        find.byKey(const Key('documents-type-dialog-key')),
        'Bad Key!',
      );
      await tester.tap(find.byKey(const Key('documents-type-dialog-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Kleinbuchstaben'), findsOneWidget);
      expect(backend.typeCommands, isEmpty);

      await tester.enterText(
        find.byKey(const Key('documents-type-dialog-key')),
        'party_file',
      );
      await tester.tap(find.byKey(const Key('documents-type-dialog-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('bereits'), findsOneWidget);
      expect(backend.typeCommands, isEmpty);
      expect(find.byKey(const Key('documents-type-dialog')), findsOneWidget);
    });

    testWidgets('editing deactivates instead of deleting', (tester) async {
      final backend = FakeDocumentBackend();
      await pumpTab(tester, backend: backend, tab: DocumentsHostTab.types);

      await tester.tap(
        find.byKey(const Key('documents-types-edit-party_file')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('documents-type-dialog')), findsOneWidget);
      // The key is immutable after creation: shown, never editable.
      expect(find.byKey(const Key('documents-type-dialog-key')), findsNothing);
      expect(
        find.byKey(const Key('documents-type-dialog-key-readonly')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('documents-type-dialog-active')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('documents-type-dialog-submit')));
      await tester.pumpAndSettle();

      final draft = backend.typeCommands.single.draft;
      expect(draft.key, 'party_file');
      expect(draft.isActive, isFalse);
      expect(draft.name, 'Parteiunterlage');
      expect(find.text('Löschen'), findsNothing);
      expect(find.text('Loeschen'), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });
  });

  group('Pflichtregeln', () {
    testWidgets('rules are scoped by level with Objekt as the default', (
      tester,
    ) async {
      final backend = FakeDocumentBackend(
        requirements: <RequiredDocumentDto>[
          propertyRule,
          partyRule,
          instanceRule,
        ],
      );
      await pumpTab(
        tester,
        backend: backend,
        tab: DocumentsHostTab.requirements,
      );

      expect(find.byKey(const Key('documents-requirements')), findsOneWidget);
      expect(find.text('Alle Objekte'), findsOneWidget);
      expect(find.textContaining('Instanz: prop-123'), findsOneWidget);
      expect(find.text('24 Monate gültig'), findsOneWidget);
      expect(find.text('Objektart: Mieter'), findsNothing);

      await tester.tap(find.byKey(const Key('documents-requirements-level')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Partei').last);
      await tester.pumpAndSettle();

      expect(find.text('Objektart: Mieter'), findsOneWidget);
      expect(find.text('Optional'), findsOneWidget);
      expect(find.text('Alle Objekte'), findsNothing);
      expect(backend.listRequirementsCalls, greaterThanOrEqualTo(2));
    });

    testWidgets('an empty level names itself', (tester) async {
      await pumpTab(
        tester,
        backend: FakeDocumentBackend(),
        tab: DocumentsHostTab.requirements,
      );
      expect(
        find.byKey(const Key('documents-requirements-empty')),
        findsOneWidget,
      );
      expect(
        find.text('Noch keine Pflichtregeln für diese Ebene'),
        findsOneWidget,
      );
    });

    testWidgets('creating an object-type rule sends the scope key', (
      tester,
    ) async {
      final backend = FakeDocumentBackend();
      await pumpTab(
        tester,
        backend: backend,
        tab: DocumentsHostTab.requirements,
      );

      await tester.tap(find.byKey(const Key('documents-primary-action')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('documents-requirement-dialog')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('documents-requirement-dialog-type')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vertragsunterlage').last);
      await tester.pumpAndSettle();
      // Only active types of the chosen level are offered.
      expect(find.text('Alter Energieausweis'), findsNothing);
      expect(find.text('Parteiunterlage'), findsNothing);

      await tester.tap(
        find.byKey(const Key('documents-requirement-dialog-scope-key')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('documents-requirement-dialog-scope-key-field')),
        'MFH',
      );
      await tester.tap(
        find.byKey(const Key('documents-requirement-dialog-submit')),
      );
      await tester.pumpAndSettle();

      final draft = backend.requirementCommands.single.draft;
      expect(draft.entityType, DocumentLinkEntityType.property);
      expect(draft.documentTypeId, 'type-1');
      expect(draft.scopeKey, 'MFH');
      expect(draft.entityId, isNull);
      expect(draft.isMandatory, isTrue);
      expect(draft.retired, isFalse);
      expect(find.text('Objektart: MFH'), findsOneWidget);
    });

    testWidgets('a waiver requires a reason', (tester) async {
      final backend = FakeDocumentBackend(
        requirements: <RequiredDocumentDto>[propertyRule],
      );
      await pumpTab(
        tester,
        backend: backend,
        tab: DocumentsHostTab.requirements,
      );

      await tester.tap(
        find.byKey(const Key('documents-requirements-edit-rule-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('documents-requirement-dialog-waived')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('documents-requirement-dialog-submit')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pflichtfeld'), findsOneWidget);
      expect(backend.requirementCommands, isEmpty);

      await tester.enterText(
        find.byKey(const Key('documents-requirement-dialog-waiver-reason')),
        'Objekt ist unbebaut',
      );
      await tester.tap(
        find.byKey(const Key('documents-requirement-dialog-submit')),
      );
      await tester.pumpAndSettle();

      final draft = backend.requirementCommands.single.draft;
      expect(draft.waived, isTrue);
      expect(draft.waiverReason, 'Objekt ist unbebaut');
      expect(draft.documentTypeId, 'type-1');
      expect(draft.validityMonths, 24);
      expect(find.text('Nicht relevant'), findsOneWidget);
    });

    testWidgets('a duplicate live rule is refused inline', (tester) async {
      final backend = FakeDocumentBackend(
        requirements: <RequiredDocumentDto>[propertyRule],
      );
      await pumpTab(
        tester,
        backend: backend,
        tab: DocumentsHostTab.requirements,
      );

      await tester.tap(find.byKey(const Key('documents-primary-action')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('documents-requirement-dialog-type')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vertragsunterlage').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('documents-requirement-dialog-submit')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('bereits'), findsOneWidget);
      expect(backend.requirementCommands, isEmpty);
      expect(
        find.byKey(const Key('documents-requirement-dialog')),
        findsOneWidget,
      );
    });

    testWidgets('retiring is a confirmation with a reason and no delete', (
      tester,
    ) async {
      final backend = FakeDocumentBackend(
        requirements: <RequiredDocumentDto>[propertyRule],
      );
      await pumpTab(
        tester,
        backend: backend,
        tab: DocumentsHostTab.requirements,
      );

      await tester.tap(
        find.byKey(const Key('documents-requirements-retire-rule-1')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('documents-requirement-retire-dialog')),
        findsOneWidget,
      );
      expect(find.textContaining('Vertragsunterlage'), findsWidgets);
      expect(find.textContaining('gilt ab sofort nicht mehr'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('documents-requirement-retire-reason')),
        'Nicht mehr nötig',
      );
      await tester.tap(
        find.byKey(const Key('documents-requirement-retire-confirm')),
      );
      await tester.pumpAndSettle();

      final command = backend.requirementCommands.single;
      expect(command.draft.retired, isTrue);
      expect(command.draft.documentTypeId, 'type-1');
      expect(command.draft.isMandatory, isTrue);
      expect(command.draft.validityMonths, 24);
      expect(command.context.reason, 'Nicht mehr nötig');
      expect(find.text('Alle Objekte'), findsNothing);
      expect(find.text('Löschen'), findsNothing);
      expect(find.text('Loeschen'), findsNothing);
    });

    testWidgets('retiring without a reason still retires', (tester) async {
      final backend = FakeDocumentBackend(
        requirements: <RequiredDocumentDto>[propertyRule],
      );
      await pumpTab(
        tester,
        backend: backend,
        tab: DocumentsHostTab.requirements,
      );

      await tester.tap(
        find.byKey(const Key('documents-requirements-retire-rule-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('documents-requirement-retire-confirm')),
      );
      await tester.pumpAndSettle();

      expect(backend.requirementCommands.single.draft.retired, isTrue);
      expect(backend.requirementCommands.single.context.reason, isNull);
      expect(
        find.byKey(const Key('documents-requirement-retire-dialog')),
        findsNothing,
      );
    });

    testWidgets(
      'without document.manage the registry is read-only with tooltips',
      (tester) async {
        await pumpTab(
          tester,
          backend: FakeDocumentBackend(
            requirements: <RequiredDocumentDto>[propertyRule],
          ),
          tab: DocumentsHostTab.requirements,
          scope: cloudScope(permissions: const <String>{'document.read'}),
        );

        expect(primaryButton(tester).onPressed, isNull);
        final retire = tester.widget<TextButton>(
          find.byKey(const Key('documents-requirements-retire-rule-1')),
        );
        expect(retire.onPressed, isNull);
      },
    );

    testWidgets('forbidden names the capability', (tester) async {
      await pumpTab(
        tester,
        backend: FakeDocumentBackend(
          listRequirementsFailure:
              const DocumentRepositoryFailure<List<RequiredDocumentDto>>(
                kind: DocumentRepositoryFailureKind.forbidden,
                message: 'forbidden',
              ),
        ),
        tab: DocumentsHostTab.requirements,
      );
      expect(
        find.byKey(const Key('documents-requirements-forbidden')),
        findsOneWidget,
      );
      expect(find.textContaining('(document.read)'), findsOneWidget);
    });
  });
}
