/// The whole workspace's operations signals, as one worklist
/// (`ALERT-READER-01`, P-10).
///
/// The sibling [OperationsAlertsController] answers "what is wrong with this
/// building". This one answers "what should I do today", which is a different
/// question and cannot be assembled from the other: forty properties would be
/// forty round trips, and the ordering between them would be invented here.
///
/// **The filters are the server's, not this controller's.** The property-scoped
/// controller filters client-side over a list it already holds in full — which
/// is correct there, because a property's signals are a page. Here the list is
/// capped, so filtering after the cap would search only what fitted and report
/// "no criticals" while criticals were cut off. Every filter therefore
/// re-queries.
///
/// The category grouping the property screen offers is deliberately absent. It
/// is a client-side display grouping derived from the signal type, and applying
/// it to a capped list has the same defect: it would group what came back
/// rather than what exists.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/operations_signal_dto.dart';
import 'leasing_providers.dart';
import 'operations_signals_contract.dart';

enum WorkspaceAlertsPhase { idle, loading, ready, forbidden, error }

/// The value that means "no filter". Not null: a null in a dropdown is
/// indistinguishable from an unset one, and the server treats null as "all".
const String workspaceAlertSeverityAll = 'all';
const String workspaceAlertStatusAll = 'all';

class WorkspaceAlertsState {
  const WorkspaceAlertsState({
    this.phase = WorkspaceAlertsPhase.idle,
    this.result,
    this.severityFilter = workspaceAlertSeverityAll,
    this.statusFilter = 'open',
    this.message,
  });

  final WorkspaceAlertsPhase phase;

  /// Null until the first answer lands, and null again after a failure --
  /// never an empty list standing in for one. An empty worklist and an
  /// unreadable one look identical otherwise, and the first is good news.
  final WorkspaceOperationsSignalsDto? result;

  final String severityFilter;

  /// Defaults to `open`: a worklist is what has not been dealt with.
  /// Dismissed and resolved signals stay reachable through the filter, because
  /// "what did we decide about this" is a real question.
  final String statusFilter;

  final String? message;

  List<OperationsSignalDto> get signals =>
      result?.signals ?? const <OperationsSignalDto>[];

  /// What matched, which is not what came back. Reported by the server before
  /// it capped.
  int get total => result?.total ?? 0;
  bool get truncated => result?.truncated ?? false;
  int get criticalCount => result?.criticalCount ?? 0;
  int get warningCount => result?.warningCount ?? 0;
  int get infoCount => result?.infoCount ?? 0;
  DateTime? get computedAt => result?.computedAt;

  WorkspaceAlertsState copyWith({
    WorkspaceAlertsPhase? phase,
    Object? result = _unchanged,
    String? severityFilter,
    String? statusFilter,
    Object? message = _unchanged,
  }) {
    return WorkspaceAlertsState(
      phase: phase ?? this.phase,
      result: identical(result, _unchanged)
          ? this.result
          : result as WorkspaceOperationsSignalsDto?,
      severityFilter: severityFilter ?? this.severityFilter,
      statusFilter: statusFilter ?? this.statusFilter,
      message: identical(message, _unchanged) ? this.message : message as String?,
    );
  }
}

const Object _unchanged = Object();

class WorkspaceAlertsController extends StateNotifier<WorkspaceAlertsState> {
  WorkspaceAlertsController({
    required OperationsSignalsPort signals,
    required WorkspaceSessionScope scope,
  }) : _signals = signals,
       _scope = scope,
       super(const WorkspaceAlertsState());

  final OperationsSignalsPort _signals;
  final WorkspaceSessionScope _scope;

  /// Guards against an older answer overwriting a newer one when the reader
  /// changes a filter twice in quick succession.
  int _generation = 0;

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        phase: WorkspaceAlertsPhase.forbidden,
        result: null,
        message: 'Kein Workspace ausgewählt.',
      );
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(
      phase: WorkspaceAlertsPhase.loading,
      message: null,
    );
    final result = await _signals.listWorkspace(
      WorkspaceOperationsSignalsQuery(
        workspaceId: workspaceId,
        severity: state.severityFilter == workspaceAlertSeverityAll
            ? null
            : state.severityFilter,
        status: state.statusFilter == workspaceAlertStatusAll
            ? null
            : state.statusFilter,
      ),
    );
    if (generation != _generation || !mounted) {
      return;
    }
    switch (result) {
      case OperationsSignalsSuccess<WorkspaceOperationsSignalsDto>(:final value):
        state = state.copyWith(
          phase: WorkspaceAlertsPhase.ready,
          result: value,
          message: null,
        );
      case OperationsSignalsFailure<WorkspaceOperationsSignalsDto>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          phase: kind == OperationsSignalsFailureKind.forbidden
              ? WorkspaceAlertsPhase.forbidden
              : WorkspaceAlertsPhase.error,
          // Dropped rather than kept: a stale worklist beside an error message
          // invites acting on numbers that are no longer being maintained.
          result: null,
          message: message,
        );
    }
  }

  Future<void> setSeverityFilter(String severity) async {
    if (severity == state.severityFilter) {
      return;
    }
    state = state.copyWith(severityFilter: severity);
    // Server-side, because the list is capped: filtering the returned page
    // would search only what fitted and could report "no criticals" while
    // criticals were cut off.
    await load();
  }

  Future<void> setStatusFilter(String status) async {
    if (status == state.statusFilter) {
      return;
    }
    state = state.copyWith(statusFilter: status);
    await load();
  }
}

final workspaceAlertsControllerProvider = StateNotifierProvider.autoDispose<
  WorkspaceAlertsController,
  WorkspaceAlertsState
>((Ref ref) {
  final controller = WorkspaceAlertsController(
    signals: ref.watch(operationsSignalsProvider),
    scope: ref.watch(workspaceSessionScopeProvider),
  );
  unawaited(controller.load());
  return controller;
});
