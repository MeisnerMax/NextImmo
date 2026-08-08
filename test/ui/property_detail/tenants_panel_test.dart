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
import 'package:neximmo_app/ui/screens/property_detail/leasing/tenants_panel.dart';
// Prefixed: the legacy app state exports repository providers of its own, and
// only the navigation-intent provider is wanted here.
import 'package:neximmo_app/ui/state/app_state.dart' as app_state;

const String _workspace = 'workspace-a';

void main() {
  testWidgets('renders the empty state and explains what a tenant is', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Noch kein Mieter'), findsOneWidget);
    expect(
      find.textContaining('Partei mit Mieter-Rolle'),
      findsOneWidget,
    );
  });

  testWidgets('forbidden names the party permission, not a lease one', (
    tester,
  ) async {
    await _pump(tester, searchFailure: PartyRepositoryFailureKind.forbidden);

    expect(find.text('Kein Zugriff auf Parteien'), findsOneWidget);
    expect(find.textContaining('party.read'), findsOneWidget);
  });

  testWidgets('an infrastructure error offers a retry, not a raw exception', (
    tester,
  ) async {
    await _pump(
      tester,
      searchFailure: PartyRepositoryFailureKind.infrastructureFailure,
    );

    expect(find.text('Mieter konnten nicht geladen werden'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('a read-only backend explains itself and disables mutations', (
    tester,
  ) async {
    await _pump(
      tester,
      tenants: <PartySummaryDto>[_party('p1', 'Meier GmbH')],
      mutationsSupported: false,
    );

    expect(
      find.textContaining('schreibgeschützt', findRichText: true),
      findsOneWidget,
    );
    final buttons = tester
        .widgetList<FilledButton>(
          find.byWidgetPredicate((widget) => widget is FilledButton),
        )
        .toList();
    expect(buttons, isNotEmpty);
    expect(buttons.every((button) => button.onPressed == null), isTrue);
  });

  testWidgets('lists tenants with their party type badge', (tester) async {
    await _pump(
      tester,
      tenants: <PartySummaryDto>[
        _party('p1', 'Meier GmbH', type: PartyType.organization),
        _party('p2', 'Anna Schulz'),
      ],
    );

    expect(find.text('Meier GmbH'), findsOneWidget);
    expect(find.text('Organisation'), findsOneWidget);
    expect(find.text('Person'), findsOneWidget);
  });

  testWidgets('an empty search result is distinct from having no tenants', (
    tester,
  ) async {
    await _pump(tester, tenants: <PartySummaryDto>[_party('p1', 'Meier GmbH')]);

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('Kein Mieter für diese Suche'), findsOneWidget);
    expect(find.text('Noch kein Mieter'), findsNothing);
  });

  testWidgets('the detail shows every role of the party, not only the tenant one',
      (tester) async {
    await _pump(
      tester,
      tenants: <PartySummaryDto>[_party('p1', 'Meier GmbH')],
      party: _partyDto('p1'),
      roles: <PartyRoleDto>[
        _role('r1', PartyRoleType.tenant),
        _role('r2', PartyRoleType.contractor),
      ],
    );

    await tester.tap(find.text('Meier GmbH'));
    await tester.pumpAndSettle();

    // 'Mieter' appears twice on purpose: the list column header and the role
    // badge. The contractor role is the one that proves nothing is filtered.
    expect(find.text('Mieter'), findsWidgets);
    expect(find.text('Dienstleister'), findsOneWidget);
    expect(
      find.textContaining('Mieter ist eine Rolle dieser Partei'),
      findsOneWidget,
    );
  });

  testWidgets('unreadable leases are their own state, not "no leases"', (
    tester,
  ) async {
    await _pump(
      tester,
      tenants: <PartySummaryDto>[_party('p1', 'Meier GmbH')],
      party: _partyDto('p1'),
      roles: <PartyRoleDto>[_role('r1', PartyRoleType.tenant)],
      leaseFailure: LeasingRepositoryFailureKind.forbidden,
    );

    await tester.tap(find.text('Meier GmbH'));
    await tester.pumpAndSettle();

    expect(find.text('Verträge nicht sichtbar'), findsOneWidget);
    expect(find.text('Keine Verträge auf diesen Mieter'), findsNothing);
  });

  testWidgets('the lease section lists the leases of the party', (tester) async {
    await _pump(
      tester,
      tenants: <PartySummaryDto>[_party('p1', 'Meier GmbH')],
      party: _partyDto('p1'),
      roles: <PartyRoleDto>[_role('r1', PartyRoleType.tenant)],
      leases: <LeaseSummaryDto>[_lease('l1', 'Vertrag Eins')],
    );

    await tester.tap(find.text('Meier GmbH'));
    await tester.pumpAndSettle();

    expect(find.text('Vertrag Eins'), findsOneWidget);
    expect(find.text('1 insgesamt, 1 wirksam'), findsOneWidget);
  });

  testWidgets('a party without an open tenant role loses the end affordance', (
    tester,
  ) async {
    await _pump(
      tester,
      tenants: <PartySummaryDto>[_party('p1', 'Meier GmbH')],
      party: _partyDto('p1'),
      roles: <PartyRoleDto>[_role('r1', PartyRoleType.tenant, closed: true)],
    );

    await tester.tap(find.text('Meier GmbH'));
    await tester.pumpAndSettle();

    expect(find.text('Mieter-Rolle beenden'), findsNothing);
    expect(
      find.text('Diese Partei hält aktuell keine offene Mieter-Rolle.'),
      findsOneWidget,
    );
  });

  testWidgets('ending the role warns that effective leases are not touched', (
    tester,
  ) async {
    await _pump(
      tester,
      tenants: <PartySummaryDto>[_party('p1', 'Meier GmbH')],
      party: _partyDto('p1'),
      roles: <PartyRoleDto>[_role('r1', PartyRoleType.tenant)],
      leases: <LeaseSummaryDto>[_lease('l1', 'Vertrag Eins')],
    );

    await tester.tap(find.text('Meier GmbH'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mieter-Rolle beenden'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Das Beenden der Rolle beendet ihn nicht'),
      findsOneWidget,
    );
    expect(find.textContaining('Gelöscht wird nichts'), findsOneWidget);
  });

  testWidgets('opens the tenant another screen deep-linked to', (tester) async {
    await _pump(
      tester,
      tenants: <PartySummaryDto>[_party('p1', 'Meier GmbH')],
      party: _partyDto('p1'),
      roles: <PartyRoleDto>[_role('r1', PartyRoleType.tenant)],
      deepLinkedTenantId: 'p1',
    );

    expect(find.text('Identität'), findsOneWidget);
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
        tenants: <PartySummaryDto>[
          _party('p1', 'Meier GmbH', type: PartyType.organization),
          _party('p2', 'Anna Schulz'),
        ],
      );

      expect(find.text('Meier GmbH'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester, {
  List<PartySummaryDto> tenants = const <PartySummaryDto>[],
  List<PartyRoleDto> roles = const <PartyRoleDto>[],
  List<LeaseSummaryDto> leases = const <LeaseSummaryDto>[],
  PartyDto? party,
  PartyRepositoryFailureKind? searchFailure,
  LeasingRepositoryFailureKind? leaseFailure,
  bool mutationsSupported = true,
  String? deepLinkedTenantId,
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
            permissions: const <String>{
              'party.read',
              'party.manage',
              'lease.read',
            },
            mutationsSupported: mutationsSupported,
          ),
        ),
        partySearchProvider.overrideWithValue(
          _FakePartySearch(parties: tenants, failure: searchFailure),
        ),
        partyRepositoryProvider.overrideWithValue(
          _FakePartyRepository(party: party),
        ),
        partyRoleProvider.overrideWithValue(_FakePartyRoles(roles)),
        leaseSearchProvider.overrideWithValue(
          _FakeLeaseSearch(leases: leases, failure: leaseFailure),
        ),
        if (deepLinkedTenantId != null)
          app_state.selectedOperationsTenantIdProvider.overrideWith(
            (ref) => deepLinkedTenantId,
          ),
      ],
      child: const MaterialApp(home: Scaffold(body: TenantsPanel())),
    ),
  );
  await tester.pumpAndSettle();
}

PartySummaryDto _party(
  String id,
  String name, {
  PartyType type = PartyType.person,
}) => PartySummaryDto(
  id: id,
  workspaceId: _workspace,
  type: type,
  displayName: name,
  version: 1,
);

PartyDto _partyDto(String id) => PartyDto(
  id: id,
  workspaceId: _workspace,
  type: PartyType.organization,
  displayName: 'Meier GmbH',
  version: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  createdBy: 'actor-1',
  updatedBy: 'actor-1',
);

PartyRoleDto _role(String id, PartyRoleType type, {bool closed = false}) =>
    PartyRoleDto(
  id: id,
  workspaceId: _workspace,
  partyId: 'p1',
  roleType: type,
  validFrom: DateTime.utc(2026, 1, 1),
  validUntil: closed ? DateTime.utc(2026, 6, 30) : null,
  version: 1,
);

LeaseSummaryDto _lease(String id, String name) => LeaseSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: 'property-a',
  unitId: 'u1',
  leaseName: name,
  status: LeaseStatus.active,
  startDate: DateTime.utc(2026, 1, 1),
  baseRentMonthly: 1000,
  currencyCode: 'EUR',
  version: 1,
  tenantPartyId: 'p1',
);

