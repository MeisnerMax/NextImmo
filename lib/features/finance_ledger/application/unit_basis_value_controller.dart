/// Screen-facing orchestration for the per-unit basis values
/// (`UNIT-BASIS-VALUES-01`, P-2c).
///
/// **The verdict is the server's, and it is the same one the allocation keys
/// get.** Whether this basis can be used, what it totals, how many units are
/// missing a figure and whether the units agree on a convention are read, never
/// recomputed here — a screen that derived its own verdict could tell the user
/// the basis is ready while the settlement engine refuses it.
///
/// **The date is state, not a filter.** A settlement for a past year needs
/// that year's figures, and the same property answers differently for two
/// different days. So [UnitBasisState.asOf] is carried explicitly and comes
/// back from the server rather than being assumed to be today.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/cost_pool_dto.dart';
import 'cost_pool_controller.dart' show CostPoolActionFailure;
import 'finance_ledger_port.dart';
import 'finance_providers.dart';

const Object _unchanged = Object();

enum UnitBasisPhase { idle, loading, ready, forbidden, error }

enum UnitBasisActionPhase { idle, running, failed, succeeded }

/// Which property and basis a controller answers for. A family key, because
/// the same screen opened for two bases must not share one controller.
class UnitBasisScope {
  const UnitBasisScope({required this.propertyId, required this.basis});

  final String propertyId;
  final AllocationBasis basis;

  @override
  bool operator ==(Object other) =>
      other is UnitBasisScope &&
      other.propertyId == propertyId &&
      other.basis == basis;

  @override
  int get hashCode => Object.hash(propertyId, basis);
}

class UnitBasisState {
  const UnitBasisState({
    this.phase = UnitBasisPhase.idle,
    this.actionPhase = UnitBasisActionPhase.idle,
    this.overview,
    this.asOf,
    this.message,
    this.actionMessage,
    this.actionField,
  });

  final UnitBasisPhase phase;
  final UnitBasisActionPhase actionPhase;

  /// Null until the first answer, and null again after a failure. An empty
  /// list and an unreadable one are different statements, and only the first
  /// is safe to act on.
  final UnitBasisOverviewDto? overview;

  /// The day the figures were asked for, as the server echoed it.
  final DateTime? asOf;

  final String? message;
  final String? actionMessage;
  final String? actionField;

  List<UnitBasisRowDto> get units =>
      overview?.units ?? const <UnitBasisRowDto>[];

  AllocationBasisResolutionDto? get resolution => overview?.resolution;

  /// Whether a settlement run could act on this basis today. Read from the
  /// server's verdict, never derived from the rows on screen.
  bool get isResolvable => overview?.resolution.resolvable ?? false;

  int get recordedCount => overview?.recordedCount ?? 0;
  int get missingCount => overview?.missing.length ?? 0;

