/// Screen-facing orchestration over the leasing-case half of the
/// leasing_operations contract (P2-D05, Welle 3 AP4), mirroring
/// [UnitsController] and [LeasesController]: explicit phases per zone, a
/// generation guard, and every mandatory screen state as data.
///
/// What is specific to STM-004:
///
///   * **The pipeline moves one stage at a time and never backwards.** There is
///     no reopen: a failed screening or a withdrawn offer is a cancellation
///     with a reason, and the next attempt is a new case. Reopening would
///     overwrite the record of why the first attempt died.
///   * **A blocked step is known before it is attempted.**
///     `LeasingCaseDto.blockedReason` mirrors the server's preconditions, so
///     the surface can disable the affordance *with* the reason instead of
///     letting the user run into a `validationFailed`. This layer refuses such
///     a step locally rather than spending a round trip on a certain refusal —
///     the server stays the authority, this only avoids proposing a refusal.
///   * **A prospect is not a tenant.** The party companion read is deliberately
///     unfiltered by role: there is no `prospect` role type, and stamping an
///     enquiry as a tenant would assert a relationship that does not exist yet.
///     The role attaches when a lease names the party.
///   * **Reaching `signed` means naming the lease the case produced.** The
///     command carries the lease id, so the leases of the property are read as
///     a companion — the pipeline hands over to the lease surface (AP3) rather
///     than growing a second lease-creation path.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../contacts_parties/application/party_providers.dart';
import '../../contacts_parties/application/party_repository.dart';
import '../../contacts_parties/domain/party_dto.dart';
import '../../identity_access/application/authorization_port.dart';
import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/lease_dto.dart';
import '../domain/leasing_case_dto.dart';
import '../domain/unit_dto.dart';
import 'leasing_providers.dart';
import 'leasing_query_invalidation_source.dart';
import 'leasing_repository.dart';

const Object _unchanged = Object();

enum LeasingCasesListPhase { idle, loading, ready, empty, forbidden, error }

enum LeasingCasesDetailPhase { idle, loading, ready, notFound, forbidden, error }

enum LeasingCasesActionPhase {
  idle,
  submitting,
  succeeded,
  conflict,
  forbidden,

  /// The bound backend cannot mutate yet (the legacy SQLite adapters are
  /// read-only by design).
  readOnly,

  /// The step is not available in the case's current state — either STM-004
  /// does not contain it, or a precondition is missing. Rendered inline with
  /// its reason rather than flashed as a failure.
  blocked,
  failed,
}

/// Why a step was not taken. Exactly one of the two fields is set: either a
/// precondition is missing ([blockedReason]) or the chain itself does not
/// contain the step ([attempted] absent means the case is terminal).
class LeasingCaseStepRefusal {
  const LeasingCaseStepRefusal({
    required this.from,
    this.attempted,
    this.blockedReason,
    this.serverMessage,
  });

  final LeasingCaseStatus from;
  final LeasingCaseStatus? attempted;
  final LeasingCaseBlockedReason? blockedReason;
  final String? serverMessage;
}

class LeasingCasesState {
  const LeasingCasesState({
    required this.listPhase,
    this.detailPhase = LeasingCasesDetailPhase.idle,
    this.actionPhase = LeasingCasesActionPhase.idle,
    this.cases = const <LeasingCaseSummaryDto>[],
    this.units = const <UnitSummaryDto>[],
    this.parties = const <PartySummaryDto>[],
    this.leases = const <LeaseSummaryDto>[],
    this.nextCursor,
    this.loadingMore = false,
    this.openOnly = true,
    this.stageFilter,
    this.selectedCaseId,
    this.selectedCase,
    this.versionConflict,
    this.refusal,
    this.message,
    this.actionMessage,
  });

  const LeasingCasesState.loading()
    : this(listPhase: LeasingCasesListPhase.loading);

  final LeasingCasesListPhase listPhase;
  final LeasingCasesDetailPhase detailPhase;
  final LeasingCasesActionPhase actionPhase;
  final List<LeasingCaseSummaryDto> cases;

  /// Companion reads. Each degrades to empty on failure — a label lookup that
  /// failed must not take the board down with it.
  final List<UnitSummaryDto> units;

  /// **Unfiltered by role on purpose** — a prospect holds no `tenant` role yet.
  final List<PartySummaryDto> parties;
  final List<LeaseSummaryDto> leases;

