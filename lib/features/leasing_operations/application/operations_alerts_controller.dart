/// Screen-facing orchestration for the operations alerts list (Welle 3, AP10
/// — SCR-032), fully on the `P2-D05a` contract (Befund 1 in
/// `04c_wave3_leasing_operations.md`): the client filters and acknowledges,
/// it does not derive.
///
/// The category filter (lease / rent roll / tenant / data quality) is a
/// display grouping only, computed client-side from [OperationsSignalDto.type]
/// exactly the way the legacy screen's `_alertCategory` did — kept for
/// continuity, not because the server needs it; `P2-D05a` already treats
/// every signal type as one flat list.
///
/// `expectedVersion` for an acknowledgement is always
/// [OperationsSignalDto.statusVersion] read straight off the signal being
/// acted on: null there means no acknowledgement row exists yet (the RPC's
/// "create" path), non-null means "acknowledge exactly this version" (the
/// RPC's optimistic-concurrency path). The controller never invents one.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/operations_signal_dto.dart';
import 'leasing_providers.dart';
import 'leasing_query_invalidation_source.dart';
import 'operations_signals_contract.dart';

const Object _unchanged = Object();

enum OperationsAlertsPhase { idle, loading, ready, forbidden, error }

const String statusFilterAll = 'all';
const String severityFilterAll = 'all';
const String categoryFilterAll = 'all';

class OperationsAlertsState {
  const OperationsAlertsState({
    required this.phase,
    this.signals = const <OperationsSignalDto>[],
    this.statusFilter = 'open',
    this.severityFilter = severityFilterAll,
    this.categoryFilter = categoryFilterAll,
    this.message,
    this.actionError,
  });

  const OperationsAlertsState.loading() : this(phase: OperationsAlertsPhase.loading);

  final OperationsAlertsPhase phase;

  /// Every signal the server returned for this property, unfiltered.
  final List<OperationsSignalDto> signals;

  final String statusFilter;
  final String severityFilter;
  final String categoryFilter;
  final String? message;

  /// Set when an acknowledgement failed (e.g. a version conflict from a
  /// concurrent update) so the UI can surface it without losing the list.
  final String? actionError;

  List<OperationsSignalDto> get filtered {
    return signals.where((signal) {
      final statusMatches =
          statusFilter == statusFilterAll || signal.status == statusFilter;
      final severityMatches =
          severityFilter == severityFilterAll || signal.severity == severityFilter;
      final categoryMatches =
          categoryFilter == categoryFilterAll ||
          alertCategory(signal) == categoryFilter;
      return statusMatches && severityMatches && categoryMatches;
    }).toList(growable: false);
  }

  int get openCount => signals.where((signal) => signal.status == 'open').length;
  int get criticalCount =>
      signals.where((signal) => signal.severity == 'critical').length;
  int get warningCount =>
      signals.where((signal) => signal.severity == 'warning').length;
  int get resolvedCount =>
      signals.where((signal) => signal.status == 'resolved').length;

  OperationsAlertsState copyWith({
    OperationsAlertsPhase? phase,
    List<OperationsSignalDto>? signals,
    String? statusFilter,
    String? severityFilter,
    String? categoryFilter,
    Object? message = _unchanged,
    Object? actionError = _unchanged,
  }) {
    return OperationsAlertsState(
      phase: phase ?? this.phase,
      signals: signals ?? this.signals,
      statusFilter: statusFilter ?? this.statusFilter,
      severityFilter: severityFilter ?? this.severityFilter,
      categoryFilter: categoryFilter ?? this.categoryFilter,
      message: identical(message, _unchanged) ? this.message : message as String?,
      actionError: identical(actionError, _unchanged)
          ? this.actionError
          : actionError as String?,
    );
  }
}

/// Mirrors the legacy `_alertCategory`: a display grouping, not a server
/// concept.
String alertCategory(OperationsSignalDto signal) {
  if (signal.type.contains('lease')) {
    return 'lease';
  }
  if (signal.type.contains('rent_roll')) {
    return 'rent_roll';
  }
  if (signal.type.contains('tenant')) {
    return 'tenant';
  }
  return 'data_quality';
}

