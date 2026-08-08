/// Screen-facing orchestration for the operations overview (Welle 3, AP9 —
/// SCR-022), fully on cloud contracts per Befund 3 in
/// `04c_wave3_leasing_operations.md`: no mixed operation, no "not yet
/// available" tiles.
///
/// Four reads combine here, and each answers a different question:
///
///   * `RentRollPort.readLive` (P2-D05b) — the canonical occupancy and rent
///     numbers. Reused rather than recomputed, the same principle AP7 already
///     applied to the portfolio view: one place decides what counts.
///   * `UnitSearchPort` — area. `RentRollLiveDto` carries no area figure, so
///     this is the one number this screen still sums itself.
///   * `LeaseSearchPort` (effective only) — the expiry windows. Each count is
///     cumulative ("expires within N days"), matching the legacy engine's
///     `_countExpiring` exactly, so a 30-day figure is a subset of the 90-day
///     one, not a separate bucket.
///   * `OperationsSignalsPort` (P2-D05a) — every open/acknowledged signal.
///     Alerts and data-quality issues are **one list** here, not two: Befund 3
///     folded them because `P2-D05a` already folds them server-side, the same
///     way the legacy engine's `_buildQualityAlerts` always did.
///
/// **A legacy figure that structurally cannot exist anymore:** the old bundle
/// tracked `occupiedAreaSqft` and `leasedAreaSqft` as two numbers, because the
/// legacy schema allowed a unit to be "occupied" without an effective lease.
/// AGG-004 makes that state unreachable (occupied ⟺ has at least one effective
/// lease), so the two figures are identical by construction now — this screen
/// reports one, `leasedAreaSqm`, and does not invent a second.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/lease_dto.dart';
import '../domain/operations_signal_dto.dart';
import '../domain/rent_roll_dto.dart';
import '../domain/unit_dto.dart';
import 'leasing_providers.dart';
import 'leasing_query_invalidation_source.dart';
import 'leasing_repository.dart';
import 'operations_signals_contract.dart';

const Object _unchanged = Object();

enum OperationsOverviewPhase { idle, loading, ready, forbidden, error }

class OperationsOverviewSummary {
  const OperationsOverviewSummary({
    required this.rentRoll,
    required this.leasedAreaSqm,
    required this.expiringIn30Days,
    required this.expiringIn60Days,
    required this.expiringIn90Days,
    required this.expiringIn180Days,
    required this.alerts,
    this.truncated = false,
  });

  final RentRollLiveDto rentRoll;
  final double leasedAreaSqm;
  final int expiringIn30Days;
  final int expiringIn60Days;
  final int expiringIn90Days;
  final int expiringIn180Days;

  /// Every computed signal, severity-sorted (the RPC's own order). Alerts and
  /// data-quality issues in one list — see the library header.
  final List<OperationsSignalDto> alerts;

  /// True when the bounded unit/lease read hit `maxPages` — the area and
  /// expiry figures then describe only part of the property. Never hidden.
  final bool truncated;

  int get openAlertCount =>
      alerts.where((signal) => signal.status == 'open').length;
  int get criticalAlertCount =>
      alerts.where((signal) => signal.severity == 'critical').length;
  int get warningAlertCount =>
      alerts.where((signal) => signal.severity == 'warning').length;
}

class OperationsOverviewState {
  const OperationsOverviewState({
    required this.phase,
    this.summary,
    this.message,
  });

  const OperationsOverviewState.loading()
    : this(phase: OperationsOverviewPhase.loading);

  final OperationsOverviewPhase phase;
  final OperationsOverviewSummary? summary;
  final String? message;

  OperationsOverviewState copyWith({
    OperationsOverviewPhase? phase,
    Object? summary = _unchanged,
    Object? message = _unchanged,
  }) {
    return OperationsOverviewState(
      phase: phase ?? this.phase,
      summary: identical(summary, _unchanged)
          ? this.summary
          : summary as OperationsOverviewSummary?,
      message: identical(message, _unchanged) ? this.message : message as String?,
    );
  }
}

typedef OperationsOverviewClock = DateTime Function();

