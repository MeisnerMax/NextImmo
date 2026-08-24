import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/documents_compliance/data/supabase_document_query_invalidation_adapter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SupabaseDocumentQueryInvalidationAdapter', () {
    test('maps an empty ready signal to a reconciliation', () async {
      final gateway = _FakeDocumentRealtimeGateway(<Map<String, dynamic>>[
        const <String, dynamic>{},
      ]);
      final adapter = SupabaseDocumentQueryInvalidationAdapter.withGateway(
        gateway,
      );

      final event = await adapter
          .watchWorkspace(workspaceId: 'workspace-a')
          .first;

      expect(event.isReconciliation, isTrue);
      expect(event.workspaceId, 'workspace-a');
      expect(gateway.watchedWorkspaceId, 'workspace-a');
    });

    test('maps a document update to a scoped invalidation', () async {
      final gateway = _FakeDocumentRealtimeGateway(<Map<String, dynamic>>[
        <String, dynamic>{'id': 'document-a', 'workspace_id': 'workspace-a'},
      ]);
      final adapter = SupabaseDocumentQueryInvalidationAdapter.withGateway(
        gateway,
      );

      final event = await adapter
          .watchWorkspace(workspaceId: 'workspace-a')
          .first;

      expect(event.isReconciliation, isFalse);
      expect(event.documentId, 'document-a');
      expect(event.workspaceId, 'workspace-a');
    });

    test('coalesces a reconciliation followed by document updates', () async {
      final gateway = _FakeDocumentRealtimeGateway(<Map<String, dynamic>>[
        const <String, dynamic>{},
        <String, dynamic>{'id': 'document-a', 'workspace_id': 'workspace-a'},
        <String, dynamic>{'id': 'document-b', 'workspace_id': 'workspace-a'},
      ]);
      final adapter = SupabaseDocumentQueryInvalidationAdapter.withGateway(
        gateway,
      );

      final events = await adapter
          .watchWorkspace(workspaceId: 'workspace-a')
          .toList();

      expect(events, hasLength(3));
      expect(events.first.isReconciliation, isTrue);
      expect(
        events.skip(1).map((event) => event.documentId),
        <String>['document-a', 'document-b'],
      );
    });

    test('rejects a workspace mismatch', () async {
      final gateway = _FakeDocumentRealtimeGateway(<Map<String, dynamic>>[
        <String, dynamic>{'id': 'document-a', 'workspace_id': 'workspace-b'},
      ]);
      final adapter = SupabaseDocumentQueryInvalidationAdapter.withGateway(
        gateway,
      );

      expect(
        adapter.watchWorkspace(workspaceId: 'workspace-a'),
        emitsError(isA<FormatException>()),
      );
    });

    test('rejects an event without a document id', () async {
      final gateway = _FakeDocumentRealtimeGateway(<Map<String, dynamic>>[
        <String, dynamic>{'workspace_id': 'workspace-a'},
      ]);
      final adapter = SupabaseDocumentQueryInvalidationAdapter.withGateway(
        gateway,
      );

      expect(
        adapter.watchWorkspace(workspaceId: 'workspace-a'),
        emitsError(isA<FormatException>()),
      );
    });

    test('errors on an empty workspace id', () async {
      final gateway = _FakeDocumentRealtimeGateway(<Map<String, dynamic>>[]);
      final adapter = SupabaseDocumentQueryInvalidationAdapter.withGateway(
        gateway,
      );

      expect(
        adapter.watchWorkspace(workspaceId: ''),
        emitsError(isA<FormatException>()),
      );
    });
  });

  // REALTIME-RECONNECT-CONSISTENCY-01. Same defect as the property adapter,
  // proven remotely there (REALTIME-STAGING-FIX-01): the reconciliation was
  // latched to the first join, so a rejoin after a dropped socket recovered
  // nothing. The latch lives in the real gateway, so this drives the actual
  // channel callbacks rather than a fake gateway.
  group('SupabaseDocumentRealtimeGateway', () {
    test('reconciles on every postgres_changes ok, rejoins included', () async {
      final client = SupabaseClient('http://127.0.0.1:1', 'test-key');
      final gateway = SupabaseDocumentRealtimeGateway(client);
      final records = <Map<String, dynamic>>[];
      final subscription = gateway
          .watchWorkspaceUpdates(workspaceId: 'workspace-a')
          .listen(records.add, onError: (Object _) {});
      addTearDown(() => unawaited(subscription.cancel()));

      final channel = await _awaitDocumentChannel(client);
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

Future<RealtimeChannel> _awaitDocumentChannel(SupabaseClient client) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    final channels = client.realtime.getChannels();
    if (channels.isNotEmpty) {
      return channels.first;
    }
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('The gateway never created a channel.');
}

class _FakeDocumentRealtimeGateway
    implements DocumentRealtimeSupabaseGateway {
  _FakeDocumentRealtimeGateway(this._events);

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
