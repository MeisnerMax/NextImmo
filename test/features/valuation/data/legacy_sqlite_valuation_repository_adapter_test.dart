import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/scenario.dart';
import 'package:neximmo_app/core/models/scenario_valuation.dart';
import 'package:neximmo_app/features/valuation/application/valuation_repository.dart';
import 'package:neximmo_app/features/valuation/data/legacy_sqlite_valuation_repository_adapter.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case_dto.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_report.dart';

class _FakeSource implements LegacyValuationReadSource {
  _FakeSource(this.rows);

  final List<LegacyScenarioValuation> rows;
  String? lastPropertyId;

  @override
  Future<List<LegacyScenarioValuation>> listScenarioValuations({
    String? propertyId,
  }) async {
    lastPropertyId = propertyId;
    return rows;
  }
}

ScenarioRecord _scenario({
  String id = 'scn-1',
  String workflowStatus = ScenarioWorkflowStatus.draft,
  int updatedAt = 1_760_000_000_000,
}) => ScenarioRecord(
  id: id,
  propertyId: 'prop-1',
  name: 'Basisszenario',
  strategyType: 'buy_and_hold',
  isBase: true,
  workflowStatus: workflowStatus,
  createdAt: 1_750_000_000_000,
  updatedAt: updatedAt,
);

ScenarioValuationRecord _valuation({
  String scenarioId = 'scn-1',
  String mode = 'exit_cap',
  double? exitCapPercent = 4.5,
  String noiMode = 'manual',
  double? noiManual = 70000,
  int updatedAt = 1_760_000_000_000,
}) => ScenarioValuationRecord(
  scenarioId: scenarioId,
  valuationMode: mode,
  exitCapRatePercent: exitCapPercent,
  stabilizedNoiMode: noiMode,
  stabilizedNoiManual: noiManual,
  stabilizedNoiAvgYears: 3,
  updatedAt: updatedAt,
);

LegacySqliteValuationRepositoryAdapter _adapter(_FakeSource source) =>
    LegacySqliteValuationRepositoryAdapter(
      source: source,
      legacyWorkspaceId: 'legacy-ws',
    );

const _context = ValuationCommandContext(
  workspaceId: 'legacy-ws',
  actorId: 'user-1',
  mutationId: 'mut-1',
  correlationId: 'corr-1',
);