class _FakePartySearch implements PartySearchPort {
  _FakePartySearch({required this.parties, this.failure});

  final List<PartySummaryDto> parties;
  final PartyRepositoryFailureKind? failure;

  @override
  Future<PartyRepositoryResult<PartyPageResult>> search(
    PartyListQuery query,
  ) async {
    final kind = failure;
    if (kind != null) {
      return PartyRepositoryFailure<PartyPageResult>(
        kind: kind,
        message: 'failed',
      );
    }
    return PartyRepositorySuccess<PartyPageResult>(
      PartyPageResult(items: parties),
    );
  }
}

class _FakePartyRepository implements PartyRepository {
  _FakePartyRepository({this.party});

  final PartyDto? party;

  @override
  Future<PartyRepositoryResult<PartyDto>> getById({
    required String workspaceId,
    required String partyId,
  }) async {
    final value = party;
    if (value == null) {
      return const PartyRepositoryFailure<PartyDto>(
        kind: PartyRepositoryFailureKind.notFound,
        message: 'not found',
      );
    }
    return PartyRepositorySuccess<PartyDto>(value);
  }

  @override
  Future<PartyRepositoryResult<PartyDto>> create(
    CreatePartyCommand command,
  ) async => const PartyRepositoryFailure<PartyDto>(
    kind: PartyRepositoryFailureKind.dependencyConflict,
    message: 'read only',
  );

