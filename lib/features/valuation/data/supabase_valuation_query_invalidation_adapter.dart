import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/valuation_query_invalidation_source.dart';

abstract interface class ValuationRealtimeSupabaseGateway {
  Stream<Map<String, dynamic>> watchWorkspaceUpdates({
    required String workspaceId,
  });
}

class SupabaseValuationRealtimeGateway
    implements ValuationRealtimeSupabaseGateway {
  SupabaseValuationRealtimeGateway(this._client);

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
          'neximmo-valuations-$workspaceId-${_channelSequence++}',
        );
        channel = activeChannel;
        activeChannel
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'valuation_cases',
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
                  'Valuation Realtime replication failed: ${payload['message']}',
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
                    StateError('Valuation Realtime subscription failed: $error'),
                  );
                case RealtimeSubscribeStatus.closed:
                  if (!removed) {
                    controller.addError(
                      StateError('Valuation Realtime subscription closed.'),
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

/// Workspace-scoped valuation invalidation over the `valuation_cases`
/// publication (P2-D07 step 2).
///
/// Every case-level command bumps the row, so configuration edits, factor
/// writes and status transitions all arrive here. A published report does not —
/// it deliberately leaves the case version alone — which is why every
/// invalidation from this source is a [ValuationAggregate.valuationCase] event
/// and never a [ValuationAggregate.report] one. That gap is named in the
/// migration and belongs to the CTR-005 domain-event envelope, not to a
/// pretend-event here.
class SupabaseValuationQueryInvalidationAdapter
    implements ValuationQueryInvalidationSource {
  SupabaseValuationQueryInvalidationAdapter({required SupabaseClient client})
    : _gateway = SupabaseValuationRealtimeGateway(client);

  SupabaseValuationQueryInvalidationAdapter.withGateway(
    ValuationRealtimeSupabaseGateway gateway,
  ) : _gateway = gateway;

  final ValuationRealtimeSupabaseGateway _gateway;

  @override
  Stream<ValuationQueryInvalidation> watchWorkspace({
    required String workspaceId,
  }) {
    if (workspaceId.isEmpty) {
      return Stream<ValuationQueryInvalidation>.error(
        const FormatException('Workspace id must not be empty.'),
      );
    }
    return _gateway.watchWorkspaceUpdates(workspaceId: workspaceId).map((
      record,
    ) {
      if (record.isEmpty) {
        return ValuationQueryInvalidation.reconcile(workspaceId: workspaceId);
      }
      final eventWorkspaceId = _requiredString(record, 'workspace_id');
      if (eventWorkspaceId != workspaceId) {
        throw const FormatException('Valuation Realtime workspace mismatch.');
      }
      return ValuationQueryInvalidation(
        workspaceId: workspaceId,
        aggregate: ValuationAggregate.valuationCase,
        eventType: 'valuation_case.changed',
        valuationCaseId: _requiredString(record, 'id'),
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
