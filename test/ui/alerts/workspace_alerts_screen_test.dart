/// ALERT-READER-01 (P-10) on screen: the workspace worklist.
///
/// The one thing that must hold here is that **the visible numbers are the
/// server's**. The list is capped, so a tile counting the rendered rows would
/// say "3 kritisch" while forty criticals sat behind the cap — and it would
/// look entirely reasonable. Every count assertion below uses a fixture where
/// the returned rows and the reported totals deliberately disagree, so a
/// client-side count cannot pass.
///
/// The second is that a refusal never looks like an empty worklist. "Nothing
/// to do today" is good news; it must not be how "you may not look" or "the
/// read broke" renders.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_providers.dart';
import 'package:neximmo_app/features/leasing_operations/application/operations_signals_contract.dart';
import 'package:neximmo_app/features/leasing_operations/domain/operations_signal_dto.dart';
import 'package:neximmo_app/ui/screens/alerts/workspace_alerts_screen.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  required _FakePort port,
  Size viewport = const Size(1200, 1000),
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        operationsSignalsProvider.overrideWithValue(port),
        workspaceSessionScopeProvider.overrideWithValue(
          WorkspaceSessionScope(
            workspaceId: 'ws-1',
            actorId: 'actor-a',
            permissions: const <String>{'lease.read'},
            mutationsSupported: true,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: WorkspaceAlertsScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the signals with the property each belongs to', (
    tester,
  ) async {
    await _pump(tester, port: _FakePort());

    expect(find.text('Vertrag läuft aus'), findsOneWidget);
    expect(find.text('Alpha-Haus'), findsOneWidget);
    expect(find.text('Langer Leerstand'), findsOneWidget);
    expect(find.text('Beta-Haus'), findsOneWidget);
  });

  testWidgets('the counts are the server\'s, not a count of the rows shown', (
    tester,
  ) async {
    // Two rows back, 40 matched, 31 of them critical. A tile counting what it
    // renders would show 1.
    await _pump(
      tester,
      port: _FakePort(
        total: 40,
        truncated: true,
        bySeverity: const <String, int>{'critical': 31, 'warning': 9},
      ),
    );

    expect(
      find.text('31'),
      findsOneWidget,
      reason: 'the server counted before it capped. Counting the two visible '
          'rows would report 1 critical while 31 exist, and the screen would '
          'look perfectly reasonable',
    );
    expect(find.text('9'), findsOneWidget);
  });

  testWidgets('says out loud when the list was capped', (tester) async {
    await _pump(
      tester,
      port: _FakePort(
        total: 40,
        truncated: true,
        bySeverity: const <String, int>{'critical': 31, 'warning': 9},
      ),
    );

    expect(
      find.byKey(const Key('workspace-alerts-truncated')),
      findsOneWidget,
    );
    expect(find.textContaining('2 von 40'), findsOneWidget);
  });

  testWidgets('and does not when everything fitted', (tester) async {
    await _pump(tester, port: _FakePort());

    // The list renders, so the absence below is about the notice and not
    // about the screen having failed to build.
    expect(find.text('Vertrag läuft aus'), findsOneWidget);
    expect(find.byKey(const Key('workspace-alerts-truncated')), findsNothing);
  });

  testWidgets('a refusal is not an empty worklist', (tester) async {
    await _pump(
      tester,
      port: _FakePort(failure: OperationsSignalsFailureKind.forbidden),
    );

    expect(
      find.byKey(const Key('workspace-alerts-forbidden')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('workspace-alerts-empty')),
      findsNothing,
      reason: '"nothing to do today" is good news, and must never be how a '
          'missing permission renders',
    );
  });

  testWidgets('a broken read is not an empty worklist either', (tester) async {
    await _pump(
      tester,
      port: _FakePort(
        failure: OperationsSignalsFailureKind.infrastructureFailure,
      ),
    );

    expect(find.byKey(const Key('workspace-alerts-error')), findsOneWidget);
    expect(find.byKey(const Key('workspace-alerts-empty')), findsNothing);
  });

  testWidgets('a genuinely empty answer says so positively', (tester) async {
    await _pump(
      tester,
      port: _FakePort(
        signals: const <OperationsSignalDto>[],
        total: 0,
        bySeverity: const <String, int>{},
      ),
    );

    expect(find.byKey(const Key('workspace-alerts-empty')), findsOneWidget);
    expect(find.byKey(const Key('workspace-alerts-error')), findsNothing);
  });

  testWidgets('changing the severity filter asks the server again', (
    tester,
  ) async {
    final port = _FakePort();
    await _pump(tester, port: port);
    expect(port.queries, hasLength(1));

    await tester.tap(find.byKey(const Key('workspace-alerts-severity')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kritisch').last);
    await tester.pumpAndSettle();

    expect(port.queries.last.severity, 'critical');
  });

  testWidgets('states when the deadlines were judged', (tester) async {
    await _pump(tester, port: _FakePort());

    expect(
      find.textContaining('Serverseitig ermittelt am'),
      findsOneWidget,
      reason: 'there is no scheduler anywhere in this product, so nothing here '
          'is a push. Saying when it was computed is the honest substitute for '
          'a promise the stack cannot keep',
    );
  });

  testWidgets('renders without overflow at a phone width', (tester) async {
    await _pump(
      tester,
      port: _FakePort(
        total: 40,
        truncated: true,
        bySeverity: const <String, int>{'critical': 31, 'warning': 9},
      ),
      viewport: const Size(360, 780),
    );

    expect(tester.takeException(), isNull);
  });
}

const List<OperationsSignalDto> _defaultSignals = <OperationsSignalDto>[
  OperationsSignalDto(
    signalKey: 'lease_expiry:-:l-1:-',
    type: 'lease_expiry',
    severity: 'critical',
    message: 'Lease Alpha expires in 20 days.',
    recommendedAction: 'Review renewal, notice and follow-up actions.',
    propertyId: 'p-1',
    propertyName: 'Alpha-Haus',
    leaseId: 'l-1',
    status: 'open',
  ),
  OperationsSignalDto(
    signalKey: 'vacancy_aged:u-1:-:-',
    type: 'vacancy_aged',
    severity: 'warning',
    message: 'Unit B-01 has been vacant for 60 days.',
    recommendedAction: 'Review marketing status, target rent and next action.',
    propertyId: 'p-2',
    propertyName: 'Beta-Haus',
    unitId: 'u-1',
    status: 'open',
  ),
];

class _FakePort implements OperationsSignalsPort {
  _FakePort({
    this.signals = _defaultSignals,
    this.total = 2,
    this.truncated = false,
    this.bySeverity = const <String, int>{'critical': 1, 'warning': 1},
    this.failure,
  });

  final List<OperationsSignalDto> signals;
  final int total;
  final bool truncated;
  final Map<String, int> bySeverity;
  final OperationsSignalsFailureKind? failure;

  final List<WorkspaceOperationsSignalsQuery> queries =
      <WorkspaceOperationsSignalsQuery>[];

  @override
  Future<OperationsSignalsResult<WorkspaceOperationsSignalsDto>> listWorkspace(
    WorkspaceOperationsSignalsQuery query,
  ) async {
    queries.add(query);
    final kind = failure;
    if (kind != null) {
      return OperationsSignalsFailure<WorkspaceOperationsSignalsDto>(
        kind: kind,
        message: 'refused',
      );
    }
    return OperationsSignalsSuccess<WorkspaceOperationsSignalsDto>(
      WorkspaceOperationsSignalsDto(
        computedAt: DateTime.utc(2026, 9, 7, 8),
        signals: signals,
        total: total,
        truncated: truncated,
        limit: 200,
        totalBySeverity: bySeverity,
      ),
    );
  }

  @override
  Future<OperationsSignalsResult<List<OperationsSignalDto>>> list(
    OperationsSignalsQuery query,
  ) async => throw UnimplementedError('list');

  @override
  Future<OperationsSignalsResult<OperationsSignalStateDto>> updateStatus(
    UpdateOperationsSignalStatusCommand command,
  ) async => throw UnimplementedError('updateStatus');
}
