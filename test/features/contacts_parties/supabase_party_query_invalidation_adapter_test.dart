import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/contacts_parties/data/supabase_party_query_invalidation_adapter.dart';

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
