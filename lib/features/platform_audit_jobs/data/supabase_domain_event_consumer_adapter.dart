import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/platform_domain_event.dart';
import '../application/platform_query_invalidation_source.dart';

/// The permission-scoped topics the platform read models listen on. One topic
/// per aggregate, because increment 1 scopes every envelope — and its broadcast
/// topic — by the permission a reader must hold. There is deliberately no
/// workspace-wide topic: it would leak the existence and ids of rows the reader
/// may not see.
const platformTaskEventPermission = 'task.read';
const platformNotificationEventPermission = 'notification.read';
const platformImportEventPermission = 'import.read';

abstract interface class DomainEventRealtimeSupabaseGateway {
  /// Emits an empty map once the subscription is (re)established, then one map
  /// per received envelope.
  Stream<Map<String, dynamic>> watchTopic({
    required String workspaceId,
    required String requiredPermission,
  });
}

class SupabaseDomainEventRealtimeGateway
    implements DomainEventRealtimeSupabaseGateway {
  SupabaseDomainEventRealtimeGateway(this._client);

  final SupabaseClient _client;

  @override
  Stream<Map<String, dynamic>> watchTopic({
    required String workspaceId,
    required String requiredPermission,
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
        // Must match `private.publish_domain_event`'s topic exactly:
        // `workspace:<workspace_id>:<required_permission>`.
        final activeChannel = _client.channel(
          'workspace:$workspaceId:$requiredPermission',
          opts: const RealtimeChannelConfig(private: true),
        );
        channel = activeChannel;
        activeChannel
            .onBroadcast(
              event: 'domain_event',
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
                      'Domain event subscription failed for '
                      '$requiredPermission: $error',
                    ),
                  );
                case RealtimeSubscribeStatus.closed:
                  if (!removed) {
                    controller.addError(
                      StateError(
                        'Domain event subscription closed for '
                        '$requiredPermission.',
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

/// Typed view of one permission-scoped topic. The subscription-ready marker is
/// filtered out here: it is a transport fact, not an envelope, and inventing a
/// synthetic [DomainEventEnvelope] for it would put a lie in the event log's
/// own type. Consumers that need it use
/// [SupabasePlatformQueryInvalidationAdapter], whose contract has an explicit
/// reconciliation signal.
class SupabaseDomainEventConsumerAdapter implements DomainEventConsumer {
  SupabaseDomainEventConsumerAdapter({required SupabaseClient client})
    : _gateway = SupabaseDomainEventRealtimeGateway(client);

  SupabaseDomainEventConsumerAdapter.withGateway(
    DomainEventRealtimeSupabaseGateway gateway,
  ) : _gateway = gateway;

  final DomainEventRealtimeSupabaseGateway _gateway;

  @override
  Stream<DomainEventEnvelope> watch({
    required String workspaceId,
    required String requiredPermission,
  }) {
    if (workspaceId.isEmpty || requiredPermission.isEmpty) {
      return Stream<DomainEventEnvelope>.error(
        const FormatException(
          'Workspace id and required permission must not be empty.',
        ),
      );
    }
    return _gateway
        .watchTopic(
          workspaceId: workspaceId,
          requiredPermission: requiredPermission,
        )
        .where((record) => record.isNotEmpty)
        .map((record) {
          final envelope = parseDomainEventEnvelope(record);
          if (envelope.workspaceId != workspaceId) {
            throw const FormatException('Domain event workspace mismatch.');
          }
          return envelope;
        });
  }
}

/// Merges the three platform topics into the invalidation contract.
class SupabasePlatformQueryInvalidationAdapter
    implements PlatformQueryInvalidationSource {
  SupabasePlatformQueryInvalidationAdapter({required SupabaseClient client})
    : _gateway = SupabaseDomainEventRealtimeGateway(client);

  SupabasePlatformQueryInvalidationAdapter.withGateway(
    DomainEventRealtimeSupabaseGateway gateway,
  ) : _gateway = gateway;

  static const List<String> topicPermissions = <String>[
    platformTaskEventPermission,
    platformNotificationEventPermission,
    platformImportEventPermission,
  ];

  final DomainEventRealtimeSupabaseGateway _gateway;

  @override
  Stream<PlatformQueryInvalidation> watchWorkspace({
    required String workspaceId,
  }) {
    if (workspaceId.isEmpty) {
      return Stream<PlatformQueryInvalidation>.error(
        const FormatException('Workspace id must not be empty.'),
      );
    }

    late final StreamController<PlatformQueryInvalidation> controller;
    final subscriptions = <StreamSubscription<Map<String, dynamic>>>[];
    var failedTopics = 0;
    Object? firstError;
    StackTrace? firstStackTrace;

    void listenAll() {
      for (final permission in topicPermissions) {
        subscriptions.add(
          _gateway
              .watchTopic(
                workspaceId: workspaceId,
                requiredPermission: permission,
              )
              .listen(
                (record) {
                  if (controller.isClosed) {
                    return;
                  }
                  if (record.isEmpty) {
                    // This topic just (re)connected; anything it missed while
                    // down has to be recovered from the outbox rather than
                    // assumed absent. One signal per topic, because the topics
                    // reconnect independently.
                    controller.add(
                      PlatformQueryInvalidation.reconcile(
                        workspaceId: workspaceId,
                      ),
                    );
                    return;
                  }
                  final invalidation = _toInvalidation(record, workspaceId);
                  // An envelope from a domain that merely shares this topic is
                  // skipped, not treated as an error: a future aggregate
                  // publishing on `task.read` must not break this consumer.
                  if (invalidation != null) {
                    controller.add(invalidation);
                  }
                },
                onError: (Object error, StackTrace stackTrace) {
                  // A member legitimately holding only a subset of the three
                  // permissions is the normal case, and a denied topic surfaces
                  // as a channel error. One failing topic therefore yields
                  // nothing rather than failing the whole stream — but if every
                  // topic fails, that is an infrastructure problem the caller
                  // must see.
                  firstError ??= error;
                  firstStackTrace ??= stackTrace;
                  failedTopics++;
                  if (failedTopics == topicPermissions.length &&
                      !controller.isClosed) {
                    controller.addError(firstError!, firstStackTrace);
                  }
                },
              ),
        );
      }
    }

    controller = StreamController<PlatformQueryInvalidation>(
      onListen: listenAll,
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        subscriptions.clear();
      },
    );
    return controller.stream;
  }
}

PlatformQueryInvalidation? _toInvalidation(
  Map<String, dynamic> record,
  String workspaceId,
) {
  final envelope = parseDomainEventEnvelope(record);
  if (envelope.workspaceId != workspaceId) {
    throw const FormatException('Domain event workspace mismatch.');
  }
  final aggregate = _aggregateOf(envelope.aggregateType);
  if (aggregate == null) {
    return null;
  }
  return PlatformQueryInvalidation(
    workspaceId: workspaceId,
    aggregate: aggregate,
    eventType: envelope.eventType,
    // `notification.fanned_out` carries no aggregate id by design — the batch
    // deliberately does not name its recipients — so this collapses to a
    // workspace-wide notification invalidation and the reader refetches its
    // own feed.
    aggregateId: envelope.aggregateId,
  );
}

PlatformAggregate? _aggregateOf(String aggregateType) {
  switch (aggregateType) {
    case 'task':
      return PlatformAggregate.task;
    case 'notification':
    case 'notification_batch':
      return PlatformAggregate.notification;
    case 'import_job':
      return PlatformAggregate.importJob;
    default:
      return null;
  }
}

/// Parses a broadcast payload or an outbox row into a CTR-005 envelope. Both
/// carry the same field names — `private.publish_domain_event` builds the
/// broadcast body straight from the outbox row — so one parser serves the live
/// transport and the durable replay, and a drift between them shows up as a
/// parse failure instead of two subtly different readings of one event.
DomainEventEnvelope parseDomainEventEnvelope(Map<String, dynamic> record) {
  return DomainEventEnvelope(
    eventId: _requiredString(record, _eventIdKey(record)),
    eventType: _requiredString(record, 'event_type'),
    schemaVersion: _requiredInt(record, 'schema_version'),
    workspaceId: _requiredString(record, 'workspace_id'),
    aggregateType: _requiredString(record, 'aggregate_type'),
    occurredAt: _requiredDateTime(record, 'occurred_at'),
    correlationId: _requiredString(record, 'correlation_id'),
    aggregateId: _optionalString(record, 'aggregate_id'),
    aggregateVersion: _optionalInt(record, 'aggregate_version'),
    actorId: _optionalString(record, 'actor_id'),
    payload: _optionalMap(record, 'payload') ?? const <String, Object?>{},
  );
}

/// The broadcast names the envelope id `event_id`; the outbox row calls the
/// same value `id`. Accepting either keeps one parser honest for both sources
/// instead of duplicating it.
String _eventIdKey(Map<String, dynamic> record) =>
    record.containsKey('event_id') ? 'event_id' : 'id';

String _requiredString(Map<String, dynamic> record, String key) {
  final value = record[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected non-empty string field: $key.');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> record, String key) {
  final value = record[key];
  if (value == null) {
    return null;
  }
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected non-empty string field: $key.');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> record, String key) {
  final value = _optionalInt(record, key);
  if (value == null) {
    throw FormatException('Expected integer field: $key.');
  }
  return value;
}

int? _optionalInt(Map<String, dynamic> record, String key) {
  final value = record[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('Expected integer field: $key.');
}

DateTime _requiredDateTime(Map<String, dynamic> record, String key) {
  final value = record[key];
  if (value is! String) {
    throw FormatException('Expected timestamp field: $key.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Malformed timestamp field: $key.');
  }
  return parsed;
}

Map<String, Object?>? _optionalMap(Map<String, dynamic> record, String key) {
  final value = record[key];
  if (value == null) {
    return null;
  }
  if (value is! Map) {
    throw FormatException('Expected JSON object field: $key.');
  }
  return Map<String, Object?>.from(value);
}
