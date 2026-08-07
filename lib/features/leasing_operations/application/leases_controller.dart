/// Screen-facing orchestration over the lease half of the leasing_operations
/// contract (P2-D05, Welle 3 AP3), mirroring [UnitsController]: explicit phases
/// per zone, a generation guard against out-of-order responses, and every
/// mandatory screen state of `03_design_system.md` represented as data rather
/// than as an ad hoc widget branch.
///
/// Four things here are specific to leases and are why the lease screens cannot
/// simply reuse the unit controller:
///
///   * **STM-005 is a chain with one forward edge.** [advanceLease] never takes
///     a target status from the caller; it reads the one lawful next step from
///     the lease itself. A screen cannot ask for a move the chain does not
///     contain, and there is no backward edge to ask for.
///   * **A refused transition is an explained state, not an error.** A
///     `validationFailed` on a transition produces a [LeaseTransitionRejection]
///     carrying the status it started from and the one it attempted, so the
///     view can say what STM-005 *does* allow instead of echoing a server
///     string. The status labels stay in the UI layer; this layer carries the
///     facts.
///   * **Editing stops at the first signature.** `update_lease` accepts only
///     `draft`/`reviewed`/`sent`. The gate is applied here as well as
///     server-side, so a stale screen explains itself instead of spending a
///     round trip on a refusal.
///   * **Two companion reads make the list readable.** A lease carries a
///     `unitId` and a `tenantPartyId`, not a unit code and a tenant name. Units
///     come from the same contract; tenants are parties with the `tenant` role
///     (AGG-005 — there is deliberately no cloud `tenants` table). Both are
///     side reads: if either fails the lease list still renders, with the
///     unresolved reference named as such rather than a blank cell.
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
import '../domain/unit_dto.dart';
import 'leasing_providers.dart';
import 'leasing_query_invalidation_source.dart';
import 'leasing_repository.dart';

const Object _unchanged = Object();

enum LeasesListPhase { idle, loading, ready, empty, forbidden, error }

enum LeasesDetailPhase { idle, loading, ready, notFound, forbidden, error }

enum LeasesActionPhase {
  idle,
  submitting,
  succeeded,
  conflict,
  forbidden,

  /// The bound backend cannot mutate yet (the legacy SQLite adapters are
  /// read-only by design). Rendered as the mandatory "read-only until migrated"
  /// notice.
  readOnly,

  /// The command was lawful to attempt but the lease is not in a state that
  /// permits it — a refused STM-005 step, or an edit of a binding lease. Its
  /// own phase because the view explains it inline rather than flashing it as
  /// a failure.
  notAllowed,
  failed,
}

/// A transition the server (or the local mirror) refused, with both ends of the
/// attempted edge so the view can name what is allowed instead.
class LeaseTransitionRejection {
  const LeaseTransitionRejection({
    required this.from,
    required this.attempted,
    this.serverMessage,
  });

  final LeaseStatus from;
  final LeaseStatus attempted;
  final String? serverMessage;
}

class LeasesState {
  const LeasesState({
    required this.listPhase,
    this.detailPhase = LeasesDetailPhase.idle,
    this.actionPhase = LeasesActionPhase.idle,
    this.leases = const <LeaseSummaryDto>[],
    this.units = const <UnitSummaryDto>[],
    this.tenants = const <PartySummaryDto>[],
    this.nextCursor,
    this.loadingMore = false,
    this.statusFilter,
    this.effectiveOnly = false,
    this.unitFilter,
    this.tenantFilter,
    this.selectedLeaseId,
    this.selectedLease,
    this.versionConflict,
    this.rejection,
    this.message,
    this.actionMessage,
  });

  const LeasesState.loading() : this(listPhase: LeasesListPhase.loading);

  final LeasesListPhase listPhase;
  final LeasesDetailPhase detailPhase;
  final LeasesActionPhase actionPhase;
  final List<LeaseSummaryDto> leases;

  /// The property's units, for the unit column and the unit choice in the form.
  /// Empty when the companion read failed — never a reason to fail the list.
  final List<UnitSummaryDto> units;

