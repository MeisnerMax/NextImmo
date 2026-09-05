import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/audit_read_port.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_providers.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/property_activity_controller.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/audit_event_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/property_activity_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/presentation/property_activity_panel.dart';

/// PROPERTY-ACTIVITY-01, from the query the port sends to the sentence the
/// timeline renders.
///
/// Most of these assertions are about restraint. The chronicle must not name a
/// colleague it was not told to name, must not quietly file an unknown event
/// under a domain, must not filter in memory, and must not let a partial
/// coverage read as a complete history.

class _StubPort implements AuditReadPort {
  _StubPort(this.result);

  PlatformRepositoryResult<PropertyActivityPage> result;
  final List<PropertyActivityQuery> queries = <PropertyActivityQuery>[];

  @override
  Future<PlatformRepositoryResult<PropertyActivityPage>> propertyActivity(
    PropertyActivityQuery query,
  ) async {
    queries.add(query);
    return result;
  }

  @override
  Future<PlatformRepositoryResult<AuditEventPage>> propertyAuditEvents(
    PropertyAuditQuery query,
  ) async => throw UnsupportedError('not used by this test');
}

PropertyActivityEventDto _event({
  String id = 'e1',
  String entityType = 'lease',
  String action = 'update',
  PropertyActivityDomain? domain = PropertyActivityDomain.leasing,
  String? domainKey = 'leasing',
  AuditActorType actorType = AuditActorType.user,
  bool actorIsSelf = false,
  String? actorUserId,
  DateTime? occurredAt,
}) {
  return PropertyActivityEventDto(
    id: id,
    occurredAt: occurredAt ?? DateTime.utc(2026, 9, 5, 10),
    eventKey: '$entityType.$action',
    entityType: entityType,
    action: action,
    domain: domain,
    domainKey: domainKey,
    entityId: 'entity-$id',
    actorType: actorType,
    actorIsSelf: actorIsSelf,
    actorUserId: actorUserId,
  );
}

PropertyActivityPage _page({
  List<PropertyActivityEventDto>? events,
  Set<PropertyActivityDomain> visibleDomains = const <PropertyActivityDomain>{
    PropertyActivityDomain.property,
    PropertyActivityDomain.leasing,
  },
  List<String> unknownDomainKeys = const <String>[],
  bool actorNamesVisible = false,
  PropertyActivityCursor? nextCursor,
}) {
  return PropertyActivityPage(
    events: events ?? <PropertyActivityEventDto>[_event()],
    asOf: DateTime.utc(2026, 9, 5, 12),
    visibleDomains: visibleDomains,
    unknownDomainKeys: unknownDomainKeys,
    actorNamesVisible: actorNamesVisible,
    nextCursor: nextCursor,
  );
}

