import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/app_backend_wiring.dart';
import 'package:neximmo_app/core/config/app_environment.dart';
import 'package:neximmo_app/core/models/comps.dart';
import 'package:neximmo_app/core/models/contractor.dart';
import 'package:neximmo_app/core/models/documents.dart';
import 'package:neximmo_app/core/models/operations.dart';
import 'package:neximmo_app/core/models/property_modules.dart';
import 'package:neximmo_app/data/repositories/comps_repo.dart';
import 'package:neximmo_app/data/repositories/operations_repo.dart';
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
import 'package:neximmo_app/features/leasing_operations/application/leasing_providers.dart'
    as leasing;
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/data/legacy_operations_signals_adapter.dart';
import 'package:neximmo_app/features/leasing_operations/data/legacy_sqlite_leasing_repository_adapter.dart';
import 'package:neximmo_app/features/leasing_operations/data/supabase_leasing_query_invalidation_adapter.dart';
import 'package:neximmo_app/features/leasing_operations/data/supabase_leasing_repository_adapter.dart';
import 'package:neximmo_app/features/leasing_operations/domain/rent_roll_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';
import 'package:neximmo_app/features/valuation/application/valuation_providers.dart';
import 'package:neximmo_app/features/valuation/application/valuation_repository.dart';
import 'package:neximmo_app/features/valuation/data/legacy_comps_comparable_source.dart';
import 'package:neximmo_app/features/valuation/data/legacy_sqlite_valuation_repository_adapter.dart';
import 'package:neximmo_app/features/valuation/data/supabase_valuation_query_invalidation_adapter.dart';
import 'package:neximmo_app/features/valuation/data/supabase_valuation_repository_adapter.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
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
      compsRepositoryProvider.overrideWithValue(_StubCompsRepository()),
      legacyPartyReadSourceProvider.overrideWithValue(
        _EmptyLegacyPartyReadSource(),
      ),
      legacyDocumentReadSourceProvider.overrideWithValue(
        _EmptyLegacyDocumentReadSource(),
      ),
      legacyValuationReadSourceProvider.overrideWithValue(
        _EmptyLegacyValuationReadSource(),
      ),
      legacyLeasingReadSourceProvider.overrideWithValue(
        _EmptyLegacyLeasingReadSource(),
      ),
      // P2-D05a's legacy adapter wraps OperationsRepo directly rather than a
      // read-source abstraction (see its header) — a real Database is not
      // needed for these wiring assertions, which only compare provider
      // identity and never call a method that touches `_database`.
      operationsRepositoryProvider.overrideWithValue(const OperationsRepo()),
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

