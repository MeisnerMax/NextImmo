import '../domain/audit_event_dto.dart';
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
}
