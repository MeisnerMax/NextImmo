/// Backend-agnostic Riverpod seam for the leasing_operations contract (P2-D05).
///
/// Which implementation serves each port is decided by
/// `AppEnvironment.dataBackend` in the composition root
/// (`lib/app_backend_wiring.dart`), mirroring the P2-D02 party seam: the
/// Supabase adapters in cloud mode, the read-only legacy SQLite adapters
/// locally. Reading a port before an override is installed fails closed instead
/// of silently binding a default.
///
/// Seven ports, four adapter instances per backend — the four aggregates share
/// the natural method names, so one class cannot serve them all. That is an
/// implementation fact of the `data/` layer; a screen only ever sees these
/// provider names.
///
/// No Supabase SDK type appears here — the application layer stays
/// backend-agnostic; SDK types meet these providers only in the composition
/// root.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'leasing_query_invalidation_source.dart';
import 'leasing_repository.dart';
import 'operations_signals_contract.dart';

final unitRepositoryProvider = Provider<UnitRepository>(
  (ref) => throw StateError('UnitRepository is not configured.'),
);

final unitSearchProvider = Provider<UnitSearchPort>(
  (ref) => throw StateError('UnitSearchPort is not configured.'),
);

final leaseRepositoryProvider = Provider<LeaseRepository>(
  (ref) => throw StateError('LeaseRepository is not configured.'),
);

final leaseSearchProvider = Provider<LeaseSearchPort>(
  (ref) => throw StateError('LeaseSearchPort is not configured.'),
);

final leasingCaseRepositoryProvider = Provider<LeasingCaseRepository>(
  (ref) => throw StateError('LeasingCaseRepository is not configured.'),
);

final leasingCaseSearchProvider = Provider<LeasingCaseSearchPort>(
  (ref) => throw StateError('LeasingCaseSearchPort is not configured.'),
);

final rentRollProvider = Provider<RentRollPort>(
  (ref) => throw StateError('RentRollPort is not configured.'),
);

/// LEASING-SUMMARY-01.
final propertyLeasingSummaryProvider = Provider<PropertyLeasingSummaryPort>(
  (ref) => throw StateError('PropertyLeasingSummaryPort is not configured.'),
);

/// P2-D05a.
final operationsSignalsProvider = Provider<OperationsSignalsPort>(
  (ref) => throw StateError('OperationsSignalsPort is not configured.'),
);

/// Null outside cloud mode: the legacy adapters read a local database and have
/// no realtime channel to invalidate from.
final leasingQueryInvalidationSourceProvider =
    Provider<LeasingQueryInvalidationSource?>((ref) => null);
