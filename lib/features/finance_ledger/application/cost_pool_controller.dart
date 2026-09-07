/// Screen-facing orchestration for cost pools and allocation keys
/// (`COST-POOLS-ALLOCATION-KEYS-01`, P-2b).
///
/// The two numbers that matter — how many keys resolve on the chosen date and
/// how many do not — come from the server over every matching key. This
/// controller never counts its own list: a list-local count would answer "how
/// much of this page resolves", and the question a settlement run asks is
/// about the property.
///
/// **The date is state, not a filter.** A key is in force on a day or it is
/// not, and the same property answers differently for two different days. So
/// [CostPoolState.asOf] is carried explicitly and every reload states which
/// day it asked about, rather than quietly meaning "today" and going stale
/// across a midnight.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/cost_pool_dto.dart';
import 'finance_ledger_port.dart';
import 'finance_providers.dart';

const Object _unchanged = Object();

enum CostPoolPhase { idle, loading, ready, forbidden, error }

enum CostPoolActionPhase { idle, running, failed, succeeded }

/// Why a write was refused, handed back to whoever asked for it.
///
/// The state carries the same thing for the page-level notice, but a dialog
/// needs it as a *return value*: it has to stay open, keep what the user
/// typed, and put the message on the field the server named. A dialog that
/// pops first and reports afterwards has already thrown the input away.
class CostPoolActionFailure {
  const CostPoolActionFailure({required this.message, this.field});

  final String message;

  /// The contract field the server rejected, e.g. `poolKey` or `explanation`.
  final String? field;
}

class CostPoolState {
  const CostPoolState({
    this.phase = CostPoolPhase.idle,
    this.actionPhase = CostPoolActionPhase.idle,
    this.pools,
    this.keys,
    this.propertyId,
    this.asOf,
    this.message,
    this.actionMessage,
    this.actionField,
  });

  final CostPoolPhase phase;
  final CostPoolActionPhase actionPhase;

  /// Null until the first answer, and null again after a failure. An empty
  /// list and an unreadable one are different statements, and only the first
  /// is safe to act on.
  final CostPoolOverviewDto? pools;
  final AllocationKeyOverviewDto? keys;

  /// Null means the whole workspace. The pool list spans it; the key list is
  /// usually read one property at a time, because that is the grain a key has.
  final String? propertyId;

  /// The day the keys were asked for. Null until the server has echoed one —
  /// the surface states the server's date rather than the device's.
  final DateTime? asOf;

  final String? message;
  final String? actionMessage;

  /// The contract field the server rejected, so a form can point at it.
  final String? actionField;

  List<CostPoolDto> get poolList => pools?.pools ?? const <CostPoolDto>[];
  List<AllocationKeyDto> get keyList =>
      keys?.keys ?? const <AllocationKeyDto>[];

  int get resolvableCount => keys?.resolvableCount ?? 0;
  int get unresolvableCount => keys?.unresolvableCount ?? 0;
  int get totalKeyCount => keys?.totalCount ?? 0;

  /// Keys a settlement run could not act on. Filtered from what the server
  /// sent, not counted here — [unresolvableCount] is the authoritative figure
  /// and this is the subset on screen.
  List<AllocationKeyDto> get unresolvableKeys => keyList
      .where((AllocationKeyDto key) => !key.isUsableForSettlement)
      .toList(growable: false);

  /// Pools at a scope this schema has no entity for. They hold costs somebody
  /// assigns by hand and cannot be distributed automatically, which is a
  /// standing statement about the model rather than a data problem.
  List<CostPoolDto> get unresolvablePools => poolList
      .where((CostPoolDto pool) => !pool.scopeResolvable)
      .toList(growable: false);

  CostPoolState copyWith({
    CostPoolPhase? phase,
    CostPoolActionPhase? actionPhase,
    Object? pools = _unchanged,
    Object? keys = _unchanged,
    Object? propertyId = _unchanged,
    Object? asOf = _unchanged,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
    Object? actionField = _unchanged,
  }) {
    return CostPoolState(
      phase: phase ?? this.phase,
      actionPhase: actionPhase ?? this.actionPhase,
      pools: identical(pools, _unchanged)
          ? this.pools
          : pools as CostPoolOverviewDto?,
      keys: identical(keys, _unchanged)
          ? this.keys
          : keys as AllocationKeyOverviewDto?,
      propertyId: identical(propertyId, _unchanged)
          ? this.propertyId
          : propertyId as String?,
      asOf: identical(asOf, _unchanged) ? this.asOf : asOf as DateTime?,
      message: identical(message, _unchanged)
          ? this.message
          : message as String?,
      actionMessage: identical(actionMessage, _unchanged)
          ? this.actionMessage
          : actionMessage as String?,
      actionField: identical(actionField, _unchanged)
          ? this.actionField
          : actionField as String?,
    );
  }
}

