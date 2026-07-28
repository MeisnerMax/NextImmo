import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/contacts_parties/application/parties_controller.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_providers.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_repository.dart';
import 'package:neximmo_app/features/contacts_parties/domain/party_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/ui/screens/parties/parties_screen.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Mandatory-state coverage for the new `PartiesScreen` (Phase 2, Wave 2,
/// Arbeitspaket 1) — the pattern proof for consuming a Wave 2 feature contract
/// through the backend-selected providers. Every state of `03_design_system.md`
/// that applies is asserted here, including the three that Wave 1 rarely hit:
/// `forbidden`, `versionConflict` and "read-only until migrated".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String workspace = 'ws-1';

  /// `find.byType` matches the exact runtime type, so the private
  /// `*.icon` button subclasses would slip through. Match by `is` instead.
  Finder buttonWithText<T extends Widget>(String text) {
    return find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate((widget) => widget is T),
    );
  }

  WorkspaceSessionScope cloudScope({
    Set<String> permissions = const <String>{'party.read', 'party.manage'},
  }) {
    return WorkspaceSessionScope(
      workspaceId: workspace,
      actorId: 'actor-1',
      permissions: permissions,
      mutationsSupported: true,
    );
  }

  WorkspaceSessionScope localScope() {
    return WorkspaceSessionScope(
      workspaceId: workspace,
      actorId: 'actor-1',
      permissions: const <String>{},
      mutationsSupported: false,
    );
  }

  PartySummaryDto summary(String id, String name, {DateTime? deletedAt}) {
    return PartySummaryDto(
      id: id,
      workspaceId: workspace,
      type: PartyType.person,
      displayName: name,
      version: 3,
      email: '$id@example.test',
      deletedAt: deletedAt,
    );
  }

  PartyDto full(String id, String name) {
    return PartyDto(
      id: id,
      workspaceId: workspace,
      type: PartyType.person,
      displayName: name,
      version: 3,
      email: '$id@example.test',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 2, 1),
      createdBy: 'actor-1',
      updatedBy: 'actor-1',
    );
  }

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    required _FakePartyBackend backend,
    WorkspaceSessionScope? scope,
    Size size = const Size(1440, 900),
    AppDensityModeSetting density = AppDensityModeSetting.comfort,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          workspaceSessionScopeProvider.overrideWithValue(
            scope ?? cloudScope(),
          ),
          partyRepositoryProvider.overrideWithValue(backend),
          partySearchProvider.overrideWithValue(backend),
          partyRoleProvider.overrideWithValue(backend),
          duplicateDetectionProvider.overrideWithValue(backend),
        ],
        child: MaterialApp(
          theme: AppTheme.light(densityMode: density),
          home: const Scaffold(body: PartiesScreen()),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
    return ProviderScope.containerOf(
      tester.element(find.byType(PartiesScreen)),
    );
  }

  testWidgets('loading shows a table skeleton, not a full-page spinner', (
    tester,
  ) async {
    final backend = _FakePartyBackend(parties: <PartySummaryDto>[]);
    backend.holdSearch();
    await pumpScreen(tester, backend: backend, settle: false);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // The header stays visible while the table area loads.
    expect(find.text('Parteien'), findsWidgets);

    backend.releaseSearch();
    await tester.pumpAndSettle();
  });

  testWidgets('empty directory names the next concrete action', (tester) async {
    await pumpScreen(
      tester,
      backend: _FakePartyBackend(parties: <PartySummaryDto>[]),
    );

    expect(find.text('Noch keine Parteien'), findsOneWidget);
    expect(buttonWithText<FilledButton>('Neue Partei'), findsWidgets);
  });

  testWidgets('infrastructure failure offers retry without raw exception text', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      backend: _FakePartyBackend(
        searchFailure: const PartyRepositoryFailure<PartyPageResult>(
          kind: PartyRepositoryFailureKind.infrastructureFailure,
          message: 'Exception: socket closed',
        ),
      ),
    );

    expect(find.text('Parteien konnten nicht geladen werden'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('forbidden is its own state, distinct from empty and error', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      backend: _FakePartyBackend(
        searchFailure: const PartyRepositoryFailure<PartyPageResult>(
          kind: PartyRepositoryFailureKind.forbidden,
          message: 'party.read missing',
        ),
      ),
    );

    expect(find.text('Kein Zugriff auf Parteien'), findsOneWidget);
    expect(find.text('Noch keine Parteien'), findsNothing);
    expect(find.text('Parteien konnten nicht geladen werden'), findsNothing);
  });

  testWidgets('selecting a party shows identity and its roles', (tester) async {
    final backend = _FakePartyBackend(
      parties: <PartySummaryDto>[summary('p1', 'Ada Lovelace')],
      party: full('p1', 'Ada Lovelace'),
      roles: <PartyRoleDto>[
        PartyRoleDto(
          id: 'r1',
          workspaceId: workspace,
          partyId: 'p1',
          roleType: PartyRoleType.tenant,
          validFrom: DateTime.utc(2026, 1, 1),
          version: 1,
        ),
      ],
    );
    await pumpScreen(tester, backend: backend);

    expect(find.text('Ada Lovelace'), findsOneWidget);
    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();

    expect(find.text('Rollen'), findsOneWidget);
    expect(find.text('Mieter'), findsWidgets);
  });

  testWidgets('read-only backend explains itself and disables creating', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      backend: _FakePartyBackend(
        parties: <PartySummaryDto>[summary('p1', 'Ada Lovelace')],
      ),
      scope: localScope(),
    );

    expect(find.text('Schreibgeschützt bis zur Migration'), findsOneWidget);
    final createButton =
        tester.widgetList<FilledButton>(
          buttonWithText<FilledButton>('Neue Partei'),
        ).first;
    expect(createButton.onPressed, isNull);
  });

  testWidgets('a mutation on the read-only backend reports it instead of '
      'silently no-opping', (tester) async {
    final backend = _FakePartyBackend(
      parties: <PartySummaryDto>[summary('p1', 'Ada Lovelace')],
    );
    final container = await pumpScreen(
      tester,
      backend: backend,
      scope: localScope(),
    );

    await container
        .read(partiesControllerProvider.notifier)
        .createParty(
          const PartyDraft(type: PartyType.person, displayName: 'Neu'),
        );
    await tester.pumpAndSettle();

    expect(backend.createCalls, 0);
    expect(find.textContaining('schreibgeschützt'), findsOneWidget);
  });

  testWidgets('version conflict shows both versions and a resolve action', (
    tester,
  ) async {
    final current = full('p1', 'Ada Lovelace');
    final backend = _FakePartyBackend(
      parties: <PartySummaryDto>[summary('p1', 'Ada Lovelace')],
      party: current,
      updateFailure: PartyRepositoryFailure<PartyDto>(
        kind: PartyRepositoryFailureKind.versionConflict,
        message: 'stale',
        versionConflict: PartyVersionConflict(
          expectedVersion: 3,
          actualVersion: 5,
          currentParty: current,
        ),
      ),
    );
    final container = await pumpScreen(tester, backend: backend);

    await container
        .read(partiesControllerProvider.notifier)
        .updateParty(
          partyId: 'p1',
          expectedVersion: 3,
          changes: const PartyUpdateDto(
            type: PartyType.person,
            displayName: 'Ada L.',
          ),
        );
    await tester.pumpAndSettle();

    expect(find.text('Zwischenzeitlich geändert'), findsOneWidget);
    expect(find.textContaining('Deine Version: 3'), findsOneWidget);
    expect(find.textContaining('Aktuelle Version: 5'), findsOneWidget);
    expect(find.text('Aktuellen Stand laden'), findsOneWidget);
  });

  testWidgets('missing party.manage forbids mutations without pretending', (
    tester,
  ) async {
    final backend = _FakePartyBackend(
      parties: <PartySummaryDto>[summary('p1', 'Ada Lovelace')],
    );
    final container = await pumpScreen(
      tester,
      backend: backend,
      scope: cloudScope(permissions: const <String>{'party.read'}),
    );

    await container
        .read(partiesControllerProvider.notifier)
        .createParty(
          const PartyDraft(type: PartyType.person, displayName: 'Neu'),
        );
    await tester.pumpAndSettle();

    expect(backend.createCalls, 0);
    expect(find.textContaining('fehlt die Berechtigung'), findsOneWidget);
  });

  testWidgets('the create dialog warns about a probable duplicate', (
    tester,
  ) async {
    final backend = _FakePartyBackend(
      parties: <PartySummaryDto>[summary('p1', 'Ada Lovelace')],
      duplicates: <PartyDuplicateCandidate>[
        PartyDuplicateCandidate(
          party: summary('p1', 'Ada Lovelace'),
          matchEmail: true,
          matchPhone: false,
          matchName: true,
        ),
      ],
    );
    await pumpScreen(tester, backend: backend);

    await tester.tap(buttonWithText<FilledButton>('Neue Partei').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Anzeigename'),
      'Ada Lovelace',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Mögliche Dublette'), findsOneWidget);
    expect(find.textContaining('Treffer: Name, E-Mail'), findsOneWidget);
  });

  testWidgets('merging two parties requires an explicit confirmation', (
    tester,
  ) async {
    final backend = _FakePartyBackend(
      parties: <PartySummaryDto>[
        summary('p1', 'Ada Lovelace'),
        summary('p2', 'A. Lovelace'),
      ],
      party: full('p1', 'Ada Lovelace'),
    );
    await pumpScreen(tester, backend: backend);

    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();
    await tester.tap(buttonWithText<OutlinedButton>('Zusammenführen'));
    await tester.pumpAndSettle();

    expect(find.text('Parteien zusammenführen'), findsOneWidget);
    expect(backend.mergeCalls, 0);

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(backend.mergeCalls, 0);
  });

  group('responsive', () {
    const sizes = <String, Size>{
      'phone 390x844': Size(390, 844),
      'tablet 1024x768': Size(1024, 768),
      'desktop 1440x900': Size(1440, 900),
    };

    for (final density in AppDensityModeSetting.values) {
      for (final entry in sizes.entries) {
        testWidgets('${entry.key} renders in ${density.name} density', (
          tester,
        ) async {
          await pumpScreen(
            tester,
            backend: _FakePartyBackend(
              parties: <PartySummaryDto>[
                summary('p1', 'Ada Lovelace'),
                summary('p2', 'Grace Hopper'),
              ],
            ),
            size: entry.value,
            density: density,
          );

          expect(tester.takeException(), isNull);
          expect(find.text('Ada Lovelace'), findsOneWidget);
        });
      }
    }
  });
}

