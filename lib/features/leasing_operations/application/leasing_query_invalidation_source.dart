/// Workspace-scoped realtime invalidation for the leasing read models
/// (P2-D05 increment 3), following the P1-011 property and P2-D02 party
/// realtime pattern.
///
/// Four tables are published (`units`, `leases`, `leasing_cases`,
/// `rent_roll_snapshots`); `rent_roll_snapshot_lines` deliberately is not,
/// because a line is never written independently of its header. The two
/// realtime migrations state both decisions in full.
///
/// The invalidation carries no payload beyond "something changed here", exactly
/// as those migrations promise clients it would: one logical command can touch
/// two published tables (activating a lease also flips its unit's occupancy via
/// `sync_unit_occupancy`; a case reaching `signed` also touches its lease), so
/// a consumer must be able to collapse the duplicate. [aggregate] is carried
/// only so a consumer can refetch the one list that changed instead of all
/// four — never as a claim about what the row now contains.
library;

/// Which read model a realtime event invalidates.
enum LeasingAggregate { unit, lease, leasingCase, rentRollSnapshot }

class LeasingQueryInvalidation {
  const LeasingQueryInvalidation({
    required this.workspaceId,
    required this.aggregate,
    required this.entityId,
  });

  /// Emitted once when the subscription becomes live: everything read before
  /// that moment may be stale, so the consumer refetches rather than assuming
  /// it caught up.
  const LeasingQueryInvalidation.reconcile({required this.workspaceId})
    : aggregate = null,
      entityId = null;

  final String workspaceId;
  final LeasingAggregate? aggregate;
  final String? entityId;

  bool get isReconciliation => aggregate == null;
}

abstract interface class LeasingQueryInvalidationSource {
  Stream<LeasingQueryInvalidation> watchWorkspace({
    required String workspaceId,
  });
}
