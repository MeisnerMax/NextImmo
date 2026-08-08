import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/maintenance_capex/application/maintenance_capex_query_invalidation_source.dart';
import 'package:neximmo_app/features/maintenance_capex/data/supabase_maintenance_capex_query_invalidation_adapter.dart';

void main() {
  group('SupabaseMaintenanceCapexQueryInvalidationAdapter', () {
    test('maps the ready signal to a reconciliation', () async {
      final gateway = _FakeGateway(<MaintenanceCapexRealtimeEvent>[
        const MaintenanceCapexRealtimeEvent.ready(),
      ]);
      final adapter =
          SupabaseMaintenanceCapexQueryInvalidationAdapter.withGateway(
            gateway,
          );

      final event = await adapter
          .watchWorkspace(workspaceId: 'workspace-a')
          .first;

      expect(event.isReconciliation, isTrue);
      expect(event.workspaceId, 'workspace-a');
      expect(gateway.watchedWorkspaceId, 'workspace-a');
    });

    test('names the aggregate each of the two tables invalidates', () async {
      final gateway = _FakeGateway(<MaintenanceCapexRealtimeEvent>[
        _event(MaintenanceCapexAggregate.maintenanceTicket, 'ticket-a'),
        _event(MaintenanceCapexAggregate.capexProject, 'project-a'),
      ]);
      final adapter =
          SupabaseMaintenanceCapexQueryInvalidationAdapter.withGateway(
            gateway,
          );

      final events = await adapter
          .watchWorkspace(workspaceId: 'workspace-a')
          .toList();

      expect(events.map((event) => event.aggregate), <MaintenanceCapexAggregate>[
        MaintenanceCapexAggregate.maintenanceTicket,
        MaintenanceCapexAggregate.capexProject,
      ]);
      expect(events.map((event) => event.entityId), <String>[
        'ticket-a',
        'project-a',
      ]);
      expect(events.every((event) => event.isReconciliation), isFalse);
    });

    test('rejects a workspace mismatch', () async {
      final gateway = _FakeGateway(<MaintenanceCapexRealtimeEvent>[
        const MaintenanceCapexRealtimeEvent(
          aggregate: MaintenanceCapexAggregate.maintenanceTicket,
          record: <String, dynamic>{
            'id': 'ticket-a',
            'workspace_id': 'workspace-b',
          },
        ),
      ]);
      final adapter =
          SupabaseMaintenanceCapexQueryInvalidationAdapter.withGateway(
            gateway,
          );

      expect(
        adapter.watchWorkspace(workspaceId: 'workspace-a'),
        emitsError(isA<FormatException>()),
      );
    });

    test('rejects a record without an id', () async {
      final gateway = _FakeGateway(<MaintenanceCapexRealtimeEvent>[
        const MaintenanceCapexRealtimeEvent(
          aggregate: MaintenanceCapexAggregate.capexProject,
          record: <String, dynamic>{'workspace_id': 'workspace-a'},
        ),
      ]);
      final adapter =
          SupabaseMaintenanceCapexQueryInvalidationAdapter.withGateway(
            gateway,
          );

      expect(
        adapter.watchWorkspace(workspaceId: 'workspace-a'),
        emitsError(isA<FormatException>()),
      );
    });

    test('errors on an empty workspace id', () async {
      final adapter =
          SupabaseMaintenanceCapexQueryInvalidationAdapter.withGateway(
            _FakeGateway(const <MaintenanceCapexRealtimeEvent>[]),
          );

      expect(
        adapter.watchWorkspace(workspaceId: ''),
        emitsError(isA<FormatException>()),
      );
    });
  });
}

MaintenanceCapexRealtimeEvent _event(
  MaintenanceCapexAggregate aggregate,
  String id,
) {
  return MaintenanceCapexRealtimeEvent(
    aggregate: aggregate,
    record: <String, dynamic>{'id': id, 'workspace_id': 'workspace-a'},
  );
}

class _FakeGateway implements MaintenanceCapexRealtimeSupabaseGateway {
  _FakeGateway(this._events);

  final List<MaintenanceCapexRealtimeEvent> _events;
  String? watchedWorkspaceId;

  @override
  Stream<MaintenanceCapexRealtimeEvent> watchWorkspaceUpdates({
    required String workspaceId,
  }) {
    watchedWorkspaceId = workspaceId;
    return Stream<MaintenanceCapexRealtimeEvent>.fromIterable(_events);
  }
}
