/// Screen-facing orchestration over the unit half of the leasing_operations
/// contract (P2-D05, Welle 3 AP1), mirroring `PartiesController`: explicit
/// phases per zone, a generation guard against out-of-order responses, and
/// every mandatory screen state of `03_design_system.md` represented as data
/// rather than as an ad hoc widget branch.
///
/// Three things here are specific to this domain and are the reason the screen
/// cannot just reuse the party controller:
///
///   * **Occupancy is derived (AGG-004).** There is no "set to occupied"
///     affordance, because the server refuses it. The only caller-driven edge
///     is `offline`, which requires a reason — and that reason *is* the unit's
///     offline reason, not a separate audit note.
///   * **Leaving `offline` has to name the status the leases imply.** The
///     server honours `vacant`/`occupied` only while the unit is offline and
///     only if the value matches the effective leases, so [returnFromOffline]
///     reads the unit's leases first and sends the matching value instead of
///     guessing. A race still ends in `validationFailed`, which is surfaced
///     rather than retried blindly.
///   * **One command can emit two realtime events.** Activating a lease writes
///     the lease and, through `sync_unit_occupancy`, its unit. Both tables are
///     published on purpose. [_scheduleInvalidationReload] coalesces them into
///     a single refetch — the migration promises clients will, and a screen
///     that refetched twice per command would make that promise false.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/authorization_port.dart';
import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/lease_dto.dart';
import '../domain/unit_dto.dart';
import 'leasing_providers.dart';
import 'leasing_query_invalidation_source.dart';
import 'leasing_repository.dart';

const Object _unchanged = Object();

enum UnitsListPhase { idle, loading, ready, empty, forbidden, error }

enum UnitsDetailPhase { idle, loading, ready, notFound, forbidden, error }

enum UnitsActionPhase {
  idle,
  submitting,
  succeeded,
  conflict,
  forbidden,

  /// The bound backend cannot mutate yet (the legacy SQLite adapters are
  /// read-only by design). Rendered as the mandatory "read-only until migrated"
  /// notice.
  readOnly,
  failed,
}

class UnitsState {
  const UnitsState({
    required this.listPhase,
    this.detailPhase = UnitsDetailPhase.idle,
    this.actionPhase = UnitsActionPhase.idle,
    this.units = const <UnitSummaryDto>[],
    this.nextCursor,
    this.loadingMore = false,
    this.statusFilter,
    this.selectedUnitId,
    this.selectedUnit,
    this.selectedUnitLeases = const <LeaseSummaryDto>[],
    this.versionConflict,
    this.message,
    this.actionMessage,
  });

  const UnitsState.loading() : this(listPhase: UnitsListPhase.loading);

  final UnitsListPhase listPhase;
  final UnitsDetailPhase detailPhase;
  final UnitsActionPhase actionPhase;
  final List<UnitSummaryDto> units;
  final String? nextCursor;
  final bool loadingMore;
  final UnitStatus? statusFilter;
  final String? selectedUnitId;
  final UnitDto? selectedUnit;

  /// **Every** lease of the selected unit, effective or not — never "the"
  /// lease. `OPN-DOM-001` allows several concurrently effective ones, and the
  /// history matters for the detail view, so this is deliberately unfiltered
  /// and `LeaseSummaryDto.isEffective` marks the rows that count for occupancy.
  final List<LeaseSummaryDto> selectedUnitLeases;

  final LeasingVersionConflict? versionConflict;
  final String? message;
  final String? actionMessage;

  bool get hasMore => nextCursor != null;

  UnitsState copyWith({
    UnitsListPhase? listPhase,
    UnitsDetailPhase? detailPhase,
    UnitsActionPhase? actionPhase,
    List<UnitSummaryDto>? units,
    Object? nextCursor = _unchanged,
    bool? loadingMore,
    Object? statusFilter = _unchanged,
    Object? selectedUnitId = _unchanged,
    Object? selectedUnit = _unchanged,
    List<LeaseSummaryDto>? selectedUnitLeases,
    Object? versionConflict = _unchanged,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
  }) {
    return UnitsState(
      listPhase: listPhase ?? this.listPhase,
      detailPhase: detailPhase ?? this.detailPhase,
      actionPhase: actionPhase ?? this.actionPhase,
      units: units ?? this.units,
      nextCursor: identical(nextCursor, _unchanged)
          ? this.nextCursor
          : nextCursor as String?,
      loadingMore: loadingMore ?? this.loadingMore,
      statusFilter: identical(statusFilter, _unchanged)
          ? this.statusFilter
          : statusFilter as UnitStatus?,
      selectedUnitId: identical(selectedUnitId, _unchanged)
          ? this.selectedUnitId
          : selectedUnitId as String?,
      selectedUnit: identical(selectedUnit, _unchanged)
          ? this.selectedUnit
          : selectedUnit as UnitDto?,
      selectedUnitLeases: selectedUnitLeases ?? this.selectedUnitLeases,
      versionConflict: identical(versionConflict, _unchanged)
          ? this.versionConflict
          : versionConflict as LeasingVersionConflict?,
      message: identical(message, _unchanged) ? this.message : message as String?,
      actionMessage: identical(actionMessage, _unchanged)
          ? this.actionMessage
          : actionMessage as String?,
    );
  }
}

