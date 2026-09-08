/// Screen-facing orchestration for the service-charge preview
/// (`SERVICE-CHARGE-PREVIEW-01`).
///
/// **One read, and a period the user chooses.** There is no command here, so
/// there is no action phase, no optimistic update and no version token — the
/// preview is recomputed from scratch every time the period or the property
/// changes, which is also the only way it stays honest about bookings made
/// since it was last shown.
///
/// **The default period is last month, not this one.** A settlement over a
/// month that is still open is provisional by definition, and opening the
/// screen on a figure that will change reads as a result rather than as a
/// draft. The user can still choose the current month; it will simply say it
/// is provisional.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/service_charge_preview_dto.dart';
import 'finance_ledger_port.dart';
import 'finance_providers.dart';

const Object _unchanged = Object();

enum ServiceChargePhase { idle, loading, ready, forbidden, error }

class ServiceChargeState {
  const ServiceChargeState({
    required this.from,
    required this.to,
    this.phase = ServiceChargePhase.idle,
    this.preview,
    this.propertyId,
    this.propertyName,
    this.message,
    this.messageField,
  });

  final ServiceChargePhase phase;

  /// The chosen period, always whole months. Held here rather than derived
  /// from the answer, so a refused period is still the one on screen and can
  /// be corrected instead of silently snapping back.
  final DateTime from;
  final DateTime to;

  /// Null until the first answer, and null again after a failure. An empty
  /// statement and an unreadable one are different statements.
  final ServiceChargePreviewDto? preview;

  final String? propertyId;
  final String? propertyName;
  final String? message;
  final String? messageField;

  bool get hasProperty => propertyId != null;

  List<ServiceChargeUnitDto> get units =>
      preview?.units ?? const <ServiceChargeUnitDto>[];

  List<ServiceChargeAccountDto> get accounts =>
      preview?.accounts ?? const <ServiceChargeAccountDto>[];

  ServiceChargeState copyWith({
    ServiceChargePhase? phase,
    DateTime? from,
    DateTime? to,
    Object? preview = _unchanged,
    Object? propertyId = _unchanged,
    Object? propertyName = _unchanged,
    Object? message = _unchanged,
    Object? messageField = _unchanged,
  }) {
    return ServiceChargeState(
      phase: phase ?? this.phase,
      from: from ?? this.from,
      to: to ?? this.to,
      preview: preview == _unchanged
          ? this.preview
          : preview as ServiceChargePreviewDto?,
      propertyId: propertyId == _unchanged
          ? this.propertyId
          : propertyId as String?,
      propertyName: propertyName == _unchanged
          ? this.propertyName
          : propertyName as String?,
      message: message == _unchanged ? this.message : message as String?,
      messageField: messageField == _unchanged
          ? this.messageField
          : messageField as String?,
    );
  }
}

class ServiceChargeController extends StateNotifier<ServiceChargeState> {
  ServiceChargeController({
    required ServiceChargePreviewPort port,
    required WorkspaceSessionScope scope,
    DateTime? today,
  }) : _port = port,
       _scope = scope,
       super(_initialState(today ?? DateTime.now()));

  final ServiceChargePreviewPort _port;
  final WorkspaceSessionScope _scope;

  int _generation = 0;

  /// Last whole month. See the library comment: a period that still accepts
  /// bookings gives a figure that will move, and a screen should not open on
  /// one of those by default.
  static ServiceChargeState _initialState(DateTime today) {
    final DateTime firstOfThisMonth = DateTime(today.year, today.month, 1);
    final DateTime lastMonthEnd = firstOfThisMonth.subtract(
      const Duration(days: 1),
    );
    return ServiceChargeState(
      from: DateTime(lastMonthEnd.year, lastMonthEnd.month, 1),
      to: lastMonthEnd,
    );
  }

  bool get canRead => _scope.permissions.contains('finance.read');

  Future<void> selectProperty({
    required String propertyId,
    String? propertyName,
  }) async {
    state = state.copyWith(
      propertyId: propertyId,
      propertyName: propertyName,
      preview: null,
      message: null,
      messageField: null,
    );
    await load();
  }

  /// Sets the period from two months. The end is normalised to the last day of
  /// its month here rather than at the call site: every caller would otherwise
  /// have to know about February.
  Future<void> selectPeriod({
    required DateTime fromMonth,
    required DateTime toMonth,
  }) async {
    final DateTime start = DateTime(fromMonth.year, fromMonth.month, 1);
    final DateTime end = DateTime(
      toMonth.year,
      toMonth.month + 1,
      1,
    ).subtract(const Duration(days: 1));
    state = state.copyWith(from: start, to: end);
    await load();
  }

  Future<void> load() async {
    final String? workspaceId = _scope.workspaceId;
    final String? propertyId = state.propertyId;
    if (workspaceId == null) {
      state = state.copyWith(
        phase: ServiceChargePhase.forbidden,
        preview: null,
        message: 'Kein Arbeitsbereich ausgewählt.',
      );
      return;
    }
    if (!canRead) {
      state = state.copyWith(
        phase: ServiceChargePhase.forbidden,
        preview: null,
        message:
            'Zum Lesen der Finanzdaten fehlt die Berechtigung (finance.read).',
      );
      return;
    }
    if (propertyId == null) {
      // Not an error and not a spinner: the screen is waiting for a choice,
      // and says so.
      state = state.copyWith(
        phase: ServiceChargePhase.ready,
        preview: null,
        message: null,
        messageField: null,
      );
      return;
    }

    final int generation = ++_generation;
    state = state.copyWith(
      phase: ServiceChargePhase.loading,
      message: null,
      messageField: null,
    );

    final FinanceRepositoryResult<ServiceChargePreviewDto> result = await _port
        .readPreview(
          workspaceId: workspaceId,
          propertyId: propertyId,
          from: state.from,
          to: state.to,
        );

    if (!mounted) {
      return;
    }
    // A newer load has taken over and will set the phase itself. Bailing out
    // of the *newest* load would strand the screen on its spinner, so the two
    // conditions are kept apart.
    if (generation != _generation) {
      return;
    }

    switch (result) {
      case FinanceRepositorySuccess<ServiceChargePreviewDto>(:final value):
        state = state.copyWith(
          phase: ServiceChargePhase.ready,
          preview: value,
          message: null,
          messageField: null,
        );
      case FinanceRepositoryFailure<ServiceChargePreviewDto>(
        :final kind,
        :final message,
        :final field,
      ):
        state = state.copyWith(
          phase: kind == FinanceRepositoryFailureKind.forbidden
              ? ServiceChargePhase.forbidden
              : ServiceChargePhase.error,
          // Cleared, so a refused period cannot leave the previous period's
          // figures on screen under the new period's heading.
          preview: null,
          message: message,
          messageField: field,
        );
    }
  }
}

final serviceChargeControllerProvider =
    StateNotifierProvider.autoDispose<
      ServiceChargeController,
      ServiceChargeState
    >((Ref ref) {
      final ServiceChargeController controller = ServiceChargeController(
        port: ref.watch(serviceChargePreviewProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
      );
      unawaited(controller.load());
      return controller;
    });