  UnitBasisState copyWith({
    UnitBasisPhase? phase,
    UnitBasisActionPhase? actionPhase,
    Object? overview = _unchanged,
    Object? asOf = _unchanged,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
    Object? actionField = _unchanged,
  }) {
    return UnitBasisState(
      phase: phase ?? this.phase,
      actionPhase: actionPhase ?? this.actionPhase,
      overview: identical(overview, _unchanged)
          ? this.overview
          : overview as UnitBasisOverviewDto?,
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

class UnitBasisController extends StateNotifier<UnitBasisState> {
  UnitBasisController({
    required UnitBasisValuesPort port,
    required WorkspaceSessionScope scope,
    required this.propertyId,
    required this.basis,
    String Function()? idFactory,
  }) : _port = port,
       _scope = scope,
       _idFactory = idFactory ?? (() => const Uuid().v4()),
       super(const UnitBasisState());

  final UnitBasisValuesPort _port;
  final WorkspaceSessionScope _scope;
  final String Function() _idFactory;
  final String propertyId;
  final AllocationBasis basis;

  int _generation = 0;

  /// The server checks it too; this only decides whether an action is offered,
  /// so nobody spends a round trip on a certain refusal.
  bool get canMutate =>
      _scope.mutationsSupported && _scope.permissions.contains('finance.manage');

  Future<void> load({DateTime? asOf}) async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        phase: UnitBasisPhase.forbidden,
        overview: null,
        message: 'Kein Workspace ausgewählt.',
      );
      return;
    }
    final generation = ++_generation;
    final requestedAsOf = asOf ?? state.asOf;
    state = state.copyWith(phase: UnitBasisPhase.loading, message: null);

    final result = await _port.readBasisValues(
      workspaceId: workspaceId,
      propertyId: propertyId,
      basis: basis,
      asOf: requestedAsOf,
    );
    if (generation != _generation || !mounted) {
      return;
    }
    switch (result) {
      case FinanceRepositorySuccess<UnitBasisOverviewDto>(:final value):
        state = state.copyWith(
          phase: UnitBasisPhase.ready,
          overview: value,
          asOf: value.asOfDate,
          message: null,
        );
      case FinanceRepositoryFailure<UnitBasisOverviewDto>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          phase: kind == FinanceRepositoryFailureKind.forbidden
              ? UnitBasisPhase.forbidden
              : UnitBasisPhase.error,
          overview: null,
          message: message,
        );
    }
  }

  Future<void> showDate(DateTime asOf) => load(asOf: asOf);

  /// Returns null on success, or why the write was refused — a dialog needs it
  /// as a return value so it can stay open, keep what was typed and put the
  /// message on the field the server named.
  Future<CostPoolActionFailure?> saveValue({
    required String unitId,
    required num value,
    required String convention,
    required DateTime validFrom,
    UnitBasisValueDto? existing,
    DateTime? validTo,
    String? note,
  }) async {
    // Checked before touching state: this controller is autoDispose and its
    // provider watches the session scope, so a token refresh between opening a
    // dialog and pressing save disposes it while the dialog still holds it.
    if (!mounted) {
      return const CostPoolActionFailure(
        message: 'Die Sitzung wurde neu geladen. Bitte erneut versuchen.',
      );
    }
    if (!canMutate) {
      const CostPoolActionFailure refusal = CostPoolActionFailure(
        message:
            'Für Basiswerte fehlt die Berechtigung zur Finanzverwaltung.',
      );
      state = state.copyWith(
        actionPhase: UnitBasisActionPhase.failed,
        actionMessage: refusal.message,
        actionField: null,
      );
      return refusal;
    }

    state = state.copyWith(
      actionPhase: UnitBasisActionPhase.running,
      actionMessage: null,
      actionField: null,
    );
    final result = await _port.upsertBasisValue(
      UpsertUnitBasisValueCommand(
        context: FinanceCommandContext(
          workspaceId: _scope.workspaceId!,
          actorId: _scope.actorId!,
          mutationId: _idFactory(),
          correlationId: _idFactory(),
        ),
        valueId: existing?.id,
        // Null exactly for a create. Sending a version for a first write is
        // refused by the server, and so is omitting one for a change.
        expectedVersion: existing?.version,
        unitId: unitId,
        basis: basis,
        value: value,
        convention: convention,
        validFrom: validFrom,
        validTo: validTo,
        note: note,
      ),
    );
    if (!mounted) {
      return const CostPoolActionFailure(
        message: 'Die Sitzung wurde neu geladen. Bitte erneut versuchen.',
      );
    }
    switch (result) {
      case FinanceRepositorySuccess<UnitBasisValueDto>():
        state = state.copyWith(
          actionPhase: UnitBasisActionPhase.succeeded,
          actionMessage: 'Basiswert gespeichert.',
          actionField: null,
        );
        // Re-read rather than patching the row. One unit's figure changes the
        // verdict for the whole property -- it can complete the set, or
        // introduce a second convention that stops the set adding up.
        await load();
        return null;
      case FinanceRepositoryFailure<UnitBasisValueDto>(
        :final message,
        :final field,
      ):
        state = state.copyWith(
          actionPhase: UnitBasisActionPhase.failed,
          actionMessage: message,
          actionField: field,
        );
        // Re-read after a refusal too: a refusal means this side's picture and
        // the server's disagreed, and the next attempt is built from what is
        // on screen. Without this, a version conflict re-sends the same stale
        // version forever.
        await load();
        return CostPoolActionFailure(message: message, field: field);
    }
  }
}

final unitBasisControllerProvider = StateNotifierProvider.autoDispose
    .family<UnitBasisController, UnitBasisState, UnitBasisScope>((
      Ref ref,
      UnitBasisScope scope,
    ) {
      final controller = UnitBasisController(
        port: ref.watch(unitBasisValuesProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
        propertyId: scope.propertyId,
        basis: scope.basis,
      );
      unawaited(controller.load());
      return controller;
    });
