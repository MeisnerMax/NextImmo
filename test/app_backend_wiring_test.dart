import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/app_backend_wiring.dart';
import 'package:neximmo_app/core/config/app_environment.dart';
import 'package:neximmo_app/core/models/contractor.dart';
import 'package:neximmo_app/core/models/documents.dart';
import 'package:neximmo_app/core/models/operations.dart';
import 'package:neximmo_app/core/models/property_modules.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_providers.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_repository.dart';
import 'package:neximmo_app/features/contacts_parties/data/legacy_sqlite_party_repository_adapter.dart';
import 'package:neximmo_app/features/contacts_parties/data/supabase_party_query_invalidation_adapter.dart';
import 'package:neximmo_app/features/contacts_parties/data/supabase_party_repository_adapter.dart';
import 'package:neximmo_app/features/contacts_parties/domain/party_dto.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_providers.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_repository.dart';
import 'package:neximmo_app/features/documents_compliance/data/legacy_sqlite_document_repository_adapter.dart';
import 'package:neximmo_app/features/documents_compliance/data/supabase_document_query_invalidation_adapter.dart';
import 'package:neximmo_app/features/documents_compliance/data/supabase_document_repository_adapter.dart';
import 'package:neximmo_app/features/documents_compliance/domain/document_dto.dart';
import 'package:neximmo_app/ui/state/security_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _workspace = 'legacy-workspace';

const AppEnvironment _sqliteEnvironment = AppEnvironment(
  environment: NexImmoEnvironment.local,
  dataBackend: DataBackend.sqlite,
);

const AppEnvironment _supabaseEnvironment = AppEnvironment(
  environment: NexImmoEnvironment.local,
  dataBackend: DataBackend.supabase,
  supabaseUrl: 'http://localhost:54321',
  supabasePublishableKey: 'test-publishable-key',
);

