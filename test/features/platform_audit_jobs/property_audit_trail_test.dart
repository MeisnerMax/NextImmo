import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/audit_read_port.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/property_activity_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/property_audit_controller.dart';
import 'package:neximmo_app/features/platform_audit_jobs/data/supabase_platform_repository_adapter.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/audit_event_dto.dart';

/// AUDIT-01 on the client: the adapter that reads the trail and the controller
/// that pages it.
///
/// The adapter tests are mostly about what does *not* arrive. The stored audit
/// row carries the old and new value of every patched field; the read port
/// publishes only the field names, and nothing in the client may quietly start
/// expecting more.
void main() {
  group('SupabasePlatformRepositoryAdapter.propertyAuditEvents', () {
    late _FakeGateway gateway;
    late SupabasePlatformRepositoryAdapter adapter;

    setUp(() {
      gateway = _FakeGateway();
      adapter = SupabasePlatformRepositoryAdapter.withGateway(gateway);
    });

    Future<PlatformRepositoryResult<AuditEventPage>> read({
      AuditEventCursor? cursor,
    }) {
      return adapter.propertyAuditEvents(
        PropertyAuditQuery(
          workspaceId: 'workspace-a',
          propertyId: 'property-a',
          cursor: cursor,
        ),
      );
    }

    test('asks the read port for exactly this property', () async {
      gateway.rpcResult = _payload();

      await read();

      expect(gateway.calledFunction, 'property_audit_events');
      expect(gateway.parameters?['p_workspace_id'], 'workspace-a');
      expect(gateway.parameters?['p_property_id'], 'property-a');
      expect(gateway.parameters?['p_after_occurred_at'], isNull);
      expect(gateway.parameters?['p_limit'], 50);
    });

    test('sends the keyset cursor as the server issued it', () async {
      gateway.rpcResult = _payload();

      await read(
        cursor: AuditEventCursor(
          occurredAt: DateTime.utc(2026, 9, 1, 10),
          id: 'event-9',
        ),
      );

      expect(
        gateway.parameters?['p_after_occurred_at'],
        '2026-09-01T10:00:00.000Z',
      );
      expect(gateway.parameters?['p_after_id'], 'event-9');
    });

    test('maps the published projection', () async {
      gateway.rpcResult = _payload();

      final page =
          (await read() as PlatformRepositorySuccess<AuditEventPage>).value;

      expect(page.events, hasLength(2));
      final first = page.events.first;
      expect(first.action, 'property.updated');
      expect(first.actorType, AuditActorType.user);
      expect(first.actorUserId, 'user-a');
      expect(first.roleKey, 'manager');
      expect(first.reason, 'Adresse korrigiert');
      expect(first.changedFields, <String>[
        'city',
        'zip',
      ], reason: 'names, in the order the server sorted them');
      expect(page.nextCursor?.id, 'event-2');
      expect(page.nextCursor?.occurredAt, DateTime.utc(2026, 9, 1, 9));
    });

    test('a service actor keeps its identifier and has no user id', () async {
      gateway.rpcResult = _payload();

      final page =
          (await read() as PlatformRepositorySuccess<AuditEventPage>).value;

      final service = page.events.last;
      expect(service.actorType, AuditActorType.service);
      expect(service.actorUserId, isNull);
      expect(service.actorIdentifier, 'system.emitter');
      expect(service.changedFields, isEmpty);
    });

    test('an unknown actor type degrades to system, never to user', () async {
      gateway.rpcResult = _payload(actorType: 'robot');

      final page =
          (await read() as PlatformRepositorySuccess<AuditEventPage>).value;

      expect(
        page.events.first.actorType,
        AuditActorType.system,
        reason:
            'attributing a change to a person the server did not name '
            'would be worse than attributing it to the platform',
      );
    });

    test('no page means no cursor, and none is invented', () async {
      gateway.rpcResult = _payload(nextCursor: null);

      final page =
          (await read() as PlatformRepositorySuccess<AuditEventPage>).value;

      expect(page.nextCursor, isNull);
      expect(page.events, isNotEmpty);
    });

    test('server refusals map onto their kinds', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'forbidden',
          'message': 'Audit access is not permitted',
        },
      };
      final forbidden =
          await read() as PlatformRepositoryFailure<AuditEventPage>;
      expect(forbidden.kind, PlatformRepositoryFailureKind.forbidden);
      expect(forbidden.message, 'Audit access is not permitted');

      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'not_found',
          'message': 'Property not found',
        },
      };
      expect(
        (await read() as PlatformRepositoryFailure<AuditEventPage>).kind,
        PlatformRepositoryFailureKind.notFound,
      );
    });

    test('a transport failure is an infrastructure failure', () async {
      gateway.rpcError = StateError('offline');

      expect(
        (await read() as PlatformRepositoryFailure<AuditEventPage>).kind,
        PlatformRepositoryFailureKind.infrastructureFailure,
      );
    });
  });

  group('PropertyAuditController', () {
    test('without audit.read it reports forbidden and calls nothing', () async {
      final port = _FakePort();
      final controller = _controller(
        port,
        permissions: const <String>{'property.read'},
      );

      await controller.load();

      expect(controller.state.phase, PropertyAuditPhase.forbidden);
      expect(
        port.queries,
        isEmpty,
        reason: 'the server would refuse anyway; do not spend the round trip',
      );
    });

    test('loads the newest page and reports whether more exist', () async {
      final port =
          _FakePort()
            ..result = PlatformRepositorySuccess<AuditEventPage>(
              AuditEventPage(
                events: <AuditEventDto>[_event('event-1')],
                nextCursor: AuditEventCursor(
                  occurredAt: DateTime.utc(2026, 9, 1, 9),
                  id: 'event-1',
                ),
              ),
            );
      final controller = _controller(port);

      await controller.load();

      expect(controller.state.phase, PropertyAuditPhase.ready);
      expect(controller.state.events, hasLength(1));
      expect(controller.state.hasMore, isTrue);
    });

    test('an empty trail is empty, not an error', () async {
      final port =
          _FakePort()
            ..result = const PlatformRepositorySuccess<AuditEventPage>(
              AuditEventPage(events: <AuditEventDto>[]),
            );
      final controller = _controller(port);

      await controller.load();

      expect(controller.state.phase, PropertyAuditPhase.empty);
      expect(controller.state.hasMore, isFalse);
    });

    test(
      'load more appends without duplicating and carries the cursor',
      () async {
        final port =
            _FakePort()
              ..result = PlatformRepositorySuccess<AuditEventPage>(
                AuditEventPage(
                  events: <AuditEventDto>[_event('event-1')],
                  nextCursor: AuditEventCursor(
                    occurredAt: DateTime.utc(2026, 9, 1, 9),
                    id: 'event-1',
                  ),
                ),
              );
        final controller = _controller(port);
        await controller.load();

        port.result = PlatformRepositorySuccess<AuditEventPage>(
          AuditEventPage(
            events: <AuditEventDto>[_event('event-1'), _event('event-2')],
          ),
        );
        await controller.loadMore();

        expect(port.queries.last.cursor?.id, 'event-1');
        expect(
          controller.state.events.map((event) => event.id),
          <String>['event-1', 'event-2'],
          reason: 'a repeated id is one row, not two',
        );
        expect(controller.state.hasMore, isFalse);
      },
    );

    test('a failed continuation keeps the loaded trail visible', () async {
      final port =
          _FakePort()
            ..result = PlatformRepositorySuccess<AuditEventPage>(
              AuditEventPage(
                events: <AuditEventDto>[_event('event-1')],
                nextCursor: AuditEventCursor(
                  occurredAt: DateTime.utc(2026, 9, 1, 9),
                  id: 'event-1',
                ),
              ),
            );
      final controller = _controller(port);
      await controller.load();

      port.result = const PlatformRepositoryFailure<AuditEventPage>(
        kind: PlatformRepositoryFailureKind.infrastructureFailure,
        message: 'offline',
      );
      await controller.loadMore();

      expect(controller.state.phase, PropertyAuditPhase.ready);
      expect(controller.state.events, hasLength(1));
      expect(controller.state.loadMoreMessage, 'offline');
    });

    test('a selection that a reload no longer contains is dropped', () async {
      final port =
          _FakePort()
            ..result = PlatformRepositorySuccess<AuditEventPage>(
              AuditEventPage(events: <AuditEventDto>[_event('event-1')]),
            );
      final controller = _controller(port);
      await controller.load();
      controller.select('event-1');
      expect(controller.state.selectedEvent?.id, 'event-1');

      port.result = PlatformRepositorySuccess<AuditEventPage>(
        AuditEventPage(events: <AuditEventDto>[_event('event-2')]),
      );
      await controller.load();

      expect(controller.state.selectedEventId, isNull);
    });

    test(
      'a forbidden read clears the trail rather than leaving it on screen',
      () async {
        final port =
            _FakePort()
              ..result = PlatformRepositorySuccess<AuditEventPage>(
                AuditEventPage(events: <AuditEventDto>[_event('event-1')]),
              );
        final controller = _controller(port);
        await controller.load();

        port.result = const PlatformRepositoryFailure<AuditEventPage>(
          kind: PlatformRepositoryFailureKind.forbidden,
          message: 'revoked',
        );
        await controller.load();

        expect(controller.state.phase, PropertyAuditPhase.forbidden);
        expect(controller.state.events, isEmpty);
      },
    );
  });
}

