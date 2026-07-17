import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/property_query_invalidation_source.dart';

abstract interface class PropertyRealtimeSupabaseGateway {
  Stream<Map<String, dynamic>> watchWorkspaceUpdates({
    required String workspaceId,
  });
}

class SupabasePropertyRealtimeGateway
    implements PropertyRealtimeSupabaseGateway {
  SupabasePropertyRealtimeGateway(this._client);

  final SupabaseClient _client;
  int _channelSequence = 0;

  @override
  Stream<Map<String, dynamic>> watchWorkspaceUpdates({
    required String workspaceId,
  }) {
    late final StreamController<Map<String, dynamic>> controller;
    RealtimeChannel? channel;
    var removed = false;
    var ready = false;

    Future<void> subscribe() async {
      try {
        await _client.realtime.setAuth(
          _client.auth.currentSession?.accessToken,
        );
        if (removed || controller.isClosed) {
          return;
        }
        final activeChannel = _client.channel(
          'neximmo-properties-$workspaceId-${_channelSequence++}',
        );
        channel = activeChannel;
        activeChannel
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'properties',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'workspace_id',
                value: workspaceId,
              ),
              callback: (payload) {
                if (!controller.isClosed) {
                  controller.add(payload.newRecord);
                }
              },
            )
            .onSystemEvents((payload) {
              if (controller.isClosed ||
                  payload is! Map ||
                  payload['extension'] != 'postgres_changes') {
                return;
              }
              if (payload['status'] == 'ok') {
                if (!ready) {
                  ready = true;
                  controller.add(const <String, dynamic>{});
                }
                return;
              }
              controller.addError(
                StateError(
                  'Property Realtime replication failed: '
                  '${payload['message']}',
                ),
              );
            })
            .subscribe((status, error) {
              if (controller.isClosed) {
                return;
              }
              switch (status) {
                case RealtimeSubscribeStatus.subscribed:
                  break;
                case RealtimeSubscribeStatus.channelError:
                case RealtimeSubscribeStatus.timedOut:
                  controller.addError(
                    StateError('Property Realtime subscription failed: $error'),
                  );
                case RealtimeSubscribeStatus.closed:
                  if (!removed) {
                    controller.addError(
                      StateError('Property Realtime subscription closed.'),
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
      onListen: () {
        unawaited(subscribe());
      },
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

class SupabasePropertyQueryInvalidationAdapter
    implements PropertyQueryInvalidationSource {
  SupabasePropertyQueryInvalidationAdapter({required SupabaseClient client})
    : _gateway = SupabasePropertyRealtimeGateway(client);

  SupabasePropertyQueryInvalidationAdapter.withGateway(
    PropertyRealtimeSupabaseGateway gateway,
  ) : _gateway = gateway;

  final PropertyRealtimeSupabaseGateway _gateway;

  @override
  Stream<PropertyQueryInvalidation> watchWorkspace({
    required String workspaceId,
  }) {
    if (workspaceId.isEmpty) {
      return Stream<PropertyQueryInvalidation>.error(
        const FormatException('Workspace id must not be empty.'),
      );
    }
    return _gateway.watchWorkspaceUpdates(workspaceId: workspaceId).map((
      record,
    ) {
      if (record.isEmpty) {
        return PropertyQueryInvalidation.reconcile(workspaceId: workspaceId);
      }
      final eventWorkspaceId = _requiredString(record, 'workspace_id');
      final propertyId = _requiredString(record, 'id');
      if (eventWorkspaceId != workspaceId) {
        throw const FormatException('Property Realtime workspace mismatch.');
      }
      return PropertyQueryInvalidation(
        workspaceId: workspaceId,
        propertyId: propertyId,
      );
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
