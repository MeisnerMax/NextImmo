import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/platform_domain_event.dart';
import 'supabase_domain_event_consumer_adapter.dart';

/// Read seam over the `domain_events` outbox. There is no write method, and
/// there cannot be one: the table is append-only by construction (no
/// INSERT/UPDATE/DELETE policy, no write grant, reject triggers) and is written
/// only from inside the mutating RPCs.
abstract interface class OutboxSupabaseGateway {
  Future<List<Map<String, dynamic>>> listEvents({
    required String workspaceId,
    required String requiredPermission,
    required OutboxCursor? after,
    required int limit,
  });
}

class SupabaseOutboxGateway implements OutboxSupabaseGateway {
  SupabaseOutboxGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> listEvents({
    required String workspaceId,
    required String requiredPermission,
    required OutboxCursor? after,
    required int limit,
  }) async {
    var query = _client
        .from('domain_events')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('required_permission', requiredPermission);
    if (after != null) {
      // Ascending composite keyset: strictly newer, or the same instant with a
      // larger id. `occurred_at` alone cannot resume a replay, because every
      // envelope written by one command shares it.
      final stamp = after.occurredAt.toUtc().toIso8601String();
      query = query.or(
        'occurred_at.gt.$stamp,'
        'and(occurred_at.eq.$stamp,id.gt.${after.eventId})',
      );
    }
    final rows = await query
        .order('occurred_at', ascending: true)
        .order('id', ascending: true)
        .limit(limit);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }
}

/// DOM-010 `OutboxPort` over Supabase.
///
/// This is the catch-up path the best-effort broadcast needs: increment 1 lets
/// a failed `realtime.send` degrade to a warning so it never fails the
/// mutation, which means the transport can silently drop events. Replaying from
/// here — oldest first, resumable — is what makes "the outbox is the truth"
/// true for a client and not just for the database.
class SupabaseOutboxAdapter implements OutboxPort {
  SupabaseOutboxAdapter({required SupabaseClient client})
    : _gateway = SupabaseOutboxGateway(client);

  SupabaseOutboxAdapter.withGateway(OutboxSupabaseGateway gateway)
    : _gateway = gateway;

  final OutboxSupabaseGateway _gateway;

  @override
  Future<OutboxPage> read(OutboxQuery query) async {
    final rows = await _gateway.listEvents(
      workspaceId: query.workspaceId,
      requiredPermission: query.requiredPermission,
      after: query.after,
      limit: query.limit + 1,
    );
    final hasNextPage = rows.length > query.limit;
    final pageRows = hasNextPage ? rows.take(query.limit) : rows;
    final events = pageRows
        .map(parseDomainEventEnvelope)
        .toList(growable: false);
    if (events.any((event) => event.workspaceId != query.workspaceId)) {
      throw const FormatException('Outbox workspace mismatch.');
    }
    return OutboxPage(
      events: events,
      nextCursor: hasNextPage && events.isNotEmpty
          ? OutboxCursor(
              occurredAt: events.last.occurredAt,
              eventId: events.last.eventId,
            )
          : null,
    );
  }
}
