import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/valuation/application/valuation_case_controller.dart';
import 'package:neximmo_app/features/valuation/application/valuation_repository.dart';
import 'package:neximmo_app/features/valuation/domain/cash_flow_projection.dart';
import 'package:neximmo_app/features/valuation/domain/methods/comparison_approach_method.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case_dto.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';

ValuationCaseDto _caseDto({
  int version = 3,
  ValuationCaseStatus status = ValuationCaseStatus.draft,
}) => ValuationCaseDto(
  id: 'case-1',
  workspaceId: 'ws-1',
  propertyId: 'prop-1',
  title: 'Musterfall MFH',
  kind: ValuationCaseKind.holding,
  status: status,
  dcfTerminal: DcfTerminalMethod.exitCap,
  enabledMethods: const {
    ValuationMethodKind.incomeApproachDe,
    ValuationMethodKind.comparisonApproach,
  },
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 28),
  createdBy: 'user-1',
  updatedBy: 'user-1',
  version: version,
);

ValuationFactorDto _factor({
  required String factorId,
  required String label,
  required double value,
  FactorProvenance provenance = FactorProvenance.userProvided,
}) => ValuationFactorDto(
  caseId: 'case-1',
  factorId: factorId,
  label: label,
  provenance: provenance,
  confidence: ConfidenceBand.high,
  value: value,
);

/// A case whose Ertragswertverfahren is complete and whose comparison approach
/// is not — the mix the screen has to render side by side.
List<ValuationFactorDto> _factors({
  FactorProvenance liegenschaftszins = FactorProvenance.userProvided,
}) => [
  _factor(
    factorId: ValuationFactorIds.grossRentAnnual,
    label: 'Rohertrag',
    value: 60000,
  ),
  _factor(
    factorId: ValuationFactorIds.operatingExpensesAnnual,
    label: 'Bewirtschaftungskosten',
    value: 15000,
  ),
  _factor(
    factorId: ValuationFactorIds.landValue,
    label: 'Bodenwert',
    value: 200000,
  ),
  _factor(
    factorId: ValuationFactorIds.liegenschaftszinssatz,
    label: 'Liegenschaftszinssatz',
    value: 0.035,
    provenance: liegenschaftszins,
  ),
  _factor(
    factorId: ValuationFactorIds.remainingUsefulLifeYears,
    label: 'Restnutzungsdauer',
    value: 50,
  ),
  _factor(
    factorId: ValuationFactorIds.subjectLivingAreaSqm,
    label: 'Wohnfläche',
    value: 300,
  ),
];

