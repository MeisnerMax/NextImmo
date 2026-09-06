import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/finance_ledger/application/finance_ledger_port.dart';
import 'package:neximmo_app/features/finance_ledger/application/finance_providers.dart';
import 'package:neximmo_app/features/finance_ledger/application/property_finance_controller.dart';
import 'package:neximmo_app/features/finance_ledger/data/supabase_finance_ledger_adapter.dart';
import 'package:neximmo_app/features/finance_ledger/domain/finance_actuals_dto.dart';
import 'package:neximmo_app/features/finance_ledger/presentation/property_finance_panel.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';

/// FINANCE-01a on the client, from the RPC payload to the rendered statement.
///
/// The assertions are mostly about what the screen refuses to produce: a net
/// result, a cross-currency total, or a figure that hides how provisional it
/// is. Each of those is a way this surface could quietly turn booked facts
/// into an unreproducible claim.

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

class _StubPort implements PropertyFinanceActualsPort {
  _StubPort(this.result);

  FinanceRepositoryResult<PropertyFinanceActualsDto> result;
  final List<FinancePeriodRange> ranges = <FinancePeriodRange>[];

  @override
  Future<FinanceRepositoryResult<PropertyFinanceActualsDto>> read({
    required String workspaceId,
    required String propertyId,
    FinancePeriodRange range = const FinancePeriodRange.unbounded(),
  }) async {
    ranges.add(range);
    return result;
  }
}

Map<String, Object?> _payload({
  List<Map<String, Object?>>? accounts,
  List<Map<String, Object?>>? periods,
  bool isProvisional = true,
  int openPeriods = 1,
  int coveredPeriods = 2,
}) {
  return <String, Object?>{
    'ok': true,
    'as_of': '2026-09-06T10:00:00Z',
    'accounts':
        accounts ??
        <Map<String, Object?>>[
          <String, Object?>{
            'account_id': 'a1',
            'account_code': '4000',
            'account_name': 'Mieterträge',
            'account_type': 'income',
            'currency_code': 'EUR',
            'amount': '1000.00',
            'entries': 2,
          },
          <String, Object?>{
            'account_id': 'a2',
            'account_code': '5000',
            'account_name': 'Betriebskosten',
            'account_type': 'expense',
            'currency_code': 'EUR',
            'amount': '250.00',
            'entries': 1,
          },
          <String, Object?>{
            'account_id': 'a1',
            'account_code': '4000',
            'account_name': 'Mieterträge',
            'account_type': 'income',
            'currency_code': 'CHF',
            'amount': '900.00',
            'entries': 1,
          },
        ],
    'periods':
        periods ??
        <Map<String, Object?>>[
          <String, Object?>{
            'period_id': 'p1',
            'fiscal_year': 2026,
            'period_month': 1,
            'status': 'closed',
            'entries': 2,
          },
          <String, Object?>{
            'period_id': 'p2',
            'fiscal_year': 2026,
            'period_month': 2,
            'status': 'open',
            'entries': 1,
          },
        ],
    'is_provisional': isProvisional,
    'open_periods': openPeriods,
    'covered_periods': coveredPeriods,
  };
}

PropertyFinanceActualsDto _dto({
  List<FinanceActualLine>? lines,
  bool isProvisional = true,
  int openPeriods = 1,
  int coveredPeriods = 2,
}) {
  return PropertyFinanceActualsDto(
    asOf: DateTime.utc(2026, 9, 6, 10),
    lines:
        lines ??
        const <FinanceActualLine>[
          FinanceActualLine(
            accountId: 'a1',
            accountCode: '4000',
            accountName: 'Mieterträge',
            accountType: FinanceAccountType.income,
            accountTypeKey: 'income',
            currencyCode: 'EUR',
            amount: 1000,
            entries: 2,
          ),
          FinanceActualLine(
            accountId: 'a2',
            accountCode: '5000',
            accountName: 'Betriebskosten',
            accountType: FinanceAccountType.expense,
            accountTypeKey: 'expense',
            currencyCode: 'EUR',
            amount: 250,
            entries: 1,
          ),
          FinanceActualLine(
            accountId: 'a1',
            accountCode: '4000',
            accountName: 'Mieterträge',
            accountType: FinanceAccountType.income,
            accountTypeKey: 'income',
            currencyCode: 'CHF',
            amount: 900,
            entries: 1,
          ),
        ],
    periods: const <FinancePeriodCoverage>[
      FinancePeriodCoverage(
        periodId: 'p1',
        fiscalYear: 2026,
        periodMonth: 1,
        status: FinancePeriodStatus.closed,
        entries: 2,
      ),
      FinancePeriodCoverage(
        periodId: 'p2',
        fiscalYear: 2026,
        periodMonth: 2,
        status: FinancePeriodStatus.open,
        entries: 1,
      ),
    ],
    isProvisional: isProvisional,
    openPeriods: openPeriods,
    coveredPeriods: coveredPeriods,
  );
}