class CostPoolController extends StateNotifier<CostPoolState> {
  CostPoolController({
    required CostPoolsPort port,
    required WorkspaceSessionScope scope,
    String? propertyId,
    String Function()? idFactory,
  }) : _port = port,
       _scope = scope,
       _idFactory = idFactory ?? (() => const Uuid().v4()),
       super(CostPoolState(propertyId: propertyId));

  final CostPoolsPort _port;
  final WorkspaceSessionScope _scope;
  final String Function() _idFactory;

  int _generation = 0;

  /// The server checks it too; this only decides whether an action is offered,
  /// so nobody spends a round trip on a certain refusal.
  bool get canMutate =>
      _scope.mutationsSupported && _scope.permissions.contains('finance.manage');

  Future<void> load({DateTime? asOf}) async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        phase: CostPoolPhase.forbidden,
        pools: null,
        keys: null,
        message: 'Kein Workspace ausgewählt.',
      );
      return;
    }
    final generation = ++_generation;
    // The requested date is remembered, but the date shown comes back from the
    // server: passing none means "today" and only the server may decide which
    // day that is.
    final requestedAsOf = asOf ?? state.asOf;
    state = state.copyWith(phase: CostPoolPhase.loading, message: null);

    final poolResult = await _port.readPools(
      workspaceId: workspaceId,
      propertyId: state.propertyId,
      // Inactive pools are listed here, always. `is_active` means "do not
      // offer this for new keys", not "hide it" -- and hiding it would strand
      // it: it still holds its pool key under a unique index, so recreating it
      // comes back as a conflict pointing at a row nobody can see.
      includeInactive: true,
    );
    if (generation != _generation || !mounted) {
      return;
    }
    if (poolResult case FinanceRepositoryFailure<CostPoolOverviewDto>(
      :final kind,
      :final message,
    )) {
      state = state.copyWith(
        phase: kind == FinanceRepositoryFailureKind.forbidden
            ? CostPoolPhase.forbidden
            : CostPoolPhase.error,
        pools: null,
        keys: null,
        message: message,
      );
      return;
    }

    final keyResult = await _port.readAllocationKeys(
      workspaceId: workspaceId,
      asOf: requestedAsOf,
      propertyId: state.propertyId,
    );
    if (generation != _generation || !mounted) {
      return;
    }
    switch (keyResult) {
      case FinanceRepositorySuccess<AllocationKeyOverviewDto>(:final value):
        state = state.copyWith(
          phase: CostPoolPhase.ready,
          pools:
              (poolResult as FinanceRepositorySuccess<CostPoolOverviewDto>)
                  .value,
          keys: value,
          asOf: value.asOfDate,
          message: null,
        );
      case FinanceRepositoryFailure<AllocationKeyOverviewDto>(
        :final kind,
        :final message,
      ):
        // The pools loaded and the keys did not. Both are dropped rather than
        // showing pools beside an empty key list, which would read as "no keys
        // are in force" -- the one conclusion this failure does not support.
        state = state.copyWith(
          phase: kind == FinanceRepositoryFailureKind.forbidden
              ? CostPoolPhase.forbidden
              : CostPoolPhase.error,
          pools: null,
          keys: null,
          message: message,
        );
    }
  }

  /// Re-reads for another day. The pools do not depend on the date; they are
  /// re-read anyway because a stale pool list beside fresh keys is a list two
  /// requests apart, and nothing on screen would say so.
  Future<void> showDate(DateTime asOf) => load(asOf: asOf);

  Future<CostPoolActionFailure?> savePool({
    required String poolKey,
    required String name,
    required CostPoolScope scope,
    CostPoolDto? existing,
    String? propertyId,
    String? unitId,
    String? scopeLabel,
    String? note,
    bool isActive = true,
  }) async {
    final CostPoolActionFailure? refusal = _guardMutation('Kostenpools');
    if (refusal != null) {
      return refusal;
    }
    state = state.copyWith(
      actionPhase: CostPoolActionPhase.running,
      actionMessage: null,
      actionField: null,
    );
    final result = await _port.upsertPool(
      UpsertCostPoolCommand(
        context: _context(),
        poolId: existing?.id,
        // Null exactly for a create. Sending a version for a first write is
        // refused by the server, and so is omitting one for a change -- the
        // two states are not interchangeable.
        expectedVersion: existing?.version,
        poolKey: poolKey,
        name: name,
        scope: scope,
        propertyId: propertyId,
        unitId: unitId,
        scopeLabel: scopeLabel,
        note: note,
        isActive: isActive,
      ),
    );
    return _settle<CostPoolDto>(result, 'Kostenpool gespeichert.');
  }

  Future<CostPoolActionFailure?> saveKey({
    required String propertyId,
    required AllocationBasis basis,
    required String explanation,
    required DateTime validFrom,
    AllocationKeyDto? existing,
    String? financeAccountId,
    String? costPoolId,
    DateTime? validTo,
    String? note,
  }) async {
    final CostPoolActionFailure? refusal =
        _guardMutation('Umlageschlüssel');
    if (refusal != null) {
      return refusal;
    }
    state = state.copyWith(
      actionPhase: CostPoolActionPhase.running,
      actionMessage: null,
      actionField: null,
    );
    final result = await _port.upsertAllocationKey(
      UpsertAllocationKeyCommand(
        context: _context(),
        keyId: existing?.id,
        expectedVersion: existing?.version,
        propertyId: propertyId,
        financeAccountId: financeAccountId,
        costPoolId: costPoolId,
        basis: basis,
        explanation: explanation,
        validFrom: validFrom,
        validTo: validTo,
        note: note,
      ),
    );
    return _settle<AllocationKeyDto>(
      result,
      'Umlageschlüssel gespeichert.',
    );
  }

  CostPoolActionFailure? _guardMutation(String subject) {
    // Checked before touching state: this controller is autoDispose and its
    // provider watches the session scope, so a token refresh between opening a
    // dialog and pressing save disposes it while the dialog still holds it.
    if (!mounted) {
      return const CostPoolActionFailure(
        message: 'Die Sitzung wurde neu geladen. Bitte erneut versuchen.',
      );
    }
    if (canMutate) {
      return null;
    }
    final CostPoolActionFailure refusal = CostPoolActionFailure(
      message: 'Für $subject fehlt die Berechtigung zur Finanzverwaltung.',
    );
    state = state.copyWith(
      actionPhase: CostPoolActionPhase.failed,
      actionMessage: refusal.message,
      actionField: null,
    );
    return refusal;
  }

  FinanceCommandContext _context() => FinanceCommandContext(
    workspaceId: _scope.workspaceId!,
    actorId: _scope.actorId!,
    mutationId: _idFactory(),
    correlationId: _idFactory(),
  );

  Future<CostPoolActionFailure?> _settle<T>(
    FinanceRepositoryResult<T> result,
    String successMessage,
  ) async {
    if (!mounted) {
      return const CostPoolActionFailure(
        message: 'Die Sitzung wurde neu geladen. Bitte erneut versuchen.',
      );
    }
    switch (result) {
      case FinanceRepositorySuccess<T>():
        state = state.copyWith(
          actionPhase: CostPoolActionPhase.succeeded,
          actionMessage: successMessage,
          actionField: null,
        );
        // Re-read rather than patching the list. The resolution of a key and
        // the resolvable counts are the server's, and a write can change what
        // a neighbouring key resolves to -- adding a unit-scoped pool, for
        // instance, changes nothing, but ending one key's validity changes
        // which key answers for a day.
        await load();
        return null;
      case FinanceRepositoryFailure<T>(:final message, :final field):
        state = state.copyWith(
          actionPhase: CostPoolActionPhase.failed,
          actionMessage: message,
          actionField: field,
        );
        // Re-read after a refusal too. A server-side refusal here means this
        // side's picture and the server's disagreed -- a stale version, a
        // period another key has since taken, a pool that is gone -- and the
        // next attempt is built from what is on screen. Without this, a
        // version conflict re-sends the same stale version forever.
        await load();
        return CostPoolActionFailure(message: message, field: field);
    }
  }
}

/// Keyed by property so a property screen and the workspace-wide view do not
/// share one controller. Null is the workspace-wide reading.
final costPoolControllerProvider = StateNotifierProvider.autoDispose
    .family<CostPoolController, CostPoolState, String?>((
      Ref ref,
      String? propertyId,
    ) {
      final controller = CostPoolController(
        port: ref.watch(costPoolsProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
        propertyId: propertyId,
      );
      unawaited(controller.load());
      return controller;
    });
