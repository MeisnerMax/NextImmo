import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/data/supabase_valuation_query_invalidation_adapter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// REALTIME-RECONNECT-CONSISTENCY-01. Same defect as the property adapter,
// proven remotely there (REALTIME-STAGING-FIX-01): the reconciliation was
// latched to the first join, so a rejoin after a dropped socket recovered
// nothing that changed during the gap -- Realtime replays nothing. The latch
// lives in the real gateway, so this drives the actual channel callbacks
// instead of a fake gateway, which cannot see gateway-internal state.
void main() {
  group('SupabaseValuationRealtimeGateway', () {
    test('reconciles on every postgres_changes ok, rejoins included', () async {
      final client = SupabaseClient('http://127.0.0.1:1', 'test-key');
      final gateway = SupabaseValuationRealtimeGateway(client);
      final records = <Map<String, dynamic>>[];
      // The socket never reaches the dead URL; its failures are irrelevant
      // here and must not fail the test.
      final subscription = gateway
          .watchWorkspaceUpdates(workspaceId: 'workspace-a')
          .listen(records.add, onError: (Object _) {});
      addTearDown(() => unawaited(subscription.cancel()));

      final channel = await _awaitValuationChannel(client);
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
Future<RealtimeChannel> _awaitValuationChannel(SupabaseClient client) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    final channels = client.realtime.getChannels();
    if (channels.isNotEmpty) {
      return channels.first;
    }
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('The gateway never created a channel.');
}
