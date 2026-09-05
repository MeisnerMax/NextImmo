/// The application-facing activity event (PROPERTY-ACTIVITY-01).
///
/// Deliberately narrower than [AuditEventDto], and narrower in a different
/// direction. The audit trail answers "who changed which field of what, when
/// and why" for a caller holding `audit.read`. Activity answers "what happened
/// to this property" for a caller holding the domain's own read right, so it
/// carries no field names, no values and no `reason` — there is no field here
/// to put any of them in.
///
/// Actor identity works the same way. Every row states the actor *type* and
/// whether it was the reader themselves; the actor's user id is present only
/// when the server judged the caller already entitled to it, which today means
/// they hold `audit.read`. A surface therefore cannot name a colleague by
/// accident: without the entitlement there is nothing to name them with.
library;

import 'audit_event_dto.dart' show AuditActorType;

export 'audit_event_dto.dart' show AuditActorType;

/// The workspace domain an activity event belongs to. The server decides this
/// from the record's entity type, and the same value decides which permission
/// the row needed — the two cannot drift apart because they come from one
/// mapping.
enum PropertyActivityDomain {
  property,
  leasing,
  maintenance,
  capex,
  tasks,
  documents,
  valuation,
}

/// The domain a server key names, or null when this build does not know it.
///
/// Null rather than a fallback member: an unknown domain must be visible as
/// unknown. Bucketing it into `property` would file a stranger's event under
/// the property's own history.
PropertyActivityDomain? propertyActivityDomainFromWire(String value) {
  return switch (value) {
    'property' => PropertyActivityDomain.property,
    'leasing' => PropertyActivityDomain.leasing,
    'maintenance' => PropertyActivityDomain.maintenance,
    'capex' => PropertyActivityDomain.capex,
    'tasks' => PropertyActivityDomain.tasks,
    'documents' => PropertyActivityDomain.documents,
    'valuation' => PropertyActivityDomain.valuation,
    _ => null,
  };
}

String propertyActivityDomainToWire(PropertyActivityDomain domain) {
  return switch (domain) {
    PropertyActivityDomain.property => 'property',
    PropertyActivityDomain.leasing => 'leasing',
    PropertyActivityDomain.maintenance => 'maintenance',
    PropertyActivityDomain.capex => 'capex',
    PropertyActivityDomain.tasks => 'tasks',
    PropertyActivityDomain.documents => 'documents',
    PropertyActivityDomain.valuation => 'valuation',
  };
}

class PropertyActivityEventDto {
  const PropertyActivityEventDto({
    required this.id,
    required this.occurredAt,
    required this.eventKey,
    required this.entityType,
    required this.action,
    required this.actorType,
    required this.actorIsSelf,
    this.domain,
    this.domainKey,
    this.entityId,
    this.actorUserId,
  });

  final String id;
  final DateTime occurredAt;

  /// `entity_type.action`, e.g. `maintenance_ticket.transition`. The client
  /// renders a sentence from it and falls back to the key itself when it does
  /// not know one, so a new server event shows up rather than disappearing.
  final String eventKey;

  final String entityType;
  final String action;

  /// Null when the server named a domain this build does not know. The raw key
  /// stays in [domainKey] so the row can still be shown and labelled honestly.
  final PropertyActivityDomain? domain;

  /// The server's domain key, always present.
  final String? domainKey;

  /// The record the event is about, for a drilldown. Opening it still needs
  /// the domain's own permission — the reference is not an authorisation.
  final String? entityId;

  final AuditActorType actorType;

  /// Whether the reader made this change. Identity about oneself needs no
  /// approved visibility contract, so this is always present.
  final bool actorIsSelf;

  /// Present only when the server judged the caller entitled to it. Null means
  /// "not disclosed", never "no actor" — read [actorType] for that.
  final String? actorUserId;
}

/// One keyset page of the timeline, newest first, plus the coverage statement
/// that makes a partial timeline readable as one.
class PropertyActivityPage {
  const PropertyActivityPage({
    required this.events,
    required this.asOf,
    required this.visibleDomains,
    required this.actorNamesVisible,
    this.nextCursor,
    this.unknownDomainKeys = const <String>[],
  });

  final List<PropertyActivityEventDto> events;

  /// When the server produced the page. Shown, so the timeline states its
  /// freshness instead of implying live truth.
  final DateTime asOf;

  /// The domains this caller can see at all. A timeline covering four of seven
  /// domains says so; the server never reports how many events it withheld,
  /// because a count of records someone else may read is still a disclosure.
  final Set<PropertyActivityDomain> visibleDomains;

  /// Domain keys the server listed that this build does not know. Surfaced so
  /// a newer server is visible as "more than this app can label", not silently
  /// dropped from the coverage line.
  final List<String> unknownDomainKeys;

  /// Whether actor ids travel for this caller. False means the rows carry no
  /// names, not that the changes had no author.
  final bool actorNamesVisible;

  /// Null when the server reported no further page. Never inferred from a
  /// short page.
  final PropertyActivityCursor? nextCursor;
}

/// Keyset position: the timestamp alone is not unique, so the id travels with
/// it and two events in the same millisecond cannot hide each other.
class PropertyActivityCursor {
  const PropertyActivityCursor({required this.occurredAt, required this.id});

  final DateTime occurredAt;
  final String id;
}
