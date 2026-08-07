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
import 'package:neximmo_app/features/leasing_operations/domain/leasing_case_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';
import 'package:neximmo_app/ui/screens/property_detail/leasing/leasing_pipeline_panel.dart';

const String _workspace = 'workspace-a';
const String _property = 'property-a';

void main() {
  testWidgets('renders the empty state with a create affordance', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Noch kein Vermietungsfall'), findsOneWidget);
    expect(find.text('Fall anlegen'), findsWidgets);
  });

  testWidgets('forbidden is its own state, not empty', (tester) async {
    await _pump(tester, searchFailure: LeasingRepositoryFailureKind.forbidden);

    expect(find.text('Kein Zugriff auf die Pipeline'), findsOneWidget);
    expect(find.text('Noch kein Vermietungsfall'), findsNothing);
  });

  testWidgets('an infrastructure error offers a retry, not a raw exception', (
    tester,
  ) async {
    await _pump(
      tester,
      searchFailure: LeasingRepositoryFailureKind.infrastructureFailure,
    );

    expect(
      find.text('Die Pipeline konnte nicht geladen werden'),
      findsOneWidget,
    );
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('a read-only backend explains itself and disables mutations', (
    tester,
  ) async {
    await _pump(
      tester,
      cases: <LeasingCaseSummaryDto>[_summary('c1', 'Anfrage Meier')],
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

  testWidgets('the board shows a column per open stage, terminal ones hidden', (
    tester,
  ) async {
    await _pump(
      tester,
      cases: <LeasingCaseSummaryDto>[_summary('c1', 'Anfrage Meier')],
    );

    expect(find.text('Anfrage'), findsWidgets);
    expect(find.text('Übergabe'), findsWidgets);
    // openOnly is the board default: the archive stages are not columns.
    expect(find.text('Abgeschlossen'), findsNothing);
    expect(find.text('Abgebrochen'), findsNothing);
  });

  testWidgets('a case card names its prospect and unit, or says they are open',
      (tester) async {
    await _pump(
      tester,
      cases: <LeasingCaseSummaryDto>[_summary('c1', 'Anfrage Meier')],
    );

    expect(find.text('Anfrage Meier'), findsOneWidget);
    expect(find.text('Interessent offen'), findsOneWidget);
    expect(find.text('Einheit offen'), findsOneWidget);
  });

  testWidgets('the detail offers exactly the next stage', (tester) async {
    await _pump(
      tester,
      cases: <LeasingCaseSummaryDto>[_summary('c1', 'Anfrage Meier')],
      leasingCase: _case('c1', status: LeasingCaseStatus.inquiry),
    );

    await tester.tap(find.text('Anfrage Meier'));
    await tester.pumpAndSettle();

    expect(find.text('Auf „Kontakt"'), findsOneWidget);
    expect(find.text('Fall abbrechen'), findsOneWidget);
    // No backward edge exists to offer.
    expect(find.text('Auf „Anfrage"'), findsNothing);
  });

  testWidgets('a blocked step is disabled with its precondition named', (
    tester,
  ) async {
    await _pump(
      tester,
      cases: <LeasingCaseSummaryDto>[_summary('c1', 'Anfrage Meier')],
      // documentsPending -> screening needs a prospect, and there is none.
      leasingCase: _case('c1', status: LeasingCaseStatus.documentsPending),
    );

    await tester.tap(find.text('Anfrage Meier'));
    await tester.pumpAndSettle();

    expect(
      find.text('Der nächste Schritt ist noch nicht möglich'),
      findsOneWidget,
    );
    expect(
      find.textContaining('braucht der Fall einen benannten Interessenten'),
      findsOneWidget,
    );
    // `FilledButton.icon` builds a private subclass whose child is a row, so
    // the button is reached through its label rather than by its own shape.
    final advance = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Auf „Prüfung"'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    expect(advance.onPressed, isNull);
  });

  testWidgets('the signed step asks for the lease and blocks without one', (
    tester,
  ) async {
    await _pump(
      tester,
      cases: <LeasingCaseSummaryDto>[_summary('c1', 'Anfrage Meier')],
      leasingCase: _case(
        'c1',
        status: LeasingCaseStatus.contractDraft,
        prospectPartyId: 'p1',
        unitId: 'u1',
      ),
      units: <UnitSummaryDto>[_unit('u1', 'A-01')],
      parties: <PartySummaryDto>[_party('p1', 'Meier')],
    );

    await tester.tap(find.text('Anfrage Meier'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('braucht der Fall den Vertrag'),
      findsOneWidget,
    );
  });

  testWidgets('a terminal case offers no step at all', (tester) async {
    await _pump(
      tester,
      cases: <LeasingCaseSummaryDto>[_summary('c1', 'Anfrage Meier')],
      leasingCase: _case('c1', status: LeasingCaseStatus.cancelled),
    );

    await tester.tap(find.text('Anfrage Meier'));
    await tester.pumpAndSettle();

    expect(find.text('Fall abbrechen'), findsNothing);
    expect(find.text('Bearbeiten'), findsNothing);
    expect(
      find.textContaining('Ein neuer Anlauf ist ein neuer Fall'),
      findsOneWidget,
    );
  });

  testWidgets('the cancellation dialog refuses an empty reason', (
    tester,
  ) async {
    await _pump(
      tester,
      cases: <LeasingCaseSummaryDto>[_summary('c1', 'Anfrage Meier')],
      leasingCase: _case('c1'),
    );

    await tester.tap(find.text('Anfrage Meier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fall abbrechen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fall abbrechen').last);
    await tester.pumpAndSettle();

    expect(find.text('Bitte einen Grund angeben.'), findsOneWidget);
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
        cases: <LeasingCaseSummaryDto>[
          _summary('c1', 'Anfrage Meier'),
          _summary('c2', 'Anfrage Schulz', status: LeasingCaseStatus.viewing),
        ],
      );

      expect(find.text('Anfrage Meier'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester, {
  List<LeasingCaseSummaryDto> cases = const <LeasingCaseSummaryDto>[],
  List<UnitSummaryDto> units = const <UnitSummaryDto>[],
  List<PartySummaryDto> parties = const <PartySummaryDto>[],
  List<LeaseSummaryDto> leases = const <LeaseSummaryDto>[],
  LeasingCaseDto? leasingCase,
  LeasingRepositoryFailureKind? searchFailure,
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
        leasingCaseSearchProvider.overrideWithValue(
          _FakeCaseSearch(cases: cases, failure: searchFailure),
        ),
        leasingCaseRepositoryProvider.overrideWithValue(
          _FakeCaseRepository(leasingCase: leasingCase),
        ),
        unitSearchProvider.overrideWithValue(_FakeUnitSearch(units)),
        leaseSearchProvider.overrideWithValue(_FakeLeaseSearch(leases)),
        partySearchProvider.overrideWithValue(_FakePartySearch(parties)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: LeasingPipelinePanel(propertyId: _property)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

LeasingCaseSummaryDto _summary(
  String id,
  String name, {
  LeasingCaseStatus status = LeasingCaseStatus.inquiry,
}) => LeasingCaseSummaryDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  caseName: name,
  status: status,
  source: LeasingCaseSource.portal,
  openedAt: DateTime.utc(2026, 1, 1),
  version: 1,
);

LeasingCaseDto _case(
  String id, {
  LeasingCaseStatus status = LeasingCaseStatus.inquiry,
  String? unitId,
  String? prospectPartyId,
  String? leaseId,
}) => LeasingCaseDto(
  id: id,
  workspaceId: _workspace,
  propertyId: _property,
  caseName: 'Anfrage Meier',
  status: status,
  source: LeasingCaseSource.portal,
  openedAt: DateTime.utc(2026, 1, 1),
  version: 1,
  unitId: unitId,
  prospectPartyId: prospectPartyId,
  leaseId: leaseId,
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
  status: UnitStatus.vacant,
  version: 1,
);

PartySummaryDto _party(String id, String name) => PartySummaryDto(
  id: id,
  workspaceId: _workspace,
  type: PartyType.person,
  displayName: name,
  version: 1,
);

class _FakeCaseSearch implements LeasingCaseSearchPort {
  _FakeCaseSearch({required this.cases, this.failure});

  final List<LeasingCaseSummaryDto> cases;
  final LeasingRepositoryFailureKind? failure;

  @override
  Future<LeasingRepositoryResult<LeasingPageResult<LeasingCaseSummaryDto>>>
  search(LeasingCaseListQuery query) async {
    final kind = failure;
    if (kind != null) {
      return LeasingRepositoryFailure<LeasingPageResult<LeasingCaseSummaryDto>>(
        kind: kind,
        message: 'failed',
      );
    }
    return LeasingRepositorySuccess<LeasingPageResult<LeasingCaseSummaryDto>>(
      LeasingPageResult<LeasingCaseSummaryDto>(items: cases),
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

class _FakeCaseRepository implements LeasingCaseRepository {
  _FakeCaseRepository({this.leasingCase});

  final LeasingCaseDto? leasingCase;

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> getById({
    required String workspaceId,
    required String caseId,
  }) async {
    final value = leasingCase;
    if (value == null) {
      return const LeasingRepositoryFailure<LeasingCaseDto>(
        kind: LeasingRepositoryFailureKind.notFound,
        message: 'not found',
      );
    }
    return LeasingRepositorySuccess<LeasingCaseDto>(value);
  }

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> create(
    CreateLeasingCaseCommand command,
  ) async => const LeasingRepositoryFailure<LeasingCaseDto>(
    kind: LeasingRepositoryFailureKind.dependencyConflict,
    message: 'read only',
  );

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> update(
    UpdateLeasingCaseCommand command,
  ) async => const LeasingRepositoryFailure<LeasingCaseDto>(
    kind: LeasingRepositoryFailureKind.dependencyConflict,
    message: 'read only',
  );

  @override
  Future<LeasingRepositoryResult<LeasingCaseDto>> transitionStatus(
    TransitionLeasingCaseStatusCommand command,
  ) async => const LeasingRepositoryFailure<LeasingCaseDto>(
    kind: LeasingRepositoryFailureKind.dependencyConflict,
    message: 'read only',
  );
}
