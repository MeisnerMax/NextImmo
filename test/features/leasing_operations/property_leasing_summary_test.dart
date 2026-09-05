import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/components/nx_card.dart';
import 'package:neximmo_app/ui/components/nx_notice.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_providers.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/application/property_leasing_summary_controller.dart';
import 'package:neximmo_app/features/leasing_operations/data/supabase_leasing_repository_adapter.dart';
import 'package:neximmo_app/features/leasing_operations/domain/leasing_summary_dto.dart';
import 'package:neximmo_app/features/leasing_operations/presentation/property_leasing_summary_card.dart';

/// LEASING-SUMMARY-01, end to end from the RPC payload to the rendered block.
///
/// The assertions are mostly about what the surface refuses to do: invent an
/// occupancy rate, add two currencies, read a partial area sum as a complete
/// one, or turn an unrecorded vacancy start into "since today". Each of those
/// is a way this screen could quietly lie, so each has a test.

/// Replays a canned RPC response and records what was sent.
class _FakeGateway implements LeasingSupabaseGateway {
  Object? rpcResponse;
  final List<({String function, Map<String, Object?> parameters})> calls =
      <({String function, Map<String, Object?> parameters})>[];

  @override
  Future<Object?> callRpc(
    String function,
    Map<String, Object?> parameters,
  ) async {
    calls.add((function: function, parameters: parameters));
    return rpcResponse;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubPort implements PropertyLeasingSummaryPort {
  _StubPort(this.result);

  final LeasingRepositoryResult<PropertyLeasingSummaryDto> result;
  int reads = 0;

  @override
  Future<LeasingRepositoryResult<PropertyLeasingSummaryDto>> read({
    required String workspaceId,
    required String propertyId,
  }) async {
    reads++;
    return result;
  }
}

Map<String, Object?> _payload({
  Object? areaTotal = 260,
  Object? areaOccupied = 160,
  Object? areaVacant = 100,
  int unitsWithoutArea = 1,
  Object? longestVacancyDays = 100,
  int vacantWithoutSince = 1,
  List<Map<String, Object?>>? rentRoll,
}) {
  return <String, Object?>{
    'ok': true,
    'summary': <String, Object?>{
      'as_of': '2026-09-05T10:00:00Z',
      'units': <String, Object?>{
        'total': 6,
        'occupied': 4,
        'vacant': 2,
        'offline': 0,
        'area_sqm_total': areaTotal,
        'area_sqm_occupied': areaOccupied,
        'area_sqm_vacant': areaVacant,
        'units_without_area': unitsWithoutArea,
      },
      'vacancy': <String, Object?>{
        'longest_vacancy_days': longestVacancyDays,
        'vacant_without_since': vacantWithoutSince,
      },
      'lease_roll': <String, Object?>{
        'active': 4,
        'open_ended': 1,
        'expired_open': 1,
        'windows': <Map<String, Object?>>[
          <String, Object?>{'days': 30, 'label': '30 Tage', 'expiring': 1},
          <String, Object?>{'days': 90, 'label': '90 Tage', 'expiring': 1},
          <String, Object?>{'days': 180, 'label': '180 Tage', 'expiring': 2},
          <String, Object?>{'days': 365, 'label': '365 Tage', 'expiring': 2},
        ],
      },
      'decisions': <String, Object?>{
        'window_days': 90,
        'notice_due': 1,
        'renewal_option': 1,
        'break_option': 1,
      },
      'rent_roll':
          rentRoll ??
          <Map<String, Object?>>[
            <String, Object?>{
              'currency_code': 'CHF',
              'monthly_base': '900',
              'leases': 1,
            },
            <String, Object?>{
              'currency_code': 'EUR',
              'monthly_base': '3000',
              'leases': 3,
            },
          ],
    },
  };
}

PropertyLeasingSummaryDto _dto({
  num areaTotal = 260,
  num areaOccupied = 160,
  num areaVacant = 100,
  int total = 6,
  int unitsWithoutArea = 1,
  int? longestVacancyDays = 100,
  int vacantWithoutSince = 1,
  List<PropertyRentRollCurrency>? rentRoll,
}) {
  return PropertyLeasingSummaryDto(
    asOf: DateTime.utc(2026, 9, 5, 10),
    units: PropertyLeasingUnits(
      total: total,
      occupied: 4,
      vacant: 2,
      offline: 0,
      areaSqmTotal: areaTotal,
      areaSqmOccupied: areaOccupied,
      areaSqmVacant: areaVacant,
      unitsWithoutArea: unitsWithoutArea,
    ),
    vacancy: PropertyLeasingVacancy(
      longestVacancyDays: longestVacancyDays,
      vacantWithoutSince: vacantWithoutSince,
    ),
    leaseRoll: const PropertyLeaseRoll(
      active: 4,
      openEnded: 1,
      expiredOpen: 1,
      windows: <PropertyLeaseExpiryWindow>[
        PropertyLeaseExpiryWindow(days: 30, label: '30 Tage', expiring: 1),
        PropertyLeaseExpiryWindow(days: 90, label: '90 Tage', expiring: 1),
        PropertyLeaseExpiryWindow(days: 180, label: '180 Tage', expiring: 2),
        PropertyLeaseExpiryWindow(days: 365, label: '365 Tage', expiring: 2),
      ],
    ),
    decisions: const PropertyLeaseDecisions(
      windowDays: 90,
      noticeDue: 1,
      renewalOption: 1,
      breakOption: 1,
    ),
    rentRoll:
        rentRoll ??
        const <PropertyRentRollCurrency>[
          PropertyRentRollCurrency(
            currencyCode: 'CHF',
            monthlyBase: 900,
            leases: 1,
          ),
          PropertyRentRollCurrency(
            currencyCode: 'EUR',
            monthlyBase: 3000,
            leases: 3,
          ),
        ],
  );
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required PropertyLeasingSummaryPort port,
  Set<String> permissions = const <String>{'property.read', 'lease.read'},
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        propertyLeasingSummaryProvider.overrideWithValue(port),
        workspaceSessionScopeProvider.overrideWithValue(
          WorkspaceSessionScope(
            workspaceId: 'w1',
            actorId: 'u1',
            permissions: permissions,
            mutationsSupported: true,
          ),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PropertyLeasingSummaryCard(propertyId: 'p1'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _figure(WidgetTester tester, String key) {
  final semantics = tester.widget<Semantics>(find.byKey(Key(key)));
  return semantics.properties.label!;
}

void main() {
  group('Leasing summary adapter', () {
    test('maps the server payload without computing anything', () async {
      final gateway = _FakeGateway()..rpcResponse = _payload();
      final adapter = SupabasePropertyLeasingSummaryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.read(workspaceId: 'w1', propertyId: 'p1');

      expect(result, isA<LeasingRepositorySuccess<PropertyLeasingSummaryDto>>());
      final summary =
          (result as LeasingRepositorySuccess<PropertyLeasingSummaryDto>).value;
      expect(gateway.calls.single.function, 'property_leasing_summary');
      expect(gateway.calls.single.parameters, <String, Object?>{
        'p_workspace_id': 'w1',
        'p_property_id': 'p1',
      });
      expect(summary.units.total, 6);
      expect(summary.units.areaSqmOccupied, 160);
      expect(summary.units.unitsWithoutArea, 1);
      expect(summary.units.areaIsComplete, isFalse);
      expect(summary.leaseRoll.windows.map((w) => w.label), <String>[
        '30 Tage',
        '90 Tage',
        '180 Tage',
        '365 Tage',
      ]);
      expect(
        summary.rentRoll.map((entry) => entry.currencyCode),
        <String>['CHF', 'EUR'],
        reason: 'the server order is kept, not re-sorted here',
      );
    });

    test('keeps an unrecorded vacancy start null instead of zero', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = _payload(longestVacancyDays: null);
      final adapter = SupabasePropertyLeasingSummaryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.read(workspaceId: 'w1', propertyId: 'p1');

      final summary =
          (result as LeasingRepositorySuccess<PropertyLeasingSummaryDto>).value;
      expect(
        summary.vacancy.longestVacancyDays,
        isNull,
        reason: 'zero days would claim the vacancy began today',
      );
    });

    test('maps a server refusal to forbidden, not to an empty summary', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': 'forbidden',
            'message': 'Leasing access is not permitted',
          },
        };
      final adapter = SupabasePropertyLeasingSummaryAdapter.withGateway(
        gateway,
      );

      final result = await adapter.read(workspaceId: 'w1', propertyId: 'p1');

      expect(
        result,
        isA<LeasingRepositoryFailure<PropertyLeasingSummaryDto>>().having(
          (failure) => failure.kind,
          'kind',
          LeasingRepositoryFailureKind.forbidden,
        ),
      );
    });
  });

  group('Leasing summary controller', () {
    test('refuses before the round trip and names the missing capability', () async {
      final port = _StubPort(LeasingRepositorySuccess(_dto()));
      final controller = PropertyLeasingSummaryController(
        propertyId: 'p1',
        port: port,
        scope: WorkspaceSessionScope(
          workspaceId: 'w1',
          actorId: 'u1',
          permissions: <String>{'property.read'},
          mutationsSupported: true,
        ),
      );

      await controller.load();

      expect(controller.state.phase, PropertyLeasingSummaryPhase.forbidden);
      expect(controller.state.message, contains('lease.read'));
      expect(port.reads, 0, reason: 'the server would refuse anyway');
    });

    test('reports the property gate when that is the missing one', () async {
      final port = _StubPort(LeasingRepositorySuccess(_dto()));
      final controller = PropertyLeasingSummaryController(
        propertyId: 'p1',
        port: port,
        scope: WorkspaceSessionScope(
          workspaceId: 'w1',
          actorId: 'u1',
          permissions: <String>{'lease.read'},
          mutationsSupported: true,
        ),
      );

      await controller.load();

      expect(controller.state.message, contains('property.read'));
    });

    test('settles instead of spinning when no workspace is resolved', () async {
      final port = _StubPort(LeasingRepositorySuccess(_dto()));
      final controller = PropertyLeasingSummaryController(
        propertyId: 'p1',
        port: port,
        scope: const WorkspaceSessionScope.unresolved(),
      );

      await controller.load();

      expect(controller.state.phase, PropertyLeasingSummaryPhase.idle);
      expect(controller.state.isBusy, isFalse);
      expect(port.reads, 0);
    });

    testWidgets('renders nothing at all without a resolved workspace', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            propertyLeasingSummaryProvider.overrideWithValue(
              _StubPort(LeasingRepositorySuccess(_dto())),
            ),
            workspaceSessionScopeProvider.overrideWithValue(
              const WorkspaceSessionScope.unresolved(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: PropertyLeasingSummaryCard(propertyId: 'p1')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NxCard), findsNothing);
      expect(find.byType(NxNotice), findsNothing);
    });

    test('drops the summary on failure rather than showing a stale one', () async {
      final port = _StubPort(
        const LeasingRepositoryFailure<PropertyLeasingSummaryDto>(
          kind: LeasingRepositoryFailureKind.infrastructureFailure,
          message: 'kaputt',
        ),
      );
      final controller = PropertyLeasingSummaryController(
        propertyId: 'p1',
        port: port,
        scope: WorkspaceSessionScope(
          workspaceId: 'w1',
          actorId: 'u1',
          permissions: <String>{'property.read', 'lease.read'},
          mutationsSupported: true,
        ),
      );

      await controller.load();

      expect(controller.state.phase, PropertyLeasingSummaryPhase.error);
      expect(controller.state.summary, isNull);
      expect(controller.state.message, 'kaputt');
    });
  });

