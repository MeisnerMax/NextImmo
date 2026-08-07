/// Workspace-scoped realtime invalidation for the platform read models
/// (P2-D04 step 6).
///
/// Unlike P1-011 (property) and P2-D02/P2-D03 (party, document), which listen
/// to WAL changes on one table, this source consumes the CTR-005 domain-event
/// broadcast built in increment 1. That is the generalization CTR-005 exists
/// for: an envelope carries its own `required_permission`, so one mechanism
/// covers three aggregates and, unlike a table publication, it can also express
/// events that no single row change represents.
///
/// Two properties of the underlying transport are deliberately surfaced here
/// rather than papered over:
///
/// 1. **Per-aggregate permission scoping.** Each aggregate broadcasts on its
///    own topic (`task.read`, `notification.read`, `import.read`). A member who
///    holds only `task.read` receives task invalidations and nothing else —
///    that is the security property, not a bug.
/// 2. **Fan-out is coarse.** Increment 2 publishes exactly one
///    `notification.fanned_out` envelope per batch, with no `aggregateId` and
///    no recipient list, because a per-recipient broadcast would leak who was
///    notified to every holder of `notification.read`. The consumer therefore
///    turns that envelope into a workspace-wide notification invalidation and
///    lets the reader refetch its own feed. A recipient who does *not* hold
///    `notification.read` receives no wake at all and is refreshed by the
///    reconciliation signal or an ordinary read — that gap is named here
///    instead of being claimed as solved.
library;

enum PlatformAggregate { task, notification, importJob }

class PlatformQueryInvalidation {
  const PlatformQueryInvalidation({
    required this.workspaceId,
    required PlatformAggregate aggregate,
    required String eventType,
    this.aggregateId,
  }) : _aggregate = aggregate,
       _eventType = eventType;

  /// Emitted once the subscription is (re)established, so a listener refreshes
  /// whatever it missed while the channel was down instead of trusting a
  /// possibly stale cache. The broadcast is best-effort transport; the durable
  /// truth is the `domain_events` outbox.
  const PlatformQueryInvalidation.reconcile({required this.workspaceId})
    : _aggregate = null,
      _eventType = null,
      aggregateId = null;

  final String workspaceId;
  final PlatformAggregate? _aggregate;
  final String? _eventType;

  /// Null for coarse, batch-level envelopes such as `notification.fanned_out`,
  /// and on a reconciliation signal.
  final String? aggregateId;

  bool get isReconciliation => _aggregate == null;

  /// Non-null exactly when this is not a reconciliation signal.
  PlatformAggregate? get aggregate => _aggregate;

  /// The originating envelope's `event_type`, kept so a listener can react more
  /// narrowly than "something about tasks changed" without re-deriving it.
  String? get eventType => _eventType;
}

abstract interface class PlatformQueryInvalidationSource {
  /// Merges the task, notification and import-job topics into one stream. A
  /// topic the caller lacks the permission for simply yields nothing; it is not
  /// an error, because a workspace member legitimately holding a subset of the
  /// three permissions is the normal case.
  Stream<PlatformQueryInvalidation> watchWorkspace({
    required String workspaceId,
  });
}