  /// Parties holding the `tenant` role, for the tenant column and filter.
  final List<PartySummaryDto> tenants;

  final String? nextCursor;
  final bool loadingMore;
  final LeaseStatus? statusFilter;

  /// Restrict to leases that count for occupancy (status `active`). Server-side,
  /// and distinct from a date filter.
  final bool effectiveOnly;

  final String? unitFilter;
  final String? tenantFilter;
  final String? selectedLeaseId;
  final LeaseDto? selectedLease;
  final LeasingVersionConflict? versionConflict;
  final LeaseTransitionRejection? rejection;
  final String? message;
  final String? actionMessage;

  bool get hasMore => nextCursor != null;

  bool get hasActiveFilter =>
      statusFilter != null ||
      effectiveOnly ||
      unitFilter != null ||
      tenantFilter != null;

  /// The unit code behind a lease's `unitId`, or null when the companion read
  /// could not resolve it. Callers render the difference; this never invents a
  /// label.
  String? unitCodeFor(String unitId) => units
      .where((unit) => unit.id == unitId)
      .map((unit) => unit.unitCode)
      .firstOrNull;

  String? tenantNameFor(String? partyId) {
    if (partyId == null) {
      return null;
    }
    return tenants
        .where((party) => party.id == partyId)
        .map((party) => party.displayName)
        .firstOrNull;
  }

  LeasesState copyWith({
    LeasesListPhase? listPhase,
    LeasesDetailPhase? detailPhase,
    LeasesActionPhase? actionPhase,
    List<LeaseSummaryDto>? leases,
    List<UnitSummaryDto>? units,
    List<PartySummaryDto>? tenants,
    Object? nextCursor = _unchanged,
    bool? loadingMore,
    Object? statusFilter = _unchanged,
    bool? effectiveOnly,
    Object? unitFilter = _unchanged,
    Object? tenantFilter = _unchanged,
    Object? selectedLeaseId = _unchanged,
    Object? selectedLease = _unchanged,
    Object? versionConflict = _unchanged,
    Object? rejection = _unchanged,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
  }) {
    return LeasesState(
      listPhase: listPhase ?? this.listPhase,
      detailPhase: detailPhase ?? this.detailPhase,
      actionPhase: actionPhase ?? this.actionPhase,
      leases: leases ?? this.leases,
      units: units ?? this.units,
      tenants: tenants ?? this.tenants,
      nextCursor: identical(nextCursor, _unchanged)
          ? this.nextCursor
          : nextCursor as String?,
      loadingMore: loadingMore ?? this.loadingMore,
      statusFilter: identical(statusFilter, _unchanged)
          ? this.statusFilter
          : statusFilter as LeaseStatus?,
      effectiveOnly: effectiveOnly ?? this.effectiveOnly,
      unitFilter: identical(unitFilter, _unchanged)
          ? this.unitFilter
          : unitFilter as String?,
      tenantFilter: identical(tenantFilter, _unchanged)
          ? this.tenantFilter
          : tenantFilter as String?,
      selectedLeaseId: identical(selectedLeaseId, _unchanged)
          ? this.selectedLeaseId
          : selectedLeaseId as String?,
      selectedLease: identical(selectedLease, _unchanged)
          ? this.selectedLease
          : selectedLease as LeaseDto?,
      versionConflict: identical(versionConflict, _unchanged)
          ? this.versionConflict
          : versionConflict as LeasingVersionConflict?,
      rejection: identical(rejection, _unchanged)
          ? this.rejection
          : rejection as LeaseTransitionRejection?,
      message: identical(message, _unchanged) ? this.message : message as String?,
      actionMessage: identical(actionMessage, _unchanged)
          ? this.actionMessage
          : actionMessage as String?,
    );
  }
}

typedef LeasesIdFactory = String Function();

