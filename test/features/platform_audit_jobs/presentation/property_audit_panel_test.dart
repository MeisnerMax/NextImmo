import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/audit_read_port.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_providers.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/audit_event_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/presentation/property_audit_panel.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// The audit surface (AUDIT-01, `PROPERTY_AUDIT_V2.md`).
///
/// An audit trail earns trust by being literal, so what is pinned here is
/// mostly restraint: it shows the changed field *names* and says that it does,
/// it never renders raw JSON, and it names the actor the server named rather
/// than inventing a friendlier one.
void main() {
  testWidgets('lists events newest first with actor and time', (tester) async {
    await _pump(tester, _page());

    expect(find.byKey(const Key('property-audit-list')), findsOneWidget);
    expect(find.text('Objekt geändert'), findsOneWidget);
    expect(find.text('Fläche angelegt'), findsOneWidget);
    expect(find.textContaining('01.09.2026'), findsWidgets);
  });

  testWidgets('an event names the fields it changed, and says values are not '
      'part of the trail', (tester) async {
    await _pump(tester, _page());

    await tester.tap(find.text('Objekt geändert'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('property-audit-detail')), findsOneWidget);
    expect(find.byKey(const Key('property-audit-field-zip')), findsOneWidget);
    expect(find.byKey(const Key('property-audit-field-city')), findsOneWidget);
    expect(find.textContaining('nicht auf welchen Wert'), findsOneWidget);
    // The value itself is nowhere on the surface.
    expect(find.textContaining('10117'), findsNothing);
  });

  testWidgets('an event that changed no field says so instead of showing an '
      'empty box', (tester) async {
    await _pump(tester, _page());

    await tester.tap(find.text('Fläche angelegt'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('property-audit-no-fields')), findsOneWidget);
  });

  testWidgets('a service actor is named as one', (tester) async {
    await _pump(tester, _page());

    expect(find.textContaining('Dienst: system.emitter'), findsOneWidget);
  });

  testWidgets('an unmapped action is shown as its key rather than dropped', (
    tester,
  ) async {
    await _pump(
      tester,
      AuditEventPage(
        events: <AuditEventDto>[
          _event(id: 'event-9', action: 'insurance.renewed'),
        ],
      ),
    );

    expect(find.text('insurance.renewed'), findsOneWidget);
  });

  testWidgets('without audit.read the surface says which capability it needs', (
    tester,
  ) async {
    await _pump(
      tester,
      _page(),
      permissions: const <String>{'property.read'},
    );

    expect(find.byKey(const Key('property-audit-forbidden')), findsOneWidget);
    expect(find.textContaining('audit.read'), findsOneWidget);
  });

  testWidgets('an empty trail is stated, not shown as an error', (
    tester,
  ) async {
    await _pump(tester, const AuditEventPage(events: <AuditEventDto>[]));

    expect(find.byKey(const Key('property-audit-empty')), findsOneWidget);
  });

  testWidgets('a failed read offers a retry', (tester) async {
    await _pump(
      tester,
      _page(),
      failure: PlatformRepositoryFailureKind.infrastructureFailure,
    );

    expect(find.byKey(const Key('property-audit-error')), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('a further page is offered and appended', (tester) async {
    final port = _FakePort(
      AuditEventPage(
        events: <AuditEventDto>[_event(id: 'event-1')],
        nextCursor: AuditEventCursor(
          occurredAt: DateTime.utc(2026, 9, 1, 9),
          id: 'event-1',
        ),
      ),
    );
    await _pumpPort(tester, port);

    port.page = AuditEventPage(
      events: <AuditEventDto>[_event(id: 'event-2', action: 'property.created')],
    );
    await tester.tap(find.byKey(const Key('property-audit-load-more')));
    await tester.pumpAndSettle();

    expect(find.text('Objekt angelegt'), findsOneWidget);
    expect(find.byKey(const Key('property-audit-load-more')), findsNothing);
  });

  for (final size in const <Size>[Size(390, 844), Size(1400, 900)]) {
    testWidgets('lays out without overflow at $size', (tester) async {
      await _pump(tester, _page(), size: size);

      await tester.tap(find.text('Objekt geändert'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('property-audit-detail')), findsOneWidget);
    });
  }
}

AuditEventPage _page() => AuditEventPage(
  events: <AuditEventDto>[
    _event(
      id: 'event-1',
      changedFields: const <String>['city', 'zip'],
      reason: 'Adresse korrigiert',
    ),
    _event(
      id: 'event-2',
      action: 'unit.created',
      entityType: 'unit',
      actorType: AuditActorType.service,
      actorIdentifier: 'system.emitter',
    ),
  ],
);

AuditEventDto _event({
  required String id,
  String action = 'property.updated',
  String entityType = 'property',
  AuditActorType actorType = AuditActorType.user,
  String? actorIdentifier,
  List<String> changedFields = const <String>[],
  String? reason,
}) {
  return AuditEventDto(
    id: id,
    occurredAt: DateTime.utc(2026, 9, 1, 10),
    action: action,
    entityType: entityType,
    entityId: 'entity-$id',
    actorType: actorType,
    actorUserId: actorType == AuditActorType.user ? 'user-a' : null,
    actorIdentifier: actorIdentifier,
    roleKey: actorType == AuditActorType.user ? 'manager' : null,
    source: 'rpc',
    correlationId: 'correlation-$id',
    reason: reason,
    changedFields: changedFields,
  );
}

Future<void> _pump(
  WidgetTester tester,
  AuditEventPage page, {
  Set<String> permissions = const <String>{'property.read', 'audit.read'},
  PlatformRepositoryFailureKind? failure,
  Size size = const Size(1400, 900),
}) {
  return _pumpPort(
    tester,
    _FakePort(page, failure: failure),
    permissions: permissions,
    size: size,
  );
}

Future<void> _pumpPort(
  WidgetTester tester,
  _FakePort port, {
  Set<String> permissions = const <String>{'property.read', 'audit.read'},
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        workspaceSessionScopeProvider.overrideWithValue(
          WorkspaceSessionScope(
            workspaceId: 'workspace-a',
            actorId: 'user-a',
            permissions: permissions,
            mutationsSupported: true,
          ),
        ),
        auditReadPortProvider.overrideWithValue(port),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: PropertyAuditPanel(propertyId: 'property-a'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakePort implements AuditReadPort {
  _FakePort(this.page, {this.failure});

  AuditEventPage page;
  final PlatformRepositoryFailureKind? failure;

  @override
  Future<PlatformRepositoryResult<AuditEventPage>> propertyAuditEvents(
    PropertyAuditQuery query,
  ) async {
    final failure = this.failure;
    if (failure != null) {
      return PlatformRepositoryFailure<AuditEventPage>(
        kind: failure,
        message: 'fail',
      );
    }
    return PlatformRepositorySuccess<AuditEventPage>(page);
  }
}
