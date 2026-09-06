/// Screen-facing orchestration for `Investment → Performance → Ergebnis`
/// (FINANCE-01a).
///
/// One read, one optional period range, no derivation. The controller's only
/// judgement is the one it makes before the round trip: the server needs both
/// entity-scoped `property.read` and `finance.read`, so a session holding one
/// but not the other is told which is missing rather than shown a generic
/// failure.
///
/// The period range is a *server* filter. Narrowing the range in memory would
/// report the result of the months that happen to be loaded rather than of the
/// months asked for, which is the same mistake the activity timeline avoids.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/finance_actuals_dto.dart';
import 'finance_ledger_port.dart';
import 'finance_providers.dart';

const Object _unchanged = Object();

enum PropertyFinancePhase { idle, loading, ready, empty, forbidden, error }

class PropertyFinanceState {
  const PropertyFinanceState({
    this.phase = PropertyFinancePhase.idle,
    this.actuals,
    this.range = const FinancePeriodRange.unbounded(),
    this.message,
  });

  final PropertyFinancePhase phase;

  /// Null unless [phase] is ready. A property with no bookings is [empty]
  /// rather than a zero-valued statement: nothing booked is not the same
  /// claim as everything booked to zero.
  final PropertyFinanceActualsDto? actuals;

  final FinancePeriodRange range;
  final String? message;

  bool get isBusy => phase == PropertyFinancePhase.loading;

  PropertyFinanceState copyWith({
    PropertyFinancePhase? phase,
    Object? actuals = _unchanged,
    FinancePeriodRange? range,
    Object? message = _unchanged,
  }) {
    return PropertyFinanceState(
      phase: phase ?? this.phase,
      actuals: identical(actuals, _unchanged)
          ? this.actuals
          : actuals as PropertyFinanceActualsDto?,
      range: range ?? this.range,
      message: identical(message, _unchanged) ? this.message : message as String?,
    );
  }
}

class PropertyFinanceController extends StateNotifier<PropertyFinanceState> {
  PropertyFinanceController({
    required this.propertyId,
    required PropertyFinanceActualsPort port,
    required WorkspaceSessionScope scope,
  }) : _port = port,
       _scope = scope,
       super(const PropertyFinanceState());

  static const String financeReadPermission = 'finance.read';
  static const String propertyReadPermission = 'property.read';

  final String propertyId;
  final PropertyFinanceActualsPort _port;
  final WorkspaceSessionScope _scope;

  int _generation = 0;

  bool get canRead =>
      _scope.permissions.contains(financeReadPermission) &&
      _scope.permissions.contains(propertyReadPermission);

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      // Settled, not loading: nothing was asked, so nothing is in flight.
      state = state.copyWith(
        phase: PropertyFinancePhase.idle,
        actuals: null,
        message: null,
      );
      return;
    }
    if (!canRead) {
      state = state.copyWith(
        phase: PropertyFinancePhase.forbidden,
        actuals: null,
        message: _scope.permissions.contains(financeReadPermission)
            ? 'Für diese Ansicht fehlt die Berechtigung "property.read".'
            : 'Für diese Ansicht fehlt die Berechtigung "finance.read".',
      );
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(phase: PropertyFinancePhase.loading, message: null);
    final result = await _port.read(
      workspaceId: workspaceId,
      propertyId: propertyId,
      range: state.range,
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case FinanceRepositorySuccess<PropertyFinanceActualsDto>(:final value):
        state = state.copyWith(
          phase: value.isEmpty
              ? PropertyFinancePhase.empty
              : PropertyFinancePhase.ready,
          actuals: value,
          message: null,
        );
      case FinanceRepositoryFailure<PropertyFinanceActualsDto>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          phase: kind == FinanceRepositoryFailureKind.forbidden
              ? PropertyFinancePhase.forbidden
              : PropertyFinancePhase.error,
          actuals: null,
          message: message,
        );
    }
  }

  /// Applies a server-side period filter and re-reads. The loaded statement is
  /// dropped first: showing last range's figures under this range's heading
  /// would be a lie with a plausible layout.
  Future<void> setRange(FinancePeriodRange range) async {
    state = state.copyWith(range: range, actuals: null);
    await load();
  }

  Future<void> clearRange() => setRange(const FinancePeriodRange.unbounded());
}

final propertyFinanceControllerProvider = StateNotifierProvider.autoDispose
    .family<PropertyFinanceController, PropertyFinanceState, String>((
      ref,
      propertyId,
    ) {
      final controller = PropertyFinanceController(
        propertyId: propertyId,
        port: ref.watch(propertyFinanceActualsProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
      );
      controller.load();
      return controller;
    });
