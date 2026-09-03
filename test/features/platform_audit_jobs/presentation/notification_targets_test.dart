import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/notification_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/platform_entity_type.dart';
import 'package:neximmo_app/features/platform_audit_jobs/presentation/notification_targets.dart';

NotificationDto _notification(PlatformEntityRef? entity) {
  return NotificationDto(
    id: 'note-a',
    workspaceId: 'workspace-a',
    recipientUserId: 'user-1',
    kind: 'task.assigned',
    title: 'Titel',
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    createdBy: 'user-2',
    updatedBy: 'user-2',
    version: 1,
    entity: entity,
  );
}

void main() {
  test('resolves the §9 table: a route or honestly nothing', () {
    expect(
      notificationTargetFor(
        _notification(
          const PlatformEntityRef(
            type: PlatformEntityType.property,
            id: 'property-1',
          ),
        ),
      )?.route,
      '/properties/property-1',
    );
    expect(
      notificationTargetFor(
        _notification(
          const PlatformEntityRef(type: PlatformEntityType.party, id: 'p-1'),
        ),
      )?.route,
      '/parties',
    );
    expect(
      notificationTargetFor(
        _notification(
          const PlatformEntityRef(
            type: PlatformEntityType.workspace,
            id: 'w-1',
          ),
        ),
      )?.route,
      '/tasks',
    );

    // NOTIFICATION-EMITTER-01: an emitted task event opens the task itself.
    final taskTarget = notificationTargetFor(
      _notification(
        const PlatformEntityRef(type: PlatformEntityType.task, id: 'task-1'),
      ),
    );
    expect(taskTarget?.route, '/tasks/task-1');
    expect(taskTarget?.label, 'Aufgabe öffnen');

    // The four property-scoped types need the parent propertyId
    // (TASK-QUERY-01); portfolio/scenario surfaces are not cloud-ready.
    for (final type in <PlatformEntityType>[
      PlatformEntityType.unit,
      PlatformEntityType.lease,
      PlatformEntityType.maintenanceTicket,
      PlatformEntityType.capexProject,
      PlatformEntityType.portfolio,
      PlatformEntityType.scenario,
    ]) {
      expect(
        notificationTargetFor(
          _notification(PlatformEntityRef(type: type, id: 'x-1')),
        ),
        isNull,
        reason: type.wireName,
      );
    }

    expect(notificationTargetFor(_notification(null)), isNull);
  });
}
