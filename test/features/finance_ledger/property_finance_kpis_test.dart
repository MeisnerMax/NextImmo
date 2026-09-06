import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/finance_ledger/application/finance_ledger_port.dart';
import 'package:neximmo_app/features/finance_ledger/application/finance_providers.dart';
import 'package:neximmo_app/features/finance_ledger/application/property_finance_kpis_controller.dart';
import 'package:neximmo_app/features/finance_ledger/data/supabase_finance_ledger_adapter.dart';
import 'package:neximmo_app/features/finance_ledger/domain/finance_kpi_dto.dart';
import 'package:neximmo_app/features/finance_ledger/presentation/property_finance_kpi_section.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';

/// FINANCE-01b on the client.
///
/// The assertions cluster on two things the surface must not get wrong: every
/// figure shows the definition version that produced it, and the three empty
/// answers stay three different messages. Collapsing "nothing defined" and
/// "defined but unmatched" into one blank panel would send somebody hunting
/// through bookings for a problem that lives in the definition catalogue.

class _FakeGateway implements FinanceSupabaseGateway {
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
}

class _StubPort implements PropertyFinanceKpisPort {
  _StubPort(this.result);

  FinanceRepositoryResult<PropertyFinanceKpisDto> result;
  final List<FinancePeriodRange> ranges = <FinancePeriodRange>[];

  @override
  Future<FinanceRepositoryResult<PropertyFinanceKpisDto>> read({
    required String workspaceId,
    required String propertyId,
    FinancePeriodRange range = const FinancePeriodRange.unbounded(),
  }) async {
    ranges.add(range);
    return result;
  }
}

Map<String, Object?> _payload({
  List<Map<String, Object?>>? values,
  int activeDefinitions = 1,
  bool isProvisional = false,
}) {
  return <String, Object?>{
    'ok': true,
    'as_of': '2026-09-06T10:00:00Z',
    'values':
        values ??
        <Map<String, Object?>>[
          <String, Object?>{
            'kpi_key': 'noi',
            'definition_id': 'd1',
            'definition_version': 2,
            'name': 'Net Operating Income',
            'currency_code': 'EUR',
            'value': '750.00',
            'entries': 2,
          },
        ],
    'is_provisional': isProvisional,
    'open_periods': isProvisional ? 1 : 0,
    'covered_periods': 2,
    'active_definitions': activeDefinitions,
  };
}

