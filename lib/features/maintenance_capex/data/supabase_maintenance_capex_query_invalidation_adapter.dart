import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/maintenance_capex_query_invalidation_source.dart';

/// One realtime event as the gateway saw it. [aggregate] null means "the
/// subscription just became live", which the adapter turns into a reconcile.
class MaintenanceCapexRealtimeEvent {
  const MaintenanceCapexRealtimeEvent({
    required this.aggregate,
    required this.record,
  });

  const MaintenanceCapexRealtimeEvent.ready()
    : aggregate = null,
      record = const <String, dynamic>{};

  final MaintenanceCapexAggregate? aggregate;
  final Map<String, dynamic> record;
}

abstract interface class MaintenanceCapexRealtimeSupabaseGateway {
  Stream<MaintenanceCapexRealtimeEvent> watchWorkspaceUpdates({
    required String workspaceId,
  });
}

/// One channel carrying both published maintenance_capex tables
/// (`20260806110000_p2_d06_maintenance_capex_realtime.sql`).
///
/// Both bind INSERT and UPDATE: creation and every status transition/update
/// are state changes a list must see. Unlike leasing's rent-roll snapshot,
/// neither aggregate has a satellite line table, so there is nothing
/// deliberately left unbound here.
class SupabaseMaintenanceCapexRealtimeGateway
    implements MaintenanceCapexRealtimeSupabaseGateway {
  SupabaseMaintenanceCapexRealtimeGateway(this._client);

  static const Map<MaintenanceCapexAggregate, String> _tables =
      <MaintenanceCapexAggregate, String>{
        MaintenanceCapexAggregate.maintenanceTicket: 'maintenance_tickets',
        MaintenanceCapexAggregate.capexProject: 'capex_projects',
      };

  final SupabaseClient _client;
  int _channelSequence = 0;

  @override
  Stream<MaintenanceCapexRealtimeEvent> watchWorkspaceUpdates({
    required String workspaceId,
  }) {
    late final StreamController<MaintenanceCapexRealtimeEvent> controller;
    RealtimeChannel? channel;
    var removed = false;

    Future<void> subscribe() async {
      try {
        await _client.realtime.setAuth(_client.auth.currentSession?.accessToken);
        if (removed || controller.isClosed) {
          return;
        }
        final activeChannel = _client.channel(
          'neximmo-maintenance-capex-$workspaceId-${_channelSequence++}',
        );
        channel = activeChannel;

        final filter = PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'workspace_id',
          value: workspaceId,
        );
        void bind(
          MaintenanceCapexAggregate aggregate,
          PostgresChangeEvent event,
        ) {
          activeChannel.onPostgresChanges(
            event: event,
            schema: 'public',
            table: _tables[aggregate]!,
            filter: filter,
            callback: (payload) {
              if (!controller.isClosed) {
                controller.add(
                  MaintenanceCapexRealtimeEvent(
                    aggregate: aggregate,
                    record: payload.newRecord,
                  ),
                );
              }
            },
          );
        }

        for (final aggregate in <MaintenanceCapexAggregate>[
          MaintenanceCapexAggregate.maintenanceTicket,
          MaintenanceCapexAggregate.capexProject,
        ]) {
          bind(aggregate, PostgresChangeEvent.insert);
          bind(aggregate, PostgresChangeEvent.update);
        }

        activeChannel
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
                // disconnected for (REALTIME-STAGING-FIX-01). The bindings
                // share this channel, so one join can raise this more than
                // once; both consumers of this source coalesce through
                // `_scheduleInvalidationReload`, so that collapses into a
                // single reload instead of a burst of reads.
                controller.add(const MaintenanceCapexRealtimeEvent.ready());
                return;
              }
              controller.addError(
                StateError(
                  'MaintenanceCapex Realtime replication failed: '
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
                    StateError(
                      'MaintenanceCapex Realtime subscription failed: $error',
                    ),
                  );
                case RealtimeSubscribeStatus.closed:
                  if (!removed) {
                    controller.addError(
                      StateError(
                        'MaintenanceCapex Realtime subscription closed.',
                      ),
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

    controller = StreamController<MaintenanceCapexRealtimeEvent>(
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

class SupabaseMaintenanceCapexQueryInvalidationAdapter
    implements MaintenanceCapexQueryInvalidationSource {
  SupabaseMaintenanceCapexQueryInvalidationAdapter({
    required SupabaseClient client,
  }) : _gateway = SupabaseMaintenanceCapexRealtimeGateway(client);

  SupabaseMaintenanceCapexQueryInvalidationAdapter.withGateway(
    MaintenanceCapexRealtimeSupabaseGateway gateway,
  ) : _gateway = gateway;

  final MaintenanceCapexRealtimeSupabaseGateway _gateway;

  @override
  Stream<MaintenanceCapexQueryInvalidation> watchWorkspace({
    required String workspaceId,
  }) {
    if (workspaceId.isEmpty) {
      return Stream<MaintenanceCapexQueryInvalidation>.error(
        const FormatException('Workspace id must not be empty.'),
      );
    }
    return _gateway.watchWorkspaceUpdates(workspaceId: workspaceId).map((
      event,
    ) {
      final aggregate = event.aggregate;
      if (aggregate == null) {
        return MaintenanceCapexQueryInvalidation.reconcile(
          workspaceId: workspaceId,
        );
      }
      final eventWorkspaceId = _requiredString(event.record, 'workspace_id');
      final entityId = _requiredString(event.record, 'id');
      if (eventWorkspaceId != workspaceId) {
        // The server-side filter already scopes the channel; a row from
        // elsewhere means the subscription is not what it claims to be, so it
        // fails loudly instead of invalidating a foreign workspace's caches.
        throw const FormatException(
          'MaintenanceCapex Realtime workspace mismatch.',
        );
      }
      return MaintenanceCapexQueryInvalidation(
        workspaceId: workspaceId,
        aggregate: aggregate,
        entityId: entityId,
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