  group('Leasing summary card', () {
    testWidgets('shows the server windows with the server labels', (
      tester,
    ) async {
      await _pumpCard(tester, port: _StubPort(LeasingRepositorySuccess(_dto())));

      expect(
        find.byKey(const Key('property-overview-leasing-summary')),
        findsOneWidget,
      );
      expect(
        _figure(tester, 'property-overview-leasing-window-30'),
        '30 Tage: 1',
      );
      expect(
        _figure(tester, 'property-overview-leasing-window-365'),
        '365 Tage: 2',
      );
    });

    testWidgets('keeps currencies apart and offers no total', (tester) async {
      await _pumpCard(tester, port: _StubPort(LeasingRepositorySuccess(_dto())));

      expect(
        _figure(tester, 'property-overview-leasing-rent-EUR'),
        contains('EUR'),
      );
      expect(
        _figure(tester, 'property-overview-leasing-rent-CHF'),
        contains('CHF'),
      );
      expect(
        find.textContaining('3900'),
        findsNothing,
        reason: 'EUR plus CHF is a number that is wrong in both',
      );
      expect(find.text('Je Währung, nicht summiert'), findsOneWidget);
    });

    testWidgets('states the coverage of a partial area sum', (tester) async {
      await _pumpCard(tester, port: _StubPort(LeasingRepositorySuccess(_dto())));

      expect(
        _figure(tester, 'property-overview-leasing-area-occupied'),
        'Vermietet: 160 m²',
      );
      final coverage = tester.widget<Text>(
        find.byKey(const Key('property-overview-leasing-summary-coverage')),
      );
      expect(coverage.data, contains('1 von 6'));
      expect(coverage.data, contains('Teilsummen'));
    });

    testWidgets('shows a dash when no unit records an area at all', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        port: _StubPort(
          LeasingRepositorySuccess(
            _dto(
              areaTotal: 0,
              areaOccupied: 0,
              areaVacant: 0,
              unitsWithoutArea: 6,
            ),
          ),
        ),
      );

      expect(
        _figure(tester, 'property-overview-leasing-area-total'),
        'Erfasst gesamt: —',
        reason: '0 m² would read as a building with no floor space',
      );
    });

