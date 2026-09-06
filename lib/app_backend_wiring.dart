/// Composition root for the feature contracts of Wave 2 through Wave 5.
///
/// [featureBackendOverrides] binds every port to its Supabase adapter. There is
/// no backend switch any more: since AP-X02-2b the application runtime has
/// exactly one data layer (`DEC-024`). SQLite survives only in migration,
/// cutover and legacy tooling, none of which passes through this file.
///
/// This file is the only place where Supabase SDK types meet Riverpod
/// providers; the feature `application/` layers stay backend-agnostic.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/contacts_parties/application/party_providers.dart';
import 'features/contacts_parties/data/supabase_party_query_invalidation_adapter.dart';
import 'features/contacts_parties/data/supabase_party_repository_adapter.dart';
import 'features/documents_compliance/application/document_providers.dart';
import 'features/documents_compliance/data/supabase_document_query_invalidation_adapter.dart';
import 'features/documents_compliance/data/supabase_document_repository_adapter.dart';
import 'features/finance_ledger/application/finance_providers.dart';
import 'features/finance_ledger/data/supabase_finance_ledger_adapter.dart';
import 'features/identity_access/application/workspace_session_scope.dart';
// Prefixed: the leasing seam names its port `leaseRepositoryProvider`, and a
// legacy provider of the same name still exists in `ui/state/app_state.dart`.
// The prefix keeps the two visually distinct wherever both are in scope.
import 'features/leasing_operations/application/leasing_providers.dart'
    as leasing;
import 'features/leasing_operations/data/supabase_leasing_query_invalidation_adapter.dart';
import 'features/leasing_operations/data/supabase_leasing_repository_adapter.dart';
import 'features/maintenance_capex/application/maintenance_capex_providers.dart';
import 'features/maintenance_capex/data/supabase_maintenance_capex_query_invalidation_adapter.dart';
import 'features/maintenance_capex/data/supabase_maintenance_capex_repository_adapter.dart';
import 'features/platform_audit_jobs/application/platform_providers.dart';
import 'features/portfolio_property/application/property_media_controller.dart';
import 'features/portfolio_property/data/supabase_property_media_adapter.dart';
import 'features/platform_audit_jobs/data/supabase_domain_event_consumer_adapter.dart';
import 'features/platform_audit_jobs/data/supabase_platform_repository_adapter.dart';
import 'features/reference_slice/application/reference_slice_controller.dart';
import 'features/valuation/application/valuation_comparable_source.dart';
import 'features/valuation/application/valuation_providers.dart';
import 'features/valuation/data/supabase_valuation_query_invalidation_adapter.dart';
import 'features/valuation/data/supabase_valuation_repository_adapter.dart';
import 'features/valuation/domain/methods/comparison_approach_method.dart';

/// Comparables have no cloud source yet: the P2-D07 comps aggregate is not
/// migrated. Binding a deliberately failing source states that plainly instead
/// of pretending the comparison approach has data. `AP-X02-5` replaces this
/// with the real cloud source; until then the failure is the honest answer.
final cloudValuationComparableSourceOverride = valuationComparableSourceProvider
    .overrideWithValue(const _UnavailableCloudValuationComparableSource());

