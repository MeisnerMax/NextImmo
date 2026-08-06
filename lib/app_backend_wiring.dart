/// Composition root for the backend-selected feature contracts of Wave 2
/// (`contacts_parties` / `documents_compliance`, P2-D02 / P2-D03).
///
/// `main.dart` installs [featureBackendOverrides] for the environment's
/// `DataBackend`, so every screen reads one set of provider names and never
/// learns which backend answers:
///
/// * `supabase` — one [SupabasePartyRepositoryAdapter] and one
///   [SupabaseDocumentRepositoryAdapter] serve all ports of their domain, plus
///   the workspace-scoped realtime invalidation adapters.
/// * `sqlite` — the read-only `LegacySqlite*` adapters. Every mutation answers
///   `dependencyConflict` by design (no version token, no audited command
///   envelope locally), which is what the screens render as the mandatory
///   "read-only until migrated" state.
///
/// This file is the only place where Supabase SDK types meet Riverpod
/// providers; the feature `application/` layers stay backend-agnostic.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_environment.dart';
import 'core/security/rbac.dart';
import 'features/contacts_parties/application/party_providers.dart';
import 'features/contacts_parties/data/legacy_sqlite_party_repository_adapter.dart';
import 'features/contacts_parties/data/supabase_party_query_invalidation_adapter.dart';
import 'features/contacts_parties/data/supabase_party_repository_adapter.dart';
import 'features/documents_compliance/application/document_providers.dart';
import 'features/documents_compliance/data/legacy_sqlite_document_repository_adapter.dart';
import 'features/documents_compliance/data/supabase_document_query_invalidation_adapter.dart';
import 'features/documents_compliance/data/supabase_document_repository_adapter.dart';
import 'features/identity_access/application/workspace_session_scope.dart';
// Prefixed: the leasing seam names its port `leaseRepositoryProvider`, which
// collides with the legacy `LeaseRepo` provider of the same name in
// `ui/state/app_state.dart`. Screens import only one of the two, so the prefix
// stays local to this composition root.
import 'features/leasing_operations/application/leasing_providers.dart'
    as leasing;
import 'features/leasing_operations/data/legacy_operations_signals_adapter.dart';
import 'features/leasing_operations/data/legacy_sqlite_leasing_repository_adapter.dart';
import 'features/leasing_operations/data/supabase_leasing_query_invalidation_adapter.dart';
import 'features/leasing_operations/data/supabase_leasing_repository_adapter.dart';
import 'features/platform_audit_jobs/application/platform_providers.dart';
import 'features/platform_audit_jobs/data/legacy_sqlite_platform_repository_adapter.dart';
import 'features/platform_audit_jobs/data/supabase_platform_repository_adapter.dart';
import 'features/reference_slice/application/reference_slice_controller.dart';
import 'features/valuation/application/valuation_providers.dart';
import 'features/valuation/application/valuation_comparable_source.dart';
import 'features/valuation/data/legacy_comps_comparable_source.dart';
import 'features/valuation/data/legacy_sqlite_valuation_repository_adapter.dart';
import 'features/valuation/data/supabase_valuation_query_invalidation_adapter.dart';
import 'features/valuation/data/supabase_valuation_repository_adapter.dart';
import 'features/valuation/domain/methods/comparison_approach_method.dart';
import 'ui/state/app_state.dart';
import 'ui/state/security_state.dart';

/// Workspace the read-only legacy adapters answer for. Anything else is
/// rejected as `forbidden` by the adapters themselves, so an unresolved
/// security context (`null`) can never read another workspace's rows.
const String _unresolvedLegacyWorkspaceId = '';

final legacyPartyReadSourceProvider = Provider<LegacyPartyReadSource>((ref) {
  return RepositoryLegacyPartyReadSource(
    leaseRepo: ref.watch(leaseRepositoryProvider),
    contractorRepo: ref.watch(contractorRepositoryProvider),
    propertyModulesRepo: ref.watch(propertyModulesRepositoryProvider),
  );
});