class OperationsAlertsController extends StateNotifier<OperationsAlertsState> {
  OperationsAlertsController({
    required OperationsSignalsPort signals,
    required WorkspaceSessionScope scope,
    required String propertyId,
    LeasingQueryInvalidationSource? invalidationSource,
    Duration invalidationCoalesceWindow = const Duration(milliseconds: 250),
  }) : _signals = signals,
       _scope = scope,
       _propertyId = propertyId,
       _invalidationSource = invalidationSource,
       _coalesceWindow = invalidationCoalesceWindow,
       super(const OperationsAlertsState.loading());

  final OperationsSignalsPort _signals;
  final WorkspaceSessionScope _scope;
  final String _propertyId;
  final LeasingQueryInvalidationSource? _invalidationSource;
  final Duration _coalesceWindow;

  StreamSubscription<LeasingQueryInvalidation>? _invalidationSubscription;
  Timer? _invalidationTimer;
  int _generation = 0;

  bool get canMutate => _scope.mutationsSupported;

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(phase: OperationsAlertsPhase.idle, signals: const []);
      return;
    }
    _subscribeToInvalidation(workspaceId);
    final generation = ++_generation;
    state = state.copyWith(phase: OperationsAlertsPhase.loading, message: null);

    final result = await _signals.list(
      OperationsSignalsQuery(workspaceId: workspaceId, propertyId: _propertyId),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case OperationsSignalsFailure<List<OperationsSignalDto>>(:final kind, :final message):
        state = state.copyWith(
          phase: kind == OperationsSignalsFailureKind.forbidden
              ? OperationsAlertsPhase.forbidden
              : OperationsAlertsPhase.error,
          signals: const <OperationsSignalDto>[],
          message: message,
        );
      case OperationsSignalsSuccess<List<OperationsSignalDto>>(:final value):
        state = state.copyWith(
          phase: OperationsAlertsPhase.ready,
          signals: value,
          message: null,
          actionError: null,
        );
    }
  }

  void setStatusFilter(String value) {
    state = state.copyWith(statusFilter: value);
  }

  void setSeverityFilter(String value) {
    state = state.copyWith(severityFilter: value);
  }

  void setCategoryFilter(String value) {
    state = state.copyWith(categoryFilter: value);
  }

  Future<bool> acknowledge({
    required OperationsSignalDto signal,
    required String status,
    String? resolutionNote,
  }) async {
    final workspaceId = _scope.workspaceId;
    final actorId = _scope.actorId;
    if (workspaceId == null || actorId == null) {
      return false;
    }
    final now = DateTime.now().microsecondsSinceEpoch.toString();
    final result = await _signals.updateStatus(
      UpdateOperationsSignalStatusCommand(
        context: LeasingCommandContext(
          workspaceId: workspaceId,
          actorId: actorId,
          mutationId: 'oa-mut-$now',
          correlationId: 'oa-cor-$now',
        ),
        propertyId: _propertyId,
        signalType: signal.type,
        signalKey: signal.signalKey,
        unitId: signal.unitId,
        leaseId: signal.leaseId,
        tenantPartyId: signal.tenantPartyId,
        status: status,
        resolutionNote: resolutionNote,
        expectedVersion: signal.statusVersion,
      ),
    );
    switch (result) {
      case OperationsSignalsFailure<OperationsSignalStateDto>(:final message):
        state = state.copyWith(actionError: message);
        return false;
      case OperationsSignalsSuccess<OperationsSignalStateDto>():
        await load();
        return true;
    }
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

final operationsAlertsControllerProvider = StateNotifierProvider.autoDispose
    .family<OperationsAlertsController, OperationsAlertsState, String>((
      ref,
      propertyId,
    ) {
      final controller = OperationsAlertsController(
        signals: ref.watch(operationsSignalsProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
        propertyId: propertyId,
        invalidationSource: ref.watch(leasingQueryInvalidationSourceProvider),
      );
      unawaited(controller.load());
      return controller;
    });