PropertyFinanceKpisDto _dto({
  List<FinanceKpiValue>? values,
  int activeDefinitions = 1,
  bool isProvisional = false,
}) {
  return PropertyFinanceKpisDto(
    asOf: DateTime.utc(2026, 9, 6, 10),
    values:
        values ??
        const <FinanceKpiValue>[
          FinanceKpiValue(
            kpiKey: 'noi',
            definitionId: 'd1',
            definitionVersion: 2,
            name: 'Net Operating Income',
            currencyCode: 'EUR',
            value: 750,
            entries: 2,
          ),
        ],
    isProvisional: isProvisional,
    openPeriods: isProvisional ? 1 : 0,
    coveredPeriods: 2,
    activeDefinitions: activeDefinitions,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required _StubPort port,
  Set<String> permissions = const <String>{'property.read', 'finance.read'},
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        propertyFinanceKpisProvider.overrideWithValue(port),
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
            child: PropertyFinanceKpiSection(propertyId: 'p1'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _tile(WidgetTester tester, String key) {
  final semantics = tester.widget<Semantics>(find.byKey(Key(key)));
  return semantics.properties.label!;
}

void main() {
  group('KPI adapter', () {
    test('maps values and the two counts that explain an empty list', () async {
      final gateway = _FakeGateway()..rpcResponse = _payload();
      final adapter = SupabaseFinanceKpisAdapter.withGateway(gateway);

      final result = await adapter.read(workspaceId: 'w1', propertyId: 'p1');

      final kpis =
          (result as FinanceRepositorySuccess<PropertyFinanceKpisDto>).value;
      expect(gateway.calls.single.function, 'property_finance_kpis');
      expect(kpis.values.single.definitionVersion, 2);
      expect(kpis.values.single.value, 750);
      expect(kpis.activeDefinitions, 1);
      expect(kpis.hasDefinitions, isTrue);
    });

    test('refuses a value whose definition version is missing', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = _payload(
          values: <Map<String, Object?>>[
            <String, Object?>{
              'kpi_key': 'noi',
              'definition_id': 'd1',
              // no definition_version
              'name': 'Net Operating Income',
              'currency_code': 'EUR',
              'value': '750.00',
              'entries': 2,
            },
          ],
        );
      final adapter = SupabaseFinanceKpisAdapter.withGateway(gateway);

      final result = await adapter.read(workspaceId: 'w1', propertyId: 'p1');

      expect(
        result,
        isA<FinanceRepositoryFailure<PropertyFinanceKpisDto>>(),
        reason: 'a figure that cannot name its own meaning must not be shown; '
            'the parse fails rather than defaulting the version',
      );
    });

    test('keeps two currencies apart', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = _payload(
          values: <Map<String, Object?>>[
            <String, Object?>{
              'kpi_key': 'noi',
              'definition_id': 'd1',
              'definition_version': 2,
              'name': 'NOI',
              'currency_code': 'EUR',
              'value': '750.00',
              'entries': 2,
            },
            <String, Object?>{
              'kpi_key': 'noi',
              'definition_id': 'd1',
              'definition_version': 2,
              'name': 'NOI',
              'currency_code': 'CHF',
              'value': '900.00',
              'entries': 1,
            },
          ],
        );
      final adapter = SupabaseFinanceKpisAdapter.withGateway(gateway);

      final result = await adapter.read(workspaceId: 'w1', propertyId: 'p1');

      final kpis =
          (result as FinanceRepositorySuccess<PropertyFinanceKpisDto>).value;
      expect(kpis.currencies, <String>['EUR', 'CHF']);
      expect(kpis.valuesIn('CHF').single.value, 900);
    });
  });

  group('KPI controller', () {
    test('tells "nothing defined" apart from "defined but unmatched"', () async {
      final undefined = _StubPort(
        FinanceRepositorySuccess(
          _dto(values: const <FinanceKpiValue>[], activeDefinitions: 0),
        ),
      );
      final unmatched = _StubPort(
        FinanceRepositorySuccess(
          _dto(values: const <FinanceKpiValue>[], activeDefinitions: 3),
        ),
      );

      final a = PropertyFinanceKpisController(
        propertyId: 'p1',
        port: undefined,
        scope: WorkspaceSessionScope(
          workspaceId: 'w1',
          actorId: 'u1',
          permissions: const <String>{'property.read', 'finance.read'},
          mutationsSupported: true,
        ),
      );
      final b = PropertyFinanceKpisController(
        propertyId: 'p1',
        port: unmatched,
        scope: WorkspaceSessionScope(
          workspaceId: 'w1',
          actorId: 'u1',
          permissions: const <String>{'property.read', 'finance.read'},
          mutationsSupported: true,
        ),
      );

      await a.load();
      await b.load();

      expect(a.state.phase, PropertyFinanceKpisPhase.undefined);
      expect(b.state.phase, PropertyFinanceKpisPhase.noMatch);
    });

    test('settles instead of spinning without a resolved workspace', () async {
      final port = _StubPort(FinanceRepositorySuccess(_dto()));
      final controller = PropertyFinanceKpisController(
        propertyId: 'p1',
        port: port,
        scope: const WorkspaceSessionScope.unresolved(),
      );

      await controller.load();

      expect(controller.state.phase, PropertyFinanceKpisPhase.idle);
      expect(port.ranges, isEmpty);
    });
  });

  group('KPI section', () {
    testWidgets('shows the figure with the definition version that made it', (
      tester,
    ) async {
      await _pump(tester, port: _StubPort(FinanceRepositorySuccess(_dto())));

      final label = _tile(tester, 'property-finance-kpi-noi-EUR');
      expect(label, contains('750,00 EUR'));
      expect(
        label,
        contains('Definition Version 2'),
        reason: 'two people comparing a number across a quarter need to see '
            'that the meaning changed between them',
      );
      expect(find.textContaining('Definition v2'), findsOneWidget);
    });

    testWidgets('explains that nothing is defined, and who may define it', (
      tester,
    ) async {
      await _pump(
        tester,
        port: _StubPort(
          FinanceRepositorySuccess(
            _dto(values: const <FinanceKpiValue>[], activeDefinitions: 0),
          ),
        ),
      );

      expect(
        find.byKey(const Key('property-finance-kpis-undefined')),
        findsOneWidget,
      );
      expect(find.textContaining('finance.close'), findsOneWidget);
      expect(
        find.byKey(const Key('property-finance-kpis-no-match')),
        findsNothing,
      );
    });

    testWidgets('says when definitions exist but matched nothing', (
      tester,
    ) async {
      await _pump(
        tester,
        port: _StubPort(
          FinanceRepositorySuccess(
            _dto(values: const <FinanceKpiValue>[], activeDefinitions: 3),
          ),
        ),
      );

      expect(
        find.byKey(const Key('property-finance-kpis-no-match')),
        findsOneWidget,
      );
      expect(find.textContaining('3 aktive Definitionen'), findsOneWidget);
      expect(
        find.textContaining('keine Null'),
        findsOneWidget,
        reason: 'nothing to compute is not a computed zero',
      );
    });

    testWidgets('marks provisional figures as provisional', (tester) async {
      await _pump(
        tester,
        port: _StubPort(FinanceRepositorySuccess(_dto(isProvisional: true))),
      );

      expect(
        find.byKey(const Key('property-finance-kpis-provisional')),
        findsOneWidget,
      );
    });

    testWidgets('stays silent when the caller may not read finance', (
      tester,
    ) async {
      await _pump(
        tester,
        port: _StubPort(FinanceRepositorySuccess(_dto())),
        permissions: const <String>{'property.read'},
      );

      // The actuals panel below reports the same refusal; saying it twice
      // teaches nothing.
      expect(find.byType(Card), findsNothing);
      expect(
        find.byKey(const Key('property-finance-kpis-undefined')),
        findsNothing,
      );
    });

    testWidgets('a failed KPI read does not claim the bookings failed', (
      tester,
    ) async {
      await _pump(
        tester,
        port: _StubPort(
          const FinanceRepositoryFailure<PropertyFinanceKpisDto>(
            kind: FinanceRepositoryFailureKind.infrastructureFailure,
            message: 'nicht erreichbar',
          ),
        ),
      );

      expect(
        find.byKey(const Key('property-finance-kpis-error')),
        findsOneWidget,
      );
      expect(find.textContaining('nicht betroffen'), findsOneWidget);
    });

    for (final size in const <Size>[
      Size(320, 700),
      Size(390, 844),
      Size(1440, 900),
    ]) {
      testWidgets('has no overflow at $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pump(
          tester,
          port: _StubPort(
            FinanceRepositorySuccess(
              _dto(
                values: const <FinanceKpiValue>[
                  FinanceKpiValue(
                    kpiKey: 'noi',
                    definitionId: 'd1',
                    definitionVersion: 2,
                    name: 'Net Operating Income nach Sonderaufwand',
                    currencyCode: 'EUR',
                    value: 1234567.89,
                    entries: 42,
                  ),
                  FinanceKpiValue(
                    kpiKey: 'noi',
                    definitionId: 'd1',
                    definitionVersion: 2,
                    name: 'Net Operating Income nach Sonderaufwand',
                    currencyCode: 'CHF',
                    value: 987654.32,
                    entries: 17,
                  ),
                ],
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}
