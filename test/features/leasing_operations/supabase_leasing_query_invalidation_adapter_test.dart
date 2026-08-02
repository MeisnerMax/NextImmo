import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_query_invalidation_source.dart';
import 'package:neximmo_app/features/leasing_operations/data/supabase_leasing_query_invalidation_adapter.dart';

void main() {
  group('SupabaseLeasingQueryInvalidationAdapter', () {
    test('maps the ready signal to a reconciliation', () async {
      final gateway = _FakeLeasingRealtimeGateway(<LeasingRealtimeEvent>[
        const LeasingRealtimeEvent.ready(),
      ]);
      final adapter = SupabaseLeasingQueryInvalidationAdapter.withGateway(
        gateway,
      );

      final event = await adapter
          .watchWorkspace(workspaceId: 'workspace-a')
          .first;

      expect(event.isReconciliation, isTrue);
      expect(event.workspaceId, 'workspace-a');
      expect(gateway.watchedWorkspaceId, 'workspace-a');
    });

    test('names the aggregate each of the four tables invalidates', () async {
      final gateway = _FakeLeasingRealtimeGateway(<LeasingRealtimeEvent>[
        _event(LeasingAggregate.unit, 'unit-a'),
        _event(LeasingAggregate.lease, 'lease-a'),
        _event(LeasingAggregate.leasingCase, 'case-a'),
        _event(LeasingAggregate.rentRollSnapshot, 'snapshot-a'),
      ]);
      final adapter = SupabaseLeasingQueryInvalidationAdapter.withGateway(
        gateway,
      );

      final events = await adapter
          .watchWorkspace(workspaceId: 'workspace-a')
          .toList();

      expect(events.map((event) => event.aggregate), <LeasingAggregate>[
        LeasingAggregate.unit,
        LeasingAggregate.lease,
        LeasingAggregate.leasingCase,
        LeasingAggregate.rentRollSnapshot,
      ]);
      expect(events.map((event) => event.entityId), <String>[
        'unit-a',
        'lease-a',
        'case-a',
        'snapshot-a',
      ]);
      expect(events.every((event) => event.isReconciliation), isFalse);
    });

    test(
      'emits both events of one lease activation so neither list goes stale',
      () async {
        // transition_lease_status writes the lease and, through
        // sync_unit_occupancy, its unit. The migration publishes both tables on
        // purpose; the adapter must not swallow either half.
        final gateway = _FakeLeasingRealtimeGateway(<LeasingRealtimeEvent>[
          _event(LeasingAggregate.lease, 'lease-a'),
          _event(LeasingAggregate.unit, 'unit-a'),
        ]);
        final adapter = SupabaseLeasingQueryInvalidationAdapter.withGateway(
          gateway,
        );

        final events = await adapter
            .watchWorkspace(workspaceId: 'workspace-a')
            .toList();

        expect(events, hasLength(2));
        expect(events.map((event) => event.aggregate), <LeasingAggregate>[
          LeasingAggregate.lease,
          LeasingAggregate.unit,
        ]);
      },
    );

    test('rejects a workspace mismatch', () async {
      final gateway = _FakeLeasingRealtimeGateway(<LeasingRealtimeEvent>[
        const LeasingRealtimeEvent(
          aggregate: LeasingAggregate.unit,
          record: <String, dynamic>{
            'id': 'unit-a',
            'workspace_id': 'workspace-b',
          },
        ),
      ]);
      final adapter = SupabaseLeasingQueryInvalidationAdapter.withGateway(
        gateway,
      );

      expect(
        adapter.watchWorkspace(workspaceId: 'workspace-a'),
        emitsError(isA<FormatException>()),
      );
    });

    test('rejects a record without an id', () async {
      final gateway = _FakeLeasingRealtimeGateway(<LeasingRealtimeEvent>[
        const LeasingRealtimeEvent(
          aggregate: LeasingAggregate.lease,
          record: <String, dynamic>{'workspace_id': 'workspace-a'},
        ),
      ]);
      final adapter = SupabaseLeasingQueryInvalidationAdapter.withGateway(
        gateway,
      );

      expect(
        adapter.watchWorkspace(workspaceId: 'workspace-a'),
        emitsError(isA<FormatException>()),
      );
    });

    test('errors on an empty workspace id', () async {
      final adapter = SupabaseLeasingQueryInvalidationAdapter.withGateway(
        _FakeLeasingRealtimeGateway(const <LeasingRealtimeEvent>[]),
      );

      expect(
        adapter.watchWorkspace(workspaceId: ''),
        emitsError(isA<FormatException>()),
      );
    });
  });
}

LeasingRealtimeEvent _event(LeasingAggregate aggregate, String id) {
  return LeasingRealtimeEvent(
    aggregate: aggregate,
    record: <String, dynamic>{'id': id, 'workspace_id': 'workspace-a'},
  );
}

class _FakeLeasingRealtimeGateway implements LeasingRealtimeSupabaseGateway {
  _FakeLeasingRealtimeGateway(this._events);

  final List<LeasingRealtimeEvent> _events;
  String? watchedWorkspaceId;

  @override
  Stream<LeasingRealtimeEvent> watchWorkspaceUpdates({
    required String workspaceId,
  }) {
    watchedWorkspaceId = workspaceId;
    return Stream<LeasingRealtimeEvent>.fromIterable(_events);
  }
}
