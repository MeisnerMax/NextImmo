import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_providers.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/application/operations_signals_contract.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/operations_signal_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/rent_roll_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';
import 'package:neximmo_app/ui/screens/property_detail/leasing/operations_overview_panel.dart';

const String _workspace = 'workspace-a';
const String _propertyId = 'p1';

void main() {
  testWidgets('shows occupancy, area and alert counts', (tester) async {
    await _pump(
      tester,
      live: _live(unitCount: 2, occupied: 1, vacant: 1, rent: 1200),
      units: <UnitSummaryDto>[
        _unit('u1', UnitStatus.occupied, area: 70),
        _unit('u2', UnitStatus.vacant, area: 50),
      ],
      signals: <OperationsSignalDto>[
        _signal('lease_expiry', 'critical'),
      ],
    );

    expect(find.text('Betriebsübersicht'), findsOneWidget);
    expect(find.text('70.0 m²'), findsOneWidget);
    expect(find.text('1200.00 EUR'), findsOneWidget);
    expect(find.textContaining('1 kritisch'), findsOneWidget);
  });

  testWidgets('forbidden is its own state', (tester) async {
    await _pump(
      tester,
      liveResult: const LeasingRepositoryFailure<RentRollLiveDto>(
        kind: LeasingRepositoryFailureKind.forbidden,
        message: 'no lease.read',
      ),
    );

    expect(find.text('Kein Zugriff auf die Betriebsübersicht'), findsOneWidget);
  });

  testWidgets('an error offers a retry, not a raw exception', (tester) async {
    await _pump(
      tester,
      liveResult: const LeasingRepositoryFailure<RentRollLiveDto>(
        kind: LeasingRepositoryFailureKind.infrastructureFailure,
        message: 'boom',
      ),
    );

    expect(
      find.text('Betriebsübersicht konnte nicht geladen werden'),
      findsOneWidget,
    );
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('a truncated read says so, not silently fewer numbers', (
    tester,
  ) async {
    await _pump(tester, unitAlwaysMore: true);

    expect(find.text('Nur ein Teil des Objekts'), findsOneWidget);
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
        live: _live(unitCount: 3, occupied: 2, vacant: 1, rent: 2400),
        signals: <OperationsSignalDto>[
          _signal('lease_expiry', 'critical'),
          _signal('stale_rent_roll', 'warning'),
        ],
      );

      expect(find.text('Betriebsübersicht'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester, {
  RentRollLiveDto? live,
  LeasingRepositoryResult<RentRollLiveDto>? liveResult,
  List<UnitSummaryDto> units = const <UnitSummaryDto>[],
  bool unitAlwaysMore = false,
  List<OperationsSignalDto> signals = const <OperationsSignalDto>[],
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
            workspaceId: _workspace,
            actorId: 'actor-1',
            permissions: const <String>{'lease.read'},
            mutationsSupported: true,
          ),
        ),
        rentRollProvider.overrideWithValue(
          _FakeRentRoll(
            liveResult ??
                LeasingRepositorySuccess<RentRollLiveDto>(live ?? _live()),
          ),
        ),
        unitSearchProvider.overrideWithValue(
          _FakeUnitSearch(units: units, alwaysMore: unitAlwaysMore),
        ),
        leaseSearchProvider.overrideWithValue(
          _FakeLeaseSearch(const <LeaseSummaryDto>[]),
        ),
        operationsSignalsProvider.overrideWithValue(_FakeSignals(signals)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: OperationsOverviewPanel(propertyId: _propertyId),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

RentRollLiveDto _live({
  int unitCount = 0,
  int occupied = 0,
  int vacant = 0,
  double? rent,
}) => RentRollLiveDto(
  workspaceId: _workspace,
  propertyId: _propertyId,
  asOfDate: DateTime.utc(2026, 3, 31),
  computedAt: DateTime.utc(2026, 3, 31, 9, 5),
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

OperationsSignalDto _signal(String type, String severity) => OperationsSignalDto(
  signalKey: '$type:-:-:-',
  type: type,
  severity: severity,
  message: '$type triggered',
  recommendedAction: 'act',
  propertyId: _propertyId,
  status: 'open',
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
  _FakeSignals(this.signals);

  final List<OperationsSignalDto> signals;

  @override
  Future<OperationsSignalsResult<List<OperationsSignalDto>>> list(
    OperationsSignalsQuery query,
  ) async => OperationsSignalsSuccess<List<OperationsSignalDto>>(signals);

  @override
  Future<OperationsSignalsResult<OperationsSignalStateDto>> updateStatus(
    UpdateOperationsSignalStatusCommand command,
  ) => throw UnimplementedError();
}