final legacyPartyRepositoryAdapterProvider =
    Provider<LegacySqlitePartyRepositoryAdapter>((ref) {
      return LegacySqlitePartyRepositoryAdapter(
        source: ref.watch(legacyPartyReadSourceProvider),
        legacyWorkspaceId:
            ref.watch(activeWorkspaceIdProvider) ??
            _unresolvedLegacyWorkspaceId,
      );
    });

final legacyDocumentReadSourceProvider = Provider<LegacyDocumentReadSource>((
  ref,
) {
  return RepositoryLegacyDocumentReadSource(
    documentsRepo: ref.watch(documentsRepositoryProvider),
    documentTypesRepo: ref.watch(documentTypesRepositoryProvider),
    requiredDocumentsRepo: ref.watch(requiredDocumentsRepositoryProvider),
  );
});

final legacyDocumentRepositoryAdapterProvider =
    Provider<LegacySqliteDocumentRepositoryAdapter>((ref) {
      return LegacySqliteDocumentRepositoryAdapter(
        source: ref.watch(legacyDocumentReadSourceProvider),
        legacyWorkspaceId:
            ref.watch(activeWorkspaceIdProvider) ??
            _unresolvedLegacyWorkspaceId,
      );
    });

final legacyValuationReadSourceProvider = Provider<LegacyValuationReadSource>((
  ref,
) {
  return RepositoryLegacyValuationReadSource(
    scenarioRepo: ref.watch(scenarioRepositoryProvider),
    scenarioValuationRepo: ref.watch(scenarioValuationRepositoryProvider),
  );
});

/// Both backend modes read comparables from the legacy comps store: the P2-D07
/// comps aggregate is not migrated yet, so there is no cloud source to bind.
/// Stated here rather than hidden behind a mode switch that pretends otherwise.
final legacyValuationComparableSourceOverride =
    valuationComparableSourceProvider.overrideWith(
      (ref) => LegacyCompsComparableSource(ref.watch(compsRepositoryProvider)),
    );

final cloudValuationComparableSourceOverride = valuationComparableSourceProvider
    .overrideWithValue(const _UnavailableCloudValuationComparableSource());

final legacyValuationRepositoryAdapterProvider =
    Provider<LegacySqliteValuationRepositoryAdapter>((ref) {
      return LegacySqliteValuationRepositoryAdapter(
        source: ref.watch(legacyValuationReadSourceProvider),
        legacyWorkspaceId:
            ref.watch(activeWorkspaceIdProvider) ??
            _unresolvedLegacyWorkspaceId,
      );
    });

final legacyLeasingReadSourceProvider = Provider<LegacyLeasingReadSource>((
  ref,
) {
  return RepositoryLegacyLeasingReadSource(
    propertyRepo: ref.watch(propertyRepositoryProvider),
    rentRollRepo: ref.watch(rentRollRepositoryProvider),
    leaseRepo: ref.watch(leaseRepositoryProvider),
  );
});

/// Four legacy adapters rather than one, because the four leasing aggregates
/// share the natural method names — the same reason the Supabase side builds
/// four. They share one read source, so they still read one database.
final legacyUnitRepositoryAdapterProvider =
    Provider<LegacySqliteUnitRepositoryAdapter>((ref) {
      return LegacySqliteUnitRepositoryAdapter(
        source: ref.watch(legacyLeasingReadSourceProvider),
        legacyWorkspaceId:
            ref.watch(activeWorkspaceIdProvider) ??
            _unresolvedLegacyWorkspaceId,
      );
    });

final legacyLeaseRepositoryAdapterProvider =
    Provider<LegacySqliteLeaseRepositoryAdapter>((ref) {
      return LegacySqliteLeaseRepositoryAdapter(
        source: ref.watch(legacyLeasingReadSourceProvider),
        legacyWorkspaceId:
            ref.watch(activeWorkspaceIdProvider) ??
            _unresolvedLegacyWorkspaceId,
      );
    });

final legacyLeasingCaseRepositoryAdapterProvider =
    Provider<LegacySqliteLeasingCaseRepositoryAdapter>((ref) {
      return LegacySqliteLeasingCaseRepositoryAdapter(
        source: ref.watch(legacyLeasingReadSourceProvider),
        legacyWorkspaceId:
            ref.watch(activeWorkspaceIdProvider) ??
            _unresolvedLegacyWorkspaceId,
      );
    });