class _FakePorts
    implements ValuationCaseRepository, ValuationFactorPort, ValuationReportPort {
  _FakePorts({
    ValuationCaseDetail? detail,
    this.loadFailure,
    this.mutationFailure,
  }) : detail = detail ??
            ValuationCaseDetail(
              valuationCase: _caseDto(),
              factors: _factors(),
            );

  ValuationCaseDetail detail;
  ValuationRepositoryFailure<Object?>? loadFailure;
  ValuationRepositoryFailure<Object?>? mutationFailure;

  final upserts = <UpsertValuationFactorsCommand>[];
  final publishes = <PublishValuationReportCommand>[];
  final transitions = <TransitionValuationCaseStatusCommand>[];
  int loads = 0;

  ValuationRepositoryResult<T> _fail<T>(
    ValuationRepositoryFailure<Object?> failure,
  ) => ValuationRepositoryFailure<T>(
    kind: failure.kind,
    message: failure.message,
    versionConflict: failure.versionConflict,
  );

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> getValuationCaseById({
    required String workspaceId,
    required String valuationCaseId,
  }) async {
    loads++;
    final failure = loadFailure;
    if (failure != null) return _fail<ValuationCaseDetail>(failure);
    return ValuationRepositorySuccess(detail);
  }

  @override
  Future<ValuationRepositoryResult<List<ValuationFactorDto>>> upsertFactors(
    UpsertValuationFactorsCommand command,
  ) async {
    upserts.add(command);
    final failure = mutationFailure;
    if (failure != null) return _fail<List<ValuationFactorDto>>(failure);
    return ValuationRepositorySuccess(command.factors);
  }

  @override
  Future<ValuationRepositoryResult<ValuationReportSnapshot>> publishReport(
    PublishValuationReportCommand command,
  ) async {
    publishes.add(command);
    final failure = mutationFailure;
    if (failure != null) return _fail<ValuationReportSnapshot>(failure);
    return ValuationRepositorySuccess(
      ValuationReportSnapshot(
        valuationCaseId: command.valuationCaseId,
        computedFromVersion: command.expectedVersion,
        methodResults: const [],
      ),
    );
  }

  @override
  Future<ValuationRepositoryResult<ValuationCaseDto>>
  transitionValuationCaseStatus(
    TransitionValuationCaseStatusCommand command,
  ) async {
    transitions.add(command);
    final failure = mutationFailure;
    if (failure != null) return _fail<ValuationCaseDto>(failure);
    return ValuationRepositorySuccess(_caseDto(status: command.targetStatus));
  }

  @override
  Future<ValuationRepositoryResult<List<ValuationFactorDto>>> listFactors({
    required String workspaceId,
    required String valuationCaseId,
  }) async => ValuationRepositorySuccess(detail.factors);

  @override
  Future<ValuationRepositoryResult<ValuationReportSnapshot>> latestReport({
    required String workspaceId,
    required String valuationCaseId,
  }) async => const ValuationRepositoryFailure(
    kind: ValuationRepositoryFailureKind.notFound,
    message: 'kein Bericht',
  );

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> createValuationCase(
    CreateValuationCaseCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> updateValuationCase(
    UpdateValuationCaseCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<ValuationRepositoryResult<ValuationPageResult<ValuationCaseDto>>>
  searchValuationCases(ValuationCaseListQuery query) async =>
      throw UnimplementedError();
}

WorkspaceSessionScope _scope({
  Set<String> permissions = const {
    ValuationPermissions.read,
    ValuationPermissions.manage,
  },
  bool mutationsSupported = true,
}) => WorkspaceSessionScope(
  workspaceId: 'ws-1',
  actorId: 'user-1',
  permissions: permissions,
  mutationsSupported: mutationsSupported,
);

ValuationCaseController _controller(
  _FakePorts ports, {
  WorkspaceSessionScope? scope,
}) {
  var counter = 0;
  return ValuationCaseController(
    valuationCaseId: 'case-1',
    repository: ports,
    factors: ports,
    reports: ports,
    scope: scope ?? _scope(),
    idFactory: () => 'id-${counter++}',
  );
}

void main() {
  group('load', () {
    test('computes the live report and keeps unavailability visible', () async {
      final ports = _FakePorts();
      final controller = _controller(ports);

      await controller.load();

      expect(controller.state.loadPhase, ValuationLoadPhase.ready);
      expect(
        controller.state.availableMethods,
        contains(ValuationMethodKind.incomeApproachDe),
      );
      expect(
        controller.state.unavailableMethods,
        contains(ValuationMethodKind.comparisonApproach),
      );
      // Without comparables the comparison approach has no missing *factor* —
      // its reason is the sample size, and the screen renders that reason.
      expect(controller.state.liveReport, isNotNull);
    });

    test('an unconfirmed suggestion blocks the method and is listed as missing',
        () async {
      final ports = _FakePorts(
        detail: ValuationCaseDetail(
          valuationCase: _caseDto(),
          factors: _factors(
            liegenschaftszins: FactorProvenance.suggestedDefault,
          ),
        ),
      );
      final controller = _controller(ports);

      await controller.load();

      expect(
        controller.state.unavailableMethods,
        contains(ValuationMethodKind.incomeApproachDe),
      );
      final missing = controller.state.missingFactors;
      expect(
        missing.map((m) => m.factorId),
        contains(ValuationFactorIds.liegenschaftszinssatz),
      );
      expect(
        missing.single.reason,
        MissingFactorReason.suggestionNotConfirmed,
      );
    });

    test('reports forbidden without the read permission', () async {
      final ports = _FakePorts();
      final controller = _controller(
        ports,
        scope: _scope(permissions: const {}),
      );

      await controller.load();

      expect(controller.state.loadPhase, ValuationLoadPhase.forbidden);
      expect(ports.loads, 0, reason: 'kein Backend-Zugriff ohne Berechtigung');
    });

    test('a missing case is an empty state, not an error', () async {
      final ports = _FakePorts(
        loadFailure: const ValuationRepositoryFailure<Object?>(
          kind: ValuationRepositoryFailureKind.notFound,
          message: 'nicht gefunden',
        ),
      );
      final controller = _controller(ports);

      await controller.load();

      expect(controller.state.loadPhase, ValuationLoadPhase.empty);
    });

    test('flags a report computed from an older factor version', () async {
      final ports = _FakePorts(
        detail: ValuationCaseDetail(
          valuationCase: _caseDto(version: 5),
          factors: _factors(),
          report: const ValuationReportSnapshot(
            valuationCaseId: 'case-1',
            computedFromVersion: 3,
            methodResults: [],
          ),
        ),
      );
      final controller = _controller(ports);

      await controller.load();

      expect(controller.state.isReportStale, isTrue);
    });
  });

  group('comparables', () {
    test('supplying comparables makes the comparison approach available', () async {
      final ports = _FakePorts();
      final controller = _controller(ports);
      await controller.load();

      controller.setComparables(const [
        ComparableSale(id: 'a', label: 'A', price: 900000, areaSqm: 300),
        ComparableSale(id: 'b', label: 'B', price: 930000, areaSqm: 310),
        ComparableSale(id: 'c', label: 'C', price: 880000, areaSqm: 295),
      ]);

      expect(
        controller.state.availableMethods,
        contains(ValuationMethodKind.comparisonApproach),
      );
    });
  });

  group('mutations', () {
    test('accepting a suggestion writes it back as accepted', () async {
      final ports = _FakePorts(
        detail: ValuationCaseDetail(
          valuationCase: _caseDto(),
          factors: _factors(
            liegenschaftszins: FactorProvenance.suggestedDefault,
          ),
        ),
      );
      final controller = _controller(ports);
      await controller.load();

      await controller.acceptSuggestion(
        ValuationFactorIds.liegenschaftszinssatz,
      );

      final written = ports.upserts.single;
      expect(written.expectedVersion, 3);
      expect(written.factors.single.provenance, FactorProvenance.accepted);
      expect(written.context.reason, 'Systemvorschlag bestätigt');
      expect(controller.state.actionPhase, ValuationActionPhase.succeeded);
    });

    test('refuses to "accept" a factor that is not a suggestion', () async {
      final ports = _FakePorts();
      final controller = _controller(ports);
      await controller.load();

      await controller.acceptSuggestion(ValuationFactorIds.grossRentAnnual);

      expect(ports.upserts, isEmpty);
      expect(controller.state.actionPhase, ValuationActionPhase.failed);
    });

    test('publishes exactly the report the screen shows', () async {
      final ports = _FakePorts();
      final controller = _controller(ports);
      await controller.load();

      await controller.publishReport(reason: 'Abschluss');

      final published = ports.publishes.single;
      expect(published.expectedVersion, 3);
      expect(
        published.report.methodResults[ValuationMethodKind.comparisonApproach],
        isA<MethodUnavailable>(),
      );
      expect(controller.state.actionPhase, ValuationActionPhase.succeeded);
    });

    test('a stale publish surfaces the conflict with both versions', () async {
      final ports = _FakePorts(
        mutationFailure: ValuationRepositoryFailure<Object?>(
          kind: ValuationRepositoryFailureKind.versionConflict,
          message: 'stale',
          versionConflict: ValuationVersionConflict(
            expectedVersion: 3,
            actualVersion: 4,
            currentCase: _caseDto(version: 4),
          ),
        ),
      );
      final controller = _controller(ports);
      await controller.load();

      await controller.publishReport();

      expect(controller.state.actionPhase, ValuationActionPhase.conflict);
      expect(controller.state.versionConflict!.actualVersion, 4);
    });

    test('an approved case reports approvedImmutable, not a generic failure',
        () async {
      final ports = _FakePorts(
        detail: ValuationCaseDetail(
          valuationCase: _caseDto(status: ValuationCaseStatus.approved),
          factors: _factors(),
        ),
      );
      final controller = _controller(ports);
      await controller.load();

      await controller.saveFactors([
        _factor(
          factorId: ValuationFactorIds.capRate,
          label: 'Kapitalisierungszins',
          value: 0.05,
        ),
      ]);

      expect(ports.upserts, isEmpty);
      expect(
        controller.state.actionPhase,
        ValuationActionPhase.approvedImmutable,
      );
    });

    test('the read-only backend blocks the request instead of failing it',
        () async {
      final ports = _FakePorts();
      final controller = _controller(
        ports,
        scope: _scope(mutationsSupported: false),
      );
      await controller.load();

      await controller.publishReport();

      expect(ports.publishes, isEmpty);
      expect(controller.state.actionPhase, ValuationActionPhase.readOnly);
      expect(controller.state.actionMessage, contains('schreibgeschützt'));
    });

    test('approving needs the approve capability, not just manage', () async {
      final ports = _FakePorts();
      final controller = _controller(ports);
      await controller.load();

      await controller.transitionStatus(ValuationCaseStatus.approved);

      expect(ports.transitions, isEmpty);
      expect(controller.state.actionPhase, ValuationActionPhase.forbidden);
    });

    test('an approver can move the case to approved', () async {
      final ports = _FakePorts();
      final controller = _controller(
        ports,
        scope: _scope(
          permissions: const {
            ValuationPermissions.read,
            ValuationPermissions.manage,
            ValuationPermissions.approve,
          },
        ),
      );
      await controller.load();

      await controller.transitionStatus(
        ValuationCaseStatus.approved,
        reason: 'Freigabe',
      );

      expect(ports.transitions.single.targetStatus, ValuationCaseStatus.approved);
      expect(ports.transitions.single.context.reason, 'Freigabe');
    });
  });
}