  final String? nextCursor;
  final bool loadingMore;

  /// The board reads open cases only; switching it off adds the terminal
  /// stages, which is the archive view rather than the pipeline.
  final bool openOnly;

  final LeasingCaseStatus? stageFilter;
  final String? selectedCaseId;
  final LeasingCaseDto? selectedCase;
  final LeasingVersionConflict? versionConflict;
  final LeasingCaseStepRefusal? refusal;
  final String? message;
  final String? actionMessage;

  bool get hasMore => nextCursor != null;

  bool get hasActiveFilter => stageFilter != null || !openOnly;

  String? unitCodeFor(String? unitId) {
    if (unitId == null) {
      return null;
    }
    return units
        .where((unit) => unit.id == unitId)
        .map((unit) => unit.unitCode)
        .firstOrNull;
  }

  String? partyNameFor(String? partyId) {
    if (partyId == null) {
      return null;
    }
    return parties
        .where((party) => party.id == partyId)
        .map((party) => party.displayName)
        .firstOrNull;
  }

  String? leaseNameFor(String? leaseId) {
    if (leaseId == null) {
      return null;
    }
    return leases
        .where((lease) => lease.id == leaseId)
        .map((lease) => lease.leaseName)
        .firstOrNull;
  }

  /// The leases that may be named when a case reaches `signed`: those of the
  /// case's unit, or all of the property's while no unit is chosen.
  List<LeaseSummaryDto> leasesForCase(LeasingCaseDto value) {
    final unitId = value.unitId;
    if (unitId == null) {
      return leases;
    }
    return leases
        .where((lease) => lease.unitId == unitId)
        .toList(growable: false);
  }

  LeasingCasesState copyWith({
    LeasingCasesListPhase? listPhase,
    LeasingCasesDetailPhase? detailPhase,
    LeasingCasesActionPhase? actionPhase,
    List<LeasingCaseSummaryDto>? cases,
    List<UnitSummaryDto>? units,
    List<PartySummaryDto>? parties,
    List<LeaseSummaryDto>? leases,
    Object? nextCursor = _unchanged,
    bool? loadingMore,
    bool? openOnly,
    Object? stageFilter = _unchanged,
    Object? selectedCaseId = _unchanged,
    Object? selectedCase = _unchanged,
    Object? versionConflict = _unchanged,
    Object? refusal = _unchanged,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
  }) {
    return LeasingCasesState(
      listPhase: listPhase ?? this.listPhase,
      detailPhase: detailPhase ?? this.detailPhase,
      actionPhase: actionPhase ?? this.actionPhase,
      cases: cases ?? this.cases,
      units: units ?? this.units,
      parties: parties ?? this.parties,
      leases: leases ?? this.leases,
      nextCursor: identical(nextCursor, _unchanged)
          ? this.nextCursor
          : nextCursor as String?,
      loadingMore: loadingMore ?? this.loadingMore,
      openOnly: openOnly ?? this.openOnly,
      stageFilter: identical(stageFilter, _unchanged)
          ? this.stageFilter
          : stageFilter as LeasingCaseStatus?,
      selectedCaseId: identical(selectedCaseId, _unchanged)
          ? this.selectedCaseId
          : selectedCaseId as String?,
      selectedCase: identical(selectedCase, _unchanged)
          ? this.selectedCase
          : selectedCase as LeasingCaseDto?,
      versionConflict: identical(versionConflict, _unchanged)
          ? this.versionConflict
          : versionConflict as LeasingVersionConflict?,
      refusal: identical(refusal, _unchanged)
          ? this.refusal
          : refusal as LeasingCaseStepRefusal?,
      message: identical(message, _unchanged) ? this.message : message as String?,
      actionMessage: identical(actionMessage, _unchanged)
          ? this.actionMessage
          : actionMessage as String?,
    );
  }
}

typedef LeasingCasesIdFactory = String Function();

