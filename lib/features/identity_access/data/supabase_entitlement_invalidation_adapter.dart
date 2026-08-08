import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/entitlement_invalidation_source.dart';

abstract interface class EntitlementRealtimeSupabaseGateway {
  Stream<Map<String, dynamic>> watchUserChanges({required String userId});
}

class SupabaseEntitlementRealtimeGateway
    implements EntitlementRealtimeSupabaseGateway {
  SupabaseEntitlementRealtimeGateway(this._client);

  final SupabaseClient _client;

  @override
  Stream<Map<String, dynamic>> watchUserChanges({required String userId}) {
    late final StreamController<Map<String, dynamic>> controller;
    RealtimeChannel? channel;
    var removed = false;

    Future<void> subscribe() async {
      try {
        await _client.realtime.setAuth(
          _client.auth.currentSession?.accessToken,
        );
        if (removed || controller.isClosed) {
          return;
        }
        final activeChannel = _client.channel(
          'entitlements:$userId',
          opts: const RealtimeChannelConfig(private: true),
        );
        channel = activeChannel;
        activeChannel
            .onBroadcast(
              event: 'revalidate',
              callback: (message) {
                if (controller.isClosed) {
                  return;
                }
                final payload = message['payload'];
                controller.add(
                  payload is Map
                      ? Map<String, dynamic>.from(payload)
                      : Map<String, dynamic>.from(message),
                );
              },
            )
            .subscribe((status, error) {
              if (controller.isClosed) {
                return;
              }
              switch (status) {
                case RealtimeSubscribeStatus.subscribed:
                  controller.add(const <String, dynamic>{});
                case RealtimeSubscribeStatus.channelError:
                case RealtimeSubscribeStatus.timedOut:
                  controller.addError(
                    StateError(
                      'Entitlement Realtime subscription failed: $error',
                    ),
                  );
                case RealtimeSubscribeStatus.closed:
                  if (!removed) {
                    controller.addError(
                      StateError('Entitlement Realtime subscription closed.'),
                    );
                  }
              }
            });
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () => unawaited(subscribe()),
      onCancel: () async {
        removed = true;
        final activeChannel = channel;
        if (activeChannel != null) {
          await _client.removeChannel(activeChannel);
        }
      },
    );
    return controller.stream;
  }
}

class SupabaseEntitlementInvalidationAdapter
    implements EntitlementInvalidationSource {
  SupabaseEntitlementInvalidationAdapter({required SupabaseClient client})
    : _gateway = SupabaseEntitlementRealtimeGateway(client);

  SupabaseEntitlementInvalidationAdapter.withGateway(
    EntitlementRealtimeSupabaseGateway gateway,
  ) : _gateway = gateway;

  final EntitlementRealtimeSupabaseGateway _gateway;

  @override
  Stream<EntitlementInvalidation> watchUser({required String userId}) {
    if (userId.trim().isEmpty) {
      return Stream<EntitlementInvalidation>.error(
        const FormatException('User id must not be empty.'),
      );
    }
    return _gateway.watchUserChanges(userId: userId).map((record) {
      if (record.isEmpty) {
        return EntitlementInvalidation.reconcile(userId: userId);
      }
      final eventUserId = _requiredString(record, 'user_id');
      final workspaceId = _requiredString(record, 'workspace_id');
      if (eventUserId != userId) {
        throw const FormatException('Entitlement Realtime user mismatch.');
      }
      return EntitlementInvalidation(userId: userId, workspaceId: workspaceId);
    });
  }
}

String _requiredString(Map<String, dynamic> record, String key) {
  final value = record[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected non-empty string field: $key.');
  }
  return value;
}
