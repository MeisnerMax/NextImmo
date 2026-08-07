import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/documents_compliance/data/supabase_document_query_invalidation_adapter.dart';

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