    testWidgets('reports an unrecorded vacancy start instead of a day count', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        port: _StubPort(
          LeasingRepositorySuccess(
            _dto(longestVacancyDays: null, vacantWithoutSince: 2),
          ),
        ),
      );

      expect(
        _figure(tester, 'property-overview-leasing-vacancy-longest'),
        'Längster Leerstand: —',
      );
      expect(
        _figure(tester, 'property-overview-leasing-vacancy-unknown'),
        'Ohne Beginn: 2',
      );
    });

    testWidgets('renders no occupancy rate and no renewal risk', (
      tester,
    ) async {
      await _pumpCard(tester, port: _StubPort(LeasingRepositorySuccess(_dto())));

      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('Risiko'), findsNothing);
    });

    testWidgets('names the missing capability instead of an empty exposure', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        port: _StubPort(LeasingRepositorySuccess(_dto())),
        permissions: const <String>{'property.read'},
      );

      expect(
        find.byKey(const Key('property-overview-leasing-summary-forbidden')),
        findsOneWidget,
      );
      expect(find.textContaining('lease.read'), findsOneWidget);
      expect(
        find.byKey(const Key('property-overview-leasing-summary')),
        findsNothing,
      );
    });

    testWidgets('does not re-read when it scrolls out of view and back', (
      tester,
    ) async {
      // The card lives in the overview's ListView, which disposes children
      // that leave the viewport. Its controller is autoDispose, so without a
      // keep-alive the read fires again on every scroll past it — on a phone,
      // where the block sits below the fold, that is every single scroll.
      tester.view.physicalSize = const Size(390, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final port = _StubPort(LeasingRepositorySuccess(_dto()));
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            propertyLeasingSummaryProvider.overrideWithValue(port),
            workspaceSessionScopeProvider.overrideWithValue(
              WorkspaceSessionScope(
                workspaceId: 'w1',
                actorId: 'u1',
                permissions: const <String>{'property.read', 'lease.read'},
                mutationsSupported: true,
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: const <Widget>[
                  SizedBox(height: 1200),
                  PropertyLeasingSummaryCard(propertyId: 'p1'),
                  SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -1400));
      await tester.pumpAndSettle();
      expect(port.reads, 1, reason: 'the first sighting reads once');

      await tester.drag(find.byType(ListView), const Offset(0, -1400));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 2800));
      await tester.pumpAndSettle();

      expect(
        port.reads,
        1,
        reason: 'scrolling is not a reason to ask the server again',
      );
    });

    testWidgets('offers a retry when the read failed', (tester) async {
      await _pumpCard(
        tester,
        port: _StubPort(
          const LeasingRepositoryFailure<PropertyLeasingSummaryDto>(
            kind: LeasingRepositoryFailureKind.infrastructureFailure,
            message: 'nicht erreichbar',
          ),
        ),
      );

      expect(
        find.byKey(const Key('property-overview-leasing-summary-retry')),
        findsOneWidget,
      );
      expect(find.text('nicht erreichbar'), findsOneWidget);
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

        await _pumpCard(
          tester,
          port: _StubPort(LeasingRepositorySuccess(_dto())),
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}
