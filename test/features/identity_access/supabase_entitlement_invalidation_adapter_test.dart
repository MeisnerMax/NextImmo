import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/entitlement_invalidation_source.dart';
import 'package:neximmo_app/features/identity_access/data/supabase_entitlement_invalidation_adapter.dart';

void main() {
  group('SupabaseEntitlementInvalidationAdapter', () {
    test('maps readiness and scoped entitlement signals', () async {
      final gateway = _FakeGateway();
      final adapter = SupabaseEntitlementInvalidationAdapter.withGateway(
        gateway,
      );
      final events = <Object>[];
      final subscription = adapter
          .watchUser(userId: 'user-a')
          .listen(events.add, onError: events.add);

      gateway.emit(const <String, dynamic>{});
      gateway.emit(const <String, dynamic>{
        'user_id': 'user-a',
        'workspace_id': 'workspace-a',
      });
      await _flushEvents();

      expect(gateway.userIds, <String>['user-a']);
      expect(events, hasLength(2));
      expect(
        (events.first as EntitlementInvalidation).isReconciliation,
        isTrue,
      );
      expect(
        (events.last as EntitlementInvalidation).workspaceId,
        'workspace-a',
      );
      await subscription.cancel();
      await gateway.close();
    });

    test('fails closed for foreign or malformed payloads', () async {
      final gateway = _FakeGateway();
      final adapter = SupabaseEntitlementInvalidationAdapter.withGateway(
        gateway,
      );
      final errors = <Object>[];
      final subscription = adapter
          .watchUser(userId: 'user-a')
          .listen((_) {}, onError: errors.add);

      gateway.emit(const <String, dynamic>{
        'user_id': 'user-b',
        'workspace_id': 'workspace-a',
      });
      gateway.emit(const <String, dynamic>{'user_id': 'user-a'});
      await _flushEvents();

      expect(errors, hasLength(2));
      expect(errors, everyElement(isA<FormatException>()));
      await subscription.cancel();
      await gateway.close();
    });
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

class _FakeGateway implements EntitlementRealtimeSupabaseGateway {
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<String> userIds = <String>[];

  @override
  Stream<Map<String, dynamic>> watchUserChanges({required String userId}) {
    userIds.add(userId);
    return _controller.stream;
  }

  void emit(Map<String, dynamic> event) => _controller.add(event);

  Future<void> close() => _controller.close();
}
