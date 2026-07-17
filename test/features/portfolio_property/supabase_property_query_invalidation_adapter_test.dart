import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_query_invalidation_source.dart';
import 'package:neximmo_app/features/portfolio_property/data/supabase_property_query_invalidation_adapter.dart';

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
