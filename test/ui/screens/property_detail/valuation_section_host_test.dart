import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/valuation/application/valuation_case_controller.dart';
import 'package:neximmo_app/features/valuation/application/valuation_providers.dart';
import 'package:neximmo_app/features/valuation/application/valuation_repository.dart';
import 'package:neximmo_app/features/valuation/domain/cash_flow_projection.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case_dto.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';
import 'package:neximmo_app/ui/screens/property_detail/widgets/valuation/valuation_section_host.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

ValuationCaseDto _caseDto({
  ValuationCaseStatus status = ValuationCaseStatus.draft,
}) => ValuationCaseDto(
  id: 'case-1',
  workspaceId: 'ws-1',
  propertyId: 'prop-1',
  scenarioId: 'scn-1',
  title: 'Basisszenario',
  kind: ValuationCaseKind.holding,
  status: status,
  dcfTerminal: DcfTerminalMethod.exitCap,
  enabledMethods: const {ValuationMethodKind.incomeApproachDe},
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 28),
  createdBy: 'user-1',
  updatedBy: 'user-1',
  version: 2,
);

class _FakePorts
    implements ValuationCaseRepository, ValuationFactorPort, ValuationReportPort {
  _FakePorts({this.cases = const [], this.searchFailure});

  List<ValuationCaseDto> cases;
  ValuationRepositoryFailure<Object?>? searchFailure;

  final created = <CreateValuationCaseCommand>[];
  final transitions = <TransitionValuationCaseStatusCommand>[];

  @override
  Future<ValuationRepositoryResult<ValuationPageResult<ValuationCaseDto>>>
  searchValuationCases(ValuationCaseListQuery query) async {
    final failure = searchFailure;
    if (failure != null) {
      return ValuationRepositoryFailure<ValuationPageResult<ValuationCaseDto>>(
        kind: failure.kind,
        message: failure.message,
      );
    }
    return ValuationRepositorySuccess(ValuationPageResult(items: cases));
  }

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> getValuationCaseById({
    required String workspaceId,
    required String valuationCaseId,
  }) async => ValuationRepositorySuccess(
    ValuationCaseDetail(
      valuationCase: cases.isEmpty ? _caseDto() : cases.first,
      factors: <ValuationFactorDto>[
        ValuationFactorDto(
          caseId: valuationCaseId,
          factorId: ValuationFactorIds.grossRentAnnual,
          label: 'Rohertrag',
          provenance: FactorProvenance.userProvided,
          confidence: ConfidenceBand.high,
          value: 60000,
        ),
      ],
    ),
  );

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> createValuationCase(
    CreateValuationCaseCommand command,
  ) async {
    created.add(command);
    cases = <ValuationCaseDto>[_caseDto()];
    return ValuationRepositorySuccess(
      ValuationCaseDetail(valuationCase: _caseDto(), factors: const []),
    );
  }

  @override
  Future<ValuationRepositoryResult<ValuationCaseDto>>
  transitionValuationCaseStatus(
    TransitionValuationCaseStatusCommand command,
  ) async {
    transitions.add(command);
    return ValuationRepositorySuccess(_caseDto(status: command.targetStatus));
  }

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> updateValuationCase(
    UpdateValuationCaseCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<ValuationRepositoryResult<List<ValuationFactorDto>>> listFactors({
    required String workspaceId,
    required String valuationCaseId,
  }) async => const ValuationRepositorySuccess(<ValuationFactorDto>[]);

  @override
  Future<ValuationRepositoryResult<List<ValuationFactorDto>>> upsertFactors(
    UpsertValuationFactorsCommand command,
  ) async => ValuationRepositorySuccess(command.factors);

  @override
  Future<ValuationRepositoryResult<ValuationReportSnapshot>> latestReport({
    required String workspaceId,
    required String valuationCaseId,
  }) async => const ValuationRepositoryFailure(
    kind: ValuationRepositoryFailureKind.notFound,
    message: 'kein Bericht',
  );

  @override
  Future<ValuationRepositoryResult<ValuationReportSnapshot>> publishReport(
    PublishValuationReportCommand command,
  ) async => ValuationRepositorySuccess(
    ValuationReportSnapshot(
      valuationCaseId: command.valuationCaseId,
      computedFromVersion: command.expectedVersion,
      methodResults: const [],
    ),
  );
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required _FakePorts ports,
  Set<String> permissions = const {
    ValuationPermissions.read,
    ValuationPermissions.manage,
  },
  bool mutationsSupported = true,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        valuationCaseRepositoryProvider.overrideWithValue(ports),
        valuationFactorProvider.overrideWithValue(ports),
        valuationReportProvider.overrideWithValue(ports),
        workspaceSessionScopeProvider.overrideWithValue(
          WorkspaceSessionScope(
            workspaceId: 'ws-1',
            actorId: 'user-1',
            permissions: permissions,
            mutationsSupported: mutationsSupported,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: ValuationSectionHost(
              scenarioId: 'scn-1',
              propertyId: 'prop-1',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a scenario without a case offers creating one', (tester) async {
    final ports = _FakePorts();

    await _pumpHost(tester, ports: ports);

    expect(find.text('Noch keine Bewertung'), findsOneWidget);

    await tester.tap(find.text('Bewertung anlegen'));
    await tester.pumpAndSettle();

    expect(ports.created.single.propertyId, 'prop-1');
    expect(ports.created.single.scenarioId, 'scn-1');
  });

  testWidgets('an existing case renders its valuation result', (tester) async {
    final ports = _FakePorts(cases: <ValuationCaseDto>[_caseDto()]);

    await _pumpHost(tester, ports: ports);

    expect(find.text('Wertermittlung'), findsOneWidget);
    expect(find.text('Verkehrswert'), findsOneWidget);
    // Two factors short of any method: the section says so instead of a number.
    expect(find.text('nicht ermittelbar'), findsWidgets);
  });

  testWidgets('the read-only backend offers no publish action', (tester) async {
    final ports = _FakePorts(cases: <ValuationCaseDto>[_caseDto()]);

    await _pumpHost(tester, ports: ports, mutationsSupported: false);

    expect(find.text('Bericht veröffentlichen'), findsNothing);
  });

  testWidgets('an approved case offers no write actions at all', (tester) async {
    final ports = _FakePorts(
      cases: <ValuationCaseDto>[_caseDto(status: ValuationCaseStatus.approved)],
    );

    await _pumpHost(tester, ports: ports);

    expect(find.text('Bericht veröffentlichen'), findsNothing);
    expect(find.text('Freigeben'), findsNothing);
    expect(find.text('Freigegeben'), findsOneWidget);
  });

  testWidgets('approval asks first and states that it is final', (tester) async {
    final ports = _FakePorts(
      cases: <ValuationCaseDto>[_caseDto(status: ValuationCaseStatus.inReview)],
    );

    await _pumpHost(
      tester,
      ports: ports,
      permissions: const {
        ValuationPermissions.read,
        ValuationPermissions.manage,
        ValuationPermissions.approve,
      },
    );

    await tester.tap(find.text('Freigeben'));
    await tester.pumpAndSettle();

    expect(find.text('Bewertung freigeben?'), findsOneWidget);
    expect(find.textContaining('unveränderlich'), findsOneWidget);

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(ports.transitions, isEmpty);

    await tester.tap(find.text('Freigeben'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Freigeben'));
    await tester.pumpAndSettle();

    expect(
      ports.transitions.single.targetStatus,
      ValuationCaseStatus.approved,
    );
  });

  testWidgets('a forbidden lookup is not shown as an empty scenario',
      (tester) async {
    final ports = _FakePorts(
      searchFailure: const ValuationRepositoryFailure<Object?>(
        kind: ValuationRepositoryFailureKind.forbidden,
        message: 'Kein Zugriff.',
      ),
    );

    await _pumpHost(tester, ports: ports);

    expect(find.text('Kein Zugriff auf Bewertungen'), findsOneWidget);
    expect(find.text('Bewertung anlegen'), findsNothing);
  });

  testWidgets('a failed lookup offers a retry', (tester) async {
    final ports = _FakePorts(
      searchFailure: const ValuationRepositoryFailure<Object?>(
        kind: ValuationRepositoryFailureKind.infrastructureFailure,
        message: 'Verbindung fehlgeschlagen.',
      ),
    );

    await _pumpHost(tester, ports: ports);

    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('without the read permission nothing is queried', (tester) async {
    final ports = _FakePorts();

    await _pumpHost(tester, ports: ports, permissions: const {});

    expect(find.text('Kein Zugriff auf Bewertungen'), findsOneWidget);
  });
}
