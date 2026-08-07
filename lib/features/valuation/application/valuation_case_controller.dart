/// Screen-facing orchestration over the valuation contract (Welle 5, AP1).
///
/// Same shape as the Wave 2 controllers — explicit phases, every mandatory
/// screen state of `03_design_system.md` as data rather than as a widget
/// branch, a generation guard against out-of-order responses — plus the two
/// things that are specific to this domain and that the whole rewrite exists
/// for:
///
/// * **The live result and the published report are separate, and both are
///   visible.** The engine is deterministic, so the screen recomputes from the
///   stored factors on every load instead of waiting for a backend round trip.
///   The persisted `market_value_opinions` row is the *published* stand; when it
///   was computed from an older factor version, [ValuationCaseState.isReportStale]
///   says so rather than letting a stale number pass as current.
/// * **"Nicht ermittelbar" is data, not an absence.** The live report keeps every
///   unavailable method with its missing factors, so the screen can render the
///   reason and offer the jump to the input — see
///   [ValuationCaseState.missingFactors].
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/methods/comparison_approach_method.dart';
import '../domain/valuation_case.dart';
import '../domain/valuation_case_dto.dart';
import '../domain/valuation_factor.dart';
import '../domain/valuation_method.dart';
import '../domain/valuation_report.dart';
import 'valuation_providers.dart';
import 'valuation_query_invalidation_source.dart';
import 'valuation_repository.dart';

/// Capabilities the valuation screens gate on. Server-side authority stays with
/// RLS and the RPCs; these only decide which affordances are offered.
abstract final class ValuationPermissions {
  static const read = 'valuation.read';
  static const manage = 'valuation.manage';
  static const approve = 'valuation.approve';
}

enum ValuationLoadPhase { idle, loading, ready, empty, forbidden, error }

enum ValuationActionPhase {
  idle,
  submitting,
  succeeded,
  conflict,
  forbidden,

  /// The bound backend cannot mutate (read-only legacy SQLite adapter).
  /// Rendered as the mandatory "read-only until migrated" notice.
  readOnly,

  /// The case is approved or archived — a record, not a draft (`AGG-014`).
  approvedImmutable,
  failed,
}

class ValuationCaseState {
  const ValuationCaseState({
    required this.loadPhase,
    this.actionPhase = ValuationActionPhase.idle,
    this.detail,
    this.liveReport,
    this.comparables = const <ComparableSale>[],
    this.versionConflict,
    this.message,
    this.actionMessage,
  });

  const ValuationCaseState.loading()
    : this(loadPhase: ValuationLoadPhase.loading);

  final ValuationLoadPhase loadPhase;
  final ValuationActionPhase actionPhase;

  /// The stored case: row, factors, and the last published report.
  final ValuationCaseDetail? detail;

  /// Recomputed from [detail]'s factors on every load. Null while there is no
  /// case to compute from.
  final ValuationReport? liveReport;

  /// Comparables feeding the Vergleichswertverfahren. Empty until the comps
  /// screen supplies them (AP3) — which is why that method reports
  /// "nicht ermittelbar" here, honestly, rather than being hidden.
  final List<ComparableSale> comparables;

  final ValuationVersionConflict? versionConflict;
  final String? message;
  final String? actionMessage;

  ValuationCaseDto? get valuationCase => detail?.valuationCase;

  /// Whether the published report predates the current factor set. The publish
  /// path deliberately does not bump the case version, so this is the signal
  /// that keeps a stale stored number from reading as current.
  bool get isReportStale => detail?.hasStaleReport ?? false;

  /// Every required factor any method is still waiting for, deduplicated by
  /// factor id — the screen's "what is missing" list and the source of the jump
  /// back into the input form.
  List<MissingFactor> get missingFactors {
    final report = liveReport;
    if (report == null) return const [];
    final byId = <String, MissingFactor>{};
    for (final result in report.methodResults.values) {
      if (result is! MethodUnavailable) continue;
      for (final missing in result.missingFactors) {
        byId.putIfAbsent(missing.factorId, () => missing);
      }
    }
    final all = byId.values.toList()
      ..sort((a, b) => a.factorId.compareTo(b.factorId));
    return List.unmodifiable(all);
  }

  Iterable<ValuationMethodKind> get availableMethods =>
      liveReport?.availableMethods ?? const [];

  Iterable<ValuationMethodKind> get unavailableMethods =>
      liveReport?.unavailableMethods ?? const [];

