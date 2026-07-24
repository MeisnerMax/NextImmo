import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_domain_event.dart';
import 'package:neximmo_app/features/platform_audit_jobs/data/supabase_outbox_adapter.dart';

void main() {
  group('SupabaseOutboxAdapter', () {
    late _FakeOutboxGateway gateway;
    late SupabaseOutboxAdapter outbox;

    setUp(() {
      gateway = _FakeOutboxGateway();
      outbox = SupabaseOutboxAdapter.withGateway(gateway);
    });

    test('reads a permission-scoped page oldest first', () async {
      gateway.rows = <Map<String, dynamic>>[
        _outboxRow(id: 'event-1', occurredAt: '2026-07-24T10:00:00.000Z'),
        _outboxRow(id: 'event-2', occurredAt: '2026-07-24T11:00:00.000Z'),
      ];

      final page = await outbox.read(
        const OutboxQuery(
          workspaceId: 'workspace-a',
          requiredPermission: 'task.read',
        ),
      );

      expect(gateway.requiredPermission, 'task.read');
      expect(gateway.limit, 101); // limit + 1 has-next probe.
      expect(page.events.map((event) => event.eventId), <String>[
        'event-1',
        'event-2',
      ]);
      expect(page.nextCursor, isNull);
    });

    test('resumes on the composite cursor, not the timestamp alone', () async {
      gateway.rows = <Map<String, dynamic>>[
        _outboxRow(id: 'event-1', occurredAt: '2026-07-24T10:00:00.000Z'),
        _outboxRow(id: 'event-2', occurredAt: '2026-07-24T10:00:00.000Z'),
      ];

      final first = await outbox.read(
        const OutboxQuery(
          workspaceId: 'workspace-a',
          requiredPermission: 'task.read',
          limit: 1,
        ),
      );

      // Both envelopes share `occurred_at` because one transaction wrote them;
      // only the id tie-break can resume such a page.
      expect(first.nextCursor!.eventId, 'event-1');
      expect(
        first.nextCursor!.occurredAt.toUtc().toIso8601String(),
        '2026-07-24T10:00:00.000Z',
      );

      await outbox.read(
        OutboxQuery(
          workspaceId: 'workspace-a',
          requiredPermission: 'task.read',
          after: first.nextCursor,
          limit: 1,
        ),
      );

      expect(gateway.after!.eventId, 'event-1');
    });

    test('rejects an envelope from a foreign workspace', () async {
      gateway.rows = <Map<String, dynamic>>[
        _outboxRow(id: 'event-1', workspaceId: 'workspace-b'),
      ];

      await expectLater(
        outbox.read(
          const OutboxQuery(
            workspaceId: 'workspace-a',
            requiredPermission: 'task.read',
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('carries a batch envelope that names no aggregate row', () async {
      gateway.rows = <Map<String, dynamic>>[
        _outboxRow(
          id: 'event-1',
          eventType: 'notification.fanned_out',
          aggregateType: 'notification_batch',
          aggregateId: null,
          aggregateVersion: null,
        ),
      ];

      final page = await outbox.read(
        const OutboxQuery(
          workspaceId: 'workspace-a',
          requiredPermission: 'notification.read',
        ),
      );

      final envelope = page.events.single;
      expect(envelope.aggregateId, isNull);
      expect(envelope.aggregateVersion, isNull);
      expect(envelope.aggregateType, 'notification_batch');
    });
  });
}

Map<String, dynamic> _outboxRow({
  required String id,
  String workspaceId = 'workspace-a',
  String occurredAt = '2026-07-24T10:00:00.000Z',
  String eventType = 'task.status_changed',
  String aggregateType = 'task',
  String? aggregateId = 'task-a',
  int? aggregateVersion = 4,
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'event_type': eventType,
    'schema_version': 1,
    'aggregate_type': aggregateType,
    'aggregate_id': aggregateId,
    'aggregate_version': aggregateVersion,
    'required_permission': 'task.read',
    'occurred_at': occurredAt,
    'actor_id': 'user-1',
    'correlation_id': 'correlation-1',
    'payload': <String, Object?>{'to': 'done'},
  };
}

class _FakeOutboxGateway implements OutboxSupabaseGateway {
  List<Map<String, dynamic>> rows = const <Map<String, dynamic>>[];
  String? requiredPermission;
  OutboxCursor? after;
  int? limit;

  @override
  Future<List<Map<String, dynamic>>> listEvents({
    required String workspaceId,
    required String requiredPermission,
    required OutboxCursor? after,
    required int limit,
  }) async {
    this.requiredPermission = requiredPermission;
    this.after = after;
    this.limit = limit;
    return rows;
  }
}
