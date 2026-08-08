/// Screen-facing orchestration for the rent roll (P2-D05, Welle 3 AP6).
///
/// The surface has **two halves, and they are different documents**:
///
///   * The **live rent roll** — the current state, read from
///     `RentRollPort.readLive` (P2-D05b). The screen does no arithmetic: the
///     rule that decides which lease counts lives next to the one that builds a
///     snapshot, so the two cannot drift.
///   * The **snapshot history** — frozen documents (AGG-007). A snapshot has no
///     update, transition or delete; the only lawful operation on one is
///     creating another. Hence no version and no conflict handling here: a row
///     that is never written twice has nothing to hold a concurrency token
///     against.
///
/// Where they disagree, the snapshot wins as the record: it was computed
/// server-side, its totals are structurally pinned to its lines, and it is what
/// a report cites. The live view is deliberately marked as computed-now.
///
/// DEC-011 holds on both halves: rents in different currencies are never summed.
/// The live document reports the currencies it found and leaves its totals null;
/// a snapshot is refused outright, because freezing a wrong number is worse than
/// not freezing one.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/authorization_port.dart';
import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/rent_roll_dto.dart';
import 'leasing_providers.dart';
import 'leasing_query_invalidation_source.dart';
import 'leasing_repository.dart';

const Object _unchanged = Object();

enum RentRollLivePhase { idle, loading, ready, empty, forbidden, error }

enum RentRollHistoryPhase {
  idle,
  loading,
  ready,
  empty,
  forbidden,

  /// The bound backend cannot serve frozen snapshots at all — not a permission
  /// problem and not an empty result. Carries the adapter's reason.
  unsupported,
  error,
}

enum RentRollDetailPhase { idle, loading, ready, notFound, forbidden, error }

enum RentRollActionPhase {
  idle,
  submitting,
  succeeded,
  forbidden,
  readOnly,

  /// The contributing leases do not share one currency (DEC-011). Its own phase
  /// because it carries the currencies found, which is what makes it fixable.
  currencyMismatch,
  failed,
}

class RentRollState {
  const RentRollState({
    required this.livePhase,
    this.historyPhase = RentRollHistoryPhase.idle,
    this.detailPhase = RentRollDetailPhase.idle,
    this.actionPhase = RentRollActionPhase.idle,
    this.live,
    this.snapshots = const <RentRollSnapshotDto>[],
    this.nextCursor,
    this.loadingMore = false,
    this.selectedSnapshotId,
    this.selectedSnapshot,
    this.currencyMismatch,
    this.liveMessage,
    this.historyMessage,
    this.message,
    this.actionMessage,
  });

  const RentRollState.loading() : this(livePhase: RentRollLivePhase.loading);

  final RentRollLivePhase livePhase;
  final RentRollHistoryPhase historyPhase;
  final RentRollDetailPhase detailPhase;
  final RentRollActionPhase actionPhase;

  /// The live document: header and one row per unit, as the backend computed
  /// it. Null until the first successful read.
  final RentRollLiveDto? live;

  /// Frozen snapshots, newest first. Several may share an `asOfDate`.
  final List<RentRollSnapshotDto> snapshots;

  final String? nextCursor;
  final bool loadingMore;
  final String? selectedSnapshotId;

  /// The full frozen document, lines included.
  final RentRollSnapshotDto? selectedSnapshot;

  final RentRollCurrencyMismatch? currencyMismatch;
  final String? liveMessage;
  final String? historyMessage;
  final String? message;
  final String? actionMessage;

  bool get hasMore => nextCursor != null;

  List<RentRollLiveLineDto> get occupiedOutsideTermRows =>
      live?.occupiedOutsideTermLines ?? const <RentRollLiveLineDto>[];

