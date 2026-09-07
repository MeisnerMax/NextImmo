/// Screen-facing orchestration for the cost allocation rules
/// (`COST-ALLOCATION-RULES-01`, P-2a).
///
/// The number that matters is `unclassifiedCount`, and it comes from the
/// server over every account in the workspace. This controller never counts
/// its own list: a page-local count would answer "how much of this page is
/// unclassified", and the question is about the workspace.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/cost_allocation_dto.dart';
import 'finance_ledger_port.dart';
import 'finance_providers.dart';

const Object _unchanged = Object();

enum CostAllocationPhase { idle, loading, ready, forbidden, error }

enum CostAllocationActionPhase { idle, running, failed, succeeded }

class CostAllocationState {
  const CostAllocationState({
    this.phase = CostAllocationPhase.idle,
    this.actionPhase = CostAllocationActionPhase.idle,
    this.overview,
    this.message,
    this.actionMessage,
    this.actionField,
  });

  final CostAllocationPhase phase;
  final CostAllocationActionPhase actionPhase;

  /// Null until the first answer, and null again after a failure. An empty
  /// account list and an unreadable one are different statements, and only
  /// the first is safe to act on.
  final CostAllocationOverviewDto? overview;

  final String? message;
  final String? actionMessage;

  /// The contract field the server rejected, so a form can point at it.
  final String? actionField;

  List<CostAccountAllocationDto> get accounts =>
      overview?.accounts ?? const <CostAccountAllocationDto>[];

  int get unclassifiedCount => overview?.unclassifiedCount ?? 0;
  int get classifiedCount => overview?.classifiedCount ?? 0;
  int get totalCount => overview?.totalCount ?? 0;

  /// Accounts nobody has classified. Filtered from what the server sent, not
  /// counted separately — [unclassifiedCount] is the workspace-wide figure and
  /// this is the subset on screen.
  List<CostAccountAllocationDto> get unclassified => accounts
      .where((CostAccountAllocationDto account) => !account.isClassified)
      .toList(growable: false);

  CostAllocationState copyWith({
    CostAllocationPhase? phase,
    CostAllocationActionPhase? actionPhase,
    Object? overview = _unchanged,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
    Object? actionField = _unchanged,
  }) {
    return CostAllocationState(
      phase: phase ?? this.phase,
      actionPhase: actionPhase ?? this.actionPhase,
      overview: identical(overview, _unchanged)
          ? this.overview
          : overview as CostAllocationOverviewDto?,
      message: identical(message, _unchanged) ? this.message : message as String?,
      actionMessage: identical(actionMessage, _unchanged)
          ? this.actionMessage
          : actionMessage as String?,
      actionField: identical(actionField, _unchanged)
          ? this.actionField
          : actionField as String?,
    );
  }
}

class CostAllocationController extends StateNotifier<CostAllocationState> {
  CostAllocationController({
    required CostAllocationRulesPort port,
    required WorkspaceSessionScope scope,
    String Function()? idFactory,
  }) : _port = port,
       _scope = scope,
       _idFactory = idFactory ?? (() => const Uuid().v4()),
       super(const CostAllocationState());

  final CostAllocationRulesPort _port;
  final WorkspaceSessionScope _scope;
  final String Function() _idFactory;

  int _generation = 0;

  /// The server checks it too; this only decides whether an action is offered,
  /// so nobody spends a round trip on a certain refusal.
  bool get canMutate =>
      _scope.mutationsSupported && _scope.permissions.contains('finance.manage');

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        phase: CostAllocationPhase.forbidden,
        overview: null,
        message: 'Kein Workspace ausgewählt.',
      );
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(phase: CostAllocationPhase.loading, message: null);
    final result = await _port.readRules(workspaceId: workspaceId);
    if (generation != _generation || !mounted) {
      return;
    }
    switch (result) {
      case FinanceRepositorySuccess<CostAllocationOverviewDto>(:final value):
        state = state.copyWith(
          phase: CostAllocationPhase.ready,
          overview: value,
          message: null,
        );
      case FinanceRepositoryFailure<CostAllocationOverviewDto>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          phase: kind == FinanceRepositoryFailureKind.forbidden
              ? CostAllocationPhase.forbidden
              : CostAllocationPhase.error,
          overview: null,
          message: message,
        );
    }
  }

  Future<void> setRule({
    required CostAccountAllocationDto account,
    required bool allocatable,
    CostSettlementPrinciple? settlementPrinciple,
    String? betrkvPosition,
    bool underHeatingCostRegulation = false,
    String? note,
  }) async {
    if (!canMutate) {
      state = state.copyWith(
        actionPhase: CostAllocationActionPhase.failed,
        actionMessage:
            'Für die Umlagefähigkeit fehlt die Berechtigung zur '
            'Finanzverwaltung.',
        actionField: null,
      );
      return;
    }
    state = state.copyWith(
      actionPhase: CostAllocationActionPhase.running,
      actionMessage: null,
      actionField: null,
    );
    final result = await _port.setRule(
      SetCostAllocationRuleCommand(
        context: FinanceCommandContext(
          workspaceId: _scope.workspaceId!,
          actorId: _scope.actorId!,
          mutationId: _idFactory(),
          correlationId: _idFactory(),
        ),
        financeAccountId: account.financeAccountId,
        // Null exactly when the account has no rule yet. Sending a version for
        // a first write is refused by the server, and so is omitting one for a
        // change -- the two states are not interchangeable.
        expectedVersion: account.rule?.version,
        allocatable: allocatable,
        settlementPrinciple: settlementPrinciple,
        betrkvPosition: betrkvPosition,
        underHeatingCostRegulation: underHeatingCostRegulation,
        note: note,
      ),
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case FinanceRepositorySuccess<CostAllocationRuleDto>():
        state = state.copyWith(
          actionPhase: CostAllocationActionPhase.succeeded,
          actionMessage: 'Umlagefähigkeit gespeichert.',
          actionField: null,
        );
        // Re-read rather than patching: the unclassified count is the server's
        // and this write may have changed it.
        await load();
      case FinanceRepositoryFailure<CostAllocationRuleDto>(
        :final message,
        :final field,
      ):
        state = state.copyWith(
          actionPhase: CostAllocationActionPhase.failed,
          actionMessage: message,
          actionField: field,
        );
    }
  }
}

final costAllocationControllerProvider = StateNotifierProvider.autoDispose<
  CostAllocationController,
  CostAllocationState
>((Ref ref) {
  final controller = CostAllocationController(
    port: ref.watch(costAllocationRulesProvider),
    scope: ref.watch(workspaceSessionScopeProvider),
  );
  unawaited(controller.load());
  return controller;
});
