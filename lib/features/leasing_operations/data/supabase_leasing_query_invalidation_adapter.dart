import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/leasing_query_invalidation_source.dart';

/// One realtime event as the gateway saw it. [aggregate] null means "the
/// subscription just became live", which the adapter turns into a reconcile.
class LeasingRealtimeEvent {
  const LeasingRealtimeEvent({
    required this.aggregate,
    required this.record,
  });

  const LeasingRealtimeEvent.ready()
    : aggregate = null,
      record = const <String, dynamic>{};

  final LeasingAggregate? aggregate;
  final Map<String, dynamic> record;
}

abstract interface class LeasingRealtimeSupabaseGateway {
  Stream<LeasingRealtimeEvent> watchWorkspaceUpdates({
    required String workspaceId,
  });
}

/// One channel carrying all four published leasing tables.
///
/// Bindings differ per table because the write shapes do:
///
///   * `units`, `leases`, `leasing_cases` — INSERT and UPDATE. Creation and
///     every transition/update are both state changes a list must see.
///   * `rent_roll_snapshots` — INSERT only. AGG-007 makes a snapshot immutable,
///     so there is no UPDATE to subscribe to; binding one would advertise a
///     write path that does not exist.
///
/// `rent_roll_snapshot_lines` is not published at all (see the increment 2
/// realtime migration): lines are only ever written inside the same transaction
/// as their header, so the header event already covers them, and publishing
/// them would emit one event per unit for a single command.
class SupabaseLeasingRealtimeGateway implements LeasingRealtimeSupabaseGateway {
  SupabaseLeasingRealtimeGateway(this._client);

  static const Map<LeasingAggregate, String> _tables =
      <LeasingAggregate, String>{
        LeasingAggregate.unit: 'units',
        LeasingAggregate.lease: 'leases',
        LeasingAggregate.leasingCase: 'leasing_cases',
        LeasingAggregate.rentRollSnapshot: 'rent_roll_snapshots',
      };

  final SupabaseClient _client;
  int _channelSequence = 0;

  @override
  Stream<LeasingRealtimeEvent> watchWorkspaceUpdates({
    required String workspaceId,
  }) {
    late final StreamController<LeasingRealtimeEvent> controller;
    RealtimeChannel? channel;
    var removed = false;
    var ready = false;

    Future<void> subscribe() async {
      try {
        await _client.realtime.setAuth(_client.auth.currentSession?.accessToken);
        if (removed || controller.isClosed) {
          return;
        }
        final activeChannel = _client.channel(
          'neximmo-leasing-$workspaceId-${_channelSequence++}',
        );
        channel = activeChannel;

        final filter = PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'workspace_id',
          value: workspaceId,
        );
        void bind(LeasingAggregate aggregate, PostgresChangeEvent event) {
          activeChannel.onPostgresChanges(
            event: event,
            schema: 'public',
            table: _tables[aggregate]!,
            filter: filter,
            callback: (payload) {
              if (!controller.isClosed) {
                controller.add(
                  LeasingRealtimeEvent(
                    aggregate: aggregate,
                    record: payload.newRecord,
                  ),
                );
              }
            },
          );
        }

        for (final aggregate in <LeasingAggregate>[
          LeasingAggregate.unit,
          LeasingAggregate.lease,
          LeasingAggregate.leasingCase,
        ]) {
          bind(aggregate, PostgresChangeEvent.insert);
          bind(aggregate, PostgresChangeEvent.update);
        }
        bind(LeasingAggregate.rentRollSnapshot, PostgresChangeEvent.insert);

        activeChannel
            .onSystemEvents((payload) {
              if (controller.isClosed ||
                  payload is! Map ||
                  payload['extension'] != 'postgres_changes') {
                return;
              }
              if (payload['status'] == 'ok') {
                // Several bindings share one channel, so this arrives once per
                // accepted binding; only the first becomes a reconcile.
                if (!ready) {
                  ready = true;
                  controller.add(const LeasingRealtimeEvent.ready());
                }
                return;
              }
              controller.addError(
                StateError(
                  'Leasing Realtime replication failed: ${payload['message']}',
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
                    StateError('Leasing Realtime subscription failed: $error'),
                  );
                case RealtimeSubscribeStatus.closed:
                  if (!removed) {
                    controller.addError(
                      StateError('Leasing Realtime subscription closed.'),
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

    controller = StreamController<LeasingRealtimeEvent>(
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

class SupabaseLeasingQueryInvalidationAdapter
    implements LeasingQueryInvalidationSource {
  SupabaseLeasingQueryInvalidationAdapter({required SupabaseClient client})
    : _gateway = SupabaseLeasingRealtimeGateway(client);

  SupabaseLeasingQueryInvalidationAdapter.withGateway(
    LeasingRealtimeSupabaseGateway gateway,
  ) : _gateway = gateway;

  final LeasingRealtimeSupabaseGateway _gateway;

  @override
  Stream<LeasingQueryInvalidation> watchWorkspace({
    required String workspaceId,
  }) {
    if (workspaceId.isEmpty) {
      return Stream<LeasingQueryInvalidation>.error(
        const FormatException('Workspace id must not be empty.'),
      );
    }
    return _gateway.watchWorkspaceUpdates(workspaceId: workspaceId).map((
      event,
    ) {
      final aggregate = event.aggregate;
      if (aggregate == null) {
        return LeasingQueryInvalidation.reconcile(workspaceId: workspaceId);
      }
      final eventWorkspaceId = _requiredString(event.record, 'workspace_id');
      final entityId = _requiredString(event.record, 'id');
      if (eventWorkspaceId != workspaceId) {
        // The server-side filter already scopes the channel; a row from
        // elsewhere means the subscription is not what it claims to be, so it
        // fails loudly instead of invalidating a foreign workspace's caches.
        throw const FormatException('Leasing Realtime workspace mismatch.');
      }
      return LeasingQueryInvalidation(
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
