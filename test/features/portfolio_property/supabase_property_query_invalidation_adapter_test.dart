import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_query_invalidation_source.dart';
import 'package:neximmo_app/features/portfolio_property/data/supabase_property_query_invalidation_adapter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SupabasePropertyQueryInvalidationAdapter', () {
    test('maps subscription readiness and scoped property updates', () async {
      final gateway = _FakeRealtimeGateway();
      final adapter = SupabasePropertyQueryInvalidationAdapter.withGateway(
        gateway,
      );
      final events = <PropertyQueryInvalidation>[];
      final subscription = adapter
          .watchWorkspace(workspaceId: 'workspace-a')
          .listen(events.add);

      gateway.emit(const <String, dynamic>{});
      gateway.emit(<String, dynamic>{
        'id': 'property-a',
        'workspace_id': 'workspace-a',
      });
      await _flushEvents();

      expect(gateway.workspaceIds, <String>['workspace-a']);
      expect(events, hasLength(2));
      expect(events[0].isReconciliation, isTrue);
      expect(events[1].propertyId, 'property-a');

      await subscription.cancel();
      expect(gateway.cancelCalls, 1);
    });

    test('fails closed for a foreign workspace payload', () async {
      final gateway = _FakeRealtimeGateway();
      final adapter = SupabasePropertyQueryInvalidationAdapter.withGateway(
        gateway,
      );
      final error = Completer<Object>();
      final subscription = adapter
          .watchWorkspace(workspaceId: 'workspace-a')
          .listen((_) {}, onError: (Object value) => error.complete(value));

      gateway.emit(<String, dynamic>{
        'id': 'property-b',
        'workspace_id': 'workspace-b',
      });

      expect(await error.future, isA<FormatException>());
      await subscription.cancel();
    });
  });

  // REALTIME-STAGING-FIX-01. The reconciliation latch lives in the real
  // gateway, not in the adapter, so a fake gateway cannot see this defect --
  // these drive the actual channel callbacks instead. A socket that drops and
  // reconnects rejoins and gets a second `postgres_changes` ok; Realtime
  // replays nothing across the gap, so that rejoin's reconciliation is the
  // only thing that can recover a change the client was disconnected for.
  // Measured on staging: seven reconnects in four minutes on a mobile client.
  group('SupabasePropertyRealtimeGateway', () {
    test('reconciles on every postgres_changes ok, rejoins included', () async {
      final client = SupabaseClient(_deadUrl, _anyKey);
      final gateway = SupabasePropertyRealtimeGateway(client);
      final records = <Map<String, dynamic>>[];
      // The socket never reaches the dead URL; its failures are irrelevant
      // here and must not fail the test.
      final subscription = gateway
          .watchWorkspaceUpdates(workspaceId: 'workspace-a')
          .listen(records.add, onError: (Object _) {});
      addTearDown(() => unawaited(subscription.cancel()));

      final channel = await _awaitChannel(client);
      channel.trigger('system', _postgresChangesOk); // first join
      channel.trigger('system', _postgresChangesOk); // rejoin after reconnect
      await _flushEvents();

      expect(
        records.where((record) => record.isEmpty),
        hasLength(2),
        reason: 'a rejoin must reconcile again, not stay latched on the first',
      );
    });

    test('surfaces a failed replication as a stream error', () async {
      final client = SupabaseClient(_deadUrl, _anyKey);
      final gateway = SupabasePropertyRealtimeGateway(client);
      final errors = <Object>[];
      final records = <Map<String, dynamic>>[];
      final subscription = gateway
          .watchWorkspaceUpdates(workspaceId: 'workspace-a')
          .listen(records.add, onError: errors.add);
      addTearDown(() => unawaited(subscription.cancel()));

      final channel = await _awaitChannel(client);
      channel.trigger('system', <String, dynamic>{
        'extension': 'postgres_changes',
        'status': 'error',
        'message': 'replication down',
      });
      // A system event of another extension is none of this stream's business.
      channel.trigger('system', <String, dynamic>{
        'extension': 'presence',
        'status': 'ok',
      });
      await _flushEvents();

      // The SDK also reports the failed extension through the subscribe
      // callback, so more than one error is expected; what matters is that the
      // replication failure surfaces and that no reconciliation is faked.
      expect(errors, isNotEmpty);
      expect(
        errors.first.toString(),
        contains('replication down'),
      );
      expect(records, isEmpty);
    });
  });
}

const _deadUrl = 'http://127.0.0.1:1';
const _anyKey = 'test-publishable-key';
const _postgresChangesOk = <String, dynamic>{
  'extension': 'postgres_changes',
  'status': 'ok',
};

/// The gateway creates its channel after an awaited `setAuth`, so the channel
/// exists a turn or two after `listen`. Polling keeps this deterministic
/// without pinning a sleep.
Future<RealtimeChannel> _awaitChannel(SupabaseClient client) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    final channels = client.realtime.getChannels();
    if (channels.isNotEmpty) {
      return channels.first;
    }
    await _flushEvents();
  }
  throw StateError('The gateway never created a channel.');
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

class _FakeRealtimeGateway implements PropertyRealtimeSupabaseGateway {
  late final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>(onCancel: () => cancelCalls++);
  final List<String> workspaceIds = <String>[];
  int cancelCalls = 0;

  @override
  Stream<Map<String, dynamic>> watchWorkspaceUpdates({
    required String workspaceId,
  }) {
    workspaceIds.add(workspaceId);
    return _controller.stream;
  }

  void emit(Map<String, dynamic> record) => _controller.add(record);
}
