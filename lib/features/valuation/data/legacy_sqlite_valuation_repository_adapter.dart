import '../../../core/models/scenario.dart';
import '../../../core/models/scenario_valuation.dart';
import '../../../data/repositories/scenario_repo.dart';
import '../../../data/repositories/scenario_valuation_repo.dart';
import '../application/valuation_repository.dart';
import '../domain/cash_flow_projection.dart';
import '../domain/valuation_case.dart';
import '../domain/valuation_case_dto.dart';
import '../domain/valuation_factor.dart';
import '../domain/valuation_factor_ids.dart';

/// One legacy scenario together with its `scenario_valuation` configuration —
/// the only pair the local store holds that is a valuation subject in the sense
/// of the new contract.
class LegacyScenarioValuation {
  const LegacyScenarioValuation({
    required this.scenario,
    required this.valuation,
  });

  final ScenarioRecord scenario;
  final ScenarioValuationRecord valuation;
}

/// Read source of the legacy projection. Returns the legacy records verbatim;
/// every interpretation lives in [LegacySqliteValuationRepositoryAdapter], so a
/// test can drive the whole projection without a database.
abstract interface class LegacyValuationReadSource {
  Future<List<LegacyScenarioValuation>> listScenarioValuations({
    String? propertyId,
  });
}

/// [LegacyValuationReadSource] backed by the concrete local repositories.
///
/// One documented limitation: the legacy store has no "list all scenarios"
/// call — `ScenarioRepository` only lists per property — so this source enumerates
/// nothing without a property. A query without `propertyId` therefore reads
/// empty rather than pretending to have scanned the whole store; the Supabase
/// backend is the one that can answer workspace-wide.
class RepositoryLegacyValuationReadSource implements LegacyValuationReadSource {
  const RepositoryLegacyValuationReadSource({
    required ScenarioRepository scenarioRepo,
    required ScenarioValuationRepo scenarioValuationRepo,
  }) : _scenarioRepo = scenarioRepo,
       _scenarioValuationRepo = scenarioValuationRepo;

  final ScenarioRepository _scenarioRepo;
  final ScenarioValuationRepo _scenarioValuationRepo;

  @override
  Future<List<LegacyScenarioValuation>> listScenarioValuations({
    String? propertyId,
  }) async {
    if (propertyId == null) {
      return const [];
    }
    final scenarios = await _scenarioRepo.listByProperty(propertyId);
    final result = <LegacyScenarioValuation>[];
    for (final scenario in scenarios) {
      result.add(
        LegacyScenarioValuation(
          scenario: scenario,
          valuation: await _scenarioValuationRepo.getForScenario(scenario.id),
        ),
      );
    }
    return result;
  }
}

