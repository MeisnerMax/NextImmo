import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/app_backend_wiring.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_providers.dart';
import 'package:neximmo_app/features/contacts_parties/data/supabase_party_query_invalidation_adapter.dart';
import 'package:neximmo_app/features/contacts_parties/data/supabase_party_repository_adapter.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_providers.dart';
import 'package:neximmo_app/features/documents_compliance/data/supabase_document_query_invalidation_adapter.dart';
import 'package:neximmo_app/features/documents_compliance/data/supabase_document_repository_adapter.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_providers.dart'
    as leasing;
import 'package:neximmo_app/features/leasing_operations/data/supabase_leasing_query_invalidation_adapter.dart';
import 'package:neximmo_app/features/leasing_operations/data/supabase_leasing_repository_adapter.dart';
import 'package:neximmo_app/features/maintenance_capex/application/maintenance_capex_providers.dart';
import 'package:neximmo_app/features/maintenance_capex/data/supabase_maintenance_capex_query_invalidation_adapter.dart';
import 'package:neximmo_app/features/maintenance_capex/data/supabase_maintenance_capex_repository_adapter.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_providers.dart';
import 'package:neximmo_app/features/platform_audit_jobs/data/supabase_platform_repository_adapter.dart';
import 'package:neximmo_app/features/valuation/application/valuation_providers.dart';
import 'package:neximmo_app/features/valuation/data/supabase_valuation_query_invalidation_adapter.dart';
import 'package:neximmo_app/features/valuation/data/supabase_valuation_repository_adapter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

ProviderContainer _cloudContainer() {
  final client = SupabaseClient(
    'http://localhost:54321',
    'test-publishable-key',
  );
  addTearDown(() async => client.dispose());
  final container = ProviderContainer(
    overrides: featureBackendOverrides(client: client),
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // AP-X02-2b removed the SQLite runtime backend, and with it the group that
  // asserted the read-only legacy bindings. Supabase is the only runtime
  // backend, so the only two things left to prove are: every port lands on the
  // right cloud adapter, and an unwired container still fails closed.
  group('featureBackendOverrides — supabase', () {
    test('binds every party port to the Supabase adapter', () {
      final container = _cloudContainer();
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
      final container = _cloudContainer();
      final adapter = container.read(documentRepositoryProvider);

      expect(adapter, isA<SupabaseDocumentRepositoryAdapter>());
      expect(container.read(documentContentProvider), same(adapter));
      expect(container.read(documentLinkProvider), same(adapter));
      expect(container.read(requirementPolicyProvider), same(adapter));
      expect(container.read(documentVerificationProvider), same(adapter));
      expect(container.read(signedUrlProvider), same(adapter));
      expect(container.read(documentUploadProvider), same(adapter));
      expect(
        container.read(documentQueryInvalidationSourceProvider),
        isA<SupabaseDocumentQueryInvalidationAdapter>(),
      );
    });

    test('binds every valuation port to the Supabase adapter', () {
      final container = _cloudContainer();
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
      final container = _cloudContainer();
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

    test('binds every maintenance_capex port to its Supabase adapter', () {
      final container = _cloudContainer();
      final tickets = container.read(maintenanceTicketRepositoryProvider);
      final projects = container.read(capexProjectRepositoryProvider);

      expect(tickets, isA<SupabaseMaintenanceTicketRepositoryAdapter>());
      expect(projects, isA<SupabaseCapexProjectRepositoryAdapter>());
      expect(container.read(maintenanceTicketSearchProvider), same(tickets));
      expect(container.read(capexProjectSearchProvider), same(projects));
      expect(
        container.read(maintenanceCapexQueryInvalidationSourceProvider),
        isA<SupabaseMaintenanceCapexQueryInvalidationAdapter>(),
      );
    });

    test('binds the task port to the Supabase adapter', () {
      final container = _cloudContainer();

      expect(
        container.read(taskRepositoryProvider),
        isA<SupabasePlatformRepositoryAdapter>(),
      );
    });

    test('comparables report unavailable rather than falling back', () {
      final container = _cloudContainer();

      // The comps aggregate is not migrated (AP-X02-5). Failing loudly is the
      // point: a silent empty list would read as "this property has no
      // comparables", which is a different and wrong statement.
      expect(
        container
            .read(valuationComparableSourceProvider)
            .listForProperty('property-a'),
        throwsA(isA<UnsupportedError>()),
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
      expect(
        () => container.read(taskRepositoryProvider),
        throwsA(isA<StateError>()),
      );
      expect(
        () => container.read(maintenanceTicketRepositoryProvider),
        throwsA(isA<StateError>()),
      );
      expect(
        () => container.read(capexProjectSearchProvider),
        throwsA(isA<StateError>()),
      );
      // The invalidation source is the one leasing/maintenance_capex provider
      // with a default: null means "no realtime here", which is a binding,
      // not a failure.
      expect(
        container.read(leasing.leasingQueryInvalidationSourceProvider),
        isNull,
      );
      expect(
        container.read(maintenanceCapexQueryInvalidationSourceProvider),
        isNull,
      );
    });
  });
}
