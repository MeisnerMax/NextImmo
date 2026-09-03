import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/operations_alerts_controller.dart';
import 'package:neximmo_app/features/leasing_operations/application/operations_signals_contract.dart';
import 'package:neximmo_app/features/leasing_operations/domain/operations_signal_dto.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/platform_entity_type.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/task_dto.dart';
import 'package:uuid/uuid.dart';

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
    test(
      'passes the signal statusVersion straight through as expectedVersion',
      () async {
        final gateway = _FakeSignals(
          listResult: OperationsSignalsSuccess<List<OperationsSignalDto>>(
            <OperationsSignalDto>[
              _signal('lease_expiry', 'critical', status: 'open'),
            ],
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
      },
    );

    test(
      'a failed acknowledgement is surfaced without losing the list',
      () async {
        final gateway = _FakeSignals(
          listResult: OperationsSignalsSuccess<List<OperationsSignalDto>>(
            <OperationsSignalDto>[
              _signal('lease_expiry', 'critical', status: 'open'),
            ],
          ),
          updateResult:
              const OperationsSignalsFailure<OperationsSignalStateDto>(
                kind: OperationsSignalsFailureKind.versionConflict,
                message: 'stale version',
                versionConflict: OperationsSignalVersionConflict(
                  expectedVersion: null,
                ),
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
      },
    );

    test('a successful acknowledgement reloads the list', () async {
      final gateway = _FakeSignals(
        listResult: OperationsSignalsSuccess<List<OperationsSignalDto>>(
          <OperationsSignalDto>[
            _signal('lease_expiry', 'critical', status: 'open'),
          ],
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

  group('createTaskFrom', () {
    test('links the task to the lease when one is present', () async {
      final tasks = _FakeTasks();
      final controller = _controllerWith(
        _FakeSignals(
          listResult: OperationsSignalsSuccess<List<OperationsSignalDto>>(
            const [],
          ),
        ),
        tasks: tasks,
      );

      final signal = OperationsSignalDto(
        signalKey: 'lease_expiry:u1:l1:t1',
        type: 'lease_expiry',
        severity: 'critical',
        message: 'expires soon',
        recommendedAction: 'renew',
        propertyId: _propertyId,
        unitId: 'u1',
        leaseId: 'l1',
        tenantPartyId: 't1',
        status: 'open',
      );
      final success = await controller.createTaskFrom(
        signal: signal,
        title: 'Review renewal',
        mutationId: 'intent-1',
      );

      expect(success, isTrue);
      expect(tasks.lastCommand!.draft.title, 'Review renewal');
      expect(tasks.lastCommand!.draft.entity, entityRefFor(signal));
      expect(tasks.lastCommand!.draft.entity!.type, PlatformEntityType.lease);
    });

    test('keeps the caller-owned mutationId and audits the surface', () async {
      final tasks = _FakeTasks();
      final controller = _controllerWith(
        _FakeSignals(
          listResult: OperationsSignalsSuccess<List<OperationsSignalDto>>(
            const [],
          ),
        ),
        tasks: tasks,
      );
      final signal = _signal('lease_expiry', 'critical', status: 'open');

      // The intent id is owned by the dialog (shared contract §12): a second
      // submit attempt of the same intent must reach the server with the same
      // id, so the RPC replay layer converges instead of duplicating.
      await controller.createTaskFrom(
        signal: signal,
        title: 'Follow up',
        mutationId: 'intent-1',
      );
      final first = tasks.lastCommand!.context;
      await controller.createTaskFrom(
        signal: signal,
        title: 'Follow up',
        mutationId: 'intent-1',
      );
      final second = tasks.lastCommand!.context;

      expect(first.mutationId, 'intent-1');
      expect(second.mutationId, 'intent-1');
      expect(first.reason, 'Operations-Alert');
      // `create_task` types p_correlation_id as uuid; the epoch-derived
      // `oa-task-cor-…` strings of the previous implementation could never
      // reach the server.
      expect(Uuid.isValidUUID(fromString: first.correlationId), isTrue);
      expect(Uuid.isValidUUID(fromString: second.correlationId), isTrue);
      expect(first.correlationId, isNot(second.correlationId));
    });

    test('falls back to unit, then tenant, then the property itself', () {
      expect(
        entityRefFor(
          _signal('vacancy_aged', 'warning', status: 'open', unitId: 'u1'),
        ).type,
        PlatformEntityType.unit,
      );
      expect(
        entityRefFor(
          _signal(
            'missing_tenant_contact',
            'warning',
            status: 'open',
            tenantPartyId: 't1',
          ),
        ).type,
        PlatformEntityType.party,
      );
      expect(
        entityRefFor(
          _signal('stale_rent_roll', 'warning', status: 'open'),
        ).type,
        PlatformEntityType.property,
      );
    });

    test('a failed creation is surfaced without crashing', () async {
      final tasks = _FakeTasks(
        result: const PlatformRepositoryFailure<TaskDto>(
          kind: PlatformRepositoryFailureKind.dependencyConflict,
          message: 'not supported locally',
        ),
      );
      final controller = _controllerWith(
        _FakeSignals(
          listResult: OperationsSignalsSuccess<List<OperationsSignalDto>>(
            const [],
          ),
        ),
        tasks: tasks,
      );

      final success = await controller.createTaskFrom(
        signal: _signal('lease_expiry', 'critical', status: 'open'),
        title: 'Follow up',
        mutationId: 'intent-1',
      );

      expect(success, isFalse);
      expect(controller.state.actionError, 'not supported locally');
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
          result ??
          OperationsSignalsSuccess<List<OperationsSignalDto>>(signals),
    ),
    workspaceId: workspaceId,
  );
}

OperationsAlertsController _controllerWith(
  _FakeSignals gateway, {
  String? workspaceId = _workspace,
  _FakeTasks? tasks,
}) {
  final controller = OperationsAlertsController(
    signals: gateway,
    tasks: tasks ?? _FakeTasks(),
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
  String? unitId,
  String? tenantPartyId,
}) => OperationsSignalDto(
  signalKey: '$type:-:-:-',
  type: type,
  severity: severity,
  message: '$type triggered',
  recommendedAction: 'act',
  propertyId: _propertyId,
  unitId: unitId,
  tenantPartyId: tenantPartyId,
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

class _FakeTasks implements TaskRepository {
  _FakeTasks({this.result});

  final PlatformRepositoryResult<TaskDto>? result;

  CreateTaskCommand? lastCommand;

  @override
  Future<PlatformRepositoryResult<TaskDto>> createTask(
    CreateTaskCommand command,
  ) async {
    lastCommand = command;
    return result ??
        PlatformRepositorySuccess<TaskDto>(
          TaskDto(
            id: 'task-1',
            workspaceId: command.context.workspaceId,
            title: command.draft.title,
            priority: command.draft.priority,
            status: TaskStatus.open,
            createdAt: DateTime.utc(2026, 3, 31),
            updatedAt: DateTime.utc(2026, 3, 31),
            createdBy: command.context.actorId,
            updatedBy: command.context.actorId,
            version: 1,
            entity: command.draft.entity,
            description: command.draft.description,
          ),
        );
  }

  @override
  Future<PlatformRepositoryResult<PlatformPageResult<TaskDto>>> searchTasks(
    TaskListQuery query,
  ) => throw UnimplementedError();

  @override
  Future<PlatformRepositoryResult<TaskDto>> getTaskById({
    required String workspaceId,
    required String taskId,
  }) => throw UnimplementedError();

  @override
  Future<PlatformRepositoryResult<TaskDto>> updateTask(
    UpdateTaskCommand command,
  ) => throw UnimplementedError();

  @override
  Future<PlatformRepositoryResult<TaskDto>> transitionTaskStatus(
    TransitionTaskStatusCommand command,
  ) => throw UnimplementedError();
}
