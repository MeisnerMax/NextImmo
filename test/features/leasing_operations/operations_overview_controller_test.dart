import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/application/operations_overview_controller.dart';
import 'package:neximmo_app/features/leasing_operations/application/operations_signals_contract.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/operations_signal_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/rent_roll_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';

const String _workspace = 'workspace-a';
const String _propertyId = 'p1';
final DateTime _today = DateTime.utc(2026, 3, 31);

void main() {
  group('summary', () {
    test('reuses the live rent roll for occupancy and rent', () async {
      final controller = _controller(
        live: _live(unitCount: 4, occupied: 3, vacant: 1, rent: 3000),
      );
      await controller.load();

      expect(controller.state.phase, OperationsOverviewPhase.ready);
      final summary = controller.state.summary!;
      expect(summary.rentRoll.unitCount, 4);
      expect(summary.rentRoll.occupiedUnitCount, 3);
      expect(summary.rentRoll.totalBaseRentMonthly, 3000);
    });

    test('sums area only over occupied units — AGG-004 collapses the legacy split', () async {
      final controller = _controller(
        units: <UnitSummaryDto>[
          _unit('u1', UnitStatus.occupied, area: 70),
          _unit('u2', UnitStatus.vacant, area: 50),
          _unit('u3', UnitStatus.occupied, area: 30),
        ],
      );
      await controller.load();

      expect(controller.state.summary!.leasedAreaSqm, 100);
    });

    test('counts expiring leases cumulatively across the four windows', () async {
      final controller = _controller(
        leases: <LeaseSummaryDto>[
          _lease('l1', 'u1', end: _today.add(const Duration(days: 20))),
          _lease('l2', 'u2', end: _today.add(const Duration(days: 70))),
          _lease('l3', 'u3', end: _today.add(const Duration(days: 400))),
        ],
      );
      await controller.load();

      final summary = controller.state.summary!;
      expect(summary.expiringIn30Days, 1);
      expect(summary.expiringIn60Days, 1);
      expect(summary.expiringIn90Days, 2);
      expect(summary.expiringIn180Days, 2);
    });

    test('folds alerts and data-quality signals into one list (Befund 3)', () async {
      final controller = _controller(
        signals: <OperationsSignalDto>[
          _signal('lease_expiry', 'critical', status: 'open'),
          _signal('vacancy_aged', 'warning', status: 'dismissed'),
        ],
      );
      await controller.load();

      final summary = controller.state.summary!;
      expect(summary.alerts, hasLength(2));
      expect(summary.openAlertCount, 1);
      expect(summary.criticalAlertCount, 1);
      expect(summary.warningAlertCount, 1);
    });

    test('reports truncation instead of silently showing less', () async {
      final controller = _controller(
        unitSearch: _FakeUnitSearch(
          units: <UnitSummaryDto>[_unit('u1', UnitStatus.vacant)],
          alwaysMore: true,
        ),
      );
      await controller.load();

      expect(controller.state.summary!.truncated, isTrue);
      expect(controller.state.phase, OperationsOverviewPhase.ready);
    });
  });

  group('phases', () {
    test('idle when no workspace is resolved', () async {
      final controller = _controller(workspaceId: null);
      await controller.load();

      expect(controller.state.phase, OperationsOverviewPhase.idle);
    });

    test('forbidden when the live rent roll read is refused', () async {
      final controller = _controller(
        liveResult: const LeasingRepositoryFailure<RentRollLiveDto>(
          kind: LeasingRepositoryFailureKind.forbidden,
          message: 'no lease.read',
        ),
      );
      await controller.load();

      expect(controller.state.phase, OperationsOverviewPhase.forbidden);
    });

    test('forbidden when the signals read is refused', () async {
      final controller = _controller(
        signalsResult: const OperationsSignalsFailure<List<OperationsSignalDto>>(
          kind: OperationsSignalsFailureKind.forbidden,
          message: 'no lease.read',
        ),
      );
      await controller.load();

      expect(controller.state.phase, OperationsOverviewPhase.forbidden);
    });

    test('error surfaces the adapter message', () async {
      final controller = _controller(
        liveResult: const LeasingRepositoryFailure<RentRollLiveDto>(
          kind: LeasingRepositoryFailureKind.infrastructureFailure,
          message: 'boom',
        ),
      );
      await controller.load();

      expect(controller.state.phase, OperationsOverviewPhase.error);
      expect(controller.state.message, 'boom');
    });
  });
}

