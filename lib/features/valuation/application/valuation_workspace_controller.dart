/// Screen-facing orchestration for the workspace-wide valuation work queue
/// (Welle 5, AP3).
///
/// One keyset read per page over the contract's own list query — filters are
/// server-side (`status`, `kind`, `propertyId`), so this never fetches the
/// workspace and narrows it in the client.
///
/// What it deliberately does **not** do: load each row's market value. That
/// needs a join between `valuation_cases` and `market_value_opinions`, and doing
/// it per row would be the N+1 the compliance dashboard was rebuilt to get rid
/// of. Until the list projection exists, the reconciled value belongs to the
/// selected case's detail — see [ValuationWorkspaceState.selectedCaseId].
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/valuation_case.dart';
import '../domain/valuation_case_dto.dart';
import 'valuation_case_controller.dart' show ValuationPermissions;
import 'valuation_providers.dart';
import 'valuation_query_invalidation_source.dart';
import 'valuation_repository.dart';

enum ValuationWorkspacePhase { idle, loading, ready, empty, forbidden, error }

class ValuationWorkspaceState {
  const ValuationWorkspaceState({
    required this.phase,
    this.cases = const <ValuationCaseDto>[],
    this.nextCursor,
    this.loadingMore = false,
    this.statusFilter,
    this.kindFilter,
    this.propertyFilter,
    this.includeArchived = false,
    this.selectedCaseId,
    this.message,
  });

  const ValuationWorkspaceState.loading()
    : this(phase: ValuationWorkspacePhase.loading);

  final ValuationWorkspacePhase phase;
  final List<ValuationCaseDto> cases;
  final String? nextCursor;
  final bool loadingMore;
  final ValuationCaseStatus? statusFilter;
  final ValuationCaseKind? kindFilter;

  /// Set when the queue is shown inside one property; null for the workspace
  /// view.
  final String? propertyFilter;
  final bool includeArchived;
  final String? selectedCaseId;
  final String? message;

  bool get hasMore => nextCursor != null;

  /// True when a filter is active — lets the screen tell "nothing matches this
  /// filter" apart from "no valuations exist yet", which are different answers.
  bool get isFiltered =>
      statusFilter != null || kindFilter != null || includeArchived;

  /// Cases awaiting a decision — the reason the queue exists.
  Iterable<ValuationCaseDto> get inReview =>
      cases.where((c) => c.status == ValuationCaseStatus.inReview);

  ValuationWorkspaceState copyWith({
    ValuationWorkspacePhase? phase,
    List<ValuationCaseDto>? cases,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
    ValuationCaseStatus? statusFilter,
    bool clearStatusFilter = false,
    ValuationCaseKind? kindFilter,
    bool clearKindFilter = false,
    String? propertyFilter,
    bool? includeArchived,
    String? selectedCaseId,
    bool clearSelection = false,
    String? message,
    bool clearMessage = false,
  }) => ValuationWorkspaceState(
    phase: phase ?? this.phase,
    cases: cases ?? this.cases,
    nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
    loadingMore: loadingMore ?? this.loadingMore,
    statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
    kindFilter: clearKindFilter ? null : (kindFilter ?? this.kindFilter),
    propertyFilter: propertyFilter ?? this.propertyFilter,
    includeArchived: includeArchived ?? this.includeArchived,
    selectedCaseId: clearSelection
        ? null
        : (selectedCaseId ?? this.selectedCaseId),
    message: clearMessage ? null : (message ?? this.message),
  );
}