void main() {
  group('projection', () {
    test('projects a scenario and its valuation config onto a case', () async {
      final source = _FakeSource([
        LegacyScenarioValuation(scenario: _scenario(), valuation: _valuation()),
      ]);

      final result = await _adapter(source).getValuationCaseById(
        workspaceId: 'legacy-ws',
        valuationCaseId: 'scn-1',
      );

      final detail =
          (result as ValuationRepositorySuccess<ValuationCaseDetail>).value;
      expect(detail.valuationCase.title, 'Basisszenario');
      expect(detail.valuationCase.propertyId, 'prop-1');
      expect(detail.valuationCase.scenarioId, 'scn-1');
      expect(detail.valuationCase.kind, ValuationCaseKind.holding);
      expect(
        detail.valuationCase.version,
        LegacySqliteValuationRepositoryAdapter.unsupportedVersion,
      );
      expect(
        detail.valuationCase.createdBy,
        LegacySqliteValuationRepositoryAdapter.legacyActor,
      );
      expect(detail.report, isNull);
    });

    test('converts the exit cap percentage into a fraction', () async {
      final source = _FakeSource([
        LegacyScenarioValuation(scenario: _scenario(), valuation: _valuation()),
      ]);

      final result = await _adapter(source).listFactors(
        workspaceId: 'legacy-ws',
        valuationCaseId: 'scn-1',
      );

      final factors =
          (result as ValuationRepositorySuccess<List<ValuationFactorDto>>).value;
      final exitCap = factors.firstWhere(
        (f) => f.factorId == ValuationFactorIds.exitCapRate,
      );
      expect(exitCap.value, closeTo(0.045, 1e-9));
      expect(exitCap.provenance, FactorProvenance.userProvided);
      expect(exitCap.source, contains('scenario_valuation'));
    });

    test('does not carry an exit cap that the legacy mode does not use', () async {
      final source = _FakeSource([
        LegacyScenarioValuation(
          scenario: _scenario(),
          valuation: _valuation(mode: 'appreciation'),
        ),
      ]);

      final result = await _adapter(source).listFactors(
        workspaceId: 'legacy-ws',
        valuationCaseId: 'scn-1',
      );

      final factors =
          (result as ValuationRepositorySuccess<List<ValuationFactorDto>>).value;
      expect(
        factors.map((f) => f.factorId),
        isNot(contains(ValuationFactorIds.exitCapRate)),
      );
    });

    test('projects only a manually entered NOI, not a derived one', () async {
      final derived = _FakeSource([
        LegacyScenarioValuation(
          scenario: _scenario(),
          valuation: _valuation(noiMode: 'use_year1_noi'),
        ),
      ]);

      final result = await _adapter(derived).listFactors(
        workspaceId: 'legacy-ws',
        valuationCaseId: 'scn-1',
      );

      final factors =
          (result as ValuationRepositorySuccess<List<ValuationFactorDto>>).value;
      expect(
        factors.map((f) => f.factorId),
        isNot(contains(ValuationFactorIds.stabilizedNoiAnnual)),
      );
    });

    test('a projected case feeds the engine and reports what is missing', () async {
      final source = _FakeSource([
        LegacyScenarioValuation(scenario: _scenario(), valuation: _valuation()),
      ]);
      final result = await _adapter(source).getValuationCaseById(
        workspaceId: 'legacy-ws',
        valuationCaseId: 'scn-1',
      );
      final detail =
          (result as ValuationRepositorySuccess<ValuationCaseDetail>).value;

      const engine = ValuationEngine();
      final report = engine.run(detail.toDomain());

      // Two legacy factors are not a valuation: every method must say so
      // instead of producing a number.
      expect(report.opinion, isA<MarketValueUnavailable>());
      expect(
        report.methodResults[ValuationMethodKind.incomeApproachDe],
        isA<MethodUnavailable>(),
      );
    });

    test('maps the legacy workflow status onto the new lifecycle', () {
      const map = LegacySqliteValuationRepositoryAdapter.mapWorkflowStatus;
      expect(map(ScenarioWorkflowStatus.draft), ValuationCaseStatus.draft);
      expect(map(ScenarioWorkflowStatus.inReview), ValuationCaseStatus.inReview);
      expect(map(ScenarioWorkflowStatus.approved), ValuationCaseStatus.approved);
      expect(map(ScenarioWorkflowStatus.archived), ValuationCaseStatus.archived);
      // A rejected scenario is editable again — that is draft, not a fifth state.
      expect(map(ScenarioWorkflowStatus.rejected), ValuationCaseStatus.draft);
    });
  });

  group('search', () {
    test('excludes archived cases unless asked for them', () async {
      final source = _FakeSource([
        LegacyScenarioValuation(
          scenario: _scenario(workflowStatus: ScenarioWorkflowStatus.archived),
          valuation: _valuation(),
        ),
      ]);
      final adapter = _adapter(source);

      final withoutArchived = await adapter.searchValuationCases(
        const ValuationCaseListQuery(
          workspaceId: 'legacy-ws',
          propertyId: 'prop-1',
        ),
      );
      expect(
        (withoutArchived
                as ValuationRepositorySuccess<
                  ValuationPageResult<ValuationCaseDto>
                >)
            .value
            .items,
        isEmpty,
      );

      final withArchived = await adapter.searchValuationCases(
        const ValuationCaseListQuery(
          workspaceId: 'legacy-ws',
          propertyId: 'prop-1',
          includeArchived: true,
        ),
      );
      expect(
        (withArchived
                as ValuationRepositorySuccess<
                  ValuationPageResult<ValuationCaseDto>
                >)
            .value
            .items,
        hasLength(1),
      );
    });

    test('pages newest-first with the same cursor contract as Supabase', () async {
      final source = _FakeSource([
        LegacyScenarioValuation(
          scenario: _scenario(id: 'scn-1', updatedAt: 1_760_000_000_000),
          valuation: _valuation(scenarioId: 'scn-1', updatedAt: 1_760_000_000_000),
        ),
        LegacyScenarioValuation(
          scenario: _scenario(id: 'scn-2', updatedAt: 1_770_000_000_000),
          valuation: _valuation(scenarioId: 'scn-2', updatedAt: 1_770_000_000_000),
        ),
      ]);
      final adapter = _adapter(source);

      final first = await adapter.searchValuationCases(
        const ValuationCaseListQuery(
          workspaceId: 'legacy-ws',
          propertyId: 'prop-1',
          page: ValuationPageRequest(limit: 1),
        ),
      );
      final firstPage =
          (first
                  as ValuationRepositorySuccess<
                    ValuationPageResult<ValuationCaseDto>
                  >)
              .value;
      expect(firstPage.items.single.id, 'scn-2');
      expect(firstPage.nextCursor, isNotNull);

      final second = await adapter.searchValuationCases(
        ValuationCaseListQuery(
          workspaceId: 'legacy-ws',
          propertyId: 'prop-1',
          page: ValuationPageRequest(limit: 1, cursor: firstPage.nextCursor),
        ),
      );
      expect(
        (second
                as ValuationRepositorySuccess<
                  ValuationPageResult<ValuationCaseDto>
                >)
            .value
            .items
            .single
            .id,
        'scn-1',
      );
    });

    test('a foreign workspace is refused without touching the store', () async {
      final source = _FakeSource([
        LegacyScenarioValuation(scenario: _scenario(), valuation: _valuation()),
      ]);

      final result = await _adapter(source).searchValuationCases(
        const ValuationCaseListQuery(workspaceId: 'other-ws'),
      );

      expect(
        (result as ValuationRepositoryFailure).kind,
        ValuationRepositoryFailureKind.forbidden,
      );
      expect(source.lastPropertyId, isNull, reason: 'kein Datenbankzugriff');
    });

    test('an unknown case is notFound', () async {
      final result = await _adapter(_FakeSource([])).getValuationCaseById(
        workspaceId: 'legacy-ws',
        valuationCaseId: 'scn-9',
      );

      expect(
        (result as ValuationRepositoryFailure).kind,
        ValuationRepositoryFailureKind.notFound,
      );
    });
  });

  group('mutations', () {
    final adapter = _adapter(_FakeSource([]));

    test('every write path reports unsupportedByBackend', () async {
      final results = <ValuationRepositoryResult<Object?>>[
        await adapter.createValuationCase(
          const CreateValuationCaseCommand(
            context: _context,
            propertyId: 'prop-1',
            title: 'Neu',
            kind: ValuationCaseKind.holding,
          ),
        ),
        await adapter.updateValuationCase(
          const UpdateValuationCaseCommand(
            context: _context,
            valuationCaseId: 'scn-1',
            expectedVersion: 0,
            title: 'Neu',
          ),
        ),
        await adapter.transitionValuationCaseStatus(
          const TransitionValuationCaseStatusCommand(
            context: _context,
            valuationCaseId: 'scn-1',
            expectedVersion: 0,
            targetStatus: ValuationCaseStatus.inReview,
          ),
        ),
        await adapter.upsertFactors(
          const UpsertValuationFactorsCommand(
            context: _context,
            valuationCaseId: 'scn-1',
            expectedVersion: 0,
            factors: [],
          ),
        ),
        await adapter.publishReport(
          const PublishValuationReportCommand(
            context: _context,
            valuationCaseId: 'scn-1',
            expectedVersion: 0,
            report: ValuationReport(
              methodResults: {},
              opinion: MarketValueUnavailable(reason: 'leer'),
            ),
          ),
        ),
      ];

      for (final result in results) {
        expect(
          (result as ValuationRepositoryFailure).kind,
          ValuationRepositoryFailureKind.unsupportedByBackend,
        );
      }
    });

    test('reading a report is unsupported rather than "none yet"', () async {
      final result = await adapter.latestReport(
        workspaceId: 'legacy-ws',
        valuationCaseId: 'scn-1',
      );

      expect(
        (result as ValuationRepositoryFailure).kind,
        ValuationRepositoryFailureKind.unsupportedByBackend,
      );
    });
  });
}
