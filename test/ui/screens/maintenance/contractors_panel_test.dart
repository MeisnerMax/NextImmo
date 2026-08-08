import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_providers.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_repository.dart';
import 'package:neximmo_app/features/contacts_parties/domain/party_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/ui/screens/maintenance/contractors_panel.dart';

const String _workspace = 'workspace-a';

void main() {
  testWidgets('renders the empty state and explains what a contractor is', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Noch kein Handwerker'), findsOneWidget);
    expect(
      find.textContaining('Partei mit Dienstleister-Rolle'),
      findsOneWidget,
    );
  });

  testWidgets('forbidden names the party permission', (tester) async {
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

    expect(
      find.text('Handwerker konnten nicht geladen werden'),
      findsOneWidget,
    );
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('lists contractors with their party type badge', (tester) async {
    await _pump(
      tester,
      contractors: <PartySummaryDto>[
        _party('p1', 'Handwerksbetrieb GmbH', type: PartyType.organization),
      ],
    );

    expect(find.text('Handwerksbetrieb GmbH'), findsOneWidget);
    expect(find.text('Organisation'), findsOneWidget);
  });

  testWidgets('the detail shows the contractor satellite read-only', (
    tester,
  ) async {
    await _pump(
      tester,
      contractors: <PartySummaryDto>[_party('p1', 'Handwerksbetrieb GmbH')],
      party: _partyDto('p1'),
      roles: <PartyRoleDto>[_role('r1')],
      details: const ContractorDetailsDto(
        partyId: 'p1',
        workspaceId: _workspace,
        tradeCategory: 'Sanitär',
        isActive: true,
        version: 1,
        hourlyRate: 65,
      ),
    );

    await tester.tap(find.text('Handwerksbetrieb GmbH'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sanitär'), findsOneWidget);
    expect(find.textContaining('65'), findsOneWidget);
  });

  testWidgets('a version conflict surfaces its own dialog', (tester) async {
    await _pump(
      tester,
      contractors: <PartySummaryDto>[_party('p1', 'Handwerksbetrieb GmbH')],
      party: _partyDto('p1'),
      roles: <PartyRoleDto>[_role('r1')],
      updateFailure: PartyRepositoryFailureKind.versionConflict,
    );

    await tester.tap(find.text('Handwerksbetrieb GmbH'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kontakt bearbeiten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(
      find.text('Partei wurde zwischenzeitlich geändert'),
      findsOneWidget,
    );
  });

  testWidgets('mutations are disabled without party.manage', (tester) async {
    await _pump(
      tester,
      contractors: <PartySummaryDto>[_party('p1', 'Handwerksbetrieb GmbH')],
      permissions: const <String>{'party.read'},
    );

    final createButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Handwerker anlegen'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    expect(createButton.onPressed, isNull);
  });

  for (final size in const <Size>[
    Size(390, 844),
    Size(1024, 768),
    Size(1440, 900),
  ]) {
    testWidgets('lays out without overflow at $size', (tester) async {
      await _pump(
        tester,
        contractors: <PartySummaryDto>[
          _party('p1', 'Handwerksbetrieb GmbH'),
          _party('p2', 'Zweite Firma', type: PartyType.organization),
        ],
        size: size,
      );

      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester, {
  List<PartySummaryDto> contractors = const <PartySummaryDto>[],
  List<PartyRoleDto> roles = const <PartyRoleDto>[],
  PartyDto? party,
  ContractorDetailsDto? details,
  PartyRepositoryFailureKind? searchFailure,
  PartyRepositoryFailureKind? updateFailure,
  Set<String> permissions = const <String>{'party.read', 'party.manage'},
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
            permissions: permissions,
            mutationsSupported: true,
          ),
        ),
        partySearchProvider.overrideWithValue(
          _FakePartySearch(parties: contractors, failure: searchFailure),
        ),
        partyRepositoryProvider.overrideWithValue(
          _FakePartyRepository(party: party, updateFailure: updateFailure),
        ),
        partyRoleProvider.overrideWithValue(_FakePartyRoles(roles, details)),
      ],
      child: const MaterialApp(home: Scaffold(body: ContractorsPanel())),
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
  displayName: 'Handwerksbetrieb GmbH',
  version: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  createdBy: 'actor-1',
  updatedBy: 'actor-1',
);

PartyRoleDto _role(String id) => PartyRoleDto(
  id: id,
  workspaceId: _workspace,
  partyId: 'p1',
  roleType: PartyRoleType.contractor,
  validFrom: DateTime.utc(2026, 1, 1),
  version: 1,
);

class _FakePartySearch implements PartySearchPort {
  _FakePartySearch({required this.parties, this.failure});

  final List<PartySummaryDto> parties;
  final PartyRepositoryFailureKind? failure;

  @override
  Future<PartyRepositoryResult<PartyPageResult>> search(
    PartyListQuery query,
  ) async {
    final failure = this.failure;
    if (failure != null) {
      return PartyRepositoryFailure<PartyPageResult>(
        kind: failure,
        message: 'fail',
      );
    }
    return PartyRepositorySuccess<PartyPageResult>(
      PartyPageResult(items: parties),
    );
  }
}

class _FakePartyRepository implements PartyRepository {
  _FakePartyRepository({this.party, this.updateFailure});

  final PartyDto? party;
  final PartyRepositoryFailureKind? updateFailure;

  @override
  Future<PartyRepositoryResult<PartyDto>> getById({
    required String workspaceId,
    required String partyId,
  }) async {
    final party = this.party;
    if (party == null) {
      return const PartyRepositoryFailure<PartyDto>(
        kind: PartyRepositoryFailureKind.notFound,
        message: 'not found',
      );
    }
    return PartyRepositorySuccess<PartyDto>(party);
  }

  @override
  Future<PartyRepositoryResult<PartyDto>> create(
    CreatePartyCommand command,
  ) async {
    final createdParty = PartyDto(
      id: 'new',
      workspaceId: _workspace,
      type: command.draft.type,
      displayName: command.draft.displayName,
      version: 1,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      createdBy: 'actor-1',
      updatedBy: 'actor-1',
    );
    return PartyRepositorySuccess<PartyDto>(createdParty);
  }

  @override
  Future<PartyRepositoryResult<PartyDto>> update(
    UpdatePartyCommand command,
  ) async {
    final failure = updateFailure;
    if (failure == PartyRepositoryFailureKind.versionConflict) {
      return PartyRepositoryFailure<PartyDto>(
        kind: failure!,
        message: 'stale',
        versionConflict: PartyVersionConflict(
          expectedVersion: 1,
          actualVersion: 2,
          currentParty: PartyDto(
            id: command.partyId,
            workspaceId: _workspace,
            type: PartyType.organization,
            displayName: 'Handwerksbetrieb GmbH',
            version: 2,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
            createdBy: 'actor-1',
            updatedBy: 'actor-1',
          ),
        ),
      );
    }
    if (failure != null) {
      return PartyRepositoryFailure<PartyDto>(kind: failure, message: 'fail');
    }
    final updated = PartyDto(
      id: command.partyId,
      workspaceId: _workspace,
      type: command.changes.type,
      displayName: command.changes.displayName,
      version: command.expectedVersion + 1,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      createdBy: 'actor-1',
      updatedBy: 'actor-1',
    );
    return PartyRepositorySuccess<PartyDto>(updated);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePartyRoles implements PartyRoleRepository {
  _FakePartyRoles(this.roles, this.details);

  final List<PartyRoleDto> roles;
  final ContractorDetailsDto? details;

  @override
  Future<PartyRepositoryResult<List<PartyRoleDto>>> listForParty({
    required String workspaceId,
    required String partyId,
  }) async => PartyRepositorySuccess<List<PartyRoleDto>>(roles);

  @override
  Future<PartyRepositoryResult<ContractorDetailsDto?>> getContractorDetails({
    required String workspaceId,
    required String partyId,
  }) async => PartyRepositorySuccess<ContractorDetailsDto?>(details);

  @override
  Future<PartyRepositoryResult<PartyRoleDto>> assign(
    AssignPartyRoleCommand command,
  ) async {
    return PartyRepositorySuccess<PartyRoleDto>(
      PartyRoleDto(
        id: 'r-new',
        workspaceId: _workspace,
        partyId: command.partyId,
        roleType: command.roleType,
        validFrom: DateTime.utc(2026, 1, 1),
        version: 1,
      ),
    );
  }

  @override
  Future<PartyRepositoryResult<PartyRoleDto>> end(
    EndPartyRoleCommand command,
  ) async {
    return PartyRepositorySuccess<PartyRoleDto>(
      PartyRoleDto(
        id: command.partyRoleId,
        workspaceId: _workspace,
        partyId: 'p1',
        roleType: PartyRoleType.contractor,
        validFrom: DateTime.utc(2026, 1, 1),
        validUntil: DateTime.utc(2026, 6, 1),
        version: command.expectedVersion + 1,
      ),
    );
  }
}