PropertyAuditController _controller(
  _FakePort port, {
  Set<String> permissions = const <String>{'property.read', 'audit.read'},
}) {
  return PropertyAuditController(
    propertyId: 'property-a',
    readPort: port,
    scope: WorkspaceSessionScope(
      workspaceId: 'workspace-a',
      actorId: 'user-a',
      permissions: permissions,
      mutationsSupported: true,
    ),
  );
}

AuditEventDto _event(String id) => AuditEventDto(
  id: id,
  occurredAt: DateTime.utc(2026, 9, 1, 9),
  action: 'property.updated',
  entityType: 'property',
  actorType: AuditActorType.user,
  source: 'rpc',
  correlationId: 'correlation-1',
);

Map<String, Object?> _payload({
  String actorType = 'user',
  Map<String, Object?>? nextCursor = const <String, Object?>{
    'occurred_at': '2026-09-01T09:00:00Z',
    'id': 'event-2',
  },
}) {
  return <String, Object?>{
    'ok': true,
    'events': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'event-1',
        'occurred_at': '2026-09-01T10:00:00Z',
        'action': 'property.updated',
        'entity_type': 'property',
        'entity_id': 'property-a',
        'parent_entity_type': null,
        'parent_entity_id': null,
        'actor_type': actorType,
        'actor_user_id': 'user-a',
        'actor_identifier': null,
        'role_key': 'manager',
        'source': 'rpc',
        'correlation_id': 'correlation-1',
        'mutation_id': 'mutation-1',
        'reason': 'Adresse korrigiert',
        'changed_fields': <String>['city', 'zip'],
      },
      <String, Object?>{
        'id': 'event-2',
        'occurred_at': '2026-09-01T09:00:00Z',
        'action': 'unit.created',
        'entity_type': 'unit',
        'entity_id': 'unit-1',
        'parent_entity_type': 'property',
        'parent_entity_id': 'property-a',
        'actor_type': 'service',
        'actor_user_id': null,
        'actor_identifier': 'system.emitter',
        'role_key': null,
        'source': 'job',
        'correlation_id': 'correlation-2',
        'mutation_id': null,
        'reason': null,
        'changed_fields': <String>[],
      },
    ],
    'next_cursor': nextCursor,
  };
}