typedef UnitsIdFactory = String Function();

class UnitsController extends StateNotifier<UnitsState> {
  UnitsController({
    required UnitRepository repository,
    required UnitSearchPort search,
    required LeaseSearchPort leaseSearch,
    required WorkspaceSessionScope scope,
    required String propertyId,
    LeasingQueryInvalidationSource? invalidationSource,
    UnitsIdFactory? idFactory,
    Duration invalidationCoalesceWindow = const Duration(milliseconds: 250),
  }) : _repository = repository,
       _search = search,
       _leaseSearch = leaseSearch,
       _scope = scope,
       _propertyId = propertyId,
       _invalidationSource = invalidationSource,
       _idFactory = idFactory ?? const Uuid().v4,
       _coalesceWindow = invalidationCoalesceWindow,
       super(const UnitsState.loading());

  static const String readPermission = 'lease.read';
  static const String managePermission = 'lease.manage';
  static const int pageSize = 50;

  final UnitRepository _repository;
  final UnitSearchPort _search;
  final LeaseSearchPort _leaseSearch;
  final WorkspaceSessionScope _scope;
  final String _propertyId;
  final LeasingQueryInvalidationSource? _invalidationSource;
  final UnitsIdFactory _idFactory;
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
        listPhase: UnitsListPhase.idle,
        units: const <UnitSummaryDto>[],
        nextCursor: null,
        message: null,
      );
      return;
    }
    _subscribeToInvalidation(workspaceId);
    final generation = ++_generation;
    state = state.copyWith(listPhase: UnitsListPhase.loading, message: null);
    final result = await _search.search(
      UnitListQuery(
        workspaceId: workspaceId,
        propertyId: _propertyId,
        status: state.statusFilter,
        page: const LeasingPageRequest(limit: pageSize),
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>(
        :final value,
      ):
        state = state.copyWith(
          listPhase: value.items.isEmpty
              ? UnitsListPhase.empty
              : UnitsListPhase.ready,
          units: value.items,
          nextCursor: value.nextCursor,
          message: null,
        );
      case LeasingRepositoryFailure<LeasingPageResult<UnitSummaryDto>>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          listPhase: kind == LeasingRepositoryFailureKind.forbidden
              ? UnitsListPhase.forbidden
              : UnitsListPhase.error,
          units: const <UnitSummaryDto>[],
          nextCursor: null,
          message: message,
        );
    }
  }

  Future<void> loadMore() async {
    final workspaceId = _scope.workspaceId;
    final cursor = state.nextCursor;
    if (workspaceId == null || cursor == null || state.loadingMore) {
      return;
    }
    final generation = _generation;
    state = state.copyWith(loadingMore: true);
    final result = await _search.search(
      UnitListQuery(
        workspaceId: workspaceId,
        propertyId: _propertyId,
        status: state.statusFilter,
        page: LeasingPageRequest(limit: pageSize, cursor: cursor),
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>(
        :final value,
      ):
        state = state.copyWith(
          units: <UnitSummaryDto>[...state.units, ...value.items],
          nextCursor: value.nextCursor,
          loadingMore: false,
        );
      case LeasingRepositoryFailure<LeasingPageResult<UnitSummaryDto>>(
        :final message,
      ):
        state = state.copyWith(loadingMore: false, message: message);
    }
  }

  Future<void> setStatusFilter(UnitStatus? status) async {
    if (status == state.statusFilter) {
      return;
    }
    state = state.copyWith(statusFilter: status);
    await load();
  }

  Future<void> select(String? unitId) async {
    if (unitId == null) {
      _detailGeneration++;
      state = state.copyWith(
        detailPhase: UnitsDetailPhase.idle,
        selectedUnitId: null,
        selectedUnit: null,
        selectedUnitLeases: const <LeaseSummaryDto>[],
      );
      return;
    }
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    final generation = ++_detailGeneration;
    state = state.copyWith(
      detailPhase: UnitsDetailPhase.loading,
      selectedUnitId: unitId,
      selectedUnit: null,
      selectedUnitLeases: const <LeaseSummaryDto>[],
    );
    final result = await _repository.getById(
      workspaceId: workspaceId,
      unitId: unitId,
    );
    if (generation != _detailGeneration) {
      return;
    }
    switch (result) {
      case LeasingRepositorySuccess<UnitDto>(:final value):
        final leases = await _loadUnitLeases(workspaceId, unitId);
        if (generation != _detailGeneration) {
          return;
        }
        state = state.copyWith(
          detailPhase: UnitsDetailPhase.ready,
          selectedUnit: value,
          selectedUnitLeases: leases,
        );
      case LeasingRepositoryFailure<UnitDto>(:final kind, :final message):
        state = state.copyWith(
          detailPhase: switch (kind) {
            LeasingRepositoryFailureKind.notFound => UnitsDetailPhase.notFound,
            LeasingRepositoryFailureKind.forbidden => UnitsDetailPhase.forbidden,
            _ => UnitsDetailPhase.error,
          },
          message: message,
        );
    }
  }

  /// Unfiltered on purpose — see [UnitsState.selectedUnitLeases]. A failure
  /// here degrades to an empty list rather than failing the whole detail: the
  /// unit itself loaded, and a lease list that could not be read is better
  /// reported as "no leases shown" by the view than as "unit not found".
  Future<List<LeaseSummaryDto>> _loadUnitLeases(
    String workspaceId,
    String unitId,
  ) async {
    final result = await _leaseSearch.search(
      LeaseListQuery(
        workspaceId: workspaceId,
        unitId: unitId,
        page: const LeasingPageRequest(limit: 100),
      ),
    );
    return switch (result) {
      LeasingRepositorySuccess<LeasingPageResult<LeaseSummaryDto>>(
        :final value,
      ) =>
        value.items,
      LeasingRepositoryFailure<LeasingPageResult<LeaseSummaryDto>>() =>
        const <LeaseSummaryDto>[],
    };
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: UnitsActionPhase.idle,
      actionMessage: null,
      versionConflict: null,
    );
  }

  Future<void> createUnit(UnitDraft draft) async {
    await _runMutation(
      () => _repository.create(
        CreateUnitCommand(context: _commandContext(), draft: draft),
      ),
      onSuccess: (UnitDto unit) async {
        await load();
        await select(unit.id);
      },
      successMessage: 'Einheit angelegt.',
    );
  }

  Future<void> updateUnit({
    required String unitId,
    required int expectedVersion,
    required UnitUpdateDto changes,
  }) async {
    await _runMutation(
      () => _repository.update(
        UpdateUnitCommand(
          context: _commandContext(),
          unitId: unitId,
          expectedVersion: expectedVersion,
          changes: changes,
        ),
      ),
      onSuccess: (UnitDto unit) async {
        await load();
        await select(unit.id);
      },
      successMessage: 'Einheit gespeichert.',
    );
  }

  /// STM-003's one caller-driven edge. [reason] is mandatory and becomes both
  /// the unit's `offline_reason` and the audit reason — one value, one fact.
  Future<void> takeOffline({
    required String unitId,
    required int expectedVersion,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(
        actionPhase: UnitsActionPhase.failed,
        actionMessage:
            'Für die Offline-Nahme ist ein Grund erforderlich — er wird als '
            'Offline-Grund gespeichert und auditiert.',
        versionConflict: null,
      );
      return;
    }
    await _runMutation(
      () => _repository.transitionStatus(
        TransitionUnitStatusCommand(
          context: _commandContext(reason: trimmed),
          unitId: unitId,
          expectedVersion: expectedVersion,
          targetStatus: UnitStatus.offline,
        ),
      ),
      onSuccess: (UnitDto unit) async {
        await load();
        await select(unit.id);
      },
      successMessage: 'Einheit offline genommen.',
    );
  }

  /// Returning from `offline`. The server accepts `vacant`/`occupied` only
  /// while the unit is offline and only if the value matches the effective
  /// leases, so the target is read from the leases rather than guessed. If the
  /// lease situation changes between the read and the command, the server says
  /// so and the failure is surfaced — never silently retried with the other
  /// value, which would paper over a real concurrent change.
  Future<void> returnFromOffline({
    required String unitId,
    required int expectedVersion,
    String? reason,
  }) async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    // Same gate as every other mutation, applied before the extra lease read so
    // a blocked action never costs a round trip.
    if (_applyMutationGate()) {
      return;
    }
    final leaseResult = await _leaseSearch.search(
      LeaseListQuery(
        workspaceId: workspaceId,
        unitId: unitId,
        effectiveOnly: true,
        page: const LeasingPageRequest(limit: 1),
      ),
    );
    if (leaseResult is LeasingRepositoryFailure<
        LeasingPageResult<LeaseSummaryDto>>) {
      state = state.copyWith(
        actionPhase: UnitsActionPhase.failed,
        actionMessage:
            'Die Vertragslage der Einheit konnte nicht gelesen werden, deshalb '
            'wurde der Status nicht geändert: ${leaseResult.message}',
        versionConflict: null,
      );
      return;
    }
    final effective = (leaseResult
            as LeasingRepositorySuccess<LeasingPageResult<LeaseSummaryDto>>)
        .value
        .items;
    final target = effective.isEmpty ? UnitStatus.vacant : UnitStatus.occupied;
    await _runMutation(
      () => _repository.transitionStatus(
        TransitionUnitStatusCommand(
          context: _commandContext(reason: reason?.trim()),
          unitId: unitId,
          expectedVersion: expectedVersion,
          targetStatus: target,
        ),
      ),
      onSuccess: (UnitDto unit) async {
        await load();
        await select(unit.id);
      },
      successMessage: target == UnitStatus.occupied
          ? 'Einheit zurückgeholt — sie gilt als vermietet.'
          : 'Einheit zurückgeholt — sie gilt als leerstehend.',
    );
  }

  Future<void> _runMutation<T>(
    Future<LeasingRepositoryResult<T>> Function() command, {
    required Future<void> Function(T value) onSuccess,
    required String successMessage,
  }) async {
    if (_applyMutationGate()) {
      return;
    }
    state = state.copyWith(
      actionPhase: UnitsActionPhase.submitting,
      actionMessage: null,
      versionConflict: null,
    );
    final result = await command();
    switch (result) {
      case LeasingRepositorySuccess<T>(:final value):
        await onSuccess(value);
        state = state.copyWith(
          actionPhase: UnitsActionPhase.succeeded,
          actionMessage: successMessage,
          versionConflict: null,
        );
      case LeasingRepositoryFailure<T>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        state = state.copyWith(
          actionPhase: switch (kind) {
            LeasingRepositoryFailureKind.versionConflict =>
              UnitsActionPhase.conflict,
            LeasingRepositoryFailureKind.forbidden => UnitsActionPhase.forbidden,
            LeasingRepositoryFailureKind.dependencyConflict =>
              UnitsActionPhase.readOnly,
            _ => UnitsActionPhase.failed,
          },
          actionMessage: message,
          versionConflict: versionConflict,
        );
    }
  }

  /// Writes the blocking action phase and returns true when a mutation must not
  /// be attempted: a read-only backend is a different answer from a missing
  /// right, and the screen renders them differently.
  bool _applyMutationGate() {
    if (isReadOnlyBackend) {
      state = state.copyWith(
        actionPhase: UnitsActionPhase.readOnly,
        actionMessage:
            'Einheiten sind in der lokalen Datenbank schreibgeschützt, bis '
            'diese Domäne migriert ist.',
        versionConflict: null,
      );
      return true;
    }
    if (!_scope.isResolved || !_authorization.can(managePermission)) {
      state = state.copyWith(
        actionPhase: UnitsActionPhase.forbidden,
        actionMessage: 'Für diese Aktion fehlt die Berechtigung.',
        versionConflict: null,
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
          // Lease events matter here too: activating a lease flips this unit's
          // derived occupancy without touching the unit through a unit command.
          // Case and snapshot events cannot change a unit and are ignored.
          final aggregate = invalidation.aggregate;
          if (!invalidation.isReconciliation &&
              aggregate != LeasingAggregate.unit &&
              aggregate != LeasingAggregate.lease) {
            return;
          }
          _scheduleInvalidationReload();
        });
  }

  /// Collapses the burst a single command produces into one refetch. Without
  /// this, every lease activation would refetch twice — once for the lease
  /// event and once for the derived unit event.
  void _scheduleInvalidationReload() {
    _invalidationTimer?.cancel();
    _invalidationTimer = Timer(_coalesceWindow, () {
      unawaited(load());
      final selectedId = state.selectedUnitId;
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

final unitsControllerProvider = StateNotifierProvider.autoDispose
    .family<UnitsController, UnitsState, String>((ref, propertyId) {
      final controller = UnitsController(
        repository: ref.watch(unitRepositoryProvider),
        search: ref.watch(unitSearchProvider),
        leaseSearch: ref.watch(leaseSearchProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
        propertyId: propertyId,
        invalidationSource: ref.watch(leasingQueryInvalidationSourceProvider),
      );
      unawaited(controller.load());
      return controller;
    });
