import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_query_invalidation_source.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/application/rent_roll_controller.dart';
import 'package:neximmo_app/features/leasing_operations/domain/rent_roll_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';

const String _workspace = 'workspace-a';
const String _property = 'property-a';
final DateTime _today = DateTime.utc(2026, 3, 31);

void main() {
  group('the live half', () {
    test('is one server-side read, not a client computation', () async {
      final port = _FakeRentRoll()..live = _live();
      final controller = _controller(rentRoll: port);
      await controller.load();

      expect(port.liveCalls, 1);
      expect(port.lastLivePropertyId, _property);
      expect(port.lastLiveAsOfDate, _today);
      expect(controller.state.livePhase, RentRollLivePhase.ready);
      expect(controller.state.live?.lines, hasLength(1));
    });

    test('a property without units is empty, not an error', () async {
      final port = _FakeRentRoll()
        ..live = _live(lines: const <RentRollLiveLineDto>[]);
      final controller = _controller(rentRoll: port);
      await controller.load();

      expect(controller.state.livePhase, RentRollLivePhase.empty);
    });

    test('forbidden is distinct from error', () async {
      final port = _FakeRentRoll()
        ..liveFailure = LeasingRepositoryFailureKind.forbidden;
      final controller = _controller(rentRoll: port);
      await controller.load();

      expect(controller.state.livePhase, RentRollLivePhase.forbidden);
      expect(controller.state.live, isNull);
    });

    test('an unreadable live document fails rather than showing zeros',
        () async {
      // A rent roll that could not be read is not a rent roll of zeros.
      final port = _FakeRentRoll()
        ..liveFailure = LeasingRepositoryFailureKind.infrastructureFailure;
      final controller = _controller(rentRoll: port);
      await controller.load();

      expect(controller.state.livePhase, RentRollLivePhase.error);
      expect(controller.state.live, isNull);
    });

    test('stays readable when the frozen half is not', () async {
      // The point of splitting the two: a backend that cannot serve frozen
      // snapshots still answers the live question.
      final port = _FakeRentRoll()
        ..live = _live()
        ..listFailure = LeasingRepositoryFailureKind.dependencyConflict;
      final controller = _controller(rentRoll: port);
      await controller.load();

      expect(controller.state.livePhase, RentRollLivePhase.ready);
      expect(controller.state.historyPhase, RentRollHistoryPhase.unsupported);
      expect(controller.state.historyMessage, isNotNull);
    });

    test('surfaces the occupied-but-outside-term rows the backend marked',
        () async {
      final port = _FakeRentRoll()
        ..live = _live(
          lines: <RentRollLiveLineDto>[
            _liveLine('A-01', status: UnitStatus.occupied, leaseCount: 0),
            _liveLine('A-02', status: UnitStatus.occupied),
          ],
        );
      final controller = _controller(rentRoll: port);
      await controller.load();

      expect(controller.state.occupiedOutsideTermRows, hasLength(1));
      expect(controller.state.occupiedOutsideTermRows.single.unitCode, 'A-01');
    });
  });

  group('the frozen half', () {
    test('an empty history is its own phase, not an error', () async {
      final controller = _controller();
      await controller.load();

      expect(controller.state.historyPhase, RentRollHistoryPhase.empty);
    });

    test('forbidden is distinct from error', () async {
      final port = _FakeRentRoll()
        ..listFailure = LeasingRepositoryFailureKind.forbidden;
      final controller = _controller(rentRoll: port);
      await controller.load();

      expect(controller.state.historyPhase, RentRollHistoryPhase.forbidden);
    });

    test('several snapshots may share a reporting date', () async {
      final port = _FakeRentRoll()
        ..snapshots = <RentRollSnapshotDto>[
          _snapshot('s2', generatedAt: DateTime.utc(2026, 4, 2)),
          _snapshot('s1', generatedAt: DateTime.utc(2026, 4, 1)),
        ];
      final controller = _controller(rentRoll: port);
      await controller.load();

      expect(controller.state.snapshots, hasLength(2));
      expect(
        controller.state.snapshots.map((snapshot) => snapshot.asOfDate).toSet(),
        hasLength(1),
      );
    });

    test('reads the full document with its lines', () async {
      final port = _FakeRentRoll()
        ..snapshot = _snapshot(
          's1',
          lines: <RentRollSnapshotLineDto>[_line('l1', 'A-01')],
        );
      final controller = _controller(rentRoll: port);

      await controller.select('s1');

      expect(controller.state.detailPhase, RentRollDetailPhase.ready);
      expect(controller.state.selectedSnapshot?.lines, hasLength(1));
    });

    test('a missing snapshot is notFound, not a generic error', () async {
      final port = _FakeRentRoll()
        ..getFailure = LeasingRepositoryFailureKind.notFound;
      final controller = _controller(rentRoll: port);

      await controller.select('s1');

      expect(controller.state.detailPhase, RentRollDetailPhase.notFound);
    });
  });

  group('freezing a snapshot', () {
    test('freezes it and says a correction is a new snapshot', () async {
      final port = _FakeRentRoll();
      final controller = _controller(rentRoll: port);

      await controller.createSnapshot(asOfDate: _today);

      expect(port.lastCommand?.asOfDate, _today);
      expect(port.lastCommand?.currencyCode, isNull);
      expect(controller.state.actionPhase, RentRollActionPhase.succeeded);
      expect(controller.state.actionMessage, contains('neuer Snapshot'));
    });

    test('passes an explicit currency through for the fully vacant case',
        () async {
      final port = _FakeRentRoll();
      final controller = _controller(rentRoll: port);

      await controller.createSnapshot(asOfDate: _today, currencyCode: 'CHF');

      expect(port.lastCommand?.currencyCode, 'CHF');
    });

    test('a currency mismatch carries the currencies actually found', () async {
      final port = _FakeRentRoll()
        ..createResult = const LeasingRepositoryFailure<RentRollSnapshotDto>(
          kind: LeasingRepositoryFailureKind.currencyMismatch,
          message: 'The contributing leases do not share one currency',
          currencyMismatch: RentRollCurrencyMismatch(
            currencies: <String>['CHF', 'EUR'],
          ),
        );
      final controller = _controller(rentRoll: port);

      await controller.createSnapshot(asOfDate: _today);

      expect(controller.state.actionPhase, RentRollActionPhase.currencyMismatch);
      expect(
        controller.state.currencyMismatch?.currencies,
        <String>['CHF', 'EUR'],
      );
    });

    test('a read-only backend blocks freezing but says the live view stays',
        () async {
      final port = _FakeRentRoll();
      final controller = _controller(
        rentRoll: port,
        scope: _scope(mutationsSupported: false),
      );

      await controller.createSnapshot(asOfDate: _today);

      expect(controller.state.actionPhase, RentRollActionPhase.readOnly);
      expect(controller.state.actionMessage, contains('Live-Tabelle'));
      expect(port.createCalls, 0);
    });

    test('a missing permission answers forbidden, distinct from readOnly',
        () async {
      final port = _FakeRentRoll();
      final controller = _controller(
        rentRoll: port,
        scope: _scope(permissions: const <String>{'lease.read'}),
      );

      await controller.createSnapshot(asOfDate: _today);

      expect(controller.state.actionPhase, RentRollActionPhase.forbidden);
      expect(port.createCalls, 0);
    });
  });

  group('realtime', () {
    test('a lease change refetches the live table once', () async {
      // Live is current state, so unit and lease events now matter here — and
      // one command touching both must still cause a single refetch.
      final source = _FakeInvalidationSource();
      final port = _FakeRentRoll()..live = _live();
      final controller = _controller(
        rentRoll: port,
        invalidationSource: source,
        coalesceWindow: const Duration(milliseconds: 20),
      );
      await controller.load();
      final before = port.liveCalls;

      source.emit(
        const LeasingQueryInvalidation(
          workspaceId: _workspace,
          aggregate: LeasingAggregate.lease,
          entityId: 'l1',
        ),
      );
      source.emit(
        const LeasingQueryInvalidation(
          workspaceId: _workspace,
          aggregate: LeasingAggregate.unit,
          entityId: 'u1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(port.liveCalls - before, 1);
    });

    test('ignores pipeline events, which change nothing here', () async {
      final source = _FakeInvalidationSource();
      final port = _FakeRentRoll()..live = _live();
      final controller = _controller(
        rentRoll: port,
        invalidationSource: source,
        coalesceWindow: const Duration(milliseconds: 20),
      );
      await controller.load();
      final before = port.liveCalls;

      source.emit(
        const LeasingQueryInvalidation(
          workspaceId: _workspace,
          aggregate: LeasingAggregate.leasingCase,
          entityId: 'c1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(port.liveCalls - before, 0);
    });
  });
}

RentRollController _controller({
  _FakeRentRoll? rentRoll,
  WorkspaceSessionScope? scope,
  LeasingQueryInvalidationSource? invalidationSource,
  Duration coalesceWindow = const Duration(milliseconds: 250),
}) {
  var counter = 0;
  final controller = RentRollController(
    rentRoll: rentRoll ?? _FakeRentRoll(),
    scope: scope ?? _scope(),
    propertyId: _property,
    invalidationSource: invalidationSource,
    idFactory: () => 'id-${counter++}',
    clock: () => _today,
    invalidationCoalesceWindow: coalesceWindow,
  );
  addTearDown(controller.dispose);
  return controller;
}

WorkspaceSessionScope _scope({
  bool mutationsSupported = true,
  Set<String> permissions = const <String>{'lease.read', 'lease.manage'},
}) {
  return WorkspaceSessionScope(
    workspaceId: _workspace,
    actorId: 'actor-1',
    permissions: permissions,
    mutationsSupported: mutationsSupported,
  );
}



RentRollSnapshotDto _snapshot(
  String id, {
  DateTime? generatedAt,
  List<RentRollSnapshotLineDto> lines = const <RentRollSnapshotLineDto>[],
}) => RentRollSnapshotDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  asOfDate: _today,
  currencyCode: 'EUR',
  generatedAt: generatedAt ?? DateTime.utc(2026, 4, 1),
  unitCount: 2,
  occupiedUnitCount: 1,
  vacantUnitCount: 1,
  offlineUnitCount: 0,
  effectiveLeaseCount: 1,
  totalBaseRentMonthly: 1000,
  totalAncillaryChargesMonthly: 100,
  totalParkingOtherChargesMonthly: 0,
  totalRentMonthly: 1100,
  createdAt: DateTime.utc(2026, 4, 1),
  createdBy: 'actor-1',
  lines: lines,
);

RentRollSnapshotLineDto _line(String id, String unitCode) =>
    RentRollSnapshotLineDto(
  id: id,
  unitId: 'u-$id',
  unitCode: unitCode,
  unitStatus: UnitStatus.occupied,
  effectiveLeaseCount: 1,
  baseRentMonthly: 1000,
  ancillaryChargesMonthly: 100,
  parkingOtherChargesMonthly: 0,
  totalRentMonthly: 1100,
);



RentRollLiveDto _live({
  List<RentRollLiveLineDto>? lines,
  List<String> currencies = const <String>['EUR'],
}) => RentRollLiveDto(
  workspaceId: _workspace,
  propertyId: _property,
  asOfDate: _today,
  computedAt: DateTime.utc(2026, 3, 31, 12),
  currencies: currencies,
  unitCount: (lines ?? <RentRollLiveLineDto>[_liveLine('A-01')]).length,
  occupiedUnitCount: 1,
  vacantUnitCount: 0,
  offlineUnitCount: 0,
  effectiveLeaseCount: 1,
  totalBaseRentMonthly: 1000,
  totalAncillaryChargesMonthly: 100,
  totalParkingOtherChargesMonthly: 0,
  totalRentMonthly: 1100,
  lines: lines ?? <RentRollLiveLineDto>[_liveLine('A-01')],
);

RentRollLiveLineDto _liveLine(
  String unitCode, {
  UnitStatus status = UnitStatus.occupied,
  int leaseCount = 1,
}) => RentRollLiveLineDto(
  unitId: 'u-$unitCode',
  unitCode: unitCode,
  unitStatus: status,
  effectiveLeaseCount: leaseCount,
  baseRentMonthly: leaseCount == 0 ? 0 : 1000,
  ancillaryChargesMonthly: leaseCount == 0 ? 0 : 100,
  parkingOtherChargesMonthly: 0,
  totalRentMonthly: leaseCount == 0 ? 0 : 1100,
  currencies: leaseCount == 0 ? const <String>[] : const <String>['EUR'],
  areaSqm: 60,
);

class _FakeRentRoll implements RentRollPort {
  RentRollLiveDto? live;
  LeasingRepositoryFailureKind? liveFailure;
  int liveCalls = 0;
  String? lastLivePropertyId;
  DateTime? lastLiveAsOfDate;

  @override
  Future<LeasingRepositoryResult<RentRollLiveDto>> readLive({
    required String workspaceId,
    required String propertyId,
    required DateTime asOfDate,
  }) async {
    liveCalls++;
    lastLivePropertyId = propertyId;
    lastLiveAsOfDate = asOfDate;
    final kind = liveFailure;
    if (kind != null) {
      return LeasingRepositoryFailure<RentRollLiveDto>(
        kind: kind,
        message: 'failed',
      );
    }
    return LeasingRepositorySuccess<RentRollLiveDto>(live ?? _live());
  }

  List<RentRollSnapshotDto> snapshots = const <RentRollSnapshotDto>[];
  RentRollSnapshotDto? snapshot;
  LeasingRepositoryFailureKind? listFailure;
  LeasingRepositoryFailureKind? getFailure;
  LeasingRepositoryResult<RentRollSnapshotDto>? createResult;
  CreateRentRollSnapshotCommand? lastCommand;
  int listCalls = 0;
  int createCalls = 0;

  @override
  Future<LeasingRepositoryResult<RentRollSnapshotDto>> getSnapshot({
    required String workspaceId,
    required String snapshotId,
  }) async {
    final kind = getFailure;
    if (kind != null) {
      return LeasingRepositoryFailure<RentRollSnapshotDto>(
        kind: kind,
        message: 'failed',
      );
    }
    return LeasingRepositorySuccess<RentRollSnapshotDto>(
      snapshot ?? _snapshot(snapshotId),
    );
  }

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<RentRollSnapshotDto>>>
  listSnapshots(RentRollSnapshotListQuery query) async {
    listCalls++;
    final kind = listFailure;
    if (kind != null) {
      return LeasingRepositoryFailure<LeasingPageResult<RentRollSnapshotDto>>(
        kind: kind,
        message: 'this backend cannot express the document',
      );
    }
    return LeasingRepositorySuccess<LeasingPageResult<RentRollSnapshotDto>>(
      LeasingPageResult<RentRollSnapshotDto>(items: snapshots),
    );
  }

  @override
  Future<LeasingRepositoryResult<RentRollSnapshotDto>> createSnapshot(
    CreateRentRollSnapshotCommand command,
  ) async {
    createCalls++;
    lastCommand = command;
    return createResult ??
        LeasingRepositorySuccess<RentRollSnapshotDto>(_snapshot('s-new'));
  }
}

class _FakeInvalidationSource implements LeasingQueryInvalidationSource {
  final StreamController<LeasingQueryInvalidation> _controller =
      StreamController<LeasingQueryInvalidation>.broadcast();

  void emit(LeasingQueryInvalidation invalidation) =>
      _controller.add(invalidation);

  @override
  Stream<LeasingQueryInvalidation> watchWorkspace({
    required String workspaceId,
  }) => _controller.stream;
}