  ValuationCaseState copyWith({
    ValuationLoadPhase? loadPhase,
    ValuationActionPhase? actionPhase,
    ValuationCaseDetail? detail,
    ValuationReport? liveReport,
    List<ComparableSale>? comparables,
    ValuationVersionConflict? versionConflict,
    bool clearVersionConflict = false,
    String? message,
    bool clearMessage = false,
    String? actionMessage,
    bool clearActionMessage = false,
  }) => ValuationCaseState(
    loadPhase: loadPhase ?? this.loadPhase,
    actionPhase: actionPhase ?? this.actionPhase,
    detail: detail ?? this.detail,
    liveReport: liveReport ?? this.liveReport,
    comparables: comparables ?? this.comparables,
    versionConflict: clearVersionConflict
        ? null
        : (versionConflict ?? this.versionConflict),
    message: clearMessage ? null : (message ?? this.message),
    actionMessage: clearActionMessage
        ? null
        : (actionMessage ?? this.actionMessage),
  );
}

typedef ValuationIdFactory = String Function();

class ValuationCaseController extends StateNotifier<ValuationCaseState> {
  ValuationCaseController({
    required String valuationCaseId,
    required ValuationCaseRepository repository,
    required ValuationFactorPort factors,
    required ValuationReportPort reports,
    required WorkspaceSessionScope scope,
    ValuationQueryInvalidationSource? invalidationSource,
    ValuationEngine engine = const ValuationEngine(),
    ValuationIdFactory? idFactory,
  }) : _valuationCaseId = valuationCaseId,
       _repository = repository,
       _factors = factors,
       _reports = reports,
       _scope = scope,
       _invalidationSource = invalidationSource,
       _engine = engine,
       _idFactory = idFactory ?? (() => const Uuid().v4()),
       super(const ValuationCaseState(loadPhase: ValuationLoadPhase.idle));

  final String _valuationCaseId;
  final ValuationCaseRepository _repository;
  final ValuationFactorPort _factors;
  final ValuationReportPort _reports;
  final WorkspaceSessionScope _scope;
  final ValuationQueryInvalidationSource? _invalidationSource;
  final ValuationEngine _engine;
  final ValuationIdFactory _idFactory;

  StreamSubscription<ValuationQueryInvalidation>? _invalidationSubscription;
  int _generation = 0;

  bool get canManage =>
      _scope.permissions.contains(ValuationPermissions.manage) &&
      _scope.mutationsSupported;

