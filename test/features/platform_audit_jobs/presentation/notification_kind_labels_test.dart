import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/presentation/notification_kind_labels.dart';

void main() {
  test('maps the closed §7 catalog completely', () {
    const expected = <String, String>{
      'task.assigned': 'Aufgabe zugewiesen',
      'task.unassigned': 'Zuweisung entfernt',
      'task.blocked': 'Aufgabe blockiert',
      'task.done': 'Aufgabe erledigt',
      'task.due_soon': 'Aufgabe wird fällig',
      'task.overdue': 'Aufgabe überfällig',
      'task.digest.due': 'Fällige Aufgaben',
      'document.expiring': 'Dokument läuft ab',
      'maintenance.ticket_assigned': 'Ticket zugewiesen',
      'operations.signal_raised': 'Betriebshinweis',
    };
    expected.forEach((kind, label) {
      expect(notificationKindPresentation(kind).label, label, reason: kind);
      expect(isUnknownNotificationKind(kind), isFalse, reason: kind);
    });
  });

  test('an unknown kind falls back to "Hinweis" and never renders raw', () {
    final presentation = notificationKindPresentation('lease.expiring');
    expect(presentation.label, 'Hinweis');
    expect(presentation.label, isNot(contains('lease')));
    expect(isUnknownNotificationKind('lease.expiring'), isTrue);
  });
}