class OperationsOverviewController
    extends StateNotifier<OperationsOverviewState> {
  OperationsOverviewController({
    required RentRollPort rentRoll,
    required UnitSearchPort unitSearch,
    required LeaseSearchPort leaseSearch,
    required OperationsSignalsPort signals,
    required WorkspaceSessionScope scope,
    required String propertyId,
    LeasingQueryInvalidationSource? invalidationSource,
    OperationsOverviewClock? clock,
    Duration invalidationCoalesceWindow = const Duration(milliseconds: 250),
  }) : _rentRoll = rentRoll,
       _unitSearch = unitSearch,
       _leaseSearch = leaseSearch,
       _signals = signals,
       _scope = scope,
       _propertyId = propertyId,
       _invalidationSource = invalidationSource,
       _clock = clock ?? DateTime.now,
       _coalesceWindow = invalidationCoalesceWindow,
       super(const OperationsOverviewState.loading());

  static const int pageSize = 100;

  /// A property's units/leases are bounded in practice; this many pages is
  /// generous. Hitting it does not silently show a smaller property — the
  /// bounded read helpers below simply stop, same shape as the workspace-wide
  /// portfolio view, just with a much smaller bound because the scope here is
  /// one property, not the whole workspace.
  static const int maxPages = 3;

  final RentRollPort _rentRoll;
  final UnitSearchPort _unitSearch;
  final LeaseSearchPort _leaseSearch;
  final OperationsSignalsPort _signals;
  final WorkspaceSessionScope _scope;
  final String _propertyId;
  final LeasingQueryInvalidationSource? _invalidationSource;
  final OperationsOverviewClock _clock;
  final Duration _coalesceWindow;

  StreamSubscription<LeasingQueryInvalidation>? _invalidationSubscription;
  Timer? _invalidationTimer;
  int _generation = 0;

  DateTime get asOfDate {
    final now = _clock();
    return DateTime.utc(now.year, now.month, now.day);
  }

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(phase: OperationsOverviewPhase.idle, summary: null);
      return;
    }
    _subscribeToInvalidation(workspaceId);
    final generation = ++_generation;
    state = state.copyWith(phase: OperationsOverviewPhase.loading, message: null);

    final liveResult = await _rentRoll.readLive(
      workspaceId: workspaceId,
      propertyId: _propertyId,
      asOfDate: asOfDate,
    );
    if (generation != _generation) {
      return;
    }
    if (liveResult is LeasingRepositoryFailure<RentRollLiveDto>) {
      state = state.copyWith(
        phase: liveResult.kind == LeasingRepositoryFailureKind.forbidden
            ? OperationsOverviewPhase.forbidden
            : OperationsOverviewPhase.error,
        summary: null,
        message: liveResult.message,
      );
      return;
    }
    final live = (liveResult as LeasingRepositorySuccess<RentRollLiveDto>).value;

    final unitPage = await _readAllUnits(workspaceId);
    if (generation != _generation) {
      return;
    }
    if (unitPage.failure != null) {
      state = state.copyWith(
        phase: unitPage.failure == LeasingRepositoryFailureKind.forbidden
            ? OperationsOverviewPhase.forbidden
            : OperationsOverviewPhase.error,
        summary: null,
        message: unitPage.message,
      );
      return;
    }
    final units = unitPage.items;

    final leasePage = await _readAllLeases(workspaceId);
    if (generation != _generation) {
      return;
    }
    if (leasePage.failure != null) {
      state = state.copyWith(
        phase: leasePage.failure == LeasingRepositoryFailureKind.forbidden
            ? OperationsOverviewPhase.forbidden
            : OperationsOverviewPhase.error,
        summary: null,
        message: leasePage.message,
      );
      return;
    }
    final leases = leasePage.items;
    final truncated = unitPage.truncated || leasePage.truncated;

    final signalsResult = await _signals.list(
      OperationsSignalsQuery(workspaceId: workspaceId, propertyId: _propertyId),
    );
    if (generation != _generation) {
      return;
    }
    if (signalsResult is OperationsSignalsFailure<List<OperationsSignalDto>>) {
      state = state.copyWith(
        phase: signalsResult.kind == OperationsSignalsFailureKind.forbidden
            ? OperationsOverviewPhase.forbidden
            : OperationsOverviewPhase.error,
        summary: null,
        message: signalsResult.message,
      );
      return;
    }
    final alerts =
        (signalsResult as OperationsSignalsSuccess<List<OperationsSignalDto>>).value;

    final date = asOfDate;
    final leasedAreaSqm = units
        .where((unit) => unit.status == UnitStatus.occupied)
        .fold<double>(0, (sum, unit) => sum + (unit.areaSqm ?? 0));

    state = state.copyWith(
      phase: OperationsOverviewPhase.ready,
      summary: OperationsOverviewSummary(
        rentRoll: live,
        leasedAreaSqm: leasedAreaSqm,
        expiringIn30Days: _countExpiring(leases, date, 30),
        expiringIn60Days: _countExpiring(leases, date, 60),
        expiringIn90Days: _countExpiring(leases, date, 90),
        expiringIn180Days: _countExpiring(leases, date, 180),
        alerts: alerts,
        truncated: truncated,
      ),
      message: null,
    );
  }

  Future<_PagedRead<UnitSummaryDto>> _readAllUnits(String workspaceId) async {
    final items = <UnitSummaryDto>[];
    String? cursor;
    for (var page = 0; page < maxPages; page++) {
      final result = await _unitSearch.search(
        UnitListQuery(
          workspaceId: workspaceId,
          propertyId: _propertyId,
          page: LeasingPageRequest(limit: pageSize, cursor: cursor),
        ),
      );
      switch (result) {
        case LeasingRepositoryFailure<LeasingPageResult<UnitSummaryDto>>(
          :final kind,
          :final message,
        ):
          return _PagedRead<UnitSummaryDto>(
            items: const <UnitSummaryDto>[],
            failure: kind,
            message: message,
          );
        case LeasingRepositorySuccess<LeasingPageResult<UnitSummaryDto>>(
          :final value,
        ):
          items.addAll(value.items);
          cursor = value.nextCursor;
          if (cursor == null) {
            return _PagedRead<UnitSummaryDto>(items: items);
          }
      }
    }
    return _PagedRead<UnitSummaryDto>(items: items, truncated: true);
  }

  Future<_PagedRead<LeaseSummaryDto>> _readAllLeases(String workspaceId) async {
    final items = <LeaseSummaryDto>[];
    String? cursor;
    for (var page = 0; page < maxPages; page++) {
      final result = await _leaseSearch.search(
        LeaseListQuery(
          workspaceId: workspaceId,
          propertyId: _propertyId,
          effectiveOnly: true,
          page: LeasingPageRequest(limit: pageSize, cursor: cursor),
        ),
      );
      switch (result) {
        case LeasingRepositoryFailure<LeasingPageResult<LeaseSummaryDto>>(
          :final kind,
          :final message,
        ):
          return _PagedRead<LeaseSummaryDto>(
            items: const <LeaseSummaryDto>[],
            failure: kind,
            message: message,
          );
        case LeasingRepositorySuccess<LeasingPageResult<LeaseSummaryDto>>(
          :final value,
        ):
          items.addAll(value.items);
          cursor = value.nextCursor;
          if (cursor == null) {
            return _PagedRead<LeaseSummaryDto>(items: items);
          }
      }
    }
    return _PagedRead<LeaseSummaryDto>(items: items, truncated: true);
  }

  int _countExpiring(List<LeaseSummaryDto> leases, DateTime date, int days) {
    final horizon = date.add(Duration(days: days));
    return leases
        .where(
          (lease) =>
              lease.isEffective &&
              lease.endDate != null &&
              !lease.endDate!.isBefore(date) &&
              !lease.endDate!.isAfter(horizon),
        )
        .length;
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
          // Every published leasing aggregate can move this screen's numbers
          // except the pipeline: a leasing case has no effect on units,
          // leases, the rent roll or signals.
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

final operationsOverviewControllerProvider = StateNotifierProvider.autoDispose
    .family<OperationsOverviewController, OperationsOverviewState, String>((
      ref,
      propertyId,
    ) {
      final controller = OperationsOverviewController(
        rentRoll: ref.watch(rentRollProvider),
        unitSearch: ref.watch(unitSearchProvider),
        leaseSearch: ref.watch(leaseSearchProvider),
        signals: ref.watch(operationsSignalsProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
        propertyId: propertyId,
        invalidationSource: ref.watch(leasingQueryInvalidationSourceProvider),
      );
      unawaited(controller.load());
      return controller;
    });

class _PagedRead<T> {
  const _PagedRead({
    required this.items,
    this.truncated = false,
    this.failure,
    this.message,
  });

  final List<T> items;
  final bool truncated;
  final LeasingRepositoryFailureKind? failure;
  final String? message;
}
