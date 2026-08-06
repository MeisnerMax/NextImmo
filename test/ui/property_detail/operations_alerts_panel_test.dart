import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_providers.dart';
import 'package:neximmo_app/features/leasing_operations/application/operations_signals_contract.dart';
import 'package:neximmo_app/features/leasing_operations/domain/operations_signal_dto.dart';
import 'package:neximmo_app/ui/screens/property_detail/leasing/operations_alerts_panel.dart';

const String _workspace = 'workspace-a';
const String _propertyId = 'p1';

void main() {
  testWidgets('shows open alerts by default with severity and status', (
    tester,
  ) async {
    await _pump(
      tester,
      signals: <OperationsSignalDto>[
        _signal('lease_expiry', 'critical', status: 'open'),
        _signal('vacancy_aged', 'warning', status: 'resolved'),
      ],
    );

    expect(find.text('lease_expiry triggered'), findsOneWidget);
    expect(find.text('vacancy_aged triggered'), findsNothing);
    expect(find.text('CRITICAL'), findsOneWidget);
  });

  testWidgets('dismiss calls updateStatus with dismissed', (tester) async {
    final gateway = _FakeSignals(
      signals: <OperationsSignalDto>[
        _signal('lease_expiry', 'critical', status: 'open'),
      ],
    );
    await _pump(tester, gateway: gateway);

    await tester.tap(find.text('Verwerfen'));
    await tester.pumpAndSettle();

    expect(gateway.lastCommand?.status, 'dismissed');
  });

  testWidgets('resolve opens a note dialog and submits it', (tester) async {
    final gateway = _FakeSignals(
      signals: <OperationsSignalDto>[
        _signal('lease_expiry', 'critical', status: 'open'),
      ],
    );
    await _pump(tester, gateway: gateway);

    await tester.tap(find.text('Auflösen').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'renewed');
    await tester.tap(find.text('Auflösen').last);
    await tester.pumpAndSettle();

    expect(gateway.lastCommand?.status, 'resolved');
    expect(gateway.lastCommand?.resolutionNote, 'renewed');
  });

  testWidgets('forbidden is its own state', (tester) async {
    await _pump(
      tester,
      listResult: const OperationsSignalsFailure<List<OperationsSignalDto>>(
        kind: OperationsSignalsFailureKind.forbidden,
        message: 'no lease.read',
      ),
    );

    expect(
      find.text('Kein Zugriff auf die operativen Hinweise'),
      findsOneWidget,
    );
  });

  testWidgets('an error offers a retry, not a raw exception', (tester) async {
    await _pump(
      tester,
      listResult: const OperationsSignalsFailure<List<OperationsSignalDto>>(
        kind: OperationsSignalsFailureKind.infrastructureFailure,
        message: 'boom',
      ),
    );

    expect(find.text('Hinweise konnten nicht geladen werden'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  for (final size in const <Size>[
    Size(390, 844),
    Size(1024, 768),
    Size(1440, 900),
  ]) {
    testWidgets('renders without overflow at ${size.width.toInt()} px', (
      tester,
    ) async {
      await _pump(
        tester,
        size: size,
        signals: <OperationsSignalDto>[
          _signal('lease_expiry', 'critical', status: 'open'),
          _signal('stale_rent_roll', 'warning', status: 'open'),
        ],
      );

      expect(find.text('Operative Hinweise'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester, {
  List<OperationsSignalDto> signals = const <OperationsSignalDto>[],
  OperationsSignalsResult<List<OperationsSignalDto>>? listResult,
  _FakeSignals? gateway,
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final resolvedGateway =
      gateway ??
      _FakeSignals(
        signals: signals,
        listResult: listResult,
      );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        workspaceSessionScopeProvider.overrideWithValue(
          WorkspaceSessionScope(
            workspaceId: _workspace,
            actorId: 'actor-1',
            permissions: const <String>{'lease.read', 'lease.manage'},
            mutationsSupported: true,
          ),
        ),
        operationsSignalsProvider.overrideWithValue(resolvedGateway),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: OperationsAlertsPanel(propertyId: _propertyId),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

OperationsSignalDto _signal(
  String type,
  String severity, {
  required String status,
}) => OperationsSignalDto(
  signalKey: '$type:-:-:-',
  type: type,
  severity: severity,
  message: '$type triggered',
  recommendedAction: 'act',
  propertyId: _propertyId,
  status: status,
);

class _FakeSignals implements OperationsSignalsPort {
  _FakeSignals({
    this.signals = const <OperationsSignalDto>[],
    OperationsSignalsResult<List<OperationsSignalDto>>? listResult,
  }) : listResult =
           listResult ??
           OperationsSignalsSuccess<List<OperationsSignalDto>>(signals);

  final List<OperationsSignalDto> signals;
  final OperationsSignalsResult<List<OperationsSignalDto>> listResult;

  UpdateOperationsSignalStatusCommand? lastCommand;

  @override
  Future<OperationsSignalsResult<List<OperationsSignalDto>>> list(
    OperationsSignalsQuery query,
  ) async => listResult;

  @override
  Future<OperationsSignalsResult<OperationsSignalStateDto>> updateStatus(
    UpdateOperationsSignalStatusCommand command,
  ) async {
    lastCommand = command;
    return OperationsSignalsSuccess<OperationsSignalStateDto>(
      OperationsSignalStateDto(
        id: 'state-1',
        workspaceId: command.context.workspaceId,
        propertyId: command.propertyId,
        signalType: command.signalType,
        signalKey: command.signalKey,
        status: command.status,
        resolutionNote: command.resolutionNote,
        version: 1,
        createdAt: DateTime.utc(2026, 3, 31),
        updatedAt: DateTime.utc(2026, 3, 31),
        createdBy: command.context.actorId,
        updatedBy: command.context.actorId,
      ),
    );
  }
}
