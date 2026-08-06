import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/operations_alerts_controller.dart';
import 'package:neximmo_app/features/leasing_operations/application/operations_signals_contract.dart';
import 'package:neximmo_app/features/leasing_operations/domain/operations_signal_dto.dart';

const String _workspace = 'workspace-a';
const String _propertyId = 'p1';

void main() {
  group('load', () {
    test('idle when no workspace is resolved', () async {
      final controller = _controller(workspaceId: null);
      await controller.load();

      expect(controller.state.phase, OperationsAlertsPhase.idle);
    });

    test('forbidden is distinct from error', () async {
      final controller = _controller(
        result: const OperationsSignalsFailure<List<OperationsSignalDto>>(
          kind: OperationsSignalsFailureKind.forbidden,
          message: 'no lease.read',
        ),
      );
      await controller.load();

      expect(controller.state.phase, OperationsAlertsPhase.forbidden);
    });

    test('error surfaces the adapter message', () async {
      final controller = _controller(
        result: const OperationsSignalsFailure<List<OperationsSignalDto>>(
          kind: OperationsSignalsFailureKind.infrastructureFailure,
          message: 'boom',
        ),
      );
      await controller.load();

      expect(controller.state.phase, OperationsAlertsPhase.error);
      expect(controller.state.message, 'boom');
    });

    test('summarises counts across the full unfiltered list', () async {
      final controller = _controller(
        signals: <OperationsSignalDto>[
          _signal('lease_expiry', 'critical', status: 'open'),
          _signal('vacancy_aged', 'warning', status: 'open'),
          _signal('offline_missing_reason', 'critical', status: 'resolved'),
        ],
      );
      await controller.load();

      final state = controller.state;
      expect(state.openCount, 2);
      expect(state.criticalCount, 2);
      expect(state.warningCount, 1);
      expect(state.resolvedCount, 1);
    });
  });

  group('filters', () {
    test('status filter narrows the list, default is open', () async {
      final controller = _controller(
        signals: <OperationsSignalDto>[
          _signal('lease_expiry', 'critical', status: 'open'),
          _signal('vacancy_aged', 'warning', status: 'resolved'),
        ],
      );
      await controller.load();

      expect(controller.state.filtered, hasLength(1));
      controller.setStatusFilter(statusFilterAll);
      expect(controller.state.filtered, hasLength(2));
    });

    test('severity filter', () async {
      final controller = _controller(
        signals: <OperationsSignalDto>[
          _signal('lease_expiry', 'critical', status: 'open'),
          _signal('vacancy_aged', 'warning', status: 'open'),
        ],
      );
      await controller.load();
      controller.setSeverityFilter('critical');

      expect(controller.state.filtered, hasLength(1));
      expect(controller.state.filtered.single.severity, 'critical');
    });

    test('category grouping mirrors the legacy mapping', () async {
      final controller = _controller(
        signals: <OperationsSignalDto>[
          _signal('lease_expiry', 'critical', status: 'open'),
          _signal('stale_rent_roll', 'warning', status: 'open'),
          _signal('missing_tenant_contact', 'warning', status: 'open'),
          _signal('vacancy_aged', 'warning', status: 'open'),
        ],
      );
      await controller.load();
      controller.setStatusFilter(statusFilterAll);

      expect(alertCategory(controller.state.signals[0]), 'lease');
      expect(alertCategory(controller.state.signals[1]), 'rent_roll');
      expect(alertCategory(controller.state.signals[2]), 'tenant');
      expect(alertCategory(controller.state.signals[3]), 'data_quality');
    });
  });

  group('acknowledge', () {
    test('passes the signal statusVersion straight through as expectedVersion', () async {
      final gateway = _FakeSignals(
        listResult: OperationsSignalsSuccess<List<OperationsSignalDto>>(
          <OperationsSignalDto>[_signal('lease_expiry', 'critical', status: 'open')],
        ),
      );
      final controller = _controllerWith(gateway);
      await controller.load();

      final success = await controller.acknowledge(
        signal: controller.state.signals.single,
        status: 'dismissed',
      );

      expect(success, isTrue);
      expect(gateway.lastCommand!.expectedVersion, isNull);
      expect(gateway.lastCommand!.status, 'dismissed');
    });

    test('a failed acknowledgement is surfaced without losing the list', () async {
      final gateway = _FakeSignals(
        listResult: OperationsSignalsSuccess<List<OperationsSignalDto>>(
          <OperationsSignalDto>[_signal('lease_expiry', 'critical', status: 'open')],
        ),
        updateResult: const OperationsSignalsFailure<OperationsSignalStateDto>(
          kind: OperationsSignalsFailureKind.versionConflict,
          message: 'stale version',
          versionConflict: OperationsSignalVersionConflict(expectedVersion: null),
        ),
      );
      final controller = _controllerWith(gateway);
      await controller.load();

      final success = await controller.acknowledge(
        signal: controller.state.signals.single,
        status: 'dismissed',
      );

      expect(success, isFalse);
      expect(controller.state.actionError, 'stale version');
      expect(controller.state.signals, hasLength(1));
    });

    test('a successful acknowledgement reloads the list', () async {
      final gateway = _FakeSignals(
        listResult: OperationsSignalsSuccess<List<OperationsSignalDto>>(
          <OperationsSignalDto>[_signal('lease_expiry', 'critical', status: 'open')],
        ),
      );
      final controller = _controllerWith(gateway);
      await controller.load();

      await controller.acknowledge(
        signal: controller.state.signals.single,
        status: 'resolved',
        resolutionNote: 'renewed',
      );

      expect(gateway.listCallCount, 2);
    });
  });
}

OperationsAlertsController _controller({
  String? workspaceId = _workspace,
  List<OperationsSignalDto> signals = const <OperationsSignalDto>[],
  OperationsSignalsResult<List<OperationsSignalDto>>? result,
}) {
  return _controllerWith(
    _FakeSignals(
      listResult:
          result ?? OperationsSignalsSuccess<List<OperationsSignalDto>>(signals),
    ),
    workspaceId: workspaceId,
  );
}

OperationsAlertsController _controllerWith(
  _FakeSignals gateway, {
  String? workspaceId = _workspace,
}) {
  final controller = OperationsAlertsController(
    signals: gateway,
    scope: WorkspaceSessionScope(
      workspaceId: workspaceId,
      actorId: 'actor-1',
      permissions: const <String>{'lease.read', 'lease.manage'},
      mutationsSupported: true,
    ),
    propertyId: _propertyId,
  );
  addTearDown(controller.dispose);
  return controller;
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
  _FakeSignals({required this.listResult, this.updateResult});

  final OperationsSignalsResult<List<OperationsSignalDto>> listResult;
  final OperationsSignalsResult<OperationsSignalStateDto>? updateResult;

  int listCallCount = 0;
  UpdateOperationsSignalStatusCommand? lastCommand;

  @override
  Future<OperationsSignalsResult<List<OperationsSignalDto>>> list(
    OperationsSignalsQuery query,
  ) async {
    listCallCount++;
    return listResult;
  }

  @override
  Future<OperationsSignalsResult<OperationsSignalStateDto>> updateStatus(
    UpdateOperationsSignalStatusCommand command,
  ) async {
    lastCommand = command;
    return updateResult ??
        OperationsSignalsSuccess<OperationsSignalStateDto>(
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