PropertyActivityController _controller(
  _StubPort port, {
  Set<String> permissions = const <String>{'property.read'},
  String? workspaceId = 'w1',
}) {
  return PropertyActivityController(
    propertyId: 'p1',
    readPort: port,
    scope: workspaceId == null
        ? const WorkspaceSessionScope.unresolved()
        : WorkspaceSessionScope(
            workspaceId: workspaceId,
            actorId: 'u1',
            permissions: permissions,
            mutationsSupported: true,
          ),
  );
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required _StubPort port,
  Set<String> permissions = const <String>{'property.read'},
  void Function(PropertyActivityEventDto)? onOpenRecord,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        auditReadPortProvider.overrideWithValue(port),
        workspaceSessionScopeProvider.overrideWithValue(
          WorkspaceSessionScope(
            workspaceId: 'w1',
            actorId: 'u1',
            permissions: permissions,
            mutationsSupported: true,
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PropertyActivityPanel(
            propertyId: 'p1',
            onOpenRecord: onOpenRecord,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Activity domain mapping', () {
    test('an unknown domain key stays unknown instead of being bucketed', () {
      expect(propertyActivityDomainFromWire('leasing'),
          PropertyActivityDomain.leasing);
      expect(
        propertyActivityDomainFromWire('procurement'),
        isNull,
        reason: 'filing a stranger under property would put it in this '
            'building\'s history',
      );
    });

    test('every domain round-trips through its wire key', () {
      for (final domain in PropertyActivityDomain.values) {
        expect(
          propertyActivityDomainFromWire(propertyActivityDomainToWire(domain)),
          domain,
        );
      }
    });
  });

  group('Activity controller', () {
    test('settles instead of spinning without a resolved workspace', () async {
      final port = _StubPort(PlatformRepositorySuccess(_page()));
      final controller = _controller(port, workspaceId: null);

      await controller.load();

      expect(controller.state.phase, PropertyActivityPhase.idle);
      expect(port.queries, isEmpty);
    });

    test('refuses before the round trip without property.read', () async {
      final port = _StubPort(PlatformRepositorySuccess(_page()));
      final controller = _controller(port, permissions: const <String>{});

      await controller.load();

      expect(controller.state.phase, PropertyActivityPhase.forbidden);
      expect(port.queries, isEmpty);
    });

    test('carries the coverage the server reported, not its own', () async {
      final port = _StubPort(PlatformRepositorySuccess(_page()));
      final controller = _controller(
        port,
        // A permission set that would suggest wider coverage if the client
        // computed it. The server's answer wins.
        permissions: const <String>{'property.read', 'lease.read', 'task.read'},
      );

      await controller.load();

      expect(controller.state.visibleDomains, <PropertyActivityDomain>{
        PropertyActivityDomain.property,
        PropertyActivityDomain.leasing,
      });
      expect(controller.state.coverageIsPartial, isTrue);
    });

    test('sends the domain filter to the server, and drops loaded pages', () async {
      final port = _StubPort(PlatformRepositorySuccess(_page()));
      final controller = _controller(port);
      await controller.load();

      await controller.toggleDomain(PropertyActivityDomain.leasing);

      expect(port.queries.length, 2);
      expect(port.queries.last.domains, <PropertyActivityDomain>{
        PropertyActivityDomain.leasing,
      });
      expect(
        port.queries.last.cursor,
        isNull,
        reason: 'a new filter starts a new keyset, never continues the old one',
      );
    });

    test('an empty filtered page is a no-match, an empty unfiltered one is empty',
        () async {
      final port = _StubPort(
        PlatformRepositorySuccess(_page(events: <PropertyActivityEventDto>[])),
      );
      final controller = _controller(port);

      await controller.load();
      expect(controller.state.phase, PropertyActivityPhase.empty);

      await controller.toggleDomain(PropertyActivityDomain.leasing);
      expect(controller.state.phase, PropertyActivityPhase.noMatch);
    });

    test('a failed continuation keeps the loaded events', () async {
      final port = _StubPort(
        PlatformRepositorySuccess(
          _page(
            nextCursor: PropertyActivityCursor(
              occurredAt: DateTime.utc(2026, 9, 5, 9),
              id: 'e1',
            ),
          ),
        ),
      );
      final controller = _controller(port);
      await controller.load();

      port.result = const PlatformRepositoryFailure<PropertyActivityPage>(
        kind: PlatformRepositoryFailureKind.infrastructureFailure,
        message: 'nicht erreichbar',
      );
      await controller.loadMore();

      expect(controller.state.events, hasLength(1));
      expect(controller.state.loadMoreMessage, 'nicht erreichbar');
      expect(controller.state.phase, PropertyActivityPhase.ready);
    });

    test('a duplicate id from an overlapping page is not appended twice', () async {
      final port = _StubPort(
        PlatformRepositorySuccess(
          _page(
            nextCursor: PropertyActivityCursor(
              occurredAt: DateTime.utc(2026, 9, 5, 9),
              id: 'e1',
            ),
          ),
        ),
      );
      final controller = _controller(port);
      await controller.load();

      port.result = PlatformRepositorySuccess(
        _page(
          events: <PropertyActivityEventDto>[_event(), _event(id: 'e2')],
        ),
      );
      await controller.loadMore();

      expect(controller.state.events.map((event) => event.id), <String>[
        'e1',
        'e2',
      ]);
    });
  });

  group('Activity panel', () {
    testWidgets('renders one sentence per event, grouped by day', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        port: _StubPort(
          PlatformRepositorySuccess(
            _page(
              events: <PropertyActivityEventDto>[
                _event(occurredAt: DateTime.utc(2026, 9, 5, 10)),
                _event(
                  id: 'e2',
                  entityType: 'maintenance_ticket',
                  action: 'transition',
                  domain: PropertyActivityDomain.maintenance,
                  domainKey: 'maintenance',
                  occurredAt: DateTime.utc(2026, 9, 4, 10),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('property-activity')), findsOneWidget);
      expect(find.text('Vertrag geändert'), findsOneWidget);
      expect(find.text('Wartungsticket im Status geändert'), findsOneWidget);
      expect(find.byKey(const Key('property-activity-event-e1')), findsOneWidget);
      expect(find.byKey(const Key('property-activity-event-e2')), findsOneWidget);
    });

    testWidgets('an event this build cannot name is shown as its key', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        port: _StubPort(
          PlatformRepositorySuccess(
            _page(
              events: <PropertyActivityEventDto>[
                _event(entityType: 'inspection', action: 'schedule',
                    domain: null, domainKey: 'facility'),
              ],
            ),
          ),
        ),
      );

      expect(
        find.text('inspection.schedule'),
        findsOneWidget,
        reason: 'dropping it would make the history look complete when it is '
            'not',
      );
      expect(find.textContaining('facility'), findsOneWidget);
    });

    testWidgets('names an actor only when the server allowed it', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        port: _StubPort(
          PlatformRepositorySuccess(
            _page(
              events: <PropertyActivityEventDto>[
                _event(actorUserId: 'user-9'),
              ],
            ),
          ),
        ),
      );

      expect(find.textContaining('durch ein Mitglied'), findsOneWidget);
      expect(find.textContaining('user-9'), findsNothing);
    });

    testWidgets('marks the reader\'s own change as theirs', (tester) async {
      await _pumpPanel(
        tester,
        port: _StubPort(
          PlatformRepositorySuccess(
            _page(
              events: <PropertyActivityEventDto>[_event(actorIsSelf: true)],
            ),
          ),
        ),
      );

      expect(find.textContaining('durch Sie'), findsOneWidget);
    });

    testWidgets('a system actor is reported as automatic, not as a person', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        port: _StubPort(
          PlatformRepositorySuccess(
            _page(
              events: <PropertyActivityEventDto>[
                _event(actorType: AuditActorType.system),
              ],
            ),
          ),
        ),
      );

      expect(find.textContaining('automatisch'), findsOneWidget);
    });

    testWidgets('a partial coverage is stated, never counted', (tester) async {
      await _pumpPanel(
        tester,
        port: _StubPort(PlatformRepositorySuccess(_page())),
      );

      final coverage = tester.widget<Text>(
        find.byKey(const Key('property-activity-coverage')),
      );
      expect(coverage.data, contains('Objekt'));
      expect(coverage.data, contains('Vermietung'));
      expect(
        coverage.data,
        isNot(contains('ausgeblendet')),
        reason: 'a count of records someone else may read is still a '
            'disclosure',
      );
    });

    testWidgets('a single visible domain offers no filter', (tester) async {
      await _pumpPanel(
        tester,
        port: _StubPort(
          PlatformRepositorySuccess(
            _page(
              visibleDomains: const <PropertyActivityDomain>{
                PropertyActivityDomain.property,
              },
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('property-activity-filter')), findsNothing);
    });

    testWidgets('the filter offers only the domains the caller can see', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        port: _StubPort(PlatformRepositorySuccess(_page())),
      );

      expect(
        find.byKey(const Key('property-activity-filter-leasing')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('property-activity-filter-documents')),
        findsNothing,
        reason: 'a chip for a domain that would return nothing is a promise '
            'the timeline cannot keep',
      );
    });

    testWidgets('rows are inert without a drilldown', (tester) async {
      await _pumpPanel(
        tester,
        port: _StubPort(PlatformRepositorySuccess(_page())),
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('property-activity-event-e1')),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });

    testWidgets('a drilldown reports the event it was invoked on', (
      tester,
    ) async {
      final opened = <String>[];
      await _pumpPanel(
        tester,
        port: _StubPort(PlatformRepositorySuccess(_page())),
        onOpenRecord: (event) => opened.add(event.id),
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('property-activity-event-e1')),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();

      expect(opened, <String>['e1']);
    });

    testWidgets('a refusal names the capability', (tester) async {
      await _pumpPanel(
        tester,
        port: _StubPort(
          const PlatformRepositoryFailure<PropertyActivityPage>(
            kind: PlatformRepositoryFailureKind.forbidden,
            message: 'nope',
          ),
        ),
      );

      expect(
        find.byKey(const Key('property-activity-forbidden')),
        findsOneWidget,
      );
      expect(find.textContaining('property.read'), findsOneWidget);
    });

    for (final size in const <Size>[
      Size(320, 700),
      Size(390, 844),
      Size(768, 1024),
      Size(1440, 900),
    ]) {
      testWidgets('has no overflow at $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpPanel(
          tester,
          port: _StubPort(PlatformRepositorySuccess(_page())),
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}