  RentRollState copyWith({
    RentRollLivePhase? livePhase,
    RentRollHistoryPhase? historyPhase,
    RentRollDetailPhase? detailPhase,
    RentRollActionPhase? actionPhase,
    Object? live = _unchanged,
    List<RentRollSnapshotDto>? snapshots,
    Object? nextCursor = _unchanged,
    bool? loadingMore,
    Object? selectedSnapshotId = _unchanged,
    Object? selectedSnapshot = _unchanged,
    Object? currencyMismatch = _unchanged,
    Object? liveMessage = _unchanged,
    Object? historyMessage = _unchanged,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
  }) {
    return RentRollState(
      livePhase: livePhase ?? this.livePhase,
      historyPhase: historyPhase ?? this.historyPhase,
      detailPhase: detailPhase ?? this.detailPhase,
      actionPhase: actionPhase ?? this.actionPhase,
      live: identical(live, _unchanged) ? this.live : live as RentRollLiveDto?,
      snapshots: snapshots ?? this.snapshots,
      nextCursor: identical(nextCursor, _unchanged)
          ? this.nextCursor
          : nextCursor as String?,
      loadingMore: loadingMore ?? this.loadingMore,
      selectedSnapshotId: identical(selectedSnapshotId, _unchanged)
          ? this.selectedSnapshotId
          : selectedSnapshotId as String?,
      selectedSnapshot: identical(selectedSnapshot, _unchanged)
          ? this.selectedSnapshot
          : selectedSnapshot as RentRollSnapshotDto?,
      currencyMismatch: identical(currencyMismatch, _unchanged)
          ? this.currencyMismatch
          : currencyMismatch as RentRollCurrencyMismatch?,
      liveMessage: identical(liveMessage, _unchanged)
          ? this.liveMessage
          : liveMessage as String?,
      historyMessage: identical(historyMessage, _unchanged)
          ? this.historyMessage
          : historyMessage as String?,
      message: identical(message, _unchanged) ? this.message : message as String?,
      actionMessage: identical(actionMessage, _unchanged)
          ? this.actionMessage
          : actionMessage as String?,
    );
  }
}

typedef RentRollIdFactory = String Function();
typedef RentRollClock = DateTime Function();

class RentRollController extends StateNotifier<RentRollState> {
  RentRollController({
    required RentRollPort rentRoll,
    required WorkspaceSessionScope scope,
    required String propertyId,
    LeasingQueryInvalidationSource? invalidationSource,
    RentRollIdFactory? idFactory,
    RentRollClock? clock,
    Duration invalidationCoalesceWindow = const Duration(milliseconds: 250),
  }) : _rentRoll = rentRoll,
       _scope = scope,
       _propertyId = propertyId,
       _invalidationSource = invalidationSource,
       _idFactory = idFactory ?? const Uuid().v4,
       _clock = clock ?? DateTime.now,
       _coalesceWindow = invalidationCoalesceWindow,
       super(const RentRollState.loading());

  static const String readPermission = 'lease.read';
  static const String managePermission = 'lease.manage';
  static const int pageSize = 50;

  final RentRollPort _rentRoll;
  final WorkspaceSessionScope _scope;
  final String _propertyId;
  final LeasingQueryInvalidationSource? _invalidationSource;
  final RentRollIdFactory _idFactory;
  final RentRollClock _clock;
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