/// The legacy local-SQLite implementation of the P2-D07 valuation ports.
///
/// Reads project the legacy `scenarios` + `scenario_valuation` pair onto the
/// canonical DTOs. **Every** mutation — [createValuationCase],
/// [updateValuationCase], [transitionValuationCaseStatus], [upsertFactors] and
/// [publishReport] — fails with
/// [ValuationRepositoryFailureKind.unsupportedByBackend]: the local schema has
/// no version token, no mutation receipt and no audited command envelope, so it
/// cannot honour the contract's concurrency, idempotency and audit guarantees.
/// Blocking is the honest answer; writing anyway would drop those guarantees
/// silently. (The legacy screens keep writing through their own repositories —
/// this adapter does not take that away, it just refuses to pretend those
/// writes satisfy the new contract.)
///
/// The projection is deliberately narrow, and the narrowness *is* the honesty:
/// only two legacy columns map onto the new factor vocabulary without
/// invention — the exit cap rate and a manually entered stabilized NOI. Every
/// other factor of the Ertrags-, Sach- and Vergleichswertverfahren simply does
/// not exist in the local store, so it is absent rather than defaulted, and the
/// dependent methods report "nicht ermittelbar" exactly as they should.
///
/// What is *not* projected, stated rather than implied: the legacy
/// `acquisition_*`, `renovation_*` and `disposition_*` module tables keep their
/// inputs in opaque `input_json`/`result_json` blobs whose keys are module
/// specific. Mapping them onto factor ids would mean deciding, per field, which
/// ImmoWertV factor it is — a semantic judgement this adapter has no basis for.
/// Those cases are migrated by the P2-D07 dry-run mapper when it ships, not
/// guessed at here.
class LegacySqliteValuationRepositoryAdapter
    implements ValuationCaseRepository, ValuationFactorPort, ValuationReportPort {
  LegacySqliteValuationRepositoryAdapter({
    required LegacyValuationReadSource source,
    required String legacyWorkspaceId,
  }) : _source = source,
       _legacyWorkspaceId = legacyWorkspaceId;

  /// Legacy rows carry no optimistic-concurrency token, so every projected case
  /// reports the one version it can honestly have. It is never a usable
  /// `expectedVersion` — nothing on this adapter accepts one.
  static const int unsupportedVersion = 0;

  /// Legacy rows are attributed to a synthetic actor: the local store predates
  /// workspace identity and has no actor column on either table.
  static const String legacyActor = 'legacy';

  static const String _valuationModeExitCap = 'exit_cap';
  static const String _stabilizedNoiManual = 'manual';

  final LegacyValuationReadSource _source;
  final String _legacyWorkspaceId;

  // ---------------------------------------------------------------------------
  // ValuationCaseRepository — reads
  // ---------------------------------------------------------------------------

  @override
  Future<ValuationRepositoryResult<ValuationPageResult<ValuationCaseDto>>>
  searchValuationCases(ValuationCaseListQuery query) async {
    final scope = _requireLegacyWorkspace<ValuationPageResult<ValuationCaseDto>>(
      query.workspaceId,
    );
    if (scope != null) return scope;

    final details = await _loadDetails(propertyId: query.propertyId);
    var cases = details.map((detail) => detail.valuationCase).where((entry) {
      if (query.scenarioId != null && entry.scenarioId != query.scenarioId) {
        return false;
      }
      if (query.kind != null && entry.kind != query.kind) return false;
      if (query.status != null && entry.status != query.status) return false;
      if (!query.includeArchived &&
          entry.status == ValuationCaseStatus.archived) {
        return false;
      }
      return true;
    }).toList();

    // Same order as the Supabase adapter — newest first, id breaking ties — so
    // a caller can page either backend with the same loop.
    cases.sort((a, b) {
      final byTime = b.updatedAt.compareTo(a.updatedAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });

    final after = ValuationKeysetCursor.decode(query.page.cursor);
    if (after != null) {
      cases = cases
          .where(
            (entry) =>
                entry.updatedAt.isBefore(after.timestamp) ||
                (entry.updatedAt.isAtSameMomentAs(after.timestamp) &&
                    entry.id.compareTo(after.id) < 0),
          )
          .toList();
    }

    final page = cases.take(query.page.limit).toList(growable: false);
    final nextCursor = page.length < query.page.limit
        ? null
        : ValuationKeysetCursor(
            timestamp: page.last.updatedAt,
            id: page.last.id,
          ).encode();
    return ValuationRepositorySuccess(
      ValuationPageResult(items: page, nextCursor: nextCursor),
    );
  }

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> getValuationCaseById({
    required String workspaceId,
    required String valuationCaseId,
  }) async {
    final scope = _requireLegacyWorkspace<ValuationCaseDetail>(workspaceId);
    if (scope != null) return scope;

    final details = await _loadDetails(propertyId: null, caseId: valuationCaseId);
    for (final detail in details) {
      if (detail.valuationCase.id == valuationCaseId) {
        return ValuationRepositorySuccess(detail);
      }
    }
    return const ValuationRepositoryFailure(
      kind: ValuationRepositoryFailureKind.notFound,
      message: 'Bewertungsfall im lokalen Bestand nicht gefunden.',
    );
  }

  @override
  Future<ValuationRepositoryResult<List<ValuationFactorDto>>> listFactors({
    required String workspaceId,
    required String valuationCaseId,
  }) async {
    final detail = await getValuationCaseById(
      workspaceId: workspaceId,
      valuationCaseId: valuationCaseId,
    );
    return switch (detail) {
      ValuationRepositorySuccess(:final value) => ValuationRepositorySuccess(
        value.factors,
      ),
      ValuationRepositoryFailure(:final kind, :final message) =>
        ValuationRepositoryFailure<List<ValuationFactorDto>>(
          kind: kind,
          message: message,
        ),
    };
  }

  // ---------------------------------------------------------------------------
  // Mutations — uniformly unsupported, see the class doc.
  // ---------------------------------------------------------------------------

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> createValuationCase(
    CreateValuationCaseCommand command,
  ) async => _unsupported<ValuationCaseDetail>('Bewertungsfall anlegen');

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> updateValuationCase(
    UpdateValuationCaseCommand command,
  ) async => _unsupported<ValuationCaseDetail>('Bewertungsfall ändern');

  @override
  Future<ValuationRepositoryResult<ValuationCaseDto>>
  transitionValuationCaseStatus(
    TransitionValuationCaseStatusCommand command,
  ) async => _unsupported<ValuationCaseDto>('Status ändern');

  @override
  Future<ValuationRepositoryResult<List<ValuationFactorDto>>> upsertFactors(
    UpsertValuationFactorsCommand command,
  ) async => _unsupported<List<ValuationFactorDto>>('Faktoren speichern');

  @override
  Future<ValuationRepositoryResult<ValuationReportSnapshot>> publishReport(
    PublishValuationReportCommand command,
  ) async => _unsupported<ValuationReportSnapshot>('Bericht veröffentlichen');

  /// The local store has nowhere to keep a published report, so there is never
  /// one to return — reported as unsupported rather than as "none yet", which
  /// would suggest publishing one would help.
  @override
  Future<ValuationRepositoryResult<ValuationReportSnapshot>> latestReport({
    required String workspaceId,
    required String valuationCaseId,
  }) async {
    final scope = _requireLegacyWorkspace<ValuationReportSnapshot>(workspaceId);
    if (scope != null) return scope;
    return _unsupported<ValuationReportSnapshot>('Bericht lesen');
  }

  // ---------------------------------------------------------------------------
  // Projection
  // ---------------------------------------------------------------------------

  Future<List<ValuationCaseDetail>> _loadDetails({
    required String? propertyId,
    String? caseId,
  }) async {
    final rows = await _source.listScenarioValuations(propertyId: propertyId);
    return rows
        .where((row) => caseId == null || row.scenario.id == caseId)
        .map(_project)
        .toList(growable: false);
  }

  ValuationCaseDetail _project(LegacyScenarioValuation row) {
    final scenario = row.scenario;
    final valuation = row.valuation;

    final factors = <ValuationFactorDto>[];

    // The legacy column is a percentage; the factor vocabulary is a fraction.
    // Only the exit-cap mode actually uses it — under 'appreciation' the value
    // is stale configuration, not an assumption in force, so it is not carried
    // over as if it were one.
    final exitCap = valuation.exitCapRatePercent;
    if (valuation.valuationMode == _valuationModeExitCap &&
        exitCap != null &&
        exitCap > 0) {
      factors.add(
        ValuationFactorDto(
          caseId: scenario.id,
          factorId: ValuationFactorIds.exitCapRate,
          label: 'Exit-Cap-Rate',
          provenance: FactorProvenance.userProvided,
          confidence: ConfidenceBand.medium,
          value: exitCap / 100,
          source: 'Legacy: scenario_valuation.exit_cap_rate_percent',
        ),
      );
    }

    // Only a manually entered NOI is a user-provided factor. The derived modes
    // ('use_year1_noi', averaging) are computations of the legacy pro-forma
    // engine, not stored values, so there is nothing honest to project.
    final manualNoi = valuation.stabilizedNoiManual;
    if (valuation.stabilizedNoiMode == _stabilizedNoiManual &&
        manualNoi != null) {
      factors.add(
        ValuationFactorDto(
          caseId: scenario.id,
          factorId: ValuationFactorIds.stabilizedNoiAnnual,
          label: 'Reinertrag p.a.',
          provenance: FactorProvenance.userProvided,
          confidence: ConfidenceBand.medium,
          value: manualNoi,
          unit: '€',
          source: 'Legacy: scenario_valuation.stabilized_noi_manual',
        ),
      );
    }

    final updatedAt = DateTime.fromMillisecondsSinceEpoch(
      valuation.updatedAt,
      isUtc: true,
    );

    return ValuationCaseDetail(
      valuationCase: ValuationCaseDto(
        id: scenario.id,
        workspaceId: _legacyWorkspaceId,
        propertyId: scenario.propertyId,
        scenarioId: scenario.id,
        title: scenario.name,
        // The legacy scenario is a holding/analysis subject; the module tables
        // that would justify another kind are not projected (see class doc).
        kind: ValuationCaseKind.holding,
        status: mapWorkflowStatus(scenario.workflowStatus),
        dcfTerminal: DcfTerminalMethod.exitCap,
        enabledMethods: ValuationCase.allMethodKinds,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          scenario.createdAt,
          isUtc: true,
        ),
        updatedAt: updatedAt,
        createdBy: legacyActor,
        updatedBy: legacyActor,
        version: unsupportedVersion,
      ),
      factors: factors,
    );
  }

  /// Legacy workflow status → the new lifecycle.
  ///
  /// `rejected` maps to [ValuationCaseStatus.draft] because that is what a
  /// rejected scenario *is* in the new lifecycle: editable again, not approved.
  /// The rejection itself lives in the legacy audit log; it is not lost by this
  /// mapping, but it is also not represented, and inventing a fifth state to
  /// carry it would change the contract for one backend.
  static ValuationCaseStatus mapWorkflowStatus(String workflowStatus) {
    switch (workflowStatus) {
      case ScenarioWorkflowStatus.inReview:
        return ValuationCaseStatus.inReview;
      case ScenarioWorkflowStatus.approved:
        return ValuationCaseStatus.approved;
      case ScenarioWorkflowStatus.archived:
        return ValuationCaseStatus.archived;
      case ScenarioWorkflowStatus.rejected:
      case ScenarioWorkflowStatus.draft:
      default:
        return ValuationCaseStatus.draft;
    }
  }

  ValuationRepositoryFailure<T>? _requireLegacyWorkspace<T>(String workspaceId) {
    if (workspaceId == _legacyWorkspaceId) return null;
    return const ValuationRepositoryFailure(
      kind: ValuationRepositoryFailureKind.forbidden,
      message: 'Der lokale Bestand kennt nur den eigenen Workspace.',
    );
  }

  ValuationRepositoryFailure<T> _unsupported<T>(String action) =>
      ValuationRepositoryFailure<T>(
        kind: ValuationRepositoryFailureKind.unsupportedByBackend,
        message:
            '$action ist im lokalen SQLite-Bestand nicht möglich: keine '
            'Versionierung, keine Idempotenz und kein Audit-Envelope.',
      );
}