const LeasingCommandContext _leasingContext = LeasingCommandContext(
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

    test('binds every valuation port to the one read-only legacy adapter', () {
      final container = _sqliteContainer();
      final adapter = container.read(legacyValuationRepositoryAdapterProvider);

      expect(container.read(valuationCaseRepositoryProvider), same(adapter));
      expect(container.read(valuationFactorProvider), same(adapter));
      expect(container.read(valuationReportProvider), same(adapter));
      expect(adapter, isA<LegacySqliteValuationRepositoryAdapter>());
    });

    test('binds every leasing port to its read-only legacy adapter', () {
      final container = _sqliteContainer();
      // Four adapters rather than one, unlike the domains above: the leasing
      // aggregates share the natural method names, so one class cannot serve
      // them all. Each port must still land on the right one of the four.
      final units = container.read(legacyUnitRepositoryAdapterProvider);
      final leases = container.read(legacyLeaseRepositoryAdapterProvider);
      final cases = container.read(legacyLeasingCaseRepositoryAdapterProvider);
      final rentRoll = container.read(legacyRentRollAdapterProvider);
      final signals = container.read(legacyOperationsSignalsAdapterProvider);

      expect(container.read(leasing.unitRepositoryProvider), same(units));
      expect(container.read(leasing.unitSearchProvider), same(units));
      expect(container.read(leasing.leaseRepositoryProvider), same(leases));
      expect(container.read(leasing.leaseSearchProvider), same(leases));
      expect(container.read(leasing.leasingCaseRepositoryProvider), same(cases));
      expect(container.read(leasing.leasingCaseSearchProvider), same(cases));
      expect(container.read(leasing.rentRollProvider), same(rentRoll));
      expect(container.read(leasing.operationsSignalsProvider), same(signals));
      expect(units, isA<LegacySqliteUnitRepositoryAdapter>());
      expect(rentRoll, isA<LegacySqliteRentRollAdapter>());
      expect(signals, isA<LegacySqliteOperationsSignalsAdapter>());
    });

    test('leasing reads succeed while its mutations are blocked', () async {
      final container = _sqliteContainer();

      final read = await container
          .read(leasing.unitSearchProvider)
          .search(const UnitListQuery(workspaceId: _workspace));
      expect(read, isA<LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>>());

      final mutation = await container
          .read(leasing.unitRepositoryProvider)
          .create(
            const CreateUnitCommand(
              context: _leasingContext,
              draft: UnitDraft(propertyId: 'property-a', unitCode: 'A-01'),
            ),
          );
      expect(
        (mutation as LeasingRepositoryFailure<UnitDto>).kind,
        LeasingRepositoryFailureKind.dependencyConflict,
      );
    });

    test('the local rent roll is refused with its reason, not left empty', () async {
      final container = _sqliteContainer();

      final result = await container.read(leasing.rentRollProvider).listSnapshots(
        const RentRollSnapshotListQuery(
          workspaceId: _workspace,
          propertyId: 'property-a',
        ),
      );

      // An empty list would read as "this property has no rent roll"; the
      // truth is that this backend cannot express the one it has.
      final failure =
          result as LeasingRepositoryFailure<LeasingPageResult<RentRollSnapshotDto>>;
      expect(failure.kind, LeasingRepositoryFailureKind.dependencyConflict);
      expect(failure.message, contains('reporting period'));
    });

    test('comparables use the read-only legacy store only in SQLite mode', () {
      final container = _sqliteContainer();

      expect(
        container.read(valuationComparableSourceProvider),
        isA<LegacyCompsComparableSource>(),
      );
    });

    test('leaves every realtime invalidation source unbound', () {
      final container = _sqliteContainer();

      expect(container.read(partyQueryInvalidationSourceProvider), isNull);
      expect(container.read(documentQueryInvalidationSourceProvider), isNull);
      expect(container.read(valuationQueryInvalidationSourceProvider), isNull);
      expect(container.read(leasing.leasingQueryInvalidationSourceProvider), isNull);
    });

    test(
      'valuation reads succeed while its mutations report unsupported',
      () async {
        final container = _sqliteContainer();

        final read = await container
            .read(valuationCaseRepositoryProvider)
            .searchValuationCases(
              const ValuationCaseListQuery(workspaceId: _workspace),
            );
        expect(
          read,
          isA<ValuationRepositorySuccess<ValuationPageResult<Object?>>>(),
        );

        final mutation = await container
            .read(valuationCaseRepositoryProvider)
            .createValuationCase(
              const CreateValuationCaseCommand(
                context: ValuationCommandContext(
                  workspaceId: _workspace,
                  actorId: 'actor',
                  mutationId: 'mutation',
                  correlationId: 'correlation',
                ),
                propertyId: 'prop-1',
                title: 'Musterfall',
                kind: ValuationCaseKind.holding,
              ),
            );
        expect(
          (mutation as ValuationRepositoryFailure).kind,
          ValuationRepositoryFailureKind.unsupportedByBackend,
        );
      },
    );

    test(
      'reads succeed while party mutations report read-only-until-migrated',
      () async {
        final container = _sqliteContainer();

        final read = await container
            .read(partySearchProvider)
            .search(const PartyListQuery(workspaceId: _workspace));
        expect(read, isA<PartyRepositorySuccess<PartyPageResult>>());

        final mutation = await container
            .read(partyRepositoryProvider)
            .create(
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
      },
    );

    test(
      'reads succeed while document mutations report read-only-until-migrated',
      () async {
        final container = _sqliteContainer();

        final read = await container
            .read(documentRepositoryProvider)
            .search(const DocumentListQuery(workspaceId: _workspace));
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

    test(
      'scopes the legacy adapters to another workspace as forbidden',
      () async {
        final container = _sqliteContainer();

        final result = await container
            .read(partySearchProvider)
            .search(const PartyListQuery(workspaceId: 'other-workspace'));
        expect(
          (result as PartyRepositoryFailure<PartyPageResult>).kind,
          PartyRepositoryFailureKind.forbidden,
        );

        final units = await container
            .read(leasing.unitSearchProvider)
            .search(const UnitListQuery(workspaceId: 'other-workspace'));
        expect(
          (units
                  as LeasingRepositoryFailure<
                    LeasingPageResult<UnitSummaryDto>
                  >)
              .kind,
          LeasingRepositoryFailureKind.forbidden,
        );
      },
    );
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

    test('binds every valuation port to the Supabase adapter', () {
      final container = _supabaseContainer();
      final adapter = container.read(valuationCaseRepositoryProvider);

      expect(adapter, isA<SupabaseValuationRepositoryAdapter>());
      expect(container.read(valuationFactorProvider), same(adapter));
      expect(container.read(valuationReportProvider), same(adapter));
      expect(
        container.read(valuationQueryInvalidationSourceProvider),
        isA<SupabaseValuationQueryInvalidationAdapter>(),
      );
    });

    test('binds every leasing port to its Supabase adapter', () {
      final container = _supabaseContainer();
      final units = container.read(leasing.unitRepositoryProvider);
      final leases = container.read(leasing.leaseRepositoryProvider);
      final cases = container.read(leasing.leasingCaseRepositoryProvider);

      expect(units, isA<SupabaseUnitRepositoryAdapter>());
      expect(leases, isA<SupabaseLeaseRepositoryAdapter>());
      expect(cases, isA<SupabaseLeasingCaseRepositoryAdapter>());
      expect(container.read(leasing.unitSearchProvider), same(units));
      expect(container.read(leasing.leaseSearchProvider), same(leases));
      expect(container.read(leasing.leasingCaseSearchProvider), same(cases));
      expect(
        container.read(leasing.rentRollProvider),
        isA<SupabaseRentRollAdapter>(),
      );
      expect(
        container.read(leasing.operationsSignalsProvider),
        isA<SupabaseOperationsSignalsAdapter>(),
      );
      expect(
        container.read(leasing.leasingQueryInvalidationSourceProvider),
        isA<SupabaseLeasingQueryInvalidationAdapter>(),
      );
    });

    test('does not fall back to SQLite comparables in cloud mode', () async {
      final container = _supabaseContainer();

      expect(
        container
            .read(valuationComparableSourceProvider)
            .listForProperty('property-a'),
        throwsA(isA<UnsupportedError>()),
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
      expect(
        () => container.read(valuationCaseRepositoryProvider),
        throwsA(isA<StateError>()),
      );
      expect(
        () => container.read(valuationReportProvider),
        throwsA(isA<StateError>()),
      );
      expect(
        () => container.read(leasing.unitRepositoryProvider),
        throwsA(isA<StateError>()),
      );
      expect(
        () => container.read(leasing.leaseSearchProvider),
        throwsA(isA<StateError>()),
      );
      expect(
        () => container.read(leasing.rentRollProvider),
        throwsA(isA<StateError>()),
      );
      expect(
        () => container.read(leasing.operationsSignalsProvider),
        throwsA(isA<StateError>()),
      );
      // The invalidation source is the one leasing provider with a default:
      // null means "no realtime here", which is a binding, not a failure.
      expect(
        container.read(leasing.leasingQueryInvalidationSourceProvider),
        isNull,
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

class _StubCompsRepository implements CompsRepository {
  @override
  Future<List<CompSale>> listSales(String propertyId) async =>
      const <CompSale>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyLegacyLeasingReadSource implements LegacyLeasingReadSource {
  @override
  Future<List<String>> listPropertyIds() async => const <String>[];

  @override
  Future<List<UnitRecord>> listUnits(String propertyId) async =>
      const <UnitRecord>[];

  @override
  Future<List<LeaseRecord>> listLeases(String propertyId) async =>
      const <LeaseRecord>[];

  @override
  Future<LeaseRecord?> findLease(String leaseId) async => null;
}

class _EmptyLegacyValuationReadSource implements LegacyValuationReadSource {
  @override
  Future<List<LegacyScenarioValuation>> listScenarioValuations({
    String? propertyId,
  }) async => const <LegacyScenarioValuation>[];
}

class _EmptyLegacyDocumentReadSource implements LegacyDocumentReadSource {
  @override
  Future<List<DocumentRecord>> listDocuments() async =>
      const <DocumentRecord>[];

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
