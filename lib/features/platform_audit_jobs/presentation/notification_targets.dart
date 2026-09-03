/// Deep-link resolution of the Notification Inbox (§9, A13): the entity pair
/// of a notification either resolves to an in-shell route or it does not —
/// and an unresolvable target renders a **disabled** "Öffnen" with a tooltip,
/// never a raw id and never a dead click.
///
/// The four ⚠️ rows of §9 (unit, lease, maintenance ticket, CapEx project)
/// stay unresolvable until `TASK-QUERY-01` delivers the parent-property
/// resolution; portfolio and scenario wait for their surfaces (P2-D09,
/// scenario contract). That gap is stated by the tooltip, not papered over.
library;

import '../../../ui/navigation/app_navigation.dart';
import '../domain/notification_dto.dart';
import '../domain/platform_entity_type.dart';

class NotificationTarget {
  const NotificationTarget({required this.route, required this.label});

  /// A route `cloudRouteTargetFromName` resolves — the same deep-link
  /// vocabulary A15 registered.
  final String route;

  /// German label of the jump ("Zum Vorgang öffnen" context).
  final String label;
}

/// Null when the target cannot be addressed today (§9 table).
NotificationTarget? notificationTargetFor(NotificationDto notification) {
  final entity = notification.entity;
  if (entity == null) {
    return null;
  }
  return switch (entity.type) {
    PlatformEntityType.property => NotificationTarget(
      route: referencePropertyRoute(entity.id),
      label: 'Objekt öffnen',
    ),
    PlatformEntityType.party => const NotificationTarget(
      route: partiesRoute,
      label: 'Parteien öffnen',
    ),
    // §9: a workspace-typed context carries a bundled digest; its place to
    // act is the Task Center.
    PlatformEntityType.workspace => const NotificationTarget(
      route: tasksRoute,
      label: 'Aufgaben öffnen',
    ),
    // Property-scoped routes need the parent propertyId the notification
    // does not carry (TASK-QUERY-01); portfolio/scenario surfaces are not
    // cloud-ready.
    // NOTIFICATION-EMITTER-01: an emitted task event addresses the task it
    // reports on.
    PlatformEntityType.task => NotificationTarget(
      route: taskRouteFor(entity.id),
      label: 'Aufgabe öffnen',
    ),
    PlatformEntityType.unit ||
    PlatformEntityType.lease ||
    PlatformEntityType.maintenanceTicket ||
    PlatformEntityType.capexProject ||
    PlatformEntityType.portfolio ||
    PlatformEntityType.scenario => null,
  };
}