class LeasesController extends StateNotifier<LeasesState> {
  LeasesController({
    required LeaseRepository repository,
    required LeaseSearchPort search,
    required UnitSearchPort unitSearch,
    required PartySearchPort partySearch,
    required WorkspaceSessionScope scope,
    required String propertyId,
    LeasingQueryInvalidationSource? invalidationSource,
    LeasesIdFactory? idFactory,
    Duration invalidationCoalesceWindow = const Duration(milliseconds: 250),
  }) : _repository = repository,
       _search = search,
       _unitSearch = unitSearch,
       _partySearch = partySearch,
       _scope = scope,
       _propertyId = propertyId,
       _invalidationSource = invalidationSource,
       _idFactory = idFactory ?? const Uuid().v4,
       _coalesceWindow = invalidationCoalesceWindow,
       super(const LeasesState.loading());

  static const String readPermission = 'lease.read';
  static const String managePermission = 'lease.manage';
  static const int pageSize = 50;

  /// One page is enough for the unit and tenant pickers of a single property;
  /// this wave adds no new backend reads, so neither companion is paged.
  static const int companionPageSize = 100;

  final LeaseRepository _repository;
  final LeaseSearchPort _search;
  final UnitSearchPort _unitSearch;
  final PartySearchPort _partySearch;
  final WorkspaceSessionScope _scope;
  final String _propertyId;
  final LeasingQueryInvalidationSource? _invalidationSource;
  final LeasesIdFactory _idFactory;
  final Duration _coalesceWindow;

  StreamSubscription<LeasingQueryInvalidation>? _invalidationSubscription;
  Timer? _invalidationTimer;
  int _generation = 0;
  int _detailGeneration = 0;

  AuthorizationPort get _authorization => _scope.authorization;

  /// Whether mutation affordances are actionable at all. False in a read-only
  /// backend and when the actor lacks `lease.manage` in cloud mode.
  bool get canMutate =>
      _scope.mutationsSupported &&
      _scope.isResolved &&
      _authorization.can(managePermission);