PropertyFinanceController _controller(
  _StubPort port, {
  Set<String> permissions = const <String>{'property.read', 'finance.read'},
  String? workspaceId = 'w1',
}) {
  return PropertyFinanceController(
    propertyId: 'p1',
    port: port,
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
  Set<String> permissions = const <String>{'property.read', 'finance.read'},
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        propertyFinanceActualsProvider.overrideWithValue(port),
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
        home: Scaffold(body: PropertyFinancePanel(propertyId: 'p1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _figure(WidgetTester tester, String key) {
  final semantics = tester.widget<Semantics>(find.byKey(Key(key)));
  return semantics.properties.label!;
}

/// The statement is a lazily-built `ListView`, so anything below the fold has
/// to be scrolled to before it exists at all.
Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.descendant(
      of: find.byKey(const Key('property-finance')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Finance actuals adapter', () {
    test('maps the payload and keeps numeric precision from the string', () async {
      final gateway = _FakeGateway()..rpcResponse = _payload();
      final adapter = SupabaseFinanceLedgerAdapter.withGateway(gateway);

      final result = await adapter.read(workspaceId: 'w1', propertyId: 'p1');

      expect(result, isA<FinanceRepositorySuccess<PropertyFinanceActualsDto>>());
      final actuals =
          (result as FinanceRepositorySuccess<PropertyFinanceActualsDto>).value;
      expect(gateway.calls.single.function, 'property_finance_actuals');
      expect(actuals.lines, hasLength(3));
      expect(actuals.lines.first.amount, 1000);
      expect(actuals.isProvisional, isTrue);
      expect(actuals.openPeriods, 1);
      expect(actuals.currencies, <String>['EUR', 'CHF']);
    });

    test('sends the period range the caller asked for', () async {
      final gateway = _FakeGateway()..rpcResponse = _payload();
      final adapter = SupabaseFinanceLedgerAdapter.withGateway(gateway);

      await adapter.read(
        workspaceId: 'w1',
        propertyId: 'p1',
        range: const FinancePeriodRange(fromYear: 2026, toYear: 2026, toMonth: 6),
      );

      expect(gateway.calls.single.parameters['p_from_year'], 2026);
      expect(gateway.calls.single.parameters['p_to_month'], 6);
    });

    test('an unknown account class keeps its key instead of being folded', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = _payload(
          accounts: <Map<String, Object?>>[
            <String, Object?>{
              'account_id': 'a9',
              'account_code': '9000',
              'account_name': 'Sonderposten',
              'account_type': 'provision',
              'currency_code': 'EUR',
              'amount': '10.00',
              'entries': 1,
            },
          ],
        );
      final adapter = SupabaseFinanceLedgerAdapter.withGateway(gateway);

      final result = await adapter.read(workspaceId: 'w1', propertyId: 'p1');

      final actuals =
          (result as FinanceRepositorySuccess<PropertyFinanceActualsDto>).value;
      expect(actuals.lines.single.accountType, FinanceAccountType.unknown);
      expect(actuals.lines.single.accountTypeKey, 'provision');
    });

    test('an unrecognised period status reads as open, never as closed', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = _payload(
          periods: <Map<String, Object?>>[
            <String, Object?>{
              'period_id': 'p1',
              'fiscal_year': 2026,
              'period_month': 1,
              'status': 'locked',
              'entries': 1,
            },
          ],
        );
      final adapter = SupabaseFinanceLedgerAdapter.withGateway(gateway);

      final result = await adapter.read(workspaceId: 'w1', propertyId: 'p1');

      final actuals =
          (result as FinanceRepositorySuccess<PropertyFinanceActualsDto>).value;
      expect(
        actuals.periods.single.isClosed,
        isFalse,
        reason: 'treating an unknown state as final would let a provisional '
            'figure pass for a settled one',
      );
    });

    test('maps a refusal to forbidden, not to an empty statement', () async {
      final gateway = _FakeGateway()
        ..rpcResponse = <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': 'forbidden',
            'message': 'Finance access is not permitted',
          },
        };
      final adapter = SupabaseFinanceLedgerAdapter.withGateway(gateway);

      final result = await adapter.read(workspaceId: 'w1', propertyId: 'p1');

      expect(
        result,
        isA<FinanceRepositoryFailure<PropertyFinanceActualsDto>>().having(
          (failure) => failure.kind,
          'kind',
          FinanceRepositoryFailureKind.forbidden,
        ),
      );
    });
  });

  group('Finance DTO', () {
    test('subtotals within one class and one currency, and nowhere else', () {
      final actuals = _dto();

      expect(
        actuals.subtotalOf(FinanceAccountType.income, 'EUR'),
        1000,
      );
      expect(
        actuals.subtotalOf(FinanceAccountType.income, 'CHF'),
        900,
        reason: 'the same account in another currency is its own subtotal',
      );
      expect(actuals.subtotalOf(FinanceAccountType.expense, 'EUR'), 250);
    });
  });

  group('Finance controller', () {
    test('settles instead of spinning without a resolved workspace', () async {
      final port = _StubPort(FinanceRepositorySuccess(_dto()));
      final controller = _controller(port, workspaceId: null);

      await controller.load();

      expect(controller.state.phase, PropertyFinancePhase.idle);
      expect(port.ranges, isEmpty);
    });

    test('names the missing capability before the round trip', () async {
      final port = _StubPort(FinanceRepositorySuccess(_dto()));
      final controller = _controller(
        port,
        permissions: const <String>{'property.read'},
      );

      await controller.load();

      expect(controller.state.phase, PropertyFinancePhase.forbidden);
      expect(controller.state.message, contains('finance.read'));
      expect(port.ranges, isEmpty);
    });

    test('an empty statement is empty, not a zero-valued one', () async {
      final port = _StubPort(
        FinanceRepositorySuccess(_dto(lines: const <FinanceActualLine>[])),
      );
      final controller = _controller(port);

      await controller.load();

      expect(controller.state.phase, PropertyFinancePhase.empty);
    });

    test('a period filter goes to the server and drops the old statement', () async {
      final port = _StubPort(FinanceRepositorySuccess(_dto()));
      final controller = _controller(port);
      await controller.load();

      await controller.setRange(
        const FinancePeriodRange(fromYear: 2026, fromMonth: 1),
      );

      expect(port.ranges, hasLength(2));
      expect(port.ranges.last.fromYear, 2026);
      expect(port.ranges.last.fromMonth, 1);
    });
  });

  group('Finance panel', () {
    testWidgets('shows one section per currency and never a combined total', (
      tester,
    ) async {
      await _pumpPanel(tester, port: _StubPort(FinanceRepositorySuccess(_dto())));

      expect(
        find.byKey(const Key('property-finance-currency-EUR')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('property-finance-currency-CHF')),
        findsOneWidget,
      );
      expect(
        find.textContaining('1900'),
        findsNothing,
        reason: '1000 EUR plus 900 CHF is a number that is wrong in both',
      );
    });

    testWidgets('subtotals each class but subtracts nothing', (tester) async {
      await _pumpPanel(tester, port: _StubPort(FinanceRepositorySuccess(_dto())));

      expect(
        _figure(tester, 'property-finance-subtotal-income-EUR'),
        contains('1000,00 EUR'),
      );
      expect(
        _figure(tester, 'property-finance-subtotal-expense-EUR'),
        contains('250,00 EUR'),
      );
      expect(
        find.textContaining('750'),
        findsNothing,
        reason: 'a net result is a formula and needs a definition version',
      );
      expect(find.textContaining('NOI'), findsNothing);
    });

    testWidgets('says the figures are provisional and how provisional', (
      tester,
    ) async {
      await _pumpPanel(tester, port: _StubPort(FinanceRepositorySuccess(_dto())));

      expect(
        find.byKey(const Key('property-finance-provisional')),
        findsOneWidget,
      );
      expect(find.textContaining('1 von 2'), findsOneWidget);
    });

    testWidgets('drops the provisional notice when every period is closed', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        port: _StubPort(
          FinanceRepositorySuccess(
            _dto(isProvisional: false, openPeriods: 0, coveredPeriods: 2),
          ),
        ),
      );

      expect(
        find.byKey(const Key('property-finance-provisional')),
        findsNothing,
      );
    });

    testWidgets('reports each covered period with its own status', (
      tester,
    ) async {
      await _pumpPanel(tester, port: _StubPort(FinanceRepositorySuccess(_dto())));
      await _reveal(tester, find.byKey(const Key('property-finance-periods')));

      expect(
        _figure(tester, 'property-finance-period-p1'),
        contains('abgeschlossen'),
      );
      expect(_figure(tester, 'property-finance-period-p2'), contains('offen'));
    });

    testWidgets('names on screen what it does not yet compute', (tester) async {
      await _pumpPanel(tester, port: _StubPort(FinanceRepositorySuccess(_dto())));
      await _reveal(tester, find.byKey(const Key('property-finance-scope')));

      expect(find.byKey(const Key('property-finance-scope')), findsOneWidget);
      expect(find.textContaining('FINANCE-01b'), findsOneWidget);
    });

    testWidgets('an empty statement says nothing is booked, not that it is zero', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        port: _StubPort(
          FinanceRepositorySuccess(_dto(lines: const <FinanceActualLine>[])),
        ),
      );

      expect(find.byKey(const Key('property-finance-empty')), findsOneWidget);
      expect(find.textContaining('keine Null'), findsOneWidget);
    });

    testWidgets('a refusal names the capability', (tester) async {
      await _pumpPanel(
        tester,
        port: _StubPort(FinanceRepositorySuccess(_dto())),
        permissions: const <String>{'property.read'},
      );

      expect(
        find.byKey(const Key('property-finance-forbidden')),
        findsOneWidget,
      );
      expect(find.textContaining('finance.read'), findsOneWidget);
    });

    testWidgets('offers a retry when the read failed', (tester) async {
      await _pumpPanel(
        tester,
        port: _StubPort(
          const FinanceRepositoryFailure<PropertyFinanceActualsDto>(
            kind: FinanceRepositoryFailureKind.infrastructureFailure,
            message: 'nicht erreichbar',
          ),
        ),
      );

      expect(find.byKey(const Key('property-finance-error')), findsOneWidget);
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

        await _pumpPanel(
          tester,
          port: _StubPort(FinanceRepositorySuccess(_dto())),
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}