class ValuationWorkspaceController
    extends StateNotifier<ValuationWorkspaceState> {
  ValuationWorkspaceController({
    required ValuationCaseRepository repository,
    required WorkspaceSessionScope scope,
    ValuationQueryInvalidationSource? invalidationSource,
    String? propertyFilter,
    int pageSize = 50,
  }) : _repository = repository,
       _scope = scope,
       _invalidationSource = invalidationSource,
       _pageSize = pageSize,
       super(
         ValuationWorkspaceState(
           phase: ValuationWorkspacePhase.idle,
           propertyFilter: propertyFilter,
         ),
       );

  final ValuationCaseRepository _repository;
  final WorkspaceSessionScope _scope;
  final ValuationQueryInvalidationSource? _invalidationSource;
  final int _pageSize;

  StreamSubscription<ValuationQueryInvalidation>? _invalidationSubscription;
  int _generation = 0;

  bool get canCreate =>
      _scope.permissions.contains(ValuationPermissions.manage) &&
      _scope.mutationsSupported;

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null ||
        !_scope.permissions.contains(ValuationPermissions.read)) {
      state = state.copyWith(
        phase: ValuationWorkspacePhase.forbidden,
        message: 'Keine Berechtigung für Bewertungen.',
      );
      return;
    }

    final generation = ++_generation;
    state = state.copyWith(
      phase: ValuationWorkspacePhase.loading,
      clearMessage: true,
    );

    final result = await _repository.searchValuationCases(_query(workspaceId));
    if (generation != _generation || !mounted) return;

    switch (result) {
      case ValuationRepositorySuccess(:final value):
        _subscribeToInvalidations(workspaceId);
        state = state.copyWith(
          phase: value.items.isEmpty
              ? ValuationWorkspacePhase.empty
              : ValuationWorkspacePhase.ready,
          cases: value.items,
          nextCursor: value.nextCursor,
          clearCursor: value.nextCursor == null,
          clearMessage: true,
        );
      case ValuationRepositoryFailure(:final kind, :final message):
        state = state.copyWith(
          phase: kind == ValuationRepositoryFailureKind.forbidden
              ? ValuationWorkspacePhase.forbidden
              : ValuationWorkspacePhase.error,
          message: message,
        );
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    final workspaceId = _scope.workspaceId;
    if (cursor == null || workspaceId == null || state.loadingMore) return;

    state = state.copyWith(loadingMore: true);
    final result = await _repository.searchValuationCases(
      _query(workspaceId, cursor: cursor),
    );
    if (!mounted) return;

    switch (result) {
      case ValuationRepositorySuccess(:final value):
        state = state.copyWith(
          cases: <ValuationCaseDto>[...state.cases, ...value.items],
          nextCursor: value.nextCursor,
          clearCursor: value.nextCursor == null,
          loadingMore: false,
        );
      case ValuationRepositoryFailure(:final message):
        // The page already on screen stays valid; only the append failed.
        state = state.copyWith(loadingMore: false, message: message);
    }
  }

  Future<void> filterByStatus(ValuationCaseStatus? status) async {
    state = state.copyWith(
      statusFilter: status,
      clearStatusFilter: status == null,
      clearCursor: true,
    );
    await load();
  }

  Future<void> filterByKind(ValuationCaseKind? kind) async {
    state = state.copyWith(
      kindFilter: kind,
      clearKindFilter: kind == null,
      clearCursor: true,
    );
    await load();
  }

  Future<void> setIncludeArchived(bool include) async {
    state = state.copyWith(includeArchived: include, clearCursor: true);
    await load();
  }

  void select(String? valuationCaseId) {
    state = state.copyWith(
      selectedCaseId: valuationCaseId,
      clearSelection: valuationCaseId == null,
    );
  }

  ValuationCaseListQuery _query(String workspaceId, {String? cursor}) =>
      ValuationCaseListQuery(
        workspaceId: workspaceId,
        propertyId: state.propertyFilter,
        kind: state.kindFilter,
        status: state.statusFilter,
        includeArchived: state.includeArchived,
        page: ValuationPageRequest(limit: _pageSize, cursor: cursor),
      );

  void _subscribeToInvalidations(String workspaceId) {
    if (_invalidationSubscription != null || _invalidationSource == null) {
      return;
    }
    _invalidationSubscription = _invalidationSource
        .watchWorkspace(workspaceId: workspaceId)
        .listen(
          (_) {
            if (mounted) unawaited(load());
          },
          // A dead channel must not blank the queue: what is on screen stays
          // valid, it just stops refreshing itself.
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

/// Workspace-wide queue. Pass a property id to get the same queue scoped to one
/// object — the object view is a filter, not a second screen.
final valuationWorkspaceControllerProvider =
    StateNotifierProvider.autoDispose.family<
      ValuationWorkspaceController,
      ValuationWorkspaceState,
      String?
    >((ref, propertyId) {
      final controller = ValuationWorkspaceController(
        repository: ref.watch(valuationCaseRepositoryProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
        invalidationSource: ref.watch(valuationQueryInvalidationSourceProvider),
        propertyFilter: propertyId,
      );
      unawaited(controller.load());
      return controller;
    });
