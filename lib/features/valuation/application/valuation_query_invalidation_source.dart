/// Workspace-scoped realtime invalidation for the valuation read models
/// (P2-D07).
///
/// Follows the P2-D04 domain-event pattern rather than a per-table publication:
/// one topic (`valuation.read`), envelopes that name the aggregate they concern,
/// so a member without `valuation.read` receives nothing — that is the security
/// property, not a gap.
///
/// A published report and a factor edit are separate signals on purpose: a
/// factor change invalidates the *inputs* view (and makes a stored report stale
/// without replacing it), while a published report invalidates the results view.
/// Collapsing them would hide exactly the staleness this engine exists to make
/// visible.
library;

enum ValuationAggregate { valuationCase, factors, report }

class ValuationQueryInvalidation {
  const ValuationQueryInvalidation({
    required this.workspaceId,
    required ValuationAggregate aggregate,
    required String eventType,
    this.valuationCaseId,
  }) : _aggregate = aggregate,
       _eventType = eventType;

  /// Emitted once the subscription is (re)established, so a listener refreshes
  /// whatever it missed while the channel was down. The broadcast is best-effort
  /// transport; the durable truth is the `domain_events` outbox.
  const ValuationQueryInvalidation.reconcile({required this.workspaceId})
    : _aggregate = null,
      _eventType = null,
      valuationCaseId = null;

  final String workspaceId;
  final ValuationAggregate? _aggregate;
  final String? _eventType;

  /// Null on a reconciliation signal and on workspace-wide envelopes.
  final String? valuationCaseId;

  bool get isReconciliation => _aggregate == null;

  /// Non-null exactly when this is not a reconciliation signal.
  ValuationAggregate? get aggregate => _aggregate;

  /// The originating envelope's `event_type`, so a listener can react more
  /// narrowly than "something about valuations changed".
  String? get eventType => _eventType;
}

abstract interface class ValuationQueryInvalidationSource {
  Stream<ValuationQueryInvalidation> watchWorkspace({
    required String workspaceId,
  });
}
