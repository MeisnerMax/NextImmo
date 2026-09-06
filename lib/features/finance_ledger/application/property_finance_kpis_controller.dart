/// Screen-facing orchestration for the computed figures (FINANCE-01b).
///
/// Its own controller beside the actuals one, because the two can legitimately
/// disagree about what to show: a workspace with a full ledger and no
/// definitions has actuals and no KPIs, and that is a setup step to explain
/// rather than an error to report. Folding both into one state would force the
/// surface to pick a single phase for two independent answers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/finance_kpi_dto.dart';
import 'finance_ledger_port.dart';
import 'finance_providers.dart';

const Object _unchanged = Object();

enum PropertyFinanceKpisPhase {
  idle,
  loading,
  ready,
  /// Definitions exist but none matched anything booked.
  noMatch,
  /// No definition is active in this workspace at all.
  undefined,
  forbidden,
  error,
}

class PropertyFinanceKpisState {
  const PropertyFinanceKpisState({
    this.phase = PropertyFinanceKpisPhase.idle,
    this.kpis,
    this.range = const FinancePeriodRange.unbounded(),
    this.message,
  });

  final PropertyFinanceKpisPhase phase;

  /// Present for [ready], [noMatch] and [undefined] alike: the last two still
  /// carry the freshness and coverage the surface needs to explain itself.
  final PropertyFinanceKpisDto? kpis;

  final FinancePeriodRange range;
  final String? message;

  PropertyFinanceKpisState copyWith({
    PropertyFinanceKpisPhase? phase,
    Object? kpis = _unchanged,
    FinancePeriodRange? range,
    Object? message = _unchanged,
  }) {
    return PropertyFinanceKpisState(
      phase: phase ?? this.phase,
      kpis: identical(kpis, _unchanged)
          ? this.kpis
          : kpis as PropertyFinanceKpisDto?,
      range: range ?? this.range,
      message: identical(message, _unchanged) ? this.message : message as String?,
    );
  }
}

class PropertyFinanceKpisController
    extends StateNotifier<PropertyFinanceKpisState> {
  PropertyFinanceKpisController({
    required this.propertyId,
    required PropertyFinanceKpisPort port,
    required WorkspaceSessionScope scope,
  }) : _port = port,
       _scope = scope,
       super(const PropertyFinanceKpisState());

  static const String financeReadPermission = 'finance.read';
  static const String propertyReadPermission = 'property.read';

  final String propertyId;
  final PropertyFinanceKpisPort _port;
  final WorkspaceSessionScope _scope;

  int _generation = 0;

  bool get canRead =>
      _scope.permissions.contains(financeReadPermission) &&
      _scope.permissions.contains(propertyReadPermission);

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        phase: PropertyFinanceKpisPhase.idle,
        kpis: null,
        message: null,
      );
      return;
    }
    if (!canRead) {
      state = state.copyWith(
        phase: PropertyFinanceKpisPhase.forbidden,
        kpis: null,
        message: _scope.permissions.contains(financeReadPermission)
            ? 'Für diese Ansicht fehlt die Berechtigung "property.read".'
            : 'Für diese Ansicht fehlt die Berechtigung "finance.read".',
      );
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(
      phase: PropertyFinanceKpisPhase.loading,
      message: null,
    );
    final result = await _port.read(
      workspaceId: workspaceId,
      propertyId: propertyId,
      range: state.range,
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case FinanceRepositorySuccess<PropertyFinanceKpisDto>(:final value):
        state = state.copyWith(
          // The three empty answers are not the same answer. Nothing defined
          // is a setup step; defined-but-unmatched is a data observation; and
          // values present is neither.
          phase: value.values.isNotEmpty
              ? PropertyFinanceKpisPhase.ready
              : (value.hasDefinitions
                    ? PropertyFinanceKpisPhase.noMatch
                    : PropertyFinanceKpisPhase.undefined),
          kpis: value,
          message: null,
        );
      case FinanceRepositoryFailure<PropertyFinanceKpisDto>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          phase: kind == FinanceRepositoryFailureKind.forbidden
              ? PropertyFinanceKpisPhase.forbidden
              : PropertyFinanceKpisPhase.error,
          kpis: null,
          message: message,
        );
    }
  }

  Future<void> setRange(FinancePeriodRange range) async {
    state = state.copyWith(range: range, kpis: null);
    await load();
  }
}

final propertyFinanceKpisControllerProvider = StateNotifierProvider.autoDispose
    .family<
      PropertyFinanceKpisController,
      PropertyFinanceKpisState,
      String
    >((ref, propertyId) {
      final controller = PropertyFinanceKpisController(
        propertyId: propertyId,
        port: ref.watch(propertyFinanceKpisProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
      );
      controller.load();
      return controller;
    });
