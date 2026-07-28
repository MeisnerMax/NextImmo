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
import 'features/reference_slice/application/reference_slice_controller.dart';
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

/// The provider overrides that bind both Wave 2 contracts to [environment]'s
/// backend. [client] is required in cloud mode and ignored otherwise.
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
        documentQueryInvalidationSourceProvider.overrideWithValue(
          SupabaseDocumentQueryInvalidationAdapter(client: client),
        ),
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
      ];
  }
}
