/// Backend-agnostic Riverpod seam for the maintenance_capex contract (P2-D06).
///
/// Which implementation serves each port is decided by
/// `AppEnvironment.dataBackend` in the composition root
/// (`lib/app_backend_wiring.dart`), mirroring the P2-D05 leasing seam: the
/// Supabase adapters in cloud mode, the read-only-for-mutations legacy SQLite
/// adapters locally. Reading a port before an override is installed fails
/// closed instead of silently binding a default.
///
/// Four ports, two adapter instances per backend — the two aggregates share
/// the natural method names, so one class cannot serve them all. That is an
/// implementation fact of the `data/` layer; a screen only ever sees these
/// provider names.
///
/// No Supabase SDK type appears here — the application layer stays
/// backend-agnostic; SDK types meet these providers only in the composition
/// root.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'maintenance_capex_query_invalidation_source.dart';
import 'maintenance_capex_repository.dart';

final maintenanceTicketRepositoryProvider =
    Provider<MaintenanceTicketRepository>(
      (ref) => throw StateError('MaintenanceTicketRepository is not configured.'),
    );

final maintenanceTicketSearchProvider = Provider<MaintenanceTicketSearchPort>(
  (ref) => throw StateError('MaintenanceTicketSearchPort is not configured.'),
);

final capexProjectRepositoryProvider = Provider<CapexProjectRepository>(
  (ref) => throw StateError('CapexProjectRepository is not configured.'),
);

final capexProjectSearchProvider = Provider<CapexProjectSearchPort>(
  (ref) => throw StateError('CapexProjectSearchPort is not configured.'),
);

/// Null outside cloud mode: the legacy adapter reads a local database and has
/// no realtime channel to invalidate from.
final maintenanceCapexQueryInvalidationSourceProvider =
    Provider<MaintenanceCapexQueryInvalidationSource?>((ref) => null);
