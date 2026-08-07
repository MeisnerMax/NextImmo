/// The CTR-005 domain-event envelope and its two read ports (P2-D04, DOM-010).
///
/// Increment 1 established the split this contract follows: the
/// `domain_events` table is the durable outbox and *the truth*; the Realtime
/// broadcast on `workspace:<id>:<permission>` is best-effort transport, and a
/// failed broadcast never fails the mutation that produced it. A consumer that
/// trusted only the broadcast would therefore silently miss events.
///
/// That is why there are two ports rather than one: [DomainEventConsumer] is
/// the live wake-up, [OutboxPort] is the authoritative catch-up read that
/// closes whatever the transport dropped.
library;

/// One CTR-005 envelope. It is a pointer, not a copy: it carries identifiers
/// and state keys so a consumer knows what to refetch, never business field
/// values (the server caps the payload at 4 KiB to keep that honest).
class DomainEventEnvelope {
  const DomainEventEnvelope({
    required this.eventId,
    required this.eventType,
    required this.schemaVersion,
    required this.workspaceId,
    required this.aggregateType,
    required this.occurredAt,
    required this.correlationId,
    this.aggregateId,
    this.aggregateVersion,
    this.actorId,
    this.payload = const <String, Object?>{},
  });

  final String eventId;

  /// A normalized key such as `task.status_changed` or
  /// `notification.fanned_out`.
  final String eventType;
  final int schemaVersion;
  final String workspaceId;

  /// Carried alongside [aggregateId] because an id alone does not identify an
  /// aggregate across domains.
  final String aggregateType;
  final DateTime occurredAt;
  final String correlationId;

  /// Null for batch envelopes such as `notification.fanned_out`, which describe
  /// a fan-out rather than one addressable row.
  final String? aggregateId;
  final int? aggregateVersion;
  final String? actorId;
  final Map<String, Object?> payload;
}

/// A keyset page over the outbox, ordered oldest-first so a consumer can resume
/// exactly where it stopped.
///
/// The cursor is composite — `occurredAt` alone cannot order envelopes, because
/// `now()` is transaction-bound and every event written by one command shares
/// it. Increment 1's pgTAP suite pins that property explicitly.
class OutboxQuery {
  const OutboxQuery({
    required this.workspaceId,
    required this.requiredPermission,
    this.after,
    this.limit = 100,
  }) : assert(limit > 0 && limit <= 500);

  final String workspaceId;

  /// The permission scope to read. The server's RLS policy already restricts
  /// rows to envelopes whose own `required_permission` the caller holds, so
  /// this narrows a legitimate read rather than granting one.
  final String requiredPermission;
  final OutboxCursor? after;
  final int limit;
}

class OutboxCursor {
  const OutboxCursor({required this.occurredAt, required this.eventId});

  final DateTime occurredAt;
  final String eventId;
}

class OutboxPage {
  const OutboxPage({required this.events, this.nextCursor});

  final List<DomainEventEnvelope> events;
  final OutboxCursor? nextCursor;
}

/// DOM-010 `OutboxPort`: the authoritative, replayable read of the event log.
abstract interface class OutboxPort {
  Future<OutboxPage> read(OutboxQuery query);
}

/// The live broadcast. Emits a reconciliation signal (see
/// [PlatformQueryInvalidation.isReconciliation] on the invalidation contract)
/// whenever the subscription is (re)established, because anything that happened
/// while the channel was down was missed by the transport and must be recovered
/// from the outbox rather than assumed absent.
abstract interface class DomainEventConsumer {
  /// [requiredPermission] selects the permission-scoped topic
  /// `workspace:<workspaceId>:<requiredPermission>`. A workspace-wide stream
  /// does not exist by design: it would leak the existence and ids of rows the
  /// reader is not allowed to see.
  Stream<DomainEventEnvelope> watch({
    required String workspaceId,
    required String requiredPermission,
  });
}