class LeasingCasesController extends StateNotifier<LeasingCasesState> {
  LeasingCasesController({
    required LeasingCaseRepository repository,
    required LeasingCaseSearchPort search,
    required UnitSearchPort unitSearch,
    required LeaseSearchPort leaseSearch,
    required PartySearchPort partySearch,
    required WorkspaceSessionScope scope,
    required String propertyId,
    LeasingQueryInvalidationSource? invalidationSource,
    LeasingCasesIdFactory? idFactory,
    Duration invalidationCoalesceWindow = const Duration(milliseconds: 250),
  }) : _repository = repository,
       _search = search,
       _unitSearch = unitSearch,
       _leaseSearch = leaseSearch,
       _partySearch = partySearch,
       _scope = scope,
       _propertyId = propertyId,
       _invalidationSource = invalidationSource,
       _idFactory = idFactory ?? const Uuid().v4,
       _coalesceWindow = invalidationCoalesceWindow,
       super(const LeasingCasesState.loading());

  static const String readPermission = 'lease.read';
  static const String managePermission = 'lease.manage';
  static const int pageSize = 50;
  static const int companionPageSize = 100;

  final LeasingCaseRepository _repository;
  final LeasingCaseSearchPort _search;
  final UnitSearchPort _unitSearch;
  final LeaseSearchPort _leaseSearch;
  final PartySearchPort _partySearch;
  final WorkspaceSessionScope _scope;
  final String _propertyId;
  final LeasingQueryInvalidationSource? _invalidationSource;
  final LeasingCasesIdFactory _idFactory;
  final Duration _coalesceWindow;

  StreamSubscription<LeasingQueryInvalidation>? _invalidationSubscription;
  Timer? _invalidationTimer;
  int _generation = 0;
  int _detailGeneration = 0;

  AuthorizationPort get _authorization => _scope.authorization;

  bool get canMutate =>
      _scope.mutationsSupported &&
      _scope.isResolved &&
      _authorization.can(managePermission);

