import '../domain/audit_event_dto.dart';
import '../domain/property_activity_dto.dart';
import 'platform_repository.dart';

/// One page of a property's audit trail (AUDIT-01).
class PropertyAuditQuery {
  const PropertyAuditQuery({
    required this.workspaceId,
    required this.propertyId,
    this.cursor,
    this.limit = 50,
  }) : assert(limit > 0 && limit <= 100);

  final String workspaceId;
  final String propertyId;

  /// Where the previous page ended. Null starts at the newest event.
  final AuditEventCursor? cursor;
  final int limit;
}

/// One page of a property's activity timeline (PROPERTY-ACTIVITY-01).
class PropertyActivityQuery {
  const PropertyActivityQuery({
    required this.workspaceId,
    required this.propertyId,
    this.domains = const <PropertyActivityDomain>{},
    this.from,
    this.to,
    this.cursor,
    this.limit = 50,
  }) : assert(limit > 0 && limit <= 100);

  final String workspaceId;
  final String propertyId;

  /// Empty means every domain the caller may see. A domain they cannot see
  /// yields an empty timeline rather than a refusal — the page's coverage
  /// statement is what explains that.
  final Set<PropertyActivityDomain> domains;

  final DateTime? from;
  final DateTime? to;

  final PropertyActivityCursor? cursor;
  final int limit;
}

/// The application's only way into `audit_events` (AUDIT-01).
///
/// It is a read port and nothing else: the audit log is append-only and is
/// written by the mutations it records, never by a client.
///
/// Two rules are the server's, not this port's, and are restated here because
/// a future adapter must not quietly relax either:
///
///   * **Two permissions.** `audit.read` says the membership may see a trail;
///     entity-scoped `property.read` says it may see *this* property's. Reading
///     the record of a change is not weaker than reading the change.
///   * **A projection, not a row.** The stored event carries the old and new
///     values of every patched field. Those never reach the client; the DTO
///     carries the field names instead.
abstract interface class AuditReadPort {
  Future<PlatformRepositoryResult<AuditEventPage>> propertyAuditEvents(
    PropertyAuditQuery query,
  );

  /// The readable chronicle of a property (PROPERTY-ACTIVITY-01).
  ///
  /// The same table, a different question and a different gate. Where the
  /// trail above needs `audit.read` and publishes field names, this needs only
  /// the domain's own read right and publishes events. A caller who may read
  /// tickets but not leases gets a timeline with the tickets in it — filtered
  /// on the server, never here.
  Future<PlatformRepositoryResult<PropertyActivityPage>> propertyActivity(
    PropertyActivityQuery query,
  );
}