  @override
  Future<PartyRepositoryResult<PartyDto>> update(
    UpdatePartyCommand command,
  ) async => const PartyRepositoryFailure<PartyDto>(
    kind: PartyRepositoryFailureKind.dependencyConflict,
    message: 'read only',
  );

  @override
  Future<PartyRepositoryResult<PartyDto>> merge(
    MergePartiesCommand command,
  ) async => const PartyRepositoryFailure<PartyDto>(
    kind: PartyRepositoryFailureKind.dependencyConflict,
    message: 'read only',
  );
}

class _FakePartyRoles implements PartyRoleRepository {
  _FakePartyRoles(this.roles);

  final List<PartyRoleDto> roles;

  @override
  Future<PartyRepositoryResult<List<PartyRoleDto>>> listForParty({
    required String workspaceId,
    required String partyId,
  }) async => PartyRepositorySuccess<List<PartyRoleDto>>(roles);

  @override
  Future<PartyRepositoryResult<ContractorDetailsDto?>> getContractorDetails({
    required String workspaceId,
    required String partyId,
  }) async => const PartyRepositorySuccess<ContractorDetailsDto?>(null);

  @override
  Future<PartyRepositoryResult<PartyRoleDto>> assign(
    AssignPartyRoleCommand command,
  ) async => const PartyRepositoryFailure<PartyRoleDto>(
    kind: PartyRepositoryFailureKind.dependencyConflict,
    message: 'read only',
  );

  @override
  Future<PartyRepositoryResult<PartyRoleDto>> end(
    EndPartyRoleCommand command,
  ) async => const PartyRepositoryFailure<PartyRoleDto>(
    kind: PartyRepositoryFailureKind.dependencyConflict,
    message: 'read only',
  );
}

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