final legacyRentRollAdapterProvider = Provider<LegacySqliteRentRollAdapter>((
  ref,
) {
  return LegacySqliteRentRollAdapter(
    source: ref.watch(legacyLeasingReadSourceProvider),
    legacyWorkspaceId:
        ref.watch(activeWorkspaceIdProvider) ?? _unresolvedLegacyWorkspaceId,
  );
});

/// P2-D05a. Wraps the existing `OperationsRepo` (`ui/state/app_state.dart`)
/// rather than `legacyLeasingReadSourceProvider` — see the adapter's header
/// for why this one aggregate is a thin projection, not a re-derivation.
final legacyOperationsSignalsAdapterProvider =
    Provider<LegacySqliteOperationsSignalsAdapter>((ref) {
      return LegacySqliteOperationsSignalsAdapter(
        repo: ref.watch(operationsRepositoryProvider),
        legacyWorkspaceId:
            ref.watch(activeWorkspaceIdProvider) ??
            _unresolvedLegacyWorkspaceId,
      );
    });

/// P2-D04. Only [TaskRepository] is consumed today (see
/// `platform_providers.dart`'s header), so this is the one adapter instance
/// `OperationsAlertsPanel`'s "create task" action needs — the same class also
/// answers `NotificationPort`/`JobRepository`/`SearchIndexPort` once a screen
/// reads one of those through the provider seam.
final legacyPlatformReadSourceProvider = Provider<LegacyPlatformReadSource>((
  ref,
) {
  return RepositoryLegacyPlatformReadSource(
    tasksRepo: ref.watch(tasksRepositoryProvider),
    notificationsRepo: ref.watch(notificationsRepositoryProvider),
    importsRepo: ref.watch(importsRepositoryProvider),
    searchRepo: ref.watch(searchRepositoryProvider),
  );
});

final legacyPlatformRepositoryAdapterProvider =
    Provider<LegacySqlitePlatformRepositoryAdapter>((ref) {
      return LegacySqlitePlatformRepositoryAdapter(
        source: ref.watch(legacyPlatformReadSourceProvider),
        legacyWorkspaceId:
            ref.watch(activeWorkspaceIdProvider) ??
            _unresolvedLegacyWorkspaceId,
      );
    });

