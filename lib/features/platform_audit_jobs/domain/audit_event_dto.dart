/// The application-facing audit event (AUDIT-01).
///
/// A deliberately narrow projection of `audit_events`. The stored row also
/// carries `old_values`, `new_values` and `scope_snapshot` — per-field patches
/// and permission snapshots that can hold anything a user typed into a form.
/// None of that is here, and there is no field to put it in: what travels is
/// [changedFields], the *names* of the fields a mutation touched.
///
/// "Who changed which field of what, when, and why" is the accountability
/// question an audit trail answers. "To which value" is a separate disclosure
/// decision, and this DTO is shaped so a surface cannot answer it by accident.
library;

enum AuditActorType { user, system, service }

class AuditEventDto {
  const AuditEventDto({
    required this.id,
    required this.occurredAt,
    required this.action,
    required this.entityType,
    required this.actorType,
    required this.source,
    required this.correlationId,
    this.entityId,
    this.parentEntityType,
    this.parentEntityId,
    this.actorUserId,
    this.actorIdentifier,
    this.roleKey,
    this.mutationId,
    this.reason,
    this.changedFields = const <String>[],
  });

  final String id;
  final DateTime occurredAt;

  /// Dotted server key, e.g. `property.updated`. Rendered through a label map;
  /// an unmapped action is shown as its key rather than dropped, so a new
  /// server event is visible instead of silently missing from a trail.
  final String action;

  final String entityType;
  final String? entityId;

  /// How a child record reaches its property. A unit or lease change carries
  /// the property here, which is what puts it in the property's trail.
  final String? parentEntityType;
  final String? parentEntityId;

  final AuditActorType actorType;

  /// Set for a human actor; null for system and service actors, which name
  /// themselves through [actorIdentifier] instead.
  final String? actorUserId;
  final String? actorIdentifier;

  /// The actor's role at the time of the mutation, not now. A role can be
  /// changed or revoked afterwards; the trail records what was in force.
  final String? roleKey;

  final String source;

  /// Ties every record written by one action together.
  final String correlationId;
  final String? mutationId;

  /// The operator's own justification, where the mutation asked for one.
  final String? reason;

  /// Names only, sorted by the server. Empty means the event patched no
  /// fields, not that the names are unknown.
  final List<String> changedFields;
}

/// One keyset page of the trail, newest first.
class AuditEventPage {
  const AuditEventPage({required this.events, this.nextCursor});

  final List<AuditEventDto> events;

  /// Null when the server reported no further page. Never inferred from a
  /// short page: a full last page is indistinguishable from a truncated one
  /// without the server saying so.
  final AuditEventCursor? nextCursor;
}

/// Keyset position: the timestamp alone is not unique, so the id travels with
/// it and two events in the same millisecond cannot hide each other.
class AuditEventCursor {
  const AuditEventCursor({required this.occurredAt, required this.id});

  final DateTime occurredAt;
  final String id;
}
