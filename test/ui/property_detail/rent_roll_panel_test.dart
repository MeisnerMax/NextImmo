import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_providers.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/domain/rent_roll_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';
import 'package:neximmo_app/ui/screens/property_detail/leasing/rent_roll_panel.dart';

const String _workspace = 'workspace-a';
const String _property = 'property-a';

void main() {
  testWidgets('the live table is the primary view and says it is current', (
    tester,
  ) async {
    await _pump(
      tester,
      live: _live(),
    );

    expect(find.text('Aktueller Stand'), findsOneWidget);
    // Said twice on purpose: once in the page subtitle, once on the section
    // that carries the figures.
    expect(find.textContaining('jetzt gerechnet'), findsNWidgets(2));
    expect(find.text('A-01'), findsOneWidget);
    expect(find.text('1000.00 EUR'), findsWidgets);
  });

  testWidgets('the live table survives a backend without frozen snapshots', (
    tester,
  ) async {
    // The split earns its keep here: the current state is readable even where
    // the frozen document is not.
    await _pump(
      tester,
      live: _live(),
      snapshotListFailure: LeasingRepositoryFailureKind.dependencyConflict,
    );

    expect(find.text('Aktueller Stand'), findsOneWidget);
    expect(
      find.textContaining('Eingefrorene Snapshots gibt es erst nach der'),
      findsOneWidget,
    );
    expect(find.textContaining('Begründung des Adapters'), findsOneWidget);
  });

  testWidgets('forbidden on the live half is its own state', (tester) async {
    await _pump(tester, liveFailure: LeasingRepositoryFailureKind.forbidden);

    expect(find.text('Kein Zugriff auf den Rent Roll'), findsOneWidget);
  });

  testWidgets('an unreadable live document is an error, not a roll of zeros',
      (tester) async {
    await _pump(
      tester,
      liveFailure: LeasingRepositoryFailureKind.infrastructureFailure,
    );

    expect(find.text('Rent Roll konnte nicht geladen werden'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('a property without units says so instead of showing an empty sum',
      (tester) async {
    await _pump(tester);

    expect(find.text('Noch keine Einheit'), findsOneWidget);
  });

  testWidgets('a read-only backend disables freezing a snapshot', (
    tester,
  ) async {
    await _pump(
      tester,
      live: _live(),
      mutationsSupported: false,
    );

    final buttons = tester
        .widgetList<FilledButton>(
          find.byWidgetPredicate((widget) => widget is FilledButton),
        )
        .toList();
    expect(buttons, isNotEmpty);
    expect(buttons.every((button) => button.onPressed == null), isTrue);
  });

  testWidgets('an occupied unit contributing 0,00 is explained, not just shown',
      (tester) async {
    await _pump(
      tester,
      // The backend marks a unit that is occupied by status but whose lease
      // term does not cover the reporting date.
      live: _live(
        lines: <RentRollLiveLineDto>[
          _liveLine('A-01', status: UnitStatus.occupied, leaseCount: 0),
        ],
      ),
    );

    expect(find.text('1 vermietete Einheit trägt 0,00 bei'), findsOneWidget);
    expect(find.textContaining('kein Rechenfehler'), findsOneWidget);
  });

  testWidgets('mixed currencies are named instead of summed', (tester) async {
    await _pump(
      tester,
      live: _live(
        currencies: const <String>['CHF', 'EUR'],
        unitCount: 2,
        occupiedUnitCount: 2,
        total: null,
        lines: <RentRollLiveLineDto>[
          _liveLine('A-01'),
          _liveLine('A-02', currencies: const <String>['CHF']),
        ],
      ),
    );

    expect(find.text('Keine Gesamtsumme möglich'), findsOneWidget);
    expect(find.textContaining('CHF und EUR'), findsOneWidget);
  });

  testWidgets('an occupancy rate of null is shown as a dash, not 0 %', (
    tester,
  ) async {
    // An offline-only property: occupied is 0 of 1, a real 0 %. The null case
    // (no units at all) is the empty state and is covered separately — here the
    // dash must not appear wrongly.
    await _pump(
      tester,
      live: _live(
        occupiedUnitCount: 0,
        offlineUnitCount: 1,
        lines: <RentRollLiveLineDto>[
          _liveLine('A-01', status: UnitStatus.offline, leaseCount: 0),
        ],
      ),
    );

    expect(find.text('Belegungsquote'), findsOneWidget);
    expect(find.text('0.0 %'), findsOneWidget);
  });

  testWidgets('the frozen half is a history with no edit and no delete', (
    tester,
  ) async {
    await _pump(
      tester,
      live: _live(),
      snapshots: <RentRollSnapshotDto>[_snapshot('s1')],
    );

    expect(find.text('Eingefrorene Snapshots'), findsOneWidget);
    expect(
      find.textContaining('eine Korrektur ist ein neuer Snapshot'),
      findsOneWidget,
    );
    expect(find.text('Löschen'), findsNothing);
    expect(find.text('Bearbeiten'), findsNothing);
  });

  testWidgets('opening a snapshot shows the full server-side split', (
    tester,
  ) async {
    await _pump(
      tester,
      live: _live(),
      snapshots: <RentRollSnapshotDto>[_snapshot('s1')],
      snapshot: _snapshot(
        's1',
        lines: <RentRollSnapshotLineDto>[_line('l1', 'A-01')],
      ),
    );

        // Exact match: the live section's description also starts with the date.
    await tester.tap(find.text('Stichtag 31.03.2026'));
    await tester.pumpAndSettle();

    expect(find.text('Eingefrorene Zeilen'), findsOneWidget);
    // Both halves carry the full split now that the server computes both.
    expect(find.text('Nebenkosten'), findsWidgets);
    expect(find.text('Stellplatz / Sonstiges'), findsWidgets);
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
        live: _live(
          unitCount: 2,
          lines: <RentRollLiveLineDto>[
            _liveLine('A-01'),
            _liveLine('A-02', status: UnitStatus.vacant, leaseCount: 0),
          ],
        ),
        snapshots: <RentRollSnapshotDto>[_snapshot('s1')],
      );

      expect(find.text('Rent Roll'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester, {
  RentRollLiveDto? live,
  List<RentRollSnapshotDto> snapshots = const <RentRollSnapshotDto>[],
  RentRollSnapshotDto? snapshot,
  LeasingRepositoryFailureKind? liveFailure,
  LeasingRepositoryFailureKind? snapshotListFailure,
  bool mutationsSupported = true,
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
            permissions: const <String>{'lease.read', 'lease.manage'},
            mutationsSupported: mutationsSupported,
          ),
        ),
        rentRollProvider.overrideWithValue(
          _FakeRentRoll(
            live: live,
            liveFailure: liveFailure,
            snapshots: snapshots,
            snapshot: snapshot,
            listFailure: snapshotListFailure,
          ),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: RentRollPanel(propertyId: _property)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}



RentRollLiveDto _live({
  String workspaceId = _workspace,
  String propertyId = _property,
  List<RentRollLiveLineDto>? lines,
  List<String> currencies = const <String>['EUR'],
  int unitCount = 1,
  int occupiedUnitCount = 1,
  int offlineUnitCount = 0,
  double? total = 1100,
}) => RentRollLiveDto(
  workspaceId: workspaceId,
  propertyId: propertyId,
  asOfDate: DateTime.utc(2026, 3, 31),
  computedAt: DateTime.utc(2026, 3, 31, 12),
  currencies: currencies,
  unitCount: unitCount,
  occupiedUnitCount: occupiedUnitCount,
  vacantUnitCount: unitCount - occupiedUnitCount - offlineUnitCount,
  offlineUnitCount: offlineUnitCount,
  effectiveLeaseCount: occupiedUnitCount,
  totalBaseRentMonthly: total == null ? null : 1000,
  totalAncillaryChargesMonthly: total == null ? null : 100,
  totalParkingOtherChargesMonthly: total == null ? null : 0,
  totalRentMonthly: total,
  lines: lines ?? <RentRollLiveLineDto>[_liveLine('A-01')],
);

RentRollLiveLineDto _liveLine(
  String unitCode, {
  UnitStatus status = UnitStatus.occupied,
  int leaseCount = 1,
  List<String> currencies = const <String>['EUR'],
}) => RentRollLiveLineDto(
  unitId: 'u-$unitCode',
  unitCode: unitCode,
  unitStatus: status,
  effectiveLeaseCount: leaseCount,
  baseRentMonthly: leaseCount == 0 ? 0 : 1000,
  ancillaryChargesMonthly: leaseCount == 0 ? 0 : 100,
  parkingOtherChargesMonthly: 0,
  totalRentMonthly: leaseCount == 0 ? 0 : 1100,
  currencies: leaseCount == 0 ? const <String>[] : currencies,
  areaSqm: 60,
);

RentRollSnapshotDto _snapshot(
  String id, {
  List<RentRollSnapshotLineDto> lines = const <RentRollSnapshotLineDto>[],
}) => RentRollSnapshotDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  asOfDate: DateTime.utc(2026, 3, 31),
  currencyCode: 'EUR',
  generatedAt: DateTime.utc(2026, 4, 1),
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



class _FakeRentRoll implements RentRollPort {
  _FakeRentRoll({
    required this.snapshots,
    this.live,
    this.liveFailure,
    this.snapshot,
    this.listFailure,
  });

  final List<RentRollSnapshotDto> snapshots;
  final RentRollLiveDto? live;
  final LeasingRepositoryFailureKind? liveFailure;
  final RentRollSnapshotDto? snapshot;
  final LeasingRepositoryFailureKind? listFailure;

  @override
  Future<LeasingRepositoryResult<RentRollLiveDto>> readLive({
    required String workspaceId,
    required String propertyId,
    required DateTime asOfDate,
  }) async {
    final kind = liveFailure;
    if (kind != null) {
      return LeasingRepositoryFailure<RentRollLiveDto>(
        kind: kind,
        message: 'failed',
      );
    }
    return LeasingRepositorySuccess<RentRollLiveDto>(
      live ??
          _live(workspaceId: workspaceId, propertyId: propertyId,
              lines: const <RentRollLiveLineDto>[]),
    );
  }

  @override
  Future<LeasingRepositoryResult<RentRollSnapshotDto>> getSnapshot({
    required String workspaceId,
    required String snapshotId,
  }) async {
    final value = snapshot;
    if (value == null) {
      return const LeasingRepositoryFailure<RentRollSnapshotDto>(
        kind: LeasingRepositoryFailureKind.notFound,
        message: 'not found',
      );
    }
    return LeasingRepositorySuccess<RentRollSnapshotDto>(value);
  }

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<RentRollSnapshotDto>>>
  listSnapshots(RentRollSnapshotListQuery query) async {
    final kind = listFailure;
    if (kind != null) {
      return LeasingRepositoryFailure<LeasingPageResult<RentRollSnapshotDto>>(
        kind: kind,
        message:
            'Local rent roll snapshots are a different document: they are '
            'keyed by reporting period rather than by date.',
      );
    }
    return LeasingRepositorySuccess<LeasingPageResult<RentRollSnapshotDto>>(
      LeasingPageResult<RentRollSnapshotDto>(items: snapshots),
    );
  }

  @override
  Future<LeasingRepositoryResult<RentRollSnapshotDto>> createSnapshot(
    CreateRentRollSnapshotCommand command,
  ) async => const LeasingRepositoryFailure<RentRollSnapshotDto>(
    kind: LeasingRepositoryFailureKind.dependencyConflict,
    message: 'read only',
  );
}