  /// The reporting date of the live half: today, as a date. A live rent roll
  /// with a date picker would be a client-computed snapshot, which is exactly
  /// the thing the frozen half exists for.
  DateTime get asOfDate {
    final now = _clock();
    return DateTime.utc(now.year, now.month, now.day);
  }

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        livePhase: RentRollLivePhase.idle,
        historyPhase: RentRollHistoryPhase.idle,
        live: null,
        snapshots: const <RentRollSnapshotDto>[],
        nextCursor: null,
      );
      return;
    }
    _subscribeToInvalidation(workspaceId);
    final generation = ++_generation;
    state = state.copyWith(
      livePhase: RentRollLivePhase.loading,
      historyPhase: RentRollHistoryPhase.loading,
      liveMessage: null,
      historyMessage: null,
    );
    await _loadLive(workspaceId, generation);
    await _loadHistory(workspaceId, generation);
  }

  /// One read. The backend computes it — P2-D05b moved the rule next to the
  /// SQL that freezes a snapshot, so this screen cannot disagree with the
  /// document it offers to freeze.
  Future<void> _loadLive(String workspaceId, int generation) async {
    final result = await _rentRoll.readLive(
      workspaceId: workspaceId,
      propertyId: _propertyId,
      asOfDate: asOfDate,
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case LeasingRepositorySuccess<RentRollLiveDto>(:final value):
        state = state.copyWith(
          livePhase: value.lines.isEmpty
              ? RentRollLivePhase.empty
              : RentRollLivePhase.ready,
          live: value,
          liveMessage: null,
        );
      case LeasingRepositoryFailure<RentRollLiveDto>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          livePhase: kind == LeasingRepositoryFailureKind.forbidden
              ? RentRollLivePhase.forbidden
              : RentRollLivePhase.error,
          live: null,
          liveMessage: message,
        );
    }
  }

  Future<void> _loadHistory(String workspaceId, int generation) async {
    final result = await _rentRoll.listSnapshots(
      RentRollSnapshotListQuery(
        workspaceId: workspaceId,
        propertyId: _propertyId,
        page: const LeasingPageRequest(limit: pageSize),
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case LeasingRepositorySuccess<LeasingPageResult<RentRollSnapshotDto>>(
        :final value,
      ):
        state = state.copyWith(
          historyPhase: value.items.isEmpty
              ? RentRollHistoryPhase.empty
              : RentRollHistoryPhase.ready,
          snapshots: value.items,
          nextCursor: value.nextCursor,
          historyMessage: null,
        );
      case LeasingRepositoryFailure<LeasingPageResult<RentRollSnapshotDto>>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          historyPhase: switch (kind) {
            LeasingRepositoryFailureKind.forbidden =>
              RentRollHistoryPhase.forbidden,
            // Befund 2a: the legacy adapter refuses the read itself, and says
            // why. Rendering that as "no snapshots" would be a false claim
            // about the data — and the live half above still works.
            LeasingRepositoryFailureKind.dependencyConflict =>
              RentRollHistoryPhase.unsupported,
            _ => RentRollHistoryPhase.error,
          },
          snapshots: const <RentRollSnapshotDto>[],
          nextCursor: null,
          historyMessage: message,
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
    final result = await _rentRoll.listSnapshots(
      RentRollSnapshotListQuery(
        workspaceId: workspaceId,
        propertyId: _propertyId,
        page: LeasingPageRequest(limit: pageSize, cursor: cursor),
      ),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case LeasingRepositorySuccess<LeasingPageResult<RentRollSnapshotDto>>(
        :final value,
      ):
        state = state.copyWith(
          snapshots: <RentRollSnapshotDto>[...state.snapshots, ...value.items],
          nextCursor: value.nextCursor,
          loadingMore: false,
        );
      case LeasingRepositoryFailure<LeasingPageResult<RentRollSnapshotDto>>(
        :final message,
      ):
        state = state.copyWith(loadingMore: false, historyMessage: message);
    }
  }

  Future<void> select(String? snapshotId) async {
    if (snapshotId == null) {
      _detailGeneration++;
      state = state.copyWith(
        detailPhase: RentRollDetailPhase.idle,
        selectedSnapshotId: null,
        selectedSnapshot: null,
      );
      return;
    }
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    final generation = ++_detailGeneration;
    state = state.copyWith(
      detailPhase: RentRollDetailPhase.loading,
      selectedSnapshotId: snapshotId,
      selectedSnapshot: null,
    );
    final result = await _rentRoll.getSnapshot(
      workspaceId: workspaceId,
      snapshotId: snapshotId,
    );
    if (generation != _detailGeneration) {
      return;
    }
    switch (result) {
      case LeasingRepositorySuccess<RentRollSnapshotDto>(:final value):
        state = state.copyWith(
          detailPhase: RentRollDetailPhase.ready,
          selectedSnapshot: value,
        );
      case LeasingRepositoryFailure<RentRollSnapshotDto>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          detailPhase: switch (kind) {
            LeasingRepositoryFailureKind.notFound =>
              RentRollDetailPhase.notFound,
            LeasingRepositoryFailureKind.forbidden =>
              RentRollDetailPhase.forbidden,
            _ => RentRollDetailPhase.error,
          },
          message: message,
        );
    }
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: RentRollActionPhase.idle,
      actionMessage: null,
      currencyMismatch: null,
    );
  }

  /// Freezes the current state as a snapshot. [currencyCode] is only needed
  /// when no effective lease implies one — the fully vacant property that still
  /// deserves a rent roll of zeros. Passing one that contradicts the leases is
  /// refused, and that refusal carries the currencies actually found.
  Future<void> createSnapshot({
    required DateTime asOfDate,
    String? currencyCode,
  }) async {
    if (_applyMutationGate()) {
      return;
    }
    state = state.copyWith(
      actionPhase: RentRollActionPhase.submitting,
      actionMessage: null,
      currencyMismatch: null,
    );
    final result = await _rentRoll.createSnapshot(
      CreateRentRollSnapshotCommand(
        context: _commandContext(),
        propertyId: _propertyId,
        asOfDate: asOfDate,
        currencyCode: currencyCode,
      ),
    );
    switch (result) {
      case LeasingRepositorySuccess<RentRollSnapshotDto>(:final value):
        await load();
        await select(value.id);
        state = state.copyWith(
          actionPhase: RentRollActionPhase.succeeded,
          actionMessage:
              'Snapshot erzeugt und eingefroren. Eine Korrektur ist ein neuer '
              'Snapshot — dieser bleibt unverändert.',
          currencyMismatch: null,
        );
      case LeasingRepositoryFailure<RentRollSnapshotDto>(
        :final kind,
        :final message,
        :final currencyMismatch,
      ):
        state = state.copyWith(
          actionPhase: switch (kind) {
            LeasingRepositoryFailureKind.forbidden =>
              RentRollActionPhase.forbidden,
            LeasingRepositoryFailureKind.dependencyConflict =>
              RentRollActionPhase.readOnly,
            LeasingRepositoryFailureKind.currencyMismatch =>
              RentRollActionPhase.currencyMismatch,
            _ => RentRollActionPhase.failed,
          },
          actionMessage: message,
          currencyMismatch: currencyMismatch,
        );
    }
  }

  bool _applyMutationGate() {
    if (isReadOnlyBackend) {
      state = state.copyWith(
        actionPhase: RentRollActionPhase.readOnly,
        actionMessage:
            'Ein Snapshot kann in der lokalen Datenbank nicht eingefroren '
            'werden, bis diese Domäne migriert ist. Die Live-Tabelle bleibt '
            'vollständig lesbar.',
        currencyMismatch: null,
      );
      return true;
    }
    if (!_scope.isResolved || !_authorization.can(managePermission)) {
      state = state.copyWith(
        actionPhase: RentRollActionPhase.forbidden,
        actionMessage: 'Für diese Aktion fehlt die Berechtigung.',
        currencyMismatch: null,
      );
      return true;
    }
    return false;
  }

  LeasingCommandContext _commandContext() {
    return LeasingCommandContext(
      workspaceId: _scope.workspaceId!,
      actorId: _scope.actorId!,
      mutationId: _idFactory(),
      correlationId: _idFactory(),
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
          // All three matter now: units and leases move the live table, and
          // snapshots the history. A frozen document still cannot change — only
          // the list it appears in can.
          if (!invalidation.isReconciliation &&
              invalidation.aggregate == LeasingAggregate.leasingCase) {
            return;
          }
          _scheduleInvalidationReload();
        });
  }

  void _scheduleInvalidationReload() {
    _invalidationTimer?.cancel();
    _invalidationTimer = Timer(_coalesceWindow, () {
      unawaited(load());
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

final rentRollControllerProvider = StateNotifierProvider.autoDispose
    .family<RentRollController, RentRollState, String>((ref, propertyId) {
      final controller = RentRollController(
        rentRoll: ref.watch(rentRollProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
        propertyId: propertyId,
        invalidationSource: ref.watch(leasingQueryInvalidationSourceProvider),
      );
      unawaited(controller.load());
      return controller;
    });
