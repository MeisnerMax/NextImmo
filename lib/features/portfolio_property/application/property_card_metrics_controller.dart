/// Operational numbers for a page of the property list
/// (`PROPERTY-CARD-METRICS-01`).
///
/// The same shape as [PropertyCoverController], and for the same reason: one
/// read for a whole page, never one per card. The difference is what a failure
/// means. A cover that will not load is a missing picture, so that controller
/// drops it silently. A missing number is not nothing — a card that quietly
/// shows no figures looks identical whether the workspace has no tickets, the
/// caller may not see them, or the read failed. So a failure is kept in the
/// state and said out loud once, above the grid.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../../reference_slice/application/reference_slice_controller.dart';
import '../domain/property_card_metrics_dto.dart';
import 'property_repository.dart';

class PropertyCardMetricsState {
  const PropertyCardMetricsState({
    this.metrics = const <String, PropertyCardMetricsDto>{},
    this.failed = false,
  });

  /// Property id to its numbers. A property is absent when the server withheld
  /// it, when it has not been asked for yet, or when the read failed — the
  /// card then shows no figures, which is the only honest rendering of all
  /// three.
  final Map<String, PropertyCardMetricsDto> metrics;

  /// At least one batch did not come back. The grid says so once instead of
  /// letting every card imply an empty portfolio.
  final bool failed;

  PropertyCardMetricsDto? operator [](String propertyId) =>
      metrics[propertyId];
}

class PropertyCardMetricsController
    extends StateNotifier<PropertyCardMetricsState> {
  PropertyCardMetricsController({
    required PropertyRepository repository,
    required WorkspaceSessionScope scope,
  }) : _repository = repository,
       _scope = scope,
       super(const PropertyCardMetricsState());

  /// The server refuses more than this in one call. Splitting here rather than
  /// letting it refuse keeps a restored session with several pages already
  /// loaded from losing its numbers entirely.
  static const int _batchSize = 200;

  final PropertyRepository _repository;
  final WorkspaceSessionScope _scope;

  /// Ids already asked for, so a rebuild does not re-ask. Cleared only by a
  /// new controller, which a workspace switch produces.
  final Set<String> _requested = <String>{};
  bool _loading = false;

  /// Loads the metrics of any [propertyIds] not fetched yet.
  Future<void> ensure(List<String> propertyIds) async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null || _loading) {
      return;
    }
    final missing = propertyIds
        .where((String id) => !_requested.contains(id))
        .toList(growable: false);
    if (missing.isEmpty) {
      return;
    }
    _loading = true;
    _requested.addAll(missing);
    try {
      for (int start = 0; start < missing.length; start += _batchSize) {
        final end = (start + _batchSize).clamp(0, missing.length);
        final result = await _repository.cardMetrics(
          workspaceId: workspaceId,
          propertyIds: missing.sublist(start, end),
        );
        if (!mounted) {
          return;
        }
        if (result is! PropertyRepositorySuccess<PropertyCardMetricsBatch>) {
          // Asked and not answered. The ids stay in `_requested`, because
          // retrying on every rebuild would turn a failing backend into a
          // request loop; the user's own refresh builds a new controller.
          state = PropertyCardMetricsState(
            metrics: state.metrics,
            failed: true,
          );
          continue;
        }
        state = PropertyCardMetricsState(
          metrics: Map<String, PropertyCardMetricsDto>.unmodifiable(
            <String, PropertyCardMetricsDto>{
              ...state.metrics,
              ...result.value.byPropertyId,
            },
          ),
          // Withheld ids are not a failure. The server answered; it said this
          // caller may not see those properties, and their cards showing no
          // numbers is the correct outcome, not a degraded one.
          failed: state.failed,
        );
      }
    } finally {
      _loading = false;
    }
  }
}

final propertyCardMetricsControllerProvider = StateNotifierProvider.autoDispose
    .family<
      PropertyCardMetricsController,
      PropertyCardMetricsState,
      String
    >((Ref ref, String workspaceId) {
      return PropertyCardMetricsController(
        repository: ref.watch(referencePropertyRepositoryProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
      );
    });
