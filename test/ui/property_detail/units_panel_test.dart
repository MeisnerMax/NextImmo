import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_providers.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';
import 'package:neximmo_app/ui/screens/property_detail/leasing/units_panel.dart';
// Prefixed: the legacy app state exports repository providers of its own, and
// only the navigation-intent provider is wanted here.
import 'package:neximmo_app/ui/state/app_state.dart' as app_state;

const String _workspace = 'workspace-a';
const String _property = 'property-a';

void main() {
  testWidgets('renders the empty state with a create affordance', (
    tester,
  ) async {
    await _pump(tester, units: const <UnitSummaryDto>[]);

    expect(find.text('Noch keine Einheit'), findsOneWidget);
    expect(find.text('Einheit anlegen'), findsWidgets);
  });

  testWidgets('forbidden is its own state, not empty', (tester) async {
    await _pump(
      tester,
      searchFailure: LeasingRepositoryFailureKind.forbidden,
    );

    expect(find.text('Kein Zugriff auf Einheiten'), findsOneWidget);
    expect(find.text('Noch keine Einheit'), findsNothing);
  });

  testWidgets('an infrastructure error offers a retry, not a raw exception', (
    tester,
  ) async {
    await _pump(
      tester,
      searchFailure: LeasingRepositoryFailureKind.infrastructureFailure,
    );

    expect(find.text('Einheiten konnten nicht geladen werden'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('a read-only backend explains itself and disables mutations', (
    tester,
  ) async {
    await _pump(
      tester,
      units: <UnitSummaryDto>[_summary('u1')],
      mutationsSupported: false,
    );

    expect(
      find.textContaining('schreibgeschützt', findRichText: true),
      findsOneWidget,
    );
    // `FilledButton.icon` builds a private subclass, so a byType finder would
    // miss it — match the base class by predicate instead.
    final buttons = tester
        .widgetList<FilledButton>(
          find.byWidgetPredicate((widget) => widget is FilledButton),
        )
        .toList();
    expect(buttons, isNotEmpty);
    expect(buttons.every((button) => button.onPressed == null), isTrue);
  });

  testWidgets('lists units with their derived status badge', (tester) async {
    await _pump(
      tester,
      units: <UnitSummaryDto>[
        _summary('u1', code: 'A-01', status: UnitStatus.occupied),
        _summary('u2', code: 'A-02', status: UnitStatus.offline),
      ],
    );

    expect(find.text('A-01'), findsOneWidget);
    expect(find.text('Vermietet'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('an empty filter result is distinct from having no units', (
    tester,
  ) async {
    await _pump(tester, units: <UnitSummaryDto>[_summary('u1', code: 'A-01')]);

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('Keine Einheit für diesen Filter'), findsOneWidget);
    expect(find.text('Noch keine Einheit'), findsNothing);
  });

  testWidgets('the detail panel says occupancy is derived, and offers no switch',
      (tester) async {
    await _pump(
      tester,
      units: <UnitSummaryDto>[_summary('u1', code: 'A-01')],
      unit: _unit('u1', code: 'A-01'),
    );

    await tester.tap(find.text('A-01'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('folgt aus den wirksamen Verträgen'),
      findsOneWidget,
    );
    // AGG-004: there is no affordance that sets occupancy directly.
    expect(find.text('Als vermietet markieren'), findsNothing);
    expect(find.text('Offline nehmen'), findsOneWidget);
  });

  testWidgets('an amount without a currency is reported, not shown bare', (
    tester,
  ) async {
    await _pump(
      tester,
      units: <UnitSummaryDto>[_summary('u1', code: 'A-01')],
      unit: _unit('u1', code: 'A-01', targetRent: 900),
    );

    await tester.tap(find.text('A-01'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Währung nicht hinterlegt'),
      findsOneWidget,
    );
  });

  testWidgets('shows every lease of a unit, never "the" lease (OPN-DOM-001)', (
    tester,
  ) async {
    await _pump(
      tester,
      units: <UnitSummaryDto>[_summary('u1', code: 'A-01')],
      unit: _unit('u1', code: 'A-01'),
      leases: <LeaseSummaryDto>[_lease('l1', 'Vertrag Eins'), _lease('l2', 'Vertrag Zwei')],
    );

    await tester.tap(find.text('A-01'));
    await tester.pumpAndSettle();

    expect(find.text('Verträge dieser Einheit'), findsOneWidget);
    expect(find.text('Vertrag Eins'), findsOneWidget);
    expect(find.text('Vertrag Zwei'), findsOneWidget);
    expect(find.text('2 insgesamt, 2 wirksam'), findsOneWidget);
  });

  testWidgets('explains a multi-lease occupancy instead of just showing it', (
    tester,
  ) async {
    await _pump(
      tester,
      units: <UnitSummaryDto>[_summary('u1', code: 'A-01')],
      unit: _unit('u1', code: 'A-01', status: UnitStatus.occupied),
      leases: <LeaseSummaryDto>[_lease('l1', 'Eins'), _lease('l2', 'Zwei')],
    );

    await tester.tap(find.text('A-01'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('2 sind gleichzeitig aktiv'),
      findsOneWidget,
    );
  });

  testWidgets('opens the unit another screen deep-linked to', (tester) async {
    // Other screens navigate to a unit through this provider; the legacy screen
    // honoured it, so the contract-based panel has to as well.
    await _pump(
      tester,
      units: <UnitSummaryDto>[_summary('u1', code: 'A-01')],
      unit: _unit('u1', code: 'A-01'),
      deepLinkedUnitId: 'u1',
    );

    expect(find.text('Stammdaten'), findsOneWidget);
  });

  testWidgets('a unit without leases says so positively', (tester) async {
    await _pump(
      tester,
      units: <UnitSummaryDto>[_summary('u1', code: 'A-01')],
      unit: _unit('u1', code: 'A-01'),
    );

    await tester.tap(find.text('A-01'));
    await tester.pumpAndSettle();

    expect(find.text('Keine Verträge auf dieser Einheit'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  List<UnitSummaryDto> units = const <UnitSummaryDto>[],
  UnitDto? unit,
  List<LeaseSummaryDto> leases = const <LeaseSummaryDto>[],
  LeasingRepositoryFailureKind? searchFailure,
  bool mutationsSupported = true,
  String? deepLinkedUnitId,
}) async {
  final search = _FakeUnitSearch(units: units, failure: searchFailure);
  final repository = _FakeUnitRepository(unit: unit);
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
        unitSearchProvider.overrideWithValue(search),
        unitRepositoryProvider.overrideWithValue(repository),
        leaseSearchProvider.overrideWithValue(_FakeLeaseSearch(leases)),
        if (deepLinkedUnitId != null)
          app_state.selectedOperationsUnitIdProvider.overrideWith(
            (ref) => deepLinkedUnitId,
          ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 900,
            child: UnitsPanel(propertyId: _property),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

UnitSummaryDto _summary(
  String id, {
  String? code,
  UnitStatus status = UnitStatus.vacant,
}) => UnitSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitCode: code ?? id.toUpperCase(),
  status: status,
  version: 1,
);

LeaseSummaryDto _lease(String id, String name) => LeaseSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitId: 'u1',
  leaseName: name,
  status: LeaseStatus.active,
  startDate: DateTime.utc(2026, 1, 1),
  baseRentMonthly: 1000,
  currencyCode: 'EUR',
  version: 1,
);

UnitDto _unit(
  String id, {
  String? code,
  double? targetRent,
  UnitStatus status = UnitStatus.vacant,
}) => UnitDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitCode: code ?? id.toUpperCase(),
  status: status,
  version: 1,
  targetRentMonthly: targetRent,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  createdBy: 'actor-1',
  updatedBy: 'actor-1',
);

class _FakeUnitSearch implements UnitSearchPort {
  _FakeUnitSearch({required this.units, this.failure});

  final List<UnitSummaryDto> units;
  final LeasingRepositoryFailureKind? failure;

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<UnitSummaryDto>>> search(
    UnitListQuery query,
  ) async {
    final kind = failure;
    if (kind != null) {
      return LeasingRepositoryFailure<LeasingPageResult<UnitSummaryDto>>(
        kind: kind,
        message: 'failed',
      );
    }
    return LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>(
      LeasingPageResult<UnitSummaryDto>(items: units),
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

class _FakeUnitRepository implements UnitRepository {
  _FakeUnitRepository({this.unit});

  final UnitDto? unit;

  @override
  Future<LeasingRepositoryResult<UnitDto>> getById({
    required String workspaceId,
    required String unitId,
  }) async {
    final value = unit;
    if (value == null) {
      return const LeasingRepositoryFailure<UnitDto>(
        kind: LeasingRepositoryFailureKind.notFound,
        message: 'not found',
      );
    }
    return LeasingRepositorySuccess<UnitDto>(value);
  }

  @override
  Future<LeasingRepositoryResult<UnitDto>> create(
    CreateUnitCommand command,
  ) async => const LeasingRepositoryFailure<UnitDto>(
    kind: LeasingRepositoryFailureKind.dependencyConflict,
    message: 'read only',
  );

  @override
  Future<LeasingRepositoryResult<UnitDto>> update(
    UpdateUnitCommand command,
  ) async => const LeasingRepositoryFailure<UnitDto>(
    kind: LeasingRepositoryFailureKind.dependencyConflict,
    message: 'read only',
  );

  @override
  Future<LeasingRepositoryResult<UnitDto>> transitionStatus(
    TransitionUnitStatusCommand command,
  ) async => const LeasingRepositoryFailure<UnitDto>(
    kind: LeasingRepositoryFailureKind.dependencyConflict,
    message: 'read only',
  );
}