OperationsOverviewController _controller({
  String? workspaceId = _workspace,
  List<UnitSummaryDto> units = const <UnitSummaryDto>[],
  List<LeaseSummaryDto> leases = const <LeaseSummaryDto>[],
  List<OperationsSignalDto> signals = const <OperationsSignalDto>[],
  RentRollLiveDto? live,
  LeasingRepositoryResult<RentRollLiveDto>? liveResult,
  _FakeUnitSearch? unitSearch,
  OperationsSignalsResult<List<OperationsSignalDto>>? signalsResult,
}) {
  final controller = OperationsOverviewController(
    rentRoll: _FakeRentRoll(
      liveResult ?? LeasingRepositorySuccess<RentRollLiveDto>(live ?? _live()),
    ),
    unitSearch: unitSearch ?? _FakeUnitSearch(units: units),
    leaseSearch: _FakeLeaseSearch(leases),
    signals: _FakeSignals(
      signalsResult ??
          OperationsSignalsSuccess<List<OperationsSignalDto>>(signals),
    ),
    scope: WorkspaceSessionScope(
      workspaceId: workspaceId,
      actorId: 'actor-1',
      permissions: const <String>{'lease.read'},
      mutationsSupported: true,
    ),
    propertyId: _propertyId,
    clock: () => _today,
  );
  addTearDown(controller.dispose);
  return controller;
}

RentRollLiveDto _live({
  int unitCount = 0,
  int occupied = 0,
  int vacant = 0,
  double? rent,
}) => RentRollLiveDto(
  workspaceId: _workspace,
  propertyId: _propertyId,
  asOfDate: _today,
  computedAt: _today,
  currencies: const <String>['EUR'],
  unitCount: unitCount,
  occupiedUnitCount: occupied,
  vacantUnitCount: vacant,
  offlineUnitCount: 0,
  effectiveLeaseCount: occupied,
  lines: const <RentRollLiveLineDto>[],
  totalBaseRentMonthly: rent,
  totalRentMonthly: rent,
);

UnitSummaryDto _unit(String id, UnitStatus status, {double? area}) =>
    UnitSummaryDto(
      id: id,
      workspaceId: _workspace,
      propertyId: _propertyId,
      unitCode: id.toUpperCase(),
      status: status,
      version: 1,
      areaSqm: area,
    );

LeaseSummaryDto _lease(String id, String unitId, {DateTime? end}) =>
    LeaseSummaryDto(
      id: id,
      workspaceId: _workspace,
      propertyId: _propertyId,
      unitId: unitId,
      leaseName: id.toUpperCase(),
      status: LeaseStatus.active,
      startDate: DateTime.utc(2020, 1, 1),
      endDate: end,
      baseRentMonthly: 1000,
      currencyCode: 'EUR',
      version: 1,
    );

OperationsSignalDto _signal(
  String type,
  String severity, {
  required String status,
}) => OperationsSignalDto(
  signalKey: '$type:-:-:-',
  type: type,
  severity: severity,
  message: 'message',
  recommendedAction: 'action',
  propertyId: _propertyId,
  status: status,
);

class _FakeRentRoll implements RentRollPort {
  _FakeRentRoll(this.liveResult);

  final LeasingRepositoryResult<RentRollLiveDto> liveResult;

  @override
  Future<LeasingRepositoryResult<RentRollLiveDto>> readLive({
    required String workspaceId,
    required String propertyId,
    required DateTime asOfDate,
  }) async => liveResult;

  @override
  Future<LeasingRepositoryResult<RentRollSnapshotDto>> getSnapshot({
    required String workspaceId,
    required String snapshotId,
  }) => throw UnimplementedError();

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<RentRollSnapshotDto>>>
  listSnapshots(RentRollSnapshotListQuery query) => throw UnimplementedError();

  @override
  Future<LeasingRepositoryResult<RentRollSnapshotDto>> createSnapshot(
    CreateRentRollSnapshotCommand command,
  ) => throw UnimplementedError();
}

class _FakeUnitSearch implements UnitSearchPort {
  _FakeUnitSearch({required this.units, this.alwaysMore = false});

  final List<UnitSummaryDto> units;
  final bool alwaysMore;

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<UnitSummaryDto>>> search(
    UnitListQuery query,
  ) async {
    return LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>(
      LeasingPageResult<UnitSummaryDto>(
        items: query.page.cursor == null || alwaysMore
            ? units
            : const <UnitSummaryDto>[],
        nextCursor: alwaysMore ? 'next' : null,
      ),
    );
  }
}

class _FakeLeaseSearch implements LeaseSearchPort {
  _FakeLeaseSearch(this.leases);

  final List<LeaseSummaryDto> leases;

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<LeaseSummaryDto>>> search(
    LeaseListQuery query,
  ) async {
    return LeasingRepositorySuccess<LeasingPageResult<LeaseSummaryDto>>(
      LeasingPageResult<LeaseSummaryDto>(items: leases),
    );
  }
}

class _FakeSignals implements OperationsSignalsPort {
  _FakeSignals(this.result);

  final OperationsSignalsResult<List<OperationsSignalDto>> result;

  @override
  Future<OperationsSignalsResult<List<OperationsSignalDto>>> list(
    OperationsSignalsQuery query,
  ) async => result;

  @override
  Future<OperationsSignalsResult<OperationsSignalStateDto>> updateStatus(
    UpdateOperationsSignalStatusCommand command,
  ) => throw UnimplementedError();
}