class _FakePort implements AuditReadPort {
  final List<PropertyAuditQuery> queries = <PropertyAuditQuery>[];
  PlatformRepositoryResult<AuditEventPage> result =
      const PlatformRepositorySuccess<AuditEventPage>(
        AuditEventPage(events: <AuditEventDto>[]),
      );

  @override
  Future<PlatformRepositoryResult<AuditEventPage>> propertyAuditEvents(
    PropertyAuditQuery query,
  ) async {
    queries.add(query);
    return result;
  }

  @override
  Future<PlatformRepositoryResult<PropertyActivityPage>> propertyActivity(
    PropertyActivityQuery query,
  ) async => throw UnsupportedError('not used by this test');
}

class _FakeGateway implements PlatformSupabaseGateway {
  @override
  String? currentUserId = 'user-a';

  Object? rpcResult;
  Object? rpcError;
  String? calledFunction;
  Map<String, Object?>? parameters;

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> params) async {
    calledFunction = function;
    parameters = params;
    if (rpcError != null) {
      throw rpcError!;
    }
    return rpcResult;
  }

  // The audit read touches exactly one gateway method. Forwarding the rest to
  // a throw keeps the fake honest: if this test ever reaches another one, it
  // fails loudly instead of quietly returning an empty list.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(
        'The audit read must not call '
        '${invocation.memberName}',
      );
}
