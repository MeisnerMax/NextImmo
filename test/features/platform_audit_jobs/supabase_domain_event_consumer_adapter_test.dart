import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_query_invalidation_source.dart';
import 'package:neximmo_app/features/platform_audit_jobs/data/supabase_domain_event_consumer_adapter.dart';

void main() {
  group('SupabaseDomainEventConsumerAdapter', () {
    late _FakeDomainEventGateway gateway;

    setUp(() => gateway = _FakeDomainEventGateway());

    test('subscribes to the permission-scoped topic', () async {
      final consumer = SupabaseDomainEventConsumerAdapter.withGateway(gateway);

      final events = consumer.watch(
        workspaceId: 'workspace-a',
        requiredPermission: platformTaskEventPermission,
      );
      final received = events.take(1).toList();
      gateway.emit(platformTaskEventPermission, _envelopeJson());

      await received;
      expect(gateway.subscribedPermissions, <String>['task.read']);
      expect(gateway.subscribedWorkspaceIds, <String>['workspace-a']);
    });

    test('parses a broadcast envelope into the CTR-005 fields', () async {
      final consumer = SupabaseDomainEventConsumerAdapter.withGateway(gateway);
      final received = consumer
          .watch(
            workspaceId: 'workspace-a',
            requiredPermission: platformTaskEventPermission,
          )
          .take(1)
          .toList();

      gateway.emit(platformTaskEventPermission, _envelopeJson());

      final envelope = (await received).single;
      expect(envelope.eventId, 'event-1');
      expect(envelope.eventType, 'task.status_changed');
      expect(envelope.aggregateType, 'task');
      expect(envelope.aggregateId, 'task-a');
      expect(envelope.aggregateVersion, 4);
      expect(envelope.payload['to'], 'done');
    });

    test('drops the subscription-ready marker', () async {
      final consumer = SupabaseDomainEventConsumerAdapter.withGateway(gateway);
      final received = consumer
          .watch(
            workspaceId: 'workspace-a',
            requiredPermission: platformTaskEventPermission,
          )
          .take(1)
          .toList();

      // Transport fact, not an envelope: it must not become a synthetic event.
      gateway.emit(platformTaskEventPermission, const <String, dynamic>{});
      gateway.emit(platformTaskEventPermission, _envelopeJson());

      expect((await received).single.eventId, 'event-1');
    });

    test('rejects an envelope from a foreign workspace', () async {
      final consumer = SupabaseDomainEventConsumerAdapter.withGateway(gateway);
      final received = consumer
          .watch(
            workspaceId: 'workspace-a',
            requiredPermission: platformTaskEventPermission,
          )
          .first;

      gateway.emit(
        platformTaskEventPermission,
        _envelopeJson(workspaceId: 'workspace-b'),
      );

      await expectLater(received, throwsA(isA<FormatException>()));
    });

    test('parses an outbox row, whose id key differs from the broadcast', () {
      final envelope = parseDomainEventEnvelope(<String, dynamic>{
        ..._envelopeJson(),
        'id': 'event-1',
      }..remove('event_id'));

      expect(envelope.eventId, 'event-1');
    });
  });

  group('SupabasePlatformQueryInvalidationAdapter', () {
    late _FakeDomainEventGateway gateway;
    late SupabasePlatformQueryInvalidationAdapter source;

    setUp(() {
      gateway = _FakeDomainEventGateway();
      source = SupabasePlatformQueryInvalidationAdapter.withGateway(gateway);
    });

    test('subscribes to all three platform topics', () async {
      final stream = source.watchWorkspace(workspaceId: 'workspace-a');
      final subscription = stream.listen((_) {});
      await Future<void>.delayed(Duration.zero);

      expect(gateway.subscribedPermissions, <String>[
        'task.read',
        'notification.read',
        'import.read',
      ]);
      await subscription.cancel();
    });

    test('maps each aggregate onto its invalidation', () async {
      final received = source
          .watchWorkspace(workspaceId: 'workspace-a')
          .take(3)
          .toList();
      await Future<void>.delayed(Duration.zero);

      gateway.emit(platformTaskEventPermission, _envelopeJson());
      gateway.emit(
        platformImportEventPermission,
        _envelopeJson(
          eventType: 'import_job.status_changed',
          aggregateType: 'import_job',
          aggregateId: 'job-a',
        ),
      );
      gateway.emit(
        platformNotificationEventPermission,
        _envelopeJson(
          eventType: 'notification.fanned_out',
          aggregateType: 'notification_batch',
          aggregateId: null,
        ),
      );

      final invalidations = await received;
      expect(invalidations[0].aggregate, PlatformAggregate.task);
      expect(invalidations[0].aggregateId, 'task-a');
      expect(invalidations[0].eventType, 'task.status_changed');
      expect(invalidations[1].aggregate, PlatformAggregate.importJob);
      expect(invalidations[2].aggregate, PlatformAggregate.notification);
      // The fan-out envelope deliberately names no recipient and no row, so the
      // invalidation is workspace-wide and the reader refetches its own feed.
      expect(invalidations[2].aggregateId, isNull);
      expect(invalidations[2].isReconciliation, isFalse);
    });

    test('emits a reconciliation signal when a topic connects', () async {
      final received = source
          .watchWorkspace(workspaceId: 'workspace-a')
          .take(1)
          .toList();
      await Future<void>.delayed(Duration.zero);

      gateway.emit(platformTaskEventPermission, const <String, dynamic>{});

      final invalidation = (await received).single;
      expect(invalidation.isReconciliation, isTrue);
      expect(invalidation.aggregate, isNull);
      expect(invalidation.workspaceId, 'workspace-a');
    });

    test('skips an envelope from a domain that shares the topic', () async {
      final received = source
          .watchWorkspace(workspaceId: 'workspace-a')
          .take(1)
          .toList();
      await Future<void>.delayed(Duration.zero);

      // A future aggregate publishing on task.read must not break this
      // consumer, so an unknown aggregate type is skipped rather than thrown.
      gateway.emit(
        platformTaskEventPermission,
        _envelopeJson(eventType: 'document.linked', aggregateType: 'document'),
      );
      gateway.emit(platformTaskEventPermission, _envelopeJson());

      expect((await received).single.aggregate, PlatformAggregate.task);
    });

    test('tolerates one denied topic and keeps the others alive', () async {
      final received = source
          .watchWorkspace(workspaceId: 'workspace-a')
          .take(1)
          .toList();
      await Future<void>.delayed(Duration.zero);

      // Holding only a subset of the three permissions is the normal case.
      gateway.fail(platformImportEventPermission, StateError('denied'));
      gateway.emit(platformTaskEventPermission, _envelopeJson());

      expect((await received).single.aggregate, PlatformAggregate.task);
    });

    test('surfaces an error only when every topic fails', () async {
      final received = source.watchWorkspace(workspaceId: 'workspace-a').first;
      await Future<void>.delayed(Duration.zero);

      gateway.fail(platformTaskEventPermission, StateError('down'));
      gateway.fail(platformNotificationEventPermission, StateError('down'));
      gateway.fail(platformImportEventPermission, StateError('down'));

      await expectLater(received, throwsA(isA<StateError>()));
    });

    test('rejects an empty workspace id', () async {
      await expectLater(
        source.watchWorkspace(workspaceId: '').first,
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Map<String, dynamic> _envelopeJson({
  String workspaceId = 'workspace-a',
  String eventType = 'task.status_changed',
  String aggregateType = 'task',
  String? aggregateId = 'task-a',
}) {
  return <String, dynamic>{
    'event_id': 'event-1',
    'event_type': eventType,
    'schema_version': 1,
    'workspace_id': workspaceId,
    'aggregate_type': aggregateType,
    'aggregate_id': aggregateId,
    'aggregate_version': 4,
    'occurred_at': '2026-07-24T10:00:00.000Z',
    'actor_id': 'user-1',
    'correlation_id': 'correlation-1',
    'payload': <String, Object?>{'from': 'in_progress', 'to': 'done'},
  };
}

class _FakeDomainEventGateway implements DomainEventRealtimeSupabaseGateway {
  final List<String> subscribedPermissions = <String>[];
  final List<String> subscribedWorkspaceIds = <String>[];
  final Map<String, StreamController<Map<String, dynamic>>> _controllers =
      <String, StreamController<Map<String, dynamic>>>{};

  @override
  Stream<Map<String, dynamic>> watchTopic({
    required String workspaceId,
    required String requiredPermission,
  }) {
    subscribedPermissions.add(requiredPermission);
    subscribedWorkspaceIds.add(workspaceId);
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    _controllers[requiredPermission] = controller;
    return controller.stream;
  }

  void emit(String permission, Map<String, dynamic> record) {
    _controllers[permission]!.add(record);
  }

  void fail(String permission, Object error) {
    _controllers[permission]!.addError(error);
  }
}