/// Binds every feature port to its Supabase adapter.
List<Override> featureBackendOverrides({required SupabaseClient client}) {
  final parties = SupabasePartyRepositoryAdapter(client: client);
  final documents = SupabaseDocumentRepositoryAdapter(client: client);
  final valuations = SupabaseValuationRepositoryAdapter(client: client);
  final leasingUnits = SupabaseUnitRepositoryAdapter(client: client);
  final leasingLeases = SupabaseLeaseRepositoryAdapter(client: client);
  final leasingCases = SupabaseLeasingCaseRepositoryAdapter(client: client);
  final leasingRentRoll = SupabaseRentRollAdapter(client: client);
  final leasingSignals = SupabaseOperationsSignalsAdapter(client: client);
  final leasingSummary = SupabasePropertyLeasingSummaryAdapter(
    client: client,
  );
  final maintenanceTickets = SupabaseMaintenanceTicketRepositoryAdapter(
    client: client,
  );
  final capexProjects = SupabaseCapexProjectRepositoryAdapter(client: client);
  final platform = SupabasePlatformRepositoryAdapter(client: client);
  final propertyMedia = SupabasePropertyMediaAdapter(client: client);
  final financeLedger = SupabaseFinanceLedgerAdapter(client: client);
  return <Override>[
    // The authenticated reference session is the cloud host's identity.
    workspaceSessionScopeProvider.overrideWith((ref) {
      final session = ref.watch(referenceSliceControllerProvider);
      final access = session.selectedWorkspace;
      return WorkspaceSessionScope(
        workspaceId: access?.workspace.id,
        actorId: session.userId,
        permissions: access?.permissions ?? const <String>{},
        mutationsSupported: true,
      );
    }),
    partyRepositoryProvider.overrideWithValue(parties),
    partySearchProvider.overrideWithValue(parties),
    partyRoleProvider.overrideWithValue(parties),
    duplicateDetectionProvider.overrideWithValue(parties),
    partyQueryInvalidationSourceProvider.overrideWithValue(
      SupabasePartyQueryInvalidationAdapter(client: client),
    ),
    documentRepositoryProvider.overrideWithValue(documents),
    documentContentProvider.overrideWithValue(documents),
    documentLinkProvider.overrideWithValue(documents),
    requirementPolicyProvider.overrideWithValue(documents),
    documentVerificationProvider.overrideWithValue(documents),
    signedUrlProvider.overrideWithValue(documents),
    documentUploadProvider.overrideWithValue(documents),
    documentQueryInvalidationSourceProvider.overrideWithValue(
      SupabaseDocumentQueryInvalidationAdapter(client: client),
    ),
    valuationCaseRepositoryProvider.overrideWithValue(valuations),
    valuationFactorProvider.overrideWithValue(valuations),
    valuationReportProvider.overrideWithValue(valuations),
    valuationQueryInvalidationSourceProvider.overrideWithValue(
      SupabaseValuationQueryInvalidationAdapter(client: client),
    ),
    cloudValuationComparableSourceOverride,
    leasing.unitRepositoryProvider.overrideWithValue(leasingUnits),
    leasing.unitSearchProvider.overrideWithValue(leasingUnits),
    leasing.leaseRepositoryProvider.overrideWithValue(leasingLeases),
    leasing.leaseSearchProvider.overrideWithValue(leasingLeases),
    leasing.leasingCaseRepositoryProvider.overrideWithValue(leasingCases),
    leasing.leasingCaseSearchProvider.overrideWithValue(leasingCases),
    leasing.rentRollProvider.overrideWithValue(leasingRentRoll),
    leasing.propertyLeasingSummaryProvider.overrideWithValue(leasingSummary),
    propertyFinanceActualsProvider.overrideWithValue(financeLedger),
    leasing.operationsSignalsProvider.overrideWithValue(leasingSignals),
    leasing.leasingQueryInvalidationSourceProvider.overrideWithValue(
      SupabaseLeasingQueryInvalidationAdapter(client: client),
    ),
    maintenanceTicketRepositoryProvider.overrideWithValue(maintenanceTickets),
    maintenanceTicketSearchProvider.overrideWithValue(maintenanceTickets),
    capexProjectRepositoryProvider.overrideWithValue(capexProjects),
    capexProjectSearchProvider.overrideWithValue(capexProjects),
    maintenanceCapexQueryInvalidationSourceProvider.overrideWithValue(
      SupabaseMaintenanceCapexQueryInvalidationAdapter(client: client),
    ),
    taskRepositoryProvider.overrideWithValue(platform),
    // A15: the same adapter instance serves the notification port — P2-D04
    // shipped all four data-plane ports in one class. The invalidation source
    // is the existing realtime consumer, instantiated here exactly like its
    // party/document/leasing/maintenance siblings.
    notificationPortProvider.overrideWithValue(platform),
    // AUDIT-01: the read port on the same adapter. The audit log is written by
    // the mutations it records, so there is no write port to bind.
    auditReadPortProvider.overrideWithValue(platform),
    // PROPERTY-MEDIA-DATA-01: metadata over PostgREST plus the private bucket.
    propertyMediaPortProvider.overrideWithValue(propertyMedia),
    platformQueryInvalidationSourceProvider.overrideWithValue(
      SupabasePlatformQueryInvalidationAdapter(client: client),
    ),
  ];
}

class _UnavailableCloudValuationComparableSource
    implements ValuationComparableSource {
  const _UnavailableCloudValuationComparableSource();

  @override
  Future<List<ComparableSale>> listForProperty(String propertyId) {
    return Future<List<ComparableSale>>.error(
      UnsupportedError('Cloud comparables are not migrated yet.'),
    );
  }
}
