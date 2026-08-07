/// Workspace-scoped realtime invalidation for the maintenance_capex read
/// models (P2-D06), following the P1-011 property / P2-D02 party / P2-D05
/// leasing realtime pattern.
///
/// Two tables are published (`maintenance_tickets`, `capex_projects` —
/// `20260806110000_p2_d06_maintenance_capex_realtime.sql`). Neither aggregate
/// has a satellite table the way leasing's rent-roll snapshot does, so there
/// is nothing deliberately left unpublished here.
///
/// The invalidation carries no payload beyond "something changed here".
/// [aggregate] is carried only so a consumer can refetch the one list that
/// changed instead of both — never as a claim about what the row now
/// contains.
library;

/// Which read model a realtime event invalidates.
enum MaintenanceCapexAggregate { maintenanceTicket, capexProject }

class MaintenanceCapexQueryInvalidation {
  const MaintenanceCapexQueryInvalidation({
    required this.workspaceId,
    required this.aggregate,
    required this.entityId,
  });

  /// Emitted once when the subscription becomes live: everything read before
  /// that moment may be stale, so the consumer refetches rather than assuming
  /// it caught up.
  const MaintenanceCapexQueryInvalidation.reconcile({required this.workspaceId})
    : aggregate = null,
      entityId = null;

  final String workspaceId;
  final MaintenanceCapexAggregate? aggregate;
  final String? entityId;

  bool get isReconciliation => aggregate == null;
}

abstract interface class MaintenanceCapexQueryInvalidationSource {
  Stream<MaintenanceCapexQueryInvalidation> watchWorkspace({
    required String workspaceId,
  });
}
