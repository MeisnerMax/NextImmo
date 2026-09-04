import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_mutation_outcome.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_registry_controller.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_repository.dart';
import 'package:neximmo_app/features/documents_compliance/domain/document_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';

import '../../ui/screens/docs/fake_document_backend.dart';

/// DOCUMENTS-V2 B1: the registry controllers on the upsert-only contract.
/// What matters here is exactly what the server does *not* do for us: refuse
/// a create that would silently update an existing key/rule identity, keep a
/// retirement's audited old/new snapshot honest, and never delete.
void main() {
  const workspace = FakeDocumentBackend.workspace;

  WorkspaceSessionScope scope({bool manage = true, bool mutations = true}) {
    return WorkspaceSessionScope(
      workspaceId: workspace,
      actorId: 'actor-1',
      permissions: <String>{'document.read', if (manage) 'document.manage'},
      mutationsSupported: mutations,
    );
  }

  const rule = RequiredDocumentDto(
    id: 'rule-1',
    workspaceId: workspace,
    entityType: DocumentLinkEntityType.property,
    documentTypeId: 'type-1',
    isMandatory: true,
    version: 2,
    scopeKey: 'MFH',
    validityMonths: 24,
    note: 'Bei Ankauf',
    requestedAt: null,
  );

  group('key helpers', () {
    test('suggests a contract-conform key from a German name', () {
      expect(suggestDocumentTypeKey('Energieausweis Neu'), 'energieausweis_neu');
      expect(suggestDocumentTypeKey('  Grundbuch-Auszug (2026) '), 'grundbuch_auszug_2026');
      expect(suggestDocumentTypeKey('Übergabeprotokoll'), 'uebergabeprotokoll');
      expect(validateDocumentTypeKey(suggestDocumentTypeKey('Mietvertrag')), isNull);
    });

    test('validates the server pattern and length', () {
      expect(validateDocumentTypeKey(''), 'Pflichtfeld');
      expect(validateDocumentTypeKey('a'), contains('2 bis 100'));
      expect(validateDocumentTypeKey('Bad Key'), contains('Kleinbuchstaben'));
      expect(validateDocumentTypeKey('_leading'), contains('Kleinbuchstaben'));
      expect(validateDocumentTypeKey('ok.key-1_x'), isNull);
    });
  });

  group('DocumentTypesController', () {
    test('loads the complete registry, inactive included', () async {
      final backend = FakeDocumentBackend();
      final controller = DocumentTypesController(
        registry: backend,
        scope: scope(),
        idFactory: () => 'id',
      );
      await controller.load();

      expect(backend.lastListTypesActiveOnly, isFalse);
      expect(controller.state.phase, DocumentRegistryPhase.ready);
      expect(controller.state.types, hasLength(3));
      // Default view hides inactive; the toggle and the search are client
      // filters over a complete list.
      expect(controller.state.visibleTypes.map((t) => t.key), <String>[
        'party_file',
        'purchase_contract',
      ]);
      controller.setShowInactive(true);
      expect(controller.state.visibleTypes, hasLength(3));
      controller.setQuery('ENERG');
      expect(controller.state.visibleTypes.map((t) => t.key), <String>[
        'old_energy',
      ]);
    });

    test('refuses a create over an existing key instead of silently updating', () async {
      final backend = FakeDocumentBackend();
      final controller = DocumentTypesController(
        registry: backend,
        scope: scope(),
        idFactory: () => 'id',
      );
      await controller.load();

      final outcome = await controller.saveType(
        const DocumentTypeDraft(
          key: 'party_file',
          name: 'Neu',
          entityType: DocumentLinkEntityType.party,
        ),
        isNew: true,
      );

      expect(outcome, isA<DocumentMutationRejected>());
      expect((outcome as DocumentMutationRejected).isValidation, isTrue);
      expect(backend.typeCommands, isEmpty);
    });

    test('edit deactivates through the same upsert and keeps the key', () async {
      final backend = FakeDocumentBackend();
      final controller = DocumentTypesController(
        registry: backend,
        scope: scope(),
        idFactory: () => 'id',
      );
      await controller.load();

      final outcome = await controller.saveType(
        const DocumentTypeDraft(
          key: 'party_file',
          name: 'Parteiunterlage',
          entityType: DocumentLinkEntityType.party,
          isActive: false,
        ),
        isNew: false,
        reason: 'nicht mehr verwendet',
      );

      expect(outcome.succeeded, isTrue);
      final command = backend.typeCommands.single;
      expect(command.draft.isActive, isFalse);
      expect(command.context.reason, 'nicht mehr verwendet');
      expect(command.context.workspaceId, workspace);
      expect(command.context.actorId, 'actor-1');
      expect(controller.state.actionMessage, 'Dokumenttyp deaktiviert.');
      expect(
        controller.state.types.firstWhere((t) => t.key == 'party_file').isActive,
        isFalse,
      );
    });

    test('without document.manage nothing reaches the backend', () async {
      final backend = FakeDocumentBackend();
      final controller = DocumentTypesController(
        registry: backend,
        scope: scope(manage: false),
        idFactory: () => 'id',
      );
      await controller.load();

      expect(controller.canManage, isFalse);
      final outcome = await controller.saveType(
        const DocumentTypeDraft(
          key: 'x_y',
          name: 'X',
          entityType: DocumentLinkEntityType.property,
        ),
        isNew: true,
      );
      expect(outcome.succeeded, isFalse);
      expect(backend.typeCommands, isEmpty);
      expect(controller.state.actionPhase, DocumentRegistryActionPhase.forbidden);
    });

    test('forbidden and infrastructure reads are distinct phases', () async {
      final forbidden = DocumentTypesController(
        registry: FakeDocumentBackend(
          listTypesFailure: const DocumentRepositoryFailure<List<DocumentTypeDto>>(
            kind: DocumentRepositoryFailureKind.forbidden,
            message: 'forbidden',
          ),
        ),
        scope: scope(),
      );
      await forbidden.load();
      expect(forbidden.state.phase, DocumentRegistryPhase.forbidden);

      final failing = DocumentTypesController(
        registry: FakeDocumentBackend(
          listTypesFailure: const DocumentRepositoryFailure<List<DocumentTypeDto>>(
            kind: DocumentRepositoryFailureKind.infrastructureFailure,
            message: 'boom',
          ),
        ),
        scope: scope(),
      );
      await failing.load();
      expect(failing.state.phase, DocumentRegistryPhase.error);
    });
  });

  group('RequiredDocumentsController', () {
    test('loads rules of the level together with the full type registry', () async {
      final backend = FakeDocumentBackend(requirements: <RequiredDocumentDto>[rule]);
      final controller = RequiredDocumentsController(
        registry: backend,
        scope: scope(),
        idFactory: () => 'id',
      );
      await controller.load();

      expect(controller.state.entityType, DocumentLinkEntityType.property);
      expect(controller.state.rules, hasLength(1));
      expect(controller.state.types, hasLength(3));
      expect(controller.state.typeName('type-3'), 'Alter Energieausweis');
      expect(controller.state.activeTypesForLevel.map((t) => t.id), <String>[
        'type-1',
      ]);

      await controller.setEntityType(DocumentLinkEntityType.party);
      expect(controller.state.phase, DocumentRegistryPhase.empty);
      expect(controller.state.activeTypesForLevel.map((t) => t.id), <String>[
        'type-2',
      ]);
    });

    test('refuses a duplicate live rule identity on create', () async {
      final backend = FakeDocumentBackend(requirements: <RequiredDocumentDto>[rule]);
      final controller = RequiredDocumentsController(
        registry: backend,
        scope: scope(),
        idFactory: () => 'id',
      );
      await controller.load();

      final duplicate = await controller.saveRule(
        const RequiredDocumentDraft(
          entityType: DocumentLinkEntityType.property,
          documentTypeId: 'type-1',
          scopeKey: 'MFH',
        ),
        isNew: true,
      );
      expect(duplicate, isA<DocumentMutationRejected>());
      expect(backend.requirementCommands, isEmpty);

      // A different scope is a different rule.
      final created = await controller.saveRule(
        const RequiredDocumentDraft(
          entityType: DocumentLinkEntityType.property,
          documentTypeId: 'type-1',
        ),
        isNew: true,
      );
      expect(created.succeeded, isTrue);
      expect(controller.state.rules, hasLength(2));
    });

    test('retiring carries the rule values and the audit reason', () async {
      final backend = FakeDocumentBackend(requirements: <RequiredDocumentDto>[rule]);
      final controller = RequiredDocumentsController(
        registry: backend,
        scope: scope(),
        idFactory: () => 'id',
      );
      await controller.load();

      final outcome = await controller.retireRule(rule, reason: 'Nicht mehr nötig');

      expect(outcome.succeeded, isTrue);
      final command = backend.requirementCommands.single;
      expect(command.draft.retired, isTrue);
      expect(command.draft.scopeKey, 'MFH');
      expect(command.draft.validityMonths, 24);
      expect(command.draft.note, 'Bei Ankauf');
      expect(command.draft.isMandatory, isTrue);
      expect(command.context.reason, 'Nicht mehr nötig');
      // Retired rules are history, not policy: gone from the live list.
      expect(controller.state.rules, isEmpty);
      expect(controller.state.phase, DocumentRegistryPhase.empty);
    });

    test('a read-only session cannot mutate the registry', () async {
      final backend = FakeDocumentBackend(requirements: <RequiredDocumentDto>[rule]);
      final controller = RequiredDocumentsController(
        registry: backend,
        scope: scope(mutations: false),
        idFactory: () => 'id',
      );
      await controller.load();

      final outcome = await controller.retireRule(rule);
      expect(outcome.succeeded, isFalse);
      expect(backend.requirementCommands, isEmpty);
      expect(controller.state.actionMessage, contains('AAL2'));
    });
  });
}