/// One fake serving all four party ports, matching how a real backend binds
/// them (one adapter instance per domain).
class _FakePartyBackend
    implements
        PartyRepository,
        PartySearchPort,
        PartyRoleRepository,
        DuplicateDetectionPort {
  _FakePartyBackend({
    this.parties = const <PartySummaryDto>[],
    this.party,
    this.roles = const <PartyRoleDto>[],
    this.duplicates = const <PartyDuplicateCandidate>[],
    this.searchFailure,
    this.updateFailure,
  });

  final List<PartySummaryDto> parties;
  final PartyDto? party;
  final List<PartyRoleDto> roles;
  final List<PartyDuplicateCandidate> duplicates;
  final PartyRepositoryFailure<PartyPageResult>? searchFailure;
  final PartyRepositoryFailure<PartyDto>? updateFailure;

  int createCalls = 0;
  int mergeCalls = 0;
  Completer<void>? _searchGate;

  void holdSearch() => _searchGate = Completer<void>();

  void releaseSearch() => _searchGate?.complete();

  @override
  Future<PartyRepositoryResult<PartyPageResult>> search(
    PartyListQuery query,
  ) async {
    await _searchGate?.future;
    final failure = searchFailure;
    if (failure != null) {
      return failure;
    }
    return PartyRepositorySuccess<PartyPageResult>(
      PartyPageResult(items: parties),
    );
  }

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
  ) async {
    createCalls++;
    final value = party;
    if (value == null) {
      return const PartyRepositoryFailure<PartyDto>(
        kind: PartyRepositoryFailureKind.infrastructureFailure,
        message: 'no fixture',
      );
    }
    return PartyRepositorySuccess<PartyDto>(value);
  }

  @override
  Future<PartyRepositoryResult<PartyDto>> update(
    UpdatePartyCommand command,
  ) async {
    final failure = updateFailure;
    if (failure != null) {
      return failure;
    }
    return PartyRepositorySuccess<PartyDto>(party!);
  }

  @override
  Future<PartyRepositoryResult<PartyDto>> merge(
    MergePartiesCommand command,
  ) async {
    mergeCalls++;
    return PartyRepositorySuccess<PartyDto>(party!);
  }

  @override
  Future<PartyRepositoryResult<List<PartyRoleDto>>> listForParty({
    required String workspaceId,
    required String partyId,
  }) async {
    return PartyRepositorySuccess<List<PartyRoleDto>>(roles);
  }

  @override
  Future<PartyRepositoryResult<ContractorDetailsDto?>> getContractorDetails({
    required String workspaceId,
    required String partyId,
  }) async {
    return const PartyRepositorySuccess<ContractorDetailsDto?>(null);
  }

  @override
  Future<PartyRepositoryResult<PartyRoleDto>> assign(
    AssignPartyRoleCommand command,
  ) async {
    return PartyRepositorySuccess<PartyRoleDto>(roles.first);
  }

  @override
  Future<PartyRepositoryResult<PartyRoleDto>> end(
    EndPartyRoleCommand command,
  ) async {
    return PartyRepositorySuccess<PartyRoleDto>(roles.first);
  }

  @override
  Future<PartyRepositoryResult<List<PartyDuplicateCandidate>>> detect(
    PartyDuplicateQuery query,
  ) async {
    return PartyRepositorySuccess<List<PartyDuplicateCandidate>>(duplicates);
  }
}
