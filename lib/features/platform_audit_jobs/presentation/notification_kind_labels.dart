/// The closed §7 kind catalog of the Notification Inbox (OD-N6): wire kind →
/// German label + icon. All V1 kinds are emitter-less today (B10–B13); the
/// mapping exists so administratively created or migrated rows render
/// correctly. A kind is **never shown raw**: unknown values fall back to
/// "Hinweis" with the raw wire value available for a tooltip only.
library;

import 'package:flutter/material.dart';

class NotificationKindPresentation {
  const NotificationKindPresentation({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;
}

const NotificationKindPresentation _fallback = NotificationKindPresentation(
  label: 'Hinweis',
  icon: Icons.notifications_none,
);

const Map<String, NotificationKindPresentation> _catalog =
    <String, NotificationKindPresentation>{
      'task.assigned': NotificationKindPresentation(
        label: 'Aufgabe zugewiesen',
        icon: Icons.assignment_ind_outlined,
      ),
      'task.unassigned': NotificationKindPresentation(
        label: 'Zuweisung entfernt',
        icon: Icons.assignment_late_outlined,
      ),
      'task.blocked': NotificationKindPresentation(
        label: 'Aufgabe blockiert',
        icon: Icons.block_outlined,
      ),
      'task.done': NotificationKindPresentation(
        label: 'Aufgabe erledigt',
        icon: Icons.check_circle_outline,
      ),
      'task.due_soon': NotificationKindPresentation(
        label: 'Aufgabe wird fällig',
        icon: Icons.schedule_outlined,
      ),
      'task.overdue': NotificationKindPresentation(
        label: 'Aufgabe überfällig',
        icon: Icons.error_outline,
      ),
      'task.digest.due': NotificationKindPresentation(
        label: 'Fällige Aufgaben',
        icon: Icons.summarize_outlined,
      ),
      'document.expiring': NotificationKindPresentation(
        label: 'Dokument läuft ab',
        icon: Icons.description_outlined,
      ),
      'maintenance.ticket_assigned': NotificationKindPresentation(
        label: 'Ticket zugewiesen',
        icon: Icons.build_outlined,
      ),
      'operations.signal_raised': NotificationKindPresentation(
        label: 'Betriebshinweis',
        icon: Icons.warning_amber_outlined,
      ),
    };

/// Never null and never the raw wire value — unknown kinds render as the
/// generic fallback (§7).
NotificationKindPresentation notificationKindPresentation(String kind) {
  return _catalog[kind] ?? _fallback;
}

/// True when [kind] is outside the closed catalog — the raw value then goes
/// into a tooltip, nowhere else.
bool isUnknownNotificationKind(String kind) => !_catalog.containsKey(kind);
