/// The controlled entity registry the platform aggregates link against
/// (P2-D04, DOM-010).
///
/// The server-side column type is `public.document_link_entity_type`: the
/// P2-D04 migrations deliberately reuse the P2-D03 registry rather than
/// introducing a parallel enum, because its values already *are* the workflow
/// entities a task, a notification or a search entry attaches to. The name is
/// document-flavoured; the reuse is intentional and documented in
/// `20260723130000_p2_d04_tasks_notifications.sql`.
///
/// This Dart enum mirrors that registry verbatim instead of importing
/// `DocumentLinkEntityType` from the documents_compliance feature: a migrated
/// vertical must not depend on another migrated vertical's domain layer. The
/// duplication is guarded — `test/features/platform_audit_jobs/
/// platform_entity_type_parity_test.dart` fails if the two wire vocabularies
/// ever drift apart.
library;

enum PlatformEntityType {
  workspace('workspace'),
  property('property'),
  portfolio('portfolio'),
  unit('unit'),
  lease('lease'),
  party('party'),
  maintenanceTicket('maintenance_ticket'),
  capexProject('capex_project'),
  scenario('scenario'),

  /// NOTIFICATION-EMITTER-01: the registry's task value. Notifications
  /// address the task they report on (`/tasks/:id`); a task never LINKS a
  /// task (server constraint `tasks_entity_not_task_check`), so task dialogs
  /// must not offer it as a context.
  task('task');

  const PlatformEntityType(this.wireName);

  final String wireName;

  static PlatformEntityType? fromWire(String? value) {
    for (final type in PlatformEntityType.values) {
      if (type.wireName == value) return type;
    }
    return null;
  }
}

/// A workspace-scoped reference to one workflow entity. Both halves move
/// together — the server enforces `(entity_type is null) = (entity_id is null)`
/// on every table that carries an optional link.
class PlatformEntityRef {
  const PlatformEntityRef({required this.type, required this.id});

  final PlatformEntityType type;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is PlatformEntityRef && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);

  @override
  String toString() => '${type.wireName}:$id';
}
