/// Backend-agnostic Riverpod seam for the documents_compliance contract
/// (P2-D03).
///
/// Which implementation serves each of the six ports is decided by
/// `AppEnvironment.dataBackend` in the composition root
/// (`lib/app_backend_wiring.dart`), mirroring
/// `referencePropertyRepositoryProvider`: the Supabase adapter in cloud mode,
/// the read-only legacy SQLite adapter locally. Reading a port before an
/// override is installed fails closed instead of silently binding a default.
///
/// These names are deliberately distinct from the legacy
/// `documentsRepositoryProvider` (`DocumentsRepo`) in `ui/state/app_state.dart`:
/// the legacy provider keeps serving its remaining consumers untouched until
/// every screen has moved over.
///
/// No Supabase SDK type appears here — the application layer stays
/// backend-agnostic; SDK types meet these providers only in the composition
/// root.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'document_query_invalidation_source.dart';
import 'document_repository.dart';

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => throw StateError('DocumentRepository is not configured.'),
);

final documentContentProvider = Provider<DocumentContentPort>(
  (ref) => throw StateError('DocumentContentPort is not configured.'),
);

final documentLinkProvider = Provider<DocumentLinkPort>(
  (ref) => throw StateError('DocumentLinkPort is not configured.'),
);

final requirementPolicyProvider = Provider<RequirementPolicyRepository>(
  (ref) => throw StateError('RequirementPolicyRepository is not configured.'),
);

final documentVerificationProvider = Provider<DocumentVerificationPort>(
  (ref) => throw StateError('DocumentVerificationPort is not configured.'),
);

final signedUrlProvider = Provider<SignedUrlPort>(
  (ref) => throw StateError('SignedUrlPort is not configured.'),
);

/// Null outside cloud mode: the legacy adapter reads a local database and has
/// no realtime channel to invalidate from.
final documentQueryInvalidationSourceProvider =
    Provider<DocumentQueryInvalidationSource?>((ref) => null);
