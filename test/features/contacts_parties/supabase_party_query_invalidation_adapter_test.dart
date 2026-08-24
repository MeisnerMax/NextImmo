import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/contacts_parties/data/supabase_party_query_invalidation_adapter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SupabasePartyQueryInvalidationAdapter', () {
    test('maps an empty ready signal to a reconciliation', () async {
      final gateway = _FakePartyRealtimeGateway(<Map<String, dynamic>>[
        const <String, dynamic>{},
      ]);
      final adapter = SupabasePartyQueryInvalidationAdapter.withGateway(gateway);

      final event = await adapter
          .watchWorkspace(workspaceId: 'workspace-a')
          .first;

      expect(event.isReconciliation, isTrue);
      expect(event.workspaceId, 'workspace-a');
      expect(gateway.watchedWorkspaceId, 'workspace-a');
    });

    test('maps a party update to a scoped invalidation', () async {
      final gateway = _FakePartyRealtimeGateway(<Map<String, dynamic>>[
        <String, dynamic>{'id': 'party-a', 'workspace_id': 'workspace-a'},
      ]);
      final adapter = SupabasePartyQueryInvalidationAdapter.withGateway(gateway);

      final event = await adapter
          .watchWorkspace(workspaceId: 'workspace-a')
          .first;

      expect(event.isReconciliation, isFalse);
      expect(event.partyId, 'party-a');
      expect(event.workspaceId, 'workspace-a');
    });

    test('rejects a workspace mismatch', () async {
      final gateway = _FakePartyRealtimeGateway(<Map<String, dynamic>>[
        <String, dynamic>{'id': 'party-a', 'workspace_id': 'workspace-b'},
      ]);
      final adapter = SupabasePartyQueryInvalidationAdapter.withGateway(gateway);

      expect(
        adapter.watchWorkspace(workspaceId: 'workspace-a'),
        emitsError(isA<FormatException>()),
      );
    });

    test('errors on an empty workspace id', () async {
      final gateway = _FakePartyRealtimeGateway(<Map<String, dynamic>>[]);
      final adapter = SupabasePartyQueryInvalidationAdapter.withGateway(gateway);

      expect(
        adapter.watchWorkspace(workspaceId: ''),
        emitsError(isA<FormatException>()),
      );
    });
  });

  // REALTIME-RECONNECT-CONSISTENCY-01. The reconciliation latch lives in the
  // real gateway, so a fake gateway cannot see it -- this drives the actual
  // channel callbacks. A dropped socket rejoins and raises the
  // `postgres_changes` ok again; Realtime replays nothing across the gap, so
  // that rejoin's reconciliation is the only way a change the client missed
  // gets picked up. Proven remotely for the property adapter
  // (REALTIME-STAGING-FIX-01); this is the same defect.
  group('SupabasePartyRealtimeGateway', () {
    test('reconciles on every postgres_changes ok, rejoins included', () async {
      final client = SupabaseClient('http://127.0.0.1:1', 'test-key');
      final gateway = SupabasePartyRealtimeGateway(client);
      final records = <Map<String, dynamic>>[];
      // The socket never reaches the dead URL; its failures are irrelevant.
      final subscription = gateway
          .watchWorkspaceUpdates(workspaceId: 'workspace-a')
          .listen(records.add, onError: (Object _) {});
      addTearDown(() => unawaited(subscription.cancel()));

      final channel = await _awaitPartyChannel(client);
      channel.trigger('system', _okPayload); // first join
      channel.trigger('system', _okPayload); // rejoin after a reconnect
      await Future<void>.delayed(Duration.zero);

      expect(
        records.where((record) => record.isEmpty),
        hasLength(2),
        reason: 'a rejoin must reconcile again, not stay latched on the first',
      );
    });
  });
}

const _okPayload = <String, dynamic>{
  'extension': 'postgres_changes',
  'status': 'ok',
};

/// The gateway creates its channel after an awaited `setAuth`, so it exists a
/// turn or two after `listen`. Polling keeps this deterministic.
Future<RealtimeChannel> _awaitPartyChannel(SupabaseClient client) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    final channels = client.realtime.getChannels();
    if (channels.isNotEmpty) {
      return channels.first;
    }
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('The gateway never created a channel.');
}

class _FakePartyRealtimeGateway implements PartyRealtimeSupabaseGateway {
  _FakePartyRealtimeGateway(this._events);

  final List<Map<String, dynamic>> _events;
  String? watchedWorkspaceId;

  @override
  Stream<Map<String, dynamic>> watchWorkspaceUpdates({
    required String workspaceId,
  }) {
    watchedWorkspaceId = workspaceId;
    return Stream<Map<String, dynamic>>.fromIterable(_events);
  }
}
