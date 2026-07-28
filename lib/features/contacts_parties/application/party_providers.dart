/// Backend-agnostic Riverpod seam for the contacts_parties contract (P2-D02).
///
/// Which implementation serves each port is decided by
/// `AppEnvironment.dataBackend` in the composition root
/// (`lib/app_backend_wiring.dart`), mirroring
/// `referencePropertyRepositoryProvider`: the Supabase adapter in cloud mode,
/// the read-only legacy SQLite adapter locally. Reading a port before an
/// override is installed fails closed instead of silently binding a default.
///
/// No Supabase SDK type appears here — the application layer stays
/// backend-agnostic; SDK types meet these providers only in the composition
/// root.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'party_query_invalidation_source.dart';
import 'party_repository.dart';

final partyRepositoryProvider = Provider<PartyRepository>(
  (ref) => throw StateError('PartyRepository is not configured.'),
);

final partySearchProvider = Provider<PartySearchPort>(
  (ref) => throw StateError('PartySearchPort is not configured.'),
);

final partyRoleProvider = Provider<PartyRoleRepository>(
  (ref) => throw StateError('PartyRoleRepository is not configured.'),
);

final duplicateDetectionProvider = Provider<DuplicateDetectionPort>(
  (ref) => throw StateError('DuplicateDetectionPort is not configured.'),
);

/// Null outside cloud mode: the legacy adapter reads a local database and has
/// no realtime channel to invalidate from.
final partyQueryInvalidationSourceProvider =
    Provider<PartyQueryInvalidationSource?>((ref) => null);
