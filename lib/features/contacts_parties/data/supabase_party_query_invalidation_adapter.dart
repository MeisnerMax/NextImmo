import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/party_query_invalidation_source.dart';

abstract interface class PartyRealtimeSupabaseGateway {
  Stream<Map<String, dynamic>> watchWorkspaceUpdates({
    required String workspaceId,
  });
}

class SupabasePartyRealtimeGateway implements PartyRealtimeSupabaseGateway {
  SupabasePartyRealtimeGateway(this._client);

  final SupabaseClient _client;
  int _channelSequence = 0;

  @override
  Stream<Map<String, dynamic>> watchWorkspaceUpdates({
    required String workspaceId,
  }) {
    late final StreamController<Map<String, dynamic>> controller;
    RealtimeChannel? channel;
    var removed = false;

    Future<void> subscribe() async {
      try {
        await _client.realtime.setAuth(_client.auth.currentSession?.accessToken);
        if (removed || controller.isClosed) {
          return;
        }
        final activeChannel = _client.channel(
          'neximmo-parties-$workspaceId-${_channelSequence++}',
        );
        channel = activeChannel;
        activeChannel
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'parties',
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
                // Every successful replication start reconciles, not just the
                // first: a dropped socket rejoins this channel and lands here
                // again, and Realtime replays nothing across the gap, so this
                // is the only signal that recovers a change the client was
                // disconnected for (REALTIME-STAGING-FIX-01).
                controller.add(const <String, dynamic>{});
                return;
              }
              controller.addError(
                StateError(
                  'Party Realtime replication failed: ${payload['message']}',
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
                    StateError('Party Realtime subscription failed: $error'),
                  );
                case RealtimeSubscribeStatus.closed:
                  if (!removed) {
                    controller.addError(
                      StateError('Party Realtime subscription closed.'),
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

class SupabasePartyQueryInvalidationAdapter
    implements PartyQueryInvalidationSource {
  SupabasePartyQueryInvalidationAdapter({required SupabaseClient client})
    : _gateway = SupabasePartyRealtimeGateway(client);

  SupabasePartyQueryInvalidationAdapter.withGateway(
    PartyRealtimeSupabaseGateway gateway,
  ) : _gateway = gateway;

  final PartyRealtimeSupabaseGateway _gateway;

  @override
  Stream<PartyQueryInvalidation> watchWorkspace({required String workspaceId}) {
    if (workspaceId.isEmpty) {
      return Stream<PartyQueryInvalidation>.error(
        const FormatException('Workspace id must not be empty.'),
      );
    }
    return _gateway.watchWorkspaceUpdates(workspaceId: workspaceId).map((
      record,
    ) {
      if (record.isEmpty) {
        return PartyQueryInvalidation.reconcile(workspaceId: workspaceId);
      }
      final eventWorkspaceId = _requiredString(record, 'workspace_id');
      final partyId = _requiredString(record, 'id');
      if (eventWorkspaceId != workspaceId) {
        throw const FormatException('Party Realtime workspace mismatch.');
      }
      return PartyQueryInvalidation(
        workspaceId: workspaceId,
        partyId: partyId,
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
