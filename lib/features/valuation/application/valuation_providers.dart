/// Backend-agnostic Riverpod seam for the valuation contract (P2-D07, Welle 5).
///
/// Which implementation serves each of the three ports is decided by
/// `AppEnvironment.dataBackend` in the composition root
/// (`lib/app_backend_wiring.dart`): the Supabase adapter in cloud mode, the
/// read-only legacy SQLite projection locally. Reading a port before an
/// override is installed fails closed instead of silently binding a default.
///
/// These names are deliberately distinct from the legacy
/// `scenarioValuationRepositoryProvider` in `ui/state/app_state.dart`: the
/// legacy provider keeps serving its remaining consumers untouched until every
/// screen has moved over.
///
/// No Supabase SDK type appears here — the application layer stays
/// backend-agnostic; SDK types meet these providers only in the composition
/// root.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/methods/comparison_approach_method.dart';
import 'valuation_comparable_source.dart';
import 'valuation_query_invalidation_source.dart';
import 'valuation_repository.dart';

final valuationCaseRepositoryProvider = Provider<ValuationCaseRepository>(
  (ref) => throw StateError('ValuationCaseRepository is not configured.'),
);

final valuationFactorProvider = Provider<ValuationFactorPort>(
  (ref) => throw StateError('ValuationFactorPort is not configured.'),
);

final valuationReportProvider = Provider<ValuationReportPort>(
  (ref) => throw StateError('ValuationReportPort is not configured.'),
);

/// Null outside cloud mode: the legacy adapter reads a local database and has
/// no realtime channel to invalidate from.
final valuationQueryInvalidationSourceProvider =
    Provider<ValuationQueryInvalidationSource?>((ref) => null);

/// Comparables for the Vergleichswertverfahren. Bound in the composition root
/// to the legacy comps store in both backend modes, because the P2-D07 comps
/// aggregate has not been migrated yet — that is a stated gap, not a default.
final valuationComparableSourceProvider = Provider<ValuationComparableSource>(
  (ref) => throw StateError('ValuationComparableSource is not configured.'),
);

/// The comparables of one property, ready for the engine.
final valuationComparablesProvider = FutureProvider.autoDispose
    .family<List<ComparableSale>, String>((ref, propertyId) {
      return ref
          .watch(valuationComparableSourceProvider)
          .listForProperty(propertyId);
    });