ProviderContainer _sqliteContainer() {
  final container = ProviderContainer(
    overrides: <Override>[
      activeWorkspaceIdProvider.overrideWithValue(_workspace),
      legacyPartyReadSourceProvider.overrideWithValue(
        _EmptyLegacyPartyReadSource(),
      ),
      legacyDocumentReadSourceProvider.overrideWithValue(
        _EmptyLegacyDocumentReadSource(),
      ),
      ...featureBackendOverrides(environment: _sqliteEnvironment),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

ProviderContainer _supabaseContainer() {
  final client = SupabaseClient(
    _supabaseEnvironment.supabaseUrl!,
    _supabaseEnvironment.supabasePublishableKey!,
  );
  addTearDown(() async => client.dispose());
  final container = ProviderContainer(
    overrides: featureBackendOverrides(
      environment: _supabaseEnvironment,
      client: client,
    ),
  );
  addTearDown(container.dispose);
  return container;
}

PartyCommandContext get _partyContext => const PartyCommandContext(
  workspaceId: _workspace,
  actorId: 'actor',
  mutationId: 'mutation',
  correlationId: 'correlation',
);

DocumentCommandContext get _documentContext => const DocumentCommandContext(
  workspaceId: _workspace,
  actorId: 'actor',
  mutationId: 'mutation',
  correlationId: 'correlation',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('featureBackendOverrides — sqlite', () {
    test('binds every party port to the one read-only legacy adapter', () {
      final container = _sqliteContainer();
      final adapter = container.read(legacyPartyRepositoryAdapterProvider);

      expect(container.read(partyRepositoryProvider), same(adapter));
      expect(container.read(partySearchProvider), same(adapter));
      expect(container.read(partyRoleProvider), same(adapter));
      expect(container.read(duplicateDetectionProvider), same(adapter));
      expect(adapter, isA<LegacySqlitePartyRepositoryAdapter>());
    });

    test('binds every document port to the one read-only legacy adapter', () {
      final container = _sqliteContainer();
      final adapter = container.read(legacyDocumentRepositoryAdapterProvider);

      expect(container.read(documentRepositoryProvider), same(adapter));
      expect(container.read(documentContentProvider), same(adapter));
      expect(container.read(documentLinkProvider), same(adapter));
      expect(container.read(requirementPolicyProvider), same(adapter));
      expect(container.read(documentVerificationProvider), same(adapter));
      expect(container.read(signedUrlProvider), same(adapter));
      expect(adapter, isA<LegacySqliteDocumentRepositoryAdapter>());
    });

    test('leaves both realtime invalidation sources unbound', () {
      final container = _sqliteContainer();

      expect(container.read(partyQueryInvalidationSourceProvider), isNull);
      expect(container.read(documentQueryInvalidationSourceProvider), isNull);
    });

    test('reads succeed while party mutations report read-only-until-migrated',
        () async {
      final container = _sqliteContainer();

      final read = await container.read(partySearchProvider).search(
            const PartyListQuery(workspaceId: _workspace),
          );
      expect(read, isA<PartyRepositorySuccess<PartyPageResult>>());

      final mutation = await container.read(partyRepositoryProvider).create(
            CreatePartyCommand(
              context: _partyContext,
              draft: const PartyDraft(
                type: PartyType.person,
                displayName: 'Ada Lovelace',
              ),
            ),
          );
      expect(
        (mutation as PartyRepositoryFailure<PartyDto>).kind,
        PartyRepositoryFailureKind.dependencyConflict,
      );
    });

    test(
      'reads succeed while document mutations report read-only-until-migrated',
      () async {
        final container = _sqliteContainer();

        final read = await container.read(documentRepositoryProvider).search(
              const DocumentListQuery(workspaceId: _workspace),
            );
        expect(read, isA<DocumentRepositorySuccess<DocumentPageResult>>());

        final mutation = await container
            .read(documentRepositoryProvider)
            .transitionStatus(
              TransitionDocumentStatusCommand(
                context: _documentContext,
                documentId: 'doc-1',
                expectedVersion: 1,
                transition: DocumentStatusTransition.archive,
              ),
            );
        expect(
          (mutation as DocumentRepositoryFailure<DocumentDto>).kind,
          DocumentRepositoryFailureKind.dependencyConflict,
        );
      },
    );

    test('scopes the legacy adapters to another workspace as forbidden',
        () async {
      final container = _sqliteContainer();

      final result = await container.read(partySearchProvider).search(
            const PartyListQuery(workspaceId: 'other-workspace'),
          );
      expect(
        (result as PartyRepositoryFailure<PartyPageResult>).kind,
        PartyRepositoryFailureKind.forbidden,
      );
    });
  });

  group('featureBackendOverrides — supabase', () {
    test('binds every party port to the Supabase adapter', () {
      final container = _supabaseContainer();
      final adapter = container.read(partyRepositoryProvider);

      expect(adapter, isA<SupabasePartyRepositoryAdapter>());
      expect(container.read(partySearchProvider), same(adapter));
      expect(container.read(partyRoleProvider), same(adapter));
      expect(container.read(duplicateDetectionProvider), same(adapter));
      expect(
        container.read(partyQueryInvalidationSourceProvider),
        isA<SupabasePartyQueryInvalidationAdapter>(),
      );
    });

    test('binds every document port to the Supabase adapter', () {
      final container = _supabaseContainer();
      final adapter = container.read(documentRepositoryProvider);

      expect(adapter, isA<SupabaseDocumentRepositoryAdapter>());
      expect(container.read(documentContentProvider), same(adapter));
      expect(container.read(documentLinkProvider), same(adapter));
      expect(container.read(requirementPolicyProvider), same(adapter));
      expect(container.read(documentVerificationProvider), same(adapter));
      expect(container.read(signedUrlProvider), same(adapter));
      expect(
        container.read(documentQueryInvalidationSourceProvider),
        isA<SupabaseDocumentQueryInvalidationAdapter>(),
      );
    });

    test('refuses to build cloud overrides without a client', () {
      expect(
        () => featureBackendOverrides(environment: _supabaseEnvironment),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('featureBackendOverrides — unwired', () {
    test('every port fails closed when no backend was selected', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(partyRepositoryProvider),
        throwsA(isA<StateError>()),
      );
      expect(
        () => container.read(documentRepositoryProvider),
        throwsA(isA<StateError>()),
      );
      expect(
        () => container.read(signedUrlProvider),
        throwsA(isA<StateError>()),
      );
    });
  });
}

class _EmptyLegacyPartyReadSource implements LegacyPartyReadSource {
  @override
  Future<List<TenantRecord>> listTenants() async => const <TenantRecord>[];

  @override
  Future<List<ContractorRecord>> listContractors() async =>
      const <ContractorRecord>[];

  @override
  Future<List<ContactRecord>> listContacts() async => const <ContactRecord>[];
}

class _EmptyLegacyDocumentReadSource implements LegacyDocumentReadSource {
  @override
  Future<List<DocumentRecord>> listDocuments() async => const <DocumentRecord>[];

  @override
  Future<List<DocumentMetadataRecord>> listMetadata(String documentId) async =>
      const <DocumentMetadataRecord>[];

  @override
  Future<List<DocumentTypeRecord>> listDocumentTypes() async =>
      const <DocumentTypeRecord>[];

  @override
  Future<List<RequiredDocumentRecord>> listRequiredDocuments() async =>
      const <RequiredDocumentRecord>[];
}
