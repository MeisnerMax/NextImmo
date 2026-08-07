import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_providers.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_repository.dart';
import 'package:neximmo_app/features/contacts_parties/domain/party_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_providers.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';
import 'package:neximmo_app/ui/screens/property_detail/leasing/leases_panel.dart';
// Prefixed: the legacy app state exports a `leaseRepositoryProvider` of its
// own, and only the navigation-intent provider is wanted here.
import 'package:neximmo_app/ui/state/app_state.dart' as app_state;

const String _workspace = 'workspace-a';
const String _property = 'property-a';

void main() {
  testWidgets('renders the empty state with a create affordance', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Noch kein Vertrag'), findsOneWidget);
    expect(find.text('Vertrag anlegen'), findsWidgets);
  });

  testWidgets('forbidden is its own state, not empty', (tester) async {
    await _pump(tester, searchFailure: LeasingRepositoryFailureKind.forbidden);

    expect(find.text('Kein Zugriff auf Verträge'), findsOneWidget);
    expect(find.text('Noch kein Vertrag'), findsNothing);
  });

  testWidgets('an infrastructure error offers a retry, not a raw exception', (
    tester,
  ) async {
    await _pump(
      tester,
      searchFailure: LeasingRepositoryFailureKind.infrastructureFailure,
    );

    expect(find.text('Verträge konnten nicht geladen werden'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('a read-only backend explains itself and disables mutations', (
    tester,
  ) async {
    await _pump(
      tester,
      leases: <LeaseSummaryDto>[_summary('l1', 'Vertrag Eins')],
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

  testWidgets('lists leases with unit code, tenant name and status badge', (
    tester,
  ) async {
    await _pump(
      tester,
      leases: <LeaseSummaryDto>[
        _summary('l1', 'Vertrag Eins', status: LeaseStatus.active),
        _summary('l2', 'Vertrag Zwei', status: LeaseStatus.draft),
      ],
      units: <UnitSummaryDto>[_unit('u1', 'A-01')],
      tenants: <PartySummaryDto>[_party('party-1', 'Meier GmbH')],
    );

    expect(find.text('Vertrag Eins'), findsOneWidget);
    expect(find.text('A-01'), findsWidgets);
    expect(find.text('Meier GmbH'), findsWidgets);
    expect(find.text('Aktiv'), findsOneWidget);
    expect(find.text('Entwurf'), findsOneWidget);
  });

  testWidgets('a lease without a tenant says so instead of showing an id', (
    tester,
  ) async {
    await _pump(
      tester,
      leases: <LeaseSummaryDto>[
        _summary('l1', 'Vertrag Eins', tenantPartyId: null),
      ],
    );

    expect(find.text('Noch nicht benannt'), findsOneWidget);
  });

  testWidgets('an empty filter result is distinct from having no leases', (
    tester,
  ) async {
    await _pump(
      tester,
      leases: <LeaseSummaryDto>[_summary('l1', 'Vertrag Eins')],
    );

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('Kein Vertrag für diesen Filter'), findsOneWidget);
    expect(find.text('Noch kein Vertrag'), findsNothing);
  });

  testWidgets('the detail offers exactly the next STM-005 step', (
    tester,
  ) async {
    await _pump(
      tester,
      leases: <LeaseSummaryDto>[_summary('l1', 'Vertrag Eins')],
      lease: _lease('l1', status: LeaseStatus.landlordSigned),
    );

    await tester.tap(find.text('Vertrag Eins'));
    await tester.pumpAndSettle();

    expect(find.text('Vertrag aktivieren'), findsOneWidget);
    // No backward edge and no status dropdown in the detail.
    expect(find.text('Als geprüft markieren'), findsNothing);
    expect(find.text('Vertrag beenden'), findsNothing);
    expect(find.text('Vertrag abbrechen'), findsOneWidget);
  });

  testWidgets('a binding lease loses the edit affordance and says why', (
    tester,
  ) async {
    await _pump(
      tester,
      leases: <LeaseSummaryDto>[_summary('l1', 'Vertrag Eins')],
      lease: _lease('l1', status: LeaseStatus.active),
    );

    await tester.tap(find.text('Vertrag Eins'));
    await tester.pumpAndSettle();

    expect(find.text('Bearbeiten'), findsNothing);
    expect(
      find.textContaining('Eine Änderung der Konditionen ist ein neuer'),
      findsOneWidget,
    );
  });

  testWidgets('a draft keeps the edit affordance', (tester) async {
    await _pump(
      tester,
      leases: <LeaseSummaryDto>[_summary('l1', 'Vertrag Eins')],
      lease: _lease('l1'),
    );

    await tester.tap(find.text('Vertrag Eins'));
    await tester.pumpAndSettle();

    expect(find.text('Bearbeiten'), findsOneWidget);
    expect(find.text('Als geprüft markieren'), findsOneWidget);
  });

  testWidgets('a terminal lease offers no step and explains the end', (
    tester,
  ) async {
    await _pump(
      tester,
      leases: <LeaseSummaryDto>[_summary('l1', 'Vertrag Eins')],
      lease: _lease('l1', status: LeaseStatus.ended),
    );

    await tester.tap(find.text('Vertrag Eins'));
    await tester.pumpAndSettle();

    expect(find.text('Vertrag abbrechen'), findsNothing);
    expect(
      find.textContaining('Ein neuer Anlauf ist ein neuer Vertrag'),
      findsOneWidget,
    );
  });

  testWidgets('a refused transition is explained inline, not as an error', (
    tester,
  ) async {
    await _pump(
      tester,
      leases: <LeaseSummaryDto>[_summary('l1', 'Vertrag Eins')],
      lease: _lease('l1'),
      transitionFailure: LeasingRepositoryFailureKind.validationFailed,
    );

    await tester.tap(find.text('Vertrag Eins'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Als geprüft markieren'));
    await tester.pumpAndSettle();
    // Confirm the step in the transition dialog.
    await tester.tap(find.text('Als geprüft markieren').last);
    await tester.pumpAndSettle();

    expect(find.text('Dieser Schritt ist nicht möglich'), findsOneWidget);
    expect(
      find.textContaining('STM-005 erlaubt von „Entwurf" nur „Geprüft"'),
      findsOneWidget,
    );
  });

  testWidgets('a version conflict opens a resolve dialog with the current lease',
      (tester) async {
    await _pump(
      tester,
      leases: <LeaseSummaryDto>[_summary('l1', 'Vertrag Eins')],
      lease: _lease('l1'),
      transitionFailure: LeasingRepositoryFailureKind.versionConflict,
    );

    await tester.tap(find.text('Vertrag Eins'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Als geprüft markieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Als geprüft markieren').last);
    await tester.pumpAndSettle();

    expect(find.text('Vertrag wurde zwischenzeitlich geändert'), findsOneWidget);
    expect(find.textContaining('jetzt Version 7'), findsOneWidget);
  });

  testWidgets('the cancellation dialog refuses an empty reason', (
    tester,
  ) async {
    await _pump(
      tester,
      leases: <LeaseSummaryDto>[_summary('l1', 'Vertrag Eins')],
      lease: _lease('l1'),
    );

    await tester.tap(find.text('Vertrag Eins'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vertrag abbrechen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vertrag abbrechen').last);
    await tester.pumpAndSettle();

    expect(find.text('Bitte einen Grund angeben.'), findsOneWidget);
  });

  testWidgets('opens the lease another screen deep-linked to', (tester) async {
    // The alerts screen, the tenant detail, the task list and the app-wide
    // navigation all set this provider and expect the lease surface to open on
    // that lease. The legacy screen honoured it; losing that silently would be
    // a regression of the swap, not of the redesign.
    await _pump(
      tester,
      leases: <LeaseSummaryDto>[_summary('l1', 'Vertrag Eins')],
      lease: _lease('l1'),
      deepLinkedLeaseId: 'l1',
    );

    expect(find.text('Laufzeit und Fristen'), findsOneWidget);
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
        leases: <LeaseSummaryDto>[
          _summary('l1', 'Vertrag Eins', status: LeaseStatus.active),
          _summary('l2', 'Vertrag Zwei'),
        ],
        units: <UnitSummaryDto>[_unit('u1', 'A-01')],
        tenants: <PartySummaryDto>[_party('party-1', 'Meier GmbH')],
      );

      expect(find.text('Vertrag Eins'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester, {
  List<LeaseSummaryDto> leases = const <LeaseSummaryDto>[],
  List<UnitSummaryDto> units = const <UnitSummaryDto>[],
  List<PartySummaryDto> tenants = const <PartySummaryDto>[],
  LeaseDto? lease,
  LeasingRepositoryFailureKind? searchFailure,
  LeasingRepositoryFailureKind? transitionFailure,
  bool mutationsSupported = true,
  String? deepLinkedLeaseId,
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
        leaseSearchProvider.overrideWithValue(
          _FakeLeaseSearch(leases: leases, failure: searchFailure),
        ),
        leaseRepositoryProvider.overrideWithValue(
          _FakeLeaseRepository(lease: lease, transitionFailure: transitionFailure),
        ),
        unitSearchProvider.overrideWithValue(_FakeUnitSearch(units)),
        partySearchProvider.overrideWithValue(_FakePartySearch(tenants)),
        if (deepLinkedLeaseId != null)
          app_state.selectedOperationsLeaseIdProvider.overrideWith(
            (ref) => deepLinkedLeaseId,
          ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: LeasesPanel(propertyId: _property)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

LeaseSummaryDto _summary(
  String id,
  String name, {
  LeaseStatus status = LeaseStatus.draft,
  String? tenantPartyId = 'party-1',
}) => LeaseSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitId: 'u1',
  leaseName: name,
  status: status,
  startDate: DateTime.utc(2026, 1, 1),
  baseRentMonthly: 1000,
  currencyCode: 'EUR',
  version: 1,
  tenantPartyId: tenantPartyId,
);

LeaseDto _lease(
  String id, {
  LeaseStatus status = LeaseStatus.draft,
  int version = 1,
}) => LeaseDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitId: 'u1',
  leaseName: 'Vertrag Eins',
  status: status,
  startDate: DateTime.utc(2026, 1, 1),
  baseRentMonthly: 1000,
  currencyCode: 'EUR',
  version: version,
  tenantPartyId: 'party-1',
  billingFrequency: LeaseBillingFrequency.monthly,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  createdBy: 'actor-1',
  updatedBy: 'actor-1',
);

UnitSummaryDto _unit(String id, String code) => UnitSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  unitCode: code,
  status: UnitStatus.occupied,
  version: 1,
);

PartySummaryDto _party(String id, String name) => PartySummaryDto(
  id: id,
  workspaceId: _workspace,
  type: PartyType.organization,
  displayName: name,
  version: 1,
);

class _FakeLeaseSearch implements LeaseSearchPort {
  _FakeLeaseSearch({required this.leases, this.failure});

  final List<LeaseSummaryDto> leases;
  final LeasingRepositoryFailureKind? failure;

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<LeaseSummaryDto>>> search(
    LeaseListQuery query,
  ) async {
    final kind = failure;
    if (kind != null) {
      return LeasingRepositoryFailure<LeasingPageResult<LeaseSummaryDto>>(
        kind: kind,
        message: 'failed',
      );
    }
    return LeasingRepositorySuccess<LeasingPageResult<LeaseSummaryDto>>(
      LeasingPageResult<LeaseSummaryDto>(items: leases),
    );
  }
}

class _FakeUnitSearch implements UnitSearchPort {
  _FakeUnitSearch(this.units);

  final List<UnitSummaryDto> units;

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<UnitSummaryDto>>> search(
    UnitListQuery query,
  ) async {
    return LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>(
      LeasingPageResult<UnitSummaryDto>(items: units),
    );
  }
}

class _FakePartySearch implements PartySearchPort {
  _FakePartySearch(this.parties);

  final List<PartySummaryDto> parties;

  @override
  Future<PartyRepositoryResult<PartyPageResult>> search(
    PartyListQuery query,
  ) async {
    return PartyRepositorySuccess<PartyPageResult>(
      PartyPageResult(items: parties),
    );
  }
}

class _FakeLeaseRepository implements LeaseRepository {
  _FakeLeaseRepository({this.lease, this.transitionFailure});

  final LeaseDto? lease;
  final LeasingRepositoryFailureKind? transitionFailure;

  @override
  Future<LeasingRepositoryResult<LeaseDto>> getById({
    required String workspaceId,
    required String leaseId,
  }) async {
    final value = lease;
    if (value == null) {
      return const LeasingRepositoryFailure<LeaseDto>(
        kind: LeasingRepositoryFailureKind.notFound,
        message: 'not found',
      );
    }
    return LeasingRepositorySuccess<LeaseDto>(value);
  }

  @override
  Future<LeasingRepositoryResult<LeaseDto>> create(
    CreateLeaseCommand command,
  ) async => const LeasingRepositoryFailure<LeaseDto>(
    kind: LeasingRepositoryFailureKind.dependencyConflict,
    message: 'read only',
  );

  @override
  Future<LeasingRepositoryResult<LeaseDto>> update(
    UpdateLeaseCommand command,
  ) async => const LeasingRepositoryFailure<LeaseDto>(
    kind: LeasingRepositoryFailureKind.dependencyConflict,
    message: 'read only',
  );

  @override
  Future<LeasingRepositoryResult<LeaseDto>> transitionStatus(
    TransitionLeaseStatusCommand command,
  ) async {
    return switch (transitionFailure) {
      LeasingRepositoryFailureKind.versionConflict =>
        LeasingRepositoryFailure<LeaseDto>(
          kind: LeasingRepositoryFailureKind.versionConflict,
          message: 'stale',
          versionConflict: LeasingVersionConflict(
            expectedVersion: 1,
            actualVersion: 7,
            currentLease: _lease('l1', version: 7),
          ),
        ),
      final LeasingRepositoryFailureKind kind? =>
        LeasingRepositoryFailure<LeaseDto>(kind: kind, message: 'refused'),
      null => LeasingRepositorySuccess<LeaseDto>(
        _lease(command.leaseId, status: command.targetStatus),
      ),
    };
  }
}