  /// True exactly when the backend itself blocks mutations, which is what the
  /// "read-only until migrated" notice reports (as opposed to a rights issue).
  bool get isReadOnlyBackend => !_scope.mutationsSupported;

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        listPhase: LeasesListPhase.idle,
        leases: const <LeaseSummaryDto>[],
        nextCursor: null,
        message: null,
      );
      return;
    }
    _subscribeToInvalidation(workspaceId);
    final generation = ++_generation;
    state = state.copyWith(listPhase: LeasesListPhase.loading, message: null);
    final result = await _search.search(_listQuery(workspaceId));
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case LeasingRepositorySuccess<LeasingPageResult<LeaseSummaryDto>>(
        :final value,
      ):
        state = state.copyWith(
          listPhase: value.items.isEmpty
              ? LeasesListPhase.empty
              : LeasesListPhase.ready,
          leases: value.items,
          nextCursor: value.nextCursor,
          message: null,
        );
      case LeasingRepositoryFailure<LeasingPageResult<LeaseSummaryDto>>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          listPhase: kind == LeasingRepositoryFailureKind.forbidden
              ? LeasesListPhase.forbidden
              : LeasesListPhase.error,
          leases: const <LeaseSummaryDto>[],
          nextCursor: null,
          message: message,
        );
    }
    // Companions come after the list so the table paints on the first response
    // instead of waiting for three.
    await _loadCompanions(workspaceId, generation);
  }

  LeaseListQuery _listQuery(String workspaceId, {String? cursor}) {
    return LeaseListQuery(
      workspaceId: workspaceId,
      propertyId: _propertyId,
      unitId: state.unitFilter,
      tenantPartyId: state.tenantFilter,
      status: state.statusFilter,
      effectiveOnly: state.effectiveOnly,
      page: LeasingPageRequest(limit: pageSize, cursor: cursor),
    );
  }

  /// Unit codes and tenant names. Either failing degrades to an empty list: the
  /// leases are readable without them, and a list that refuses to render
  /// because a label lookup failed would be worse than one that names the
  /// unresolved reference.
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
    final units =
        switch (unitResult) {
          LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>(
            :final value,
          ) =>
            value.items,
          LeasingRepositoryFailure<LeasingPageResult<UnitSummaryDto>>() =>
            const <UnitSummaryDto>[],
        };

    // AGG-005: a tenant is a party holding the `tenant` role, filtered
    // server-side. There is no tenants table to read instead.
    final partyResult = await _partySearch.search(
      PartyListQuery(
        workspaceId: workspaceId,
        roleType: PartyRoleType.tenant,
        page: const PartyPageRequest(limit: companionPageSize),
      ),
    );
    if (generation != _generation) {
      return;
    }
    final tenants = switch (partyResult) {
      PartyRepositorySuccess<PartyPageResult>(:final value) => value.items,
      PartyRepositoryFailure<PartyPageResult>() => const <PartySummaryDto>[],
    };

    state = state.copyWith(units: units, tenants: tenants);
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
      case LeasingRepositorySuccess<LeasingPageResult<LeaseSummaryDto>>(
        :final value,
      ):
        state = state.copyWith(
          leases: <LeaseSummaryDto>[...state.leases, ...value.items],
          nextCursor: value.nextCursor,
          loadingMore: false,
        );
      case LeasingRepositoryFailure<LeasingPageResult<LeaseSummaryDto>>(
        :final message,
      ):
        state = state.copyWith(loadingMore: false, message: message);
    }
  }

  Future<void> setStatusFilter(LeaseStatus? status) async {
    if (status == state.statusFilter) {
      return;
    }
    state = state.copyWith(statusFilter: status);
    await load();
  }

  Future<void> setEffectiveOnly(bool effectiveOnly) async {
    if (effectiveOnly == state.effectiveOnly) {
      return;
    }
    state = state.copyWith(effectiveOnly: effectiveOnly);
    await load();
  }

  Future<void> setUnitFilter(String? unitId) async {
    if (unitId == state.unitFilter) {
      return;
    }
    state = state.copyWith(unitFilter: unitId);
    await load();
  }

  Future<void> setTenantFilter(String? tenantPartyId) async {
    if (tenantPartyId == state.tenantFilter) {
      return;
    }
    state = state.copyWith(tenantFilter: tenantPartyId);
    await load();
  }

  Future<void> clearFilters() async {
    state = state.copyWith(
      statusFilter: null,
      effectiveOnly: false,
      unitFilter: null,
      tenantFilter: null,
    );
    await load();
  }

  Future<void> select(String? leaseId) async {
    if (leaseId == null) {
      _detailGeneration++;
      state = state.copyWith(
        detailPhase: LeasesDetailPhase.idle,
        selectedLeaseId: null,
        selectedLease: null,
        rejection: null,
      );
      return;
    }
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    final generation = ++_detailGeneration;
    state = state.copyWith(
      detailPhase: LeasesDetailPhase.loading,
      selectedLeaseId: leaseId,
      selectedLease: null,
      rejection: null,
    );
    final result = await _repository.getById(
      workspaceId: workspaceId,
      leaseId: leaseId,
    );
    if (generation != _detailGeneration) {
      return;
    }
    switch (result) {
      case LeasingRepositorySuccess<LeaseDto>(:final value):
        state = state.copyWith(
          detailPhase: LeasesDetailPhase.ready,
          selectedLease: value,
        );
      case LeasingRepositoryFailure<LeaseDto>(:final kind, :final message):
        state = state.copyWith(
          detailPhase: switch (kind) {
            LeasingRepositoryFailureKind.notFound => LeasesDetailPhase.notFound,
            LeasingRepositoryFailureKind.forbidden =>
              LeasesDetailPhase.forbidden,
            _ => LeasesDetailPhase.error,
          },
          message: message,
        );
    }
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: LeasesActionPhase.idle,
      actionMessage: null,
      versionConflict: null,
      rejection: null,
    );
  }

  /// A lease always starts in [LeaseStatus.draft]; the draft carries no status
  /// and the server would refuse one.
  Future<void> createLease(LeaseDraft draft) async {
    await _runMutation(
      () => _repository.create(
        CreateLeaseCommand(context: _commandContext(), draft: draft),
      ),
      onSuccess: (LeaseDto lease) async {
        await load();
        await select(lease.id);
      },
      successMessage: 'Vertrag angelegt — er startet als Entwurf.',
    );
  }

  /// Whole-record attribute change, and only while the lease is not binding.
  /// The gate is checked here as well as server-side so a stale screen explains
  /// itself instead of spending a round trip on a certain refusal.
  Future<void> updateLease({
    required LeaseDto lease,
    required LeaseUpdateDto changes,
  }) async {
    if (!lease.status.isEditable) {
      state = state.copyWith(
        actionPhase: LeasesActionPhase.notAllowed,
        actionMessage:
            'Ab der ersten Unterschrift ist dieser Vertrag bindend: seine '
            'Konditionen sind nicht mehr änderbar. Eine Änderung der '
            'Konditionen ist ein neuer Vertrag.',
        versionConflict: null,
        rejection: null,
      );
      return;
    }
    await _runMutation(
      () => _repository.update(
        UpdateLeaseCommand(
          context: _commandContext(),
          leaseId: lease.id,
          expectedVersion: lease.version,
          changes: changes,
        ),
      ),
      onSuccess: (LeaseDto updated) async {
        await load();
        await select(updated.id);
      },
      successMessage: 'Vertrag gespeichert.',
    );
  }

  /// The one lawful forward step of STM-005, read from the lease rather than
  /// chosen by the caller. [moveOutDate] belongs only to the step into
  /// [LeaseStatus.ended]; anywhere else it is refused here instead of being
  /// sent to be refused there.
  Future<void> advanceLease({
    required LeaseDto lease,
    DateTime? moveOutDate,
  }) async {
    final target = lease.status.nextStatus;
    if (target == null) {
      state = state.copyWith(
        actionPhase: LeasesActionPhase.notAllowed,
        actionMessage: null,
        versionConflict: null,
        rejection: LeaseTransitionRejection(
          from: lease.status,
          attempted: lease.status,
        ),
      );
      return;
    }
    if (moveOutDate != null && target != LeaseStatus.ended) {
      state = state.copyWith(
        actionPhase: LeasesActionPhase.failed,
        actionMessage:
            'Ein Auszugsdatum gehört ausschließlich zum Beenden eines '
            'Vertrags.',
        versionConflict: null,
        rejection: null,
      );
      return;
    }
    await _runMutation(
      () => _repository.transitionStatus(
        TransitionLeaseStatusCommand(
          context: _commandContext(),
          leaseId: lease.id,
          expectedVersion: lease.version,
          targetStatus: target,
          moveOutDate: moveOutDate,
        ),
      ),
      onSuccess: (LeaseDto updated) async {
        await load();
        await select(updated.id);
      },
      successMessage: _advanceMessage(target),
      attemptedFrom: lease.status,
      attemptedTo: target,
    );
  }

  /// The abort edge. The reason is mandatory — an empty one never reaches the
  /// server, which would refuse it anyway.
  Future<void> cancelLease({
    required LeaseDto lease,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(
        actionPhase: LeasesActionPhase.failed,
        actionMessage:
            'Für den Abbruch ist ein Grund erforderlich — er wird im '
            'Änderungsprotokoll festgehalten.',
        versionConflict: null,
        rejection: null,
      );
      return;
    }
    await _runMutation(
      () => _repository.transitionStatus(
        TransitionLeaseStatusCommand(
          context: _commandContext(reason: trimmed),
          leaseId: lease.id,
          expectedVersion: lease.version,
          targetStatus: LeaseStatus.cancelled,
        ),
      ),
      onSuccess: (LeaseDto updated) async {
        await load();
        await select(updated.id);
      },
      successMessage: 'Vertrag abgebrochen.',
      attemptedFrom: lease.status,
      attemptedTo: LeaseStatus.cancelled,
    );
  }

  static String _advanceMessage(LeaseStatus target) => switch (target) {
    LeaseStatus.reviewed => 'Vertrag als geprüft markiert.',
    LeaseStatus.sent => 'Vertrag als versendet markiert.',
    LeaseStatus.tenantSigned => 'Unterschrift des Mieters erfasst.',
    LeaseStatus.landlordSigned => 'Unterschrift des Vermieters erfasst.',
    LeaseStatus.active =>
      'Vertrag aktiviert — die Einheit gilt jetzt als vermietet.',
    LeaseStatus.ended => 'Vertrag beendet.',
    LeaseStatus.draft || LeaseStatus.cancelled => 'Status geändert.',
  };

  Future<void> _runMutation<T>(
    Future<LeasingRepositoryResult<T>> Function() command, {
    required Future<void> Function(T value) onSuccess,
    required String successMessage,
    LeaseStatus? attemptedFrom,
    LeaseStatus? attemptedTo,
  }) async {
    if (_applyMutationGate()) {
      return;
    }
    state = state.copyWith(
      actionPhase: LeasesActionPhase.submitting,
      actionMessage: null,
      versionConflict: null,
      rejection: null,
    );
    final result = await command();
    switch (result) {
      case LeasingRepositorySuccess<T>(:final value):
        await onSuccess(value);
        state = state.copyWith(
          actionPhase: LeasesActionPhase.succeeded,
          actionMessage: successMessage,
          versionConflict: null,
          rejection: null,
        );
      case LeasingRepositoryFailure<T>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        // A refused transition is the one failure this domain can explain in
        // its own terms, so it becomes a rejection rather than a message.
        final refusedTransition =
            kind == LeasingRepositoryFailureKind.validationFailed &&
            attemptedFrom != null &&
            attemptedTo != null;
        state = state.copyWith(
          actionPhase: switch (kind) {
            LeasingRepositoryFailureKind.versionConflict =>
              LeasesActionPhase.conflict,
            LeasingRepositoryFailureKind.forbidden =>
              LeasesActionPhase.forbidden,
            LeasingRepositoryFailureKind.dependencyConflict =>
              LeasesActionPhase.readOnly,
            LeasingRepositoryFailureKind.validationFailed when refusedTransition
                =>
              LeasesActionPhase.notAllowed,
            _ => LeasesActionPhase.failed,
          },
          actionMessage: refusedTransition ? null : message,
          versionConflict: versionConflict,
          rejection: refusedTransition
              ? LeaseTransitionRejection(
                  from: attemptedFrom,
                  attempted: attemptedTo,
                  serverMessage: message,
                )
              : null,
        );
    }
  }

  /// Writes the blocking action phase and returns true when a mutation must not
  /// be attempted: a read-only backend is a different answer from a missing
  /// right, and the screen renders them differently.
  bool _applyMutationGate() {
    if (isReadOnlyBackend) {
      state = state.copyWith(
        actionPhase: LeasesActionPhase.readOnly,
        actionMessage:
            'Verträge sind in der lokalen Datenbank schreibgeschützt, bis '
            'diese Domäne migriert ist.',
        versionConflict: null,
        rejection: null,
      );
      return true;
    }
    if (!_scope.isResolved || !_authorization.can(managePermission)) {
      state = state.copyWith(
        actionPhase: LeasesActionPhase.forbidden,
        actionMessage: 'Für diese Aktion fehlt die Berechtigung.',
        versionConflict: null,
        rejection: null,
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
          // Only lease events can change this list. The unit event that a lease
          // activation also emits describes derived occupancy, which no column
          // here shows — reacting to it would be the second refetch the
          // migration warns about.
          if (!invalidation.isReconciliation &&
              invalidation.aggregate != LeasingAggregate.lease) {
            return;
          }
          _scheduleInvalidationReload();
        });
  }

  /// Collapses the burst a single command produces into one refetch.
  void _scheduleInvalidationReload() {
    _invalidationTimer?.cancel();
    _invalidationTimer = Timer(_coalesceWindow, () {
      unawaited(load());
      final selectedId = state.selectedLeaseId;
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

final leasesControllerProvider = StateNotifierProvider.autoDispose
    .family<LeasesController, LeasesState, String>((ref, propertyId) {
      final controller = LeasesController(
        repository: ref.watch(leaseRepositoryProvider),
        search: ref.watch(leaseSearchProvider),
        unitSearch: ref.watch(unitSearchProvider),
        partySearch: ref.watch(partySearchProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
        propertyId: propertyId,
        invalidationSource: ref.watch(leasingQueryInvalidationSourceProvider),
      );
      unawaited(controller.load());
      return controller;
    });