  bool get canApprove =>
      _scope.permissions.contains(ValuationPermissions.approve) &&
      _scope.mutationsSupported;

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null ||
        !_scope.permissions.contains(ValuationPermissions.read)) {
      state = state.copyWith(
        loadPhase: ValuationLoadPhase.forbidden,
        message: 'Keine Berechtigung für Bewertungen.',
      );
      return;
    }

    final generation = ++_generation;
    state = state.copyWith(
      loadPhase: ValuationLoadPhase.loading,
      clearMessage: true,
    );

    final result = await _repository.getValuationCaseById(
      workspaceId: workspaceId,
      valuationCaseId: _valuationCaseId,
    );
    if (generation != _generation || !mounted) return;

    switch (result) {
      case ValuationRepositorySuccess(:final value):
        _subscribeToInvalidations(workspaceId);
        state = state.copyWith(
          loadPhase: ValuationLoadPhase.ready,
          detail: value,
          liveReport: _compute(value, state.comparables),
          clearMessage: true,
        );
      case ValuationRepositoryFailure(:final kind, :final message):
        state = state.copyWith(
          loadPhase: switch (kind) {
            ValuationRepositoryFailureKind.notFound => ValuationLoadPhase.empty,
            ValuationRepositoryFailureKind.forbidden =>
              ValuationLoadPhase.forbidden,
            _ => ValuationLoadPhase.error,
          },
          message: message,
        );
    }
  }

  /// Supplies the comparables the Vergleichswertverfahren runs on and
  /// recomputes the live report.
  void setComparables(List<ComparableSale> comparables) {
    final detail = state.detail;
    state = state.copyWith(
      comparables: comparables,
      liveReport: detail == null ? null : _compute(detail, comparables),
    );
  }

  /// Confirms a system suggestion. It is an ordinary audited factor write with
  /// provenance `accepted` — there is no separate "accept" endpoint, because
  /// the confirmation *is* the decision that makes the value count.
  Future<void> acceptSuggestion(String factorId, {String? note}) async {
    final detail = state.detail;
    final factor = detail?.factors
        .where((f) => f.factorId == factorId)
        .firstOrNull;
    if (detail == null || factor == null) {
      state = state.copyWith(
        actionPhase: ValuationActionPhase.failed,
        actionMessage: 'Faktor ist nicht Teil dieser Bewertung.',
      );
      return;
    }
    if (factor.provenance != FactorProvenance.suggestedDefault) {
      state = state.copyWith(
        actionPhase: ValuationActionPhase.failed,
        actionMessage: 'Nur ein unbestätigter Vorschlag kann bestätigt werden.',
      );
      return;
    }

    await saveFactors([
      ValuationFactorDto(
        caseId: factor.caseId,
        factorId: factor.factorId,
        label: factor.label,
        provenance: FactorProvenance.accepted,
        confidence: factor.confidence,
        value: factor.value,
        unit: factor.unit,
        source: factor.source,
        note: note ?? factor.note,
      ),
    ], reason: 'Systemvorschlag bestätigt');
  }

  /// Writes factors (and optionally removes some). Removing a factor makes the
  /// dependent methods report "nicht ermittelbar" again — intended, not a
  /// regression, and surfaced as such by the recomputed live report.
  Future<void> saveFactors(
    List<ValuationFactorDto> factors, {
    List<String> removeFactorIds = const [],
    String? reason,
  }) async {
    final guard = _guardMutation();
    if (guard != null) {
      state = guard;
      return;
    }

    final detail = state.detail!;
    state = state.copyWith(
      actionPhase: ValuationActionPhase.submitting,
      clearActionMessage: true,
      clearVersionConflict: true,
    );

    final result = await _factors.upsertFactors(
      UpsertValuationFactorsCommand(
        context: _context(reason),
        valuationCaseId: detail.valuationCase.id,
        expectedVersion: detail.valuationCase.version,
        factors: factors,
        removeFactorIds: removeFactorIds,
      ),
    );
    if (!mounted) return;

    switch (result) {
      case ValuationRepositorySuccess():
        state = state.copyWith(actionPhase: ValuationActionPhase.succeeded);
        await load();
      case ValuationRepositoryFailure(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        state = _applyFailure(kind, message, versionConflict);
    }
  }

  /// Publishes the live result. The engine is the single source of the numbers;
  /// this only persists what the screen already shows, so an unavailable method
  /// is stored as unavailable and never as a substituted amount.
  Future<void> publishReport({String? reason}) async {
    final guard = _guardMutation();
    if (guard != null) {
      state = guard;
      return;
    }

    final detail = state.detail!;
    final report = state.liveReport;
    if (report == null) {
      state = state.copyWith(
        actionPhase: ValuationActionPhase.failed,
        actionMessage: 'Es liegt kein berechnetes Ergebnis vor.',
      );
      return;
    }

    state = state.copyWith(
      actionPhase: ValuationActionPhase.submitting,
      clearActionMessage: true,
      clearVersionConflict: true,
    );

    final result = await _reports.publishReport(
      PublishValuationReportCommand(
        context: _context(reason),
        valuationCaseId: detail.valuationCase.id,
        expectedVersion: detail.valuationCase.version,
        report: report,
      ),
    );
    if (!mounted) return;

    switch (result) {
      case ValuationRepositorySuccess():
        state = state.copyWith(
          actionPhase: ValuationActionPhase.succeeded,
          actionMessage: 'Bericht veröffentlicht.',
        );
        await load();
      case ValuationRepositoryFailure(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        state = _applyFailure(kind, message, versionConflict);
    }
  }

  /// Copies this case into a named sibling variant and returns the new case id,
  /// or null when the command did not run. The variant is a draft with the same
  /// factors and no report of its own (`DEC-023`).
  Future<String?> createVariant({
    required String variantLabel,
    String sourceVariantLabel = 'Basis',
  }) async {
    final guard = _guardMutation();
    if (guard != null) {
      state = guard;
      return null;
    }

    final detail = state.detail!;
    state = state.copyWith(
      actionPhase: ValuationActionPhase.submitting,
      clearActionMessage: true,
      clearVersionConflict: true,
    );

    final result = await _repository.createValuationVariant(
      CreateValuationVariantCommand(
        context: _context('Variante „$variantLabel" angelegt'),
        sourceValuationCaseId: detail.valuationCase.id,
        variantLabel: variantLabel,
        sourceVariantLabel: sourceVariantLabel,
      ),
    );
    if (!mounted) return null;

    switch (result) {
      case ValuationRepositorySuccess(:final value):
        state = state.copyWith(
          actionPhase: ValuationActionPhase.succeeded,
          actionMessage: 'Variante „$variantLabel" angelegt.',
        );
        // The source now carries its own variant name, so reload it too.
        await load();
        return value.valuationCase.id;
      case ValuationRepositoryFailure(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        state = _applyFailure(kind, message, versionConflict);
        return null;
    }
  }

  /// Moves the case through its lifecycle. Approving needs `valuation.approve`
  /// and is final: an approved case is a record, and the server enforces that
  /// with `approved_immutable`.
  Future<void> transitionStatus(
    ValuationCaseStatus target, {
    String? reason,
  }) async {
    final guard = _guardMutation(
      requireApprove: target == ValuationCaseStatus.approved,
    );
    if (guard != null) {
      state = guard;
      return;
    }

    final detail = state.detail!;
    state = state.copyWith(
      actionPhase: ValuationActionPhase.submitting,
      clearActionMessage: true,
      clearVersionConflict: true,
    );

    final result = await _repository.transitionValuationCaseStatus(
      TransitionValuationCaseStatusCommand(
        context: _context(reason),
        valuationCaseId: detail.valuationCase.id,
        expectedVersion: detail.valuationCase.version,
        targetStatus: target,
      ),
    );
    if (!mounted) return;

    switch (result) {
      case ValuationRepositorySuccess():
        state = state.copyWith(actionPhase: ValuationActionPhase.succeeded);
        await load();
      case ValuationRepositoryFailure(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        state = _applyFailure(kind, message, versionConflict);
    }
  }

  ValuationReport _compute(
    ValuationCaseDetail detail,
    List<ComparableSale> comparables,
  ) => _engine.run(detail.toDomain(comparables: comparables));

  ValuationCommandContext _context(String? reason) => ValuationCommandContext(
    workspaceId: _scope.workspaceId!,
    actorId: _scope.actorId!,
    mutationId: _idFactory(),
    correlationId: _idFactory(),
    reason: reason,
  );

  /// Returns the state to publish instead of firing a mutation that cannot
  /// succeed — the screen renders the reason rather than a failed request.
  ValuationCaseState? _guardMutation({bool requireApprove = false}) {
    if (state.detail == null) {
      return state.copyWith(
        actionPhase: ValuationActionPhase.failed,
        actionMessage: 'Es ist keine Bewertung geladen.',
      );
    }
    if (!_scope.mutationsSupported) {
      return state.copyWith(
        actionPhase: ValuationActionPhase.readOnly,
        actionMessage:
            'Im lokalen Bestand schreibgeschützt, bis die Bewertung migriert ist.',
      );
    }
    if (!_scope.isResolved || (requireApprove ? !canApprove : !canManage)) {
      return state.copyWith(
        actionPhase: ValuationActionPhase.forbidden,
        actionMessage: requireApprove
            ? 'Freigabe erfordert die Berechtigung „Bewertung freigeben".'
            : 'Keine Berechtigung, Bewertungen zu ändern.',
      );
    }
    final status = state.valuationCase?.status;
    if (status == ValuationCaseStatus.approved ||
        status == ValuationCaseStatus.archived) {
      // Only a status transition may still touch a closed case (archiving).
      if (!requireApprove && status == ValuationCaseStatus.approved) {
        return state.copyWith(
          actionPhase: ValuationActionPhase.approvedImmutable,
          actionMessage:
              'Freigegebene Bewertung ist ein Datensatz — für Änderungen eine '
              'neue Version anlegen.',
        );
      }
    }
    return null;
  }

  ValuationCaseState _applyFailure(
    ValuationRepositoryFailureKind kind,
    String message,
    ValuationVersionConflict? conflict,
  ) => state.copyWith(
    actionPhase: switch (kind) {
      ValuationRepositoryFailureKind.versionConflict =>
        ValuationActionPhase.conflict,
      ValuationRepositoryFailureKind.forbidden => ValuationActionPhase.forbidden,
      ValuationRepositoryFailureKind.approvedImmutable =>
        ValuationActionPhase.approvedImmutable,
      ValuationRepositoryFailureKind.unsupportedByBackend =>
        ValuationActionPhase.readOnly,
      _ => ValuationActionPhase.failed,
    },
    versionConflict: conflict,
    actionMessage: message,
  );

  void _subscribeToInvalidations(String workspaceId) {
    if (_invalidationSubscription != null || _invalidationSource == null) {
      return;
    }
    _invalidationSubscription = _invalidationSource
        .watchWorkspace(workspaceId: workspaceId)
        .listen(
          (invalidation) {
            if (!mounted) return;
            final concernsThisCase =
                invalidation.isReconciliation ||
                invalidation.valuationCaseId == _valuationCaseId;
            if (concernsThisCase) unawaited(load());
          },
          // A broken channel must not blank the screen: the data on display
          // stays valid, it just stops refreshing itself.
          onError: (_) {},
        );
  }

  @override
  void dispose() {
    unawaited(_invalidationSubscription?.cancel());
    _invalidationSubscription = null;
    super.dispose();
  }
}

final valuationCaseControllerProvider = StateNotifierProvider.autoDispose
    .family<ValuationCaseController, ValuationCaseState, String>((
      ref,
      valuationCaseId,
    ) {
      final controller = ValuationCaseController(
        valuationCaseId: valuationCaseId,
        repository: ref.watch(valuationCaseRepositoryProvider),
        factors: ref.watch(valuationFactorProvider),
        reports: ref.watch(valuationReportProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
        invalidationSource: ref.watch(valuationQueryInvalidationSourceProvider),
      );
      unawaited(controller.load());
      return controller;
    });