  bool get isReadOnlyBackend => !_scope.mutationsSupported;

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        listPhase: LeasingCasesListPhase.idle,
        cases: const <LeasingCaseSummaryDto>[],
        nextCursor: null,
        message: null,
      );
      return;
    }
    _subscribeToInvalidation(workspaceId);
    final generation = ++_generation;
    state = state.copyWith(
      listPhase: LeasingCasesListPhase.loading,
      message: null,
    );
    final result = await _search.search(_listQuery(workspaceId));
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case LeasingRepositorySuccess<LeasingPageResult<LeasingCaseSummaryDto>>(
        :final value,
      ):
        state = state.copyWith(
          listPhase: value.items.isEmpty
              ? LeasingCasesListPhase.empty
              : LeasingCasesListPhase.ready,
          cases: value.items,
          nextCursor: value.nextCursor,
          message: null,
        );
      case LeasingRepositoryFailure<LeasingPageResult<LeasingCaseSummaryDto>>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          listPhase: kind == LeasingRepositoryFailureKind.forbidden
              ? LeasingCasesListPhase.forbidden
              : LeasingCasesListPhase.error,
          cases: const <LeasingCaseSummaryDto>[],
          nextCursor: null,
          message: message,
        );
    }
    await _loadCompanions(workspaceId, generation);
  }

  LeasingCaseListQuery _listQuery(String workspaceId, {String? cursor}) {
    return LeasingCaseListQuery(
      workspaceId: workspaceId,
      propertyId: _propertyId,
      status: state.stageFilter,
      openOnly: state.openOnly,
      page: LeasingPageRequest(limit: pageSize, cursor: cursor),
    );
  }

  Future<void> _loadCompanions(String workspaceId, int generation) async {
    final unitResult = await _unitSearch.search(
      UnitListQuery(
        workspaceId: workspaceId,
        propertyId: _propertyId,
        page: const LeasingPageRequest(limit: companionPageSize),
      ),
    );
    if (generation != _generation) {
      return;
    }
    final units = switch (unitResult) {
      LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>(:final value) =>
        value.items,
      LeasingRepositoryFailure<LeasingPageResult<UnitSummaryDto>>() =>
        const <UnitSummaryDto>[],
    };

    final leaseResult = await _leaseSearch.search(
      LeaseListQuery(
        workspaceId: workspaceId,
        propertyId: _propertyId,
        page: const LeasingPageRequest(limit: companionPageSize),
      ),
    );
    if (generation != _generation) {
      return;
    }
    final leases = switch (leaseResult) {
      LeasingRepositorySuccess<LeasingPageResult<LeaseSummaryDto>>(
        :final value,
      ) =>
        value.items,
      LeasingRepositoryFailure<LeasingPageResult<LeaseSummaryDto>>() =>
        const <LeaseSummaryDto>[],
    };

    // Unfiltered by role: a prospect is not a tenant, and there is no prospect
    // role to filter by.
    final partyResult = await _partySearch.search(
      PartyListQuery(
        workspaceId: workspaceId,
        page: const PartyPageRequest(limit: companionPageSize),
      ),
    );
    if (generation != _generation) {
      return;
    }
    final parties = switch (partyResult) {
      PartyRepositorySuccess<PartyPageResult>(:final value) => value.items,
      PartyRepositoryFailure<PartyPageResult>() => const <PartySummaryDto>[],
    };

    state = state.copyWith(units: units, leases: leases, parties: parties);
  }

  Future<void> loadMore() async {
    final workspaceId = _scope.workspaceId;
    final cursor = state.nextCursor;
    if (workspaceId == null || cursor == null || state.loadingMore) {
      return;
    }
    final generation = _generation;
    state = state.copyWith(loadingMore: true);
    final result = await _search.search(_listQuery(workspaceId, cursor: cursor));
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case LeasingRepositorySuccess<LeasingPageResult<LeasingCaseSummaryDto>>(
        :final value,
      ):
        state = state.copyWith(
          cases: <LeasingCaseSummaryDto>[...state.cases, ...value.items],
          nextCursor: value.nextCursor,
          loadingMore: false,
        );
      case LeasingRepositoryFailure<LeasingPageResult<LeasingCaseSummaryDto>>(
        :final message,
      ):
        state = state.copyWith(loadingMore: false, message: message);
    }
  }

  Future<void> setStageFilter(LeasingCaseStatus? status) async {
    if (status == state.stageFilter) {
      return;
    }
    state = state.copyWith(stageFilter: status);
    await load();
  }

  Future<void> setOpenOnly(bool openOnly) async {
    if (openOnly == state.openOnly) {
      return;
    }
    state = state.copyWith(openOnly: openOnly);
    await load();
  }

  Future<void> clearFilters() async {
    state = state.copyWith(stageFilter: null, openOnly: true);
    await load();
  }

  Future<void> select(String? caseId) async {
    if (caseId == null) {
      _detailGeneration++;
      state = state.copyWith(
        detailPhase: LeasingCasesDetailPhase.idle,
        selectedCaseId: null,
        selectedCase: null,
        refusal: null,
      );
      return;
    }
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    final generation = ++_detailGeneration;
    state = state.copyWith(
      detailPhase: LeasingCasesDetailPhase.loading,
      selectedCaseId: caseId,
      selectedCase: null,
      refusal: null,
    );
    final result = await _repository.getById(
      workspaceId: workspaceId,
      caseId: caseId,
    );
    if (generation != _detailGeneration) {
      return;
    }
    switch (result) {
      case LeasingRepositorySuccess<LeasingCaseDto>(:final value):
        state = state.copyWith(
          detailPhase: LeasingCasesDetailPhase.ready,
          selectedCase: value,
        );
      case LeasingRepositoryFailure<LeasingCaseDto>(:final kind, :final message):
        state = state.copyWith(
          detailPhase: switch (kind) {
            LeasingRepositoryFailureKind.notFound =>
              LeasingCasesDetailPhase.notFound,
            LeasingRepositoryFailureKind.forbidden =>
              LeasingCasesDetailPhase.forbidden,
            _ => LeasingCasesDetailPhase.error,
          },
          message: message,
        );
    }
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: LeasingCasesActionPhase.idle,
      actionMessage: null,
      versionConflict: null,
      refusal: null,
    );
  }

  Future<void> createCase(LeasingCaseDraft draft) async {
    await _runMutation(
      () => _repository.create(
        CreateLeasingCaseCommand(context: _commandContext(), draft: draft),
      ),
      onSuccess: (LeasingCaseDto created) async {
        await load();
        await select(created.id);
      },
      successMessage: 'Fall angelegt — er startet als Anfrage.',
    );
  }

  /// Attributes may change while the case is open. A closed case is history,
  /// not a record to be tidied up afterwards, and the server says so.
  Future<void> updateCase({
    required LeasingCaseDto leasingCase,
    required LeasingCaseUpdateDto changes,
  }) async {
    if (leasingCase.status.isTerminal) {
      state = state.copyWith(
        actionPhase: LeasingCasesActionPhase.blocked,
        actionMessage:
            'Dieser Fall ist abgeschlossen. Abgeschlossene Fälle sind '
            'Historie und werden nicht nachträglich geändert.',
        versionConflict: null,
        refusal: null,
      );
      return;
    }
    await _runMutation(
      () => _repository.update(
        UpdateLeasingCaseCommand(
          context: _commandContext(),
          caseId: leasingCase.id,
          expectedVersion: leasingCase.version,
          changes: changes,
        ),
      ),
      onSuccess: (LeasingCaseDto updated) async {
        await load();
        await select(updated.id);
      },
      successMessage: 'Fall gespeichert.',
    );
  }

  /// Exactly one stage forward. [leaseId] is required when the step reaches
  /// [LeasingCaseStatus.signed] and the case does not already name a lease.
  Future<void> advanceCase({
    required LeasingCaseDto leasingCase,
    String? leaseId,
  }) async {
    final target = leasingCase.status.nextStage;
    if (target == null) {
      state = state.copyWith(
        actionPhase: LeasingCasesActionPhase.blocked,
        actionMessage: null,
        versionConflict: null,
        refusal: LeasingCaseStepRefusal(from: leasingCase.status),
      );
      return;
    }
    // The client mirror of the server's preconditions. It decides nothing — it
    // only avoids proposing a step that is certain to be refused, and names
    // which precondition is missing instead of reporting a rejection.
    final blocked = leasingCase.blockedReason;
    final resolvedByArgument =
        blocked == LeasingCaseBlockedReason.leaseRequired && leaseId != null;
    if (blocked != null && !resolvedByArgument) {
      state = state.copyWith(
        actionPhase: LeasingCasesActionPhase.blocked,
        actionMessage: null,
        versionConflict: null,
        refusal: LeasingCaseStepRefusal(
          from: leasingCase.status,
          attempted: target,
          blockedReason: blocked,
        ),
      );
      return;
    }
    await _runMutation(
      () => _repository.transitionStatus(
        TransitionLeasingCaseStatusCommand(
          context: _commandContext(),
          caseId: leasingCase.id,
          expectedVersion: leasingCase.version,
          targetStatus: target,
          leaseId: leaseId,
        ),
      ),
      onSuccess: (LeasingCaseDto updated) async {
        await load();
        await select(updated.id);
      },
      successMessage: 'Fall auf die nächste Stufe gesetzt.',
      attemptedFrom: leasingCase.status,
      attemptedTo: target,
    );
  }

  /// The abort edge. The reason is mandatory, and there is no way back: a new
  /// attempt is a new case.
  Future<void> cancelCase({
    required LeasingCaseDto leasingCase,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(
        actionPhase: LeasingCasesActionPhase.failed,
        actionMessage:
            'Für den Abbruch ist ein Grund erforderlich — er wird im '
            'Änderungsprotokoll festgehalten.',
        versionConflict: null,
        refusal: null,
      );
      return;
    }
    await _runMutation(
      () => _repository.transitionStatus(
        TransitionLeasingCaseStatusCommand(
          context: _commandContext(reason: trimmed),
          caseId: leasingCase.id,
          expectedVersion: leasingCase.version,
          targetStatus: LeasingCaseStatus.cancelled,
        ),
      ),
      onSuccess: (LeasingCaseDto updated) async {
        await load();
        await select(updated.id);
      },
      successMessage: 'Fall abgebrochen.',
      attemptedFrom: leasingCase.status,
      attemptedTo: LeasingCaseStatus.cancelled,
    );
  }

  Future<void> _runMutation<T>(
    Future<LeasingRepositoryResult<T>> Function() command, {
    required Future<void> Function(T value) onSuccess,
    required String successMessage,
    LeasingCaseStatus? attemptedFrom,
    LeasingCaseStatus? attemptedTo,
  }) async {
    if (_applyMutationGate()) {
      return;
    }
    state = state.copyWith(
      actionPhase: LeasingCasesActionPhase.submitting,
      actionMessage: null,
      versionConflict: null,
      refusal: null,
    );
    final result = await command();
    switch (result) {
      case LeasingRepositorySuccess<T>(:final value):
        await onSuccess(value);
        state = state.copyWith(
          actionPhase: LeasingCasesActionPhase.succeeded,
          actionMessage: successMessage,
          versionConflict: null,
          refusal: null,
        );
      case LeasingRepositoryFailure<T>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        final refusedStep =
            kind == LeasingRepositoryFailureKind.validationFailed &&
            attemptedFrom != null &&
            attemptedTo != null;
        state = state.copyWith(
          actionPhase: switch (kind) {
            LeasingRepositoryFailureKind.versionConflict =>
              LeasingCasesActionPhase.conflict,
            LeasingRepositoryFailureKind.forbidden =>
              LeasingCasesActionPhase.forbidden,
            LeasingRepositoryFailureKind.dependencyConflict =>
              LeasingCasesActionPhase.readOnly,
            LeasingRepositoryFailureKind.validationFailed when refusedStep =>
              LeasingCasesActionPhase.blocked,
            _ => LeasingCasesActionPhase.failed,
          },
          actionMessage: refusedStep ? null : message,
          versionConflict: versionConflict,
          refusal: refusedStep
              ? LeasingCaseStepRefusal(
                  from: attemptedFrom,
                  attempted: attemptedTo,
                  serverMessage: message,
                )
              : null,
        );
    }
  }

  bool _applyMutationGate() {
    if (isReadOnlyBackend) {
      state = state.copyWith(
        actionPhase: LeasingCasesActionPhase.readOnly,
        actionMessage:
            'Die Vermietungspipeline ist in der lokalen Datenbank '
            'schreibgeschützt, bis diese Domäne migriert ist.',
        versionConflict: null,
        refusal: null,
      );
      return true;
    }
    if (!_scope.isResolved || !_authorization.can(managePermission)) {
      state = state.copyWith(
        actionPhase: LeasingCasesActionPhase.forbidden,
        actionMessage: 'Für diese Aktion fehlt die Berechtigung.',
        versionConflict: null,
        refusal: null,
      );
      return true;
    }
    return false;
  }

  LeasingCommandContext _commandContext({String? reason}) {
    return LeasingCommandContext(
      workspaceId: _scope.workspaceId!,
      actorId: _scope.actorId!,
      mutationId: _idFactory(),
      correlationId: _idFactory(),
      reason: reason,
    );
  }

  void _subscribeToInvalidation(String workspaceId) {
    final source = _invalidationSource;
    if (source == null || _invalidationSubscription != null) {
      return;
    }
    _invalidationSubscription = source
        .watchWorkspace(workspaceId: workspaceId)
        .listen((invalidation) {
          if (invalidation.workspaceId != _scope.workspaceId) {
            return;
          }
          // Lease events matter here too: naming the lease a case produced is a
          // case write, but a lease created elsewhere changes what this board
          // can offer at the `signed` step. Unit and snapshot events cannot.
          final aggregate = invalidation.aggregate;
          if (!invalidation.isReconciliation &&
              aggregate != LeasingAggregate.leasingCase &&
              aggregate != LeasingAggregate.lease) {
            return;
          }
          _scheduleInvalidationReload();
        });
  }

  void _scheduleInvalidationReload() {
    _invalidationTimer?.cancel();
    _invalidationTimer = Timer(_coalesceWindow, () {
      unawaited(load());
      final selectedId = state.selectedCaseId;
      if (selectedId != null) {
        unawaited(select(selectedId));
      }
    });
  }

  @override
  void dispose() {
    _invalidationTimer?.cancel();
    _invalidationTimer = null;
    unawaited(_invalidationSubscription?.cancel());
    _invalidationSubscription = null;
    super.dispose();
  }
}

final leasingCasesControllerProvider = StateNotifierProvider.autoDispose
    .family<LeasingCasesController, LeasingCasesState, String>((
      ref,
      propertyId,
    ) {
      final controller = LeasingCasesController(
        repository: ref.watch(leasingCaseRepositoryProvider),
        search: ref.watch(leasingCaseSearchProvider),
        unitSearch: ref.watch(unitSearchProvider),
        leaseSearch: ref.watch(leaseSearchProvider),
        partySearch: ref.watch(partySearchProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
        propertyId: propertyId,
        invalidationSource: ref.watch(leasingQueryInvalidationSourceProvider),
      );
      unawaited(controller.load());
      return controller;
    });