/// The provider overrides that bind the Wave 2, Wave 3 and Wave 5 contracts to
/// [environment]'s backend. [client] is required in cloud mode and ignored
/// otherwise.
List<Override> featureBackendOverrides({
  required AppEnvironment environment,
  SupabaseClient? client,
}) {
  switch (environment.dataBackend) {
    case DataBackend.supabase:
      if (client == null) {
        throw ArgumentError.notNull('client');
      }
      final parties = SupabasePartyRepositoryAdapter(client: client);
      final documents = SupabaseDocumentRepositoryAdapter(client: client);
      final valuations = SupabaseValuationRepositoryAdapter(client: client);
      final leasingUnits = SupabaseUnitRepositoryAdapter(client: client);
      final leasingLeases = SupabaseLeaseRepositoryAdapter(client: client);
      final leasingCases = SupabaseLeasingCaseRepositoryAdapter(client: client);
      final leasingRentRoll = SupabaseRentRollAdapter(client: client);
      final leasingSignals = SupabaseOperationsSignalsAdapter(client: client);
      final platform = SupabasePlatformRepositoryAdapter(client: client);
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
        leasing.operationsSignalsProvider.overrideWithValue(leasingSignals),
        leasing.leasingQueryInvalidationSourceProvider.overrideWithValue(
          SupabaseLeasingQueryInvalidationAdapter(client: client),
        ),
        taskRepositoryProvider.overrideWithValue(platform),
      ];
    case DataBackend.sqlite:
      // The invalidation sources keep their null default: no realtime locally.
      return <Override>[
        // Local security context is the identity; mutations are unsupported
        // because the legacy adapters cannot honour the command envelope.
        workspaceSessionScopeProvider.overrideWith((ref) {
          return WorkspaceSessionScope(
            workspaceId: ref.watch(activeWorkspaceIdProvider),
            actorId: ref.watch(activeUserIdProvider),
            permissions: const Rbac().permissionsForRole(
              ref.watch(activeUserRoleProvider),
            ),
            mutationsSupported: false,
          );
        }),
        partyRepositoryProvider.overrideWith(
          (ref) => ref.watch(legacyPartyRepositoryAdapterProvider),
        ),
        partySearchProvider.overrideWith(
          (ref) => ref.watch(legacyPartyRepositoryAdapterProvider),
        ),
        partyRoleProvider.overrideWith(
          (ref) => ref.watch(legacyPartyRepositoryAdapterProvider),
        ),
        duplicateDetectionProvider.overrideWith(
          (ref) => ref.watch(legacyPartyRepositoryAdapterProvider),
        ),
        documentRepositoryProvider.overrideWith(
          (ref) => ref.watch(legacyDocumentRepositoryAdapterProvider),
        ),
        documentContentProvider.overrideWith(
          (ref) => ref.watch(legacyDocumentRepositoryAdapterProvider),
        ),
        documentLinkProvider.overrideWith(
          (ref) => ref.watch(legacyDocumentRepositoryAdapterProvider),
        ),
        requirementPolicyProvider.overrideWith(
          (ref) => ref.watch(legacyDocumentRepositoryAdapterProvider),
        ),
        documentVerificationProvider.overrideWith(
          (ref) => ref.watch(legacyDocumentRepositoryAdapterProvider),
        ),
        signedUrlProvider.overrideWith(
          (ref) => ref.watch(legacyDocumentRepositoryAdapterProvider),
        ),
        documentUploadProvider.overrideWith(
          (ref) => ref.watch(legacyDocumentRepositoryAdapterProvider),
        ),
        valuationCaseRepositoryProvider.overrideWith(
          (ref) => ref.watch(legacyValuationRepositoryAdapterProvider),
        ),
        valuationFactorProvider.overrideWith(
          (ref) => ref.watch(legacyValuationRepositoryAdapterProvider),
        ),
        valuationReportProvider.overrideWith(
          (ref) => ref.watch(legacyValuationRepositoryAdapterProvider),
        ),
        legacyValuationComparableSourceOverride,
        leasing.unitRepositoryProvider.overrideWith(
          (ref) => ref.watch(legacyUnitRepositoryAdapterProvider),
        ),
        leasing.unitSearchProvider.overrideWith(
          (ref) => ref.watch(legacyUnitRepositoryAdapterProvider),
        ),
        leasing.leaseRepositoryProvider.overrideWith(
          (ref) => ref.watch(legacyLeaseRepositoryAdapterProvider),
        ),
        leasing.leaseSearchProvider.overrideWith(
          (ref) => ref.watch(legacyLeaseRepositoryAdapterProvider),
        ),
        leasing.leasingCaseRepositoryProvider.overrideWith(
          (ref) => ref.watch(legacyLeasingCaseRepositoryAdapterProvider),
        ),
        leasing.leasingCaseSearchProvider.overrideWith(
          (ref) => ref.watch(legacyLeasingCaseRepositoryAdapterProvider),
        ),
        leasing.rentRollProvider.overrideWith(
          (ref) => ref.watch(legacyRentRollAdapterProvider),
        ),
        leasing.operationsSignalsProvider.overrideWith(
          (ref) => ref.watch(legacyOperationsSignalsAdapterProvider),
        ),
        taskRepositoryProvider.overrideWith(
          (ref) => ref.watch(legacyPlatformRepositoryAdapterProvider),
        ),
      ];
  }
}

class _UnavailableCloudValuationComparableSource
    implements ValuationComparableSource {
  const _UnavailableCloudValuationComparableSource();

  @override
  Future<List<ComparableSale>> listForProperty(String propertyId) {
    return Future<List<ComparableSale>>.error(
      UnsupportedError(
        'Cloud comparables are not migrated; SQLite fallback is disabled.',
      ),
    );
  }
}
