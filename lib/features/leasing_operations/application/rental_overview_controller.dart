/// Screen-facing orchestration for the portfolio-wide rental view (Welle 3,
/// AP7 — SCR-065).
///
/// The same question as the rent roll, asked across every property instead of
/// one: how much is let, how much stands empty, what does it earn, and what
/// runs out soon. It therefore **reuses [computeLiveRentRoll] per property**
/// rather than growing a second occupancy rule — one place decides what
/// "effective on this date" means, and both surfaces obey it.
///
/// Three things this read has to be honest about:
///
///   * **It is workspace-wide and paged.** Units and leases are read without a
///     property filter, so a large portfolio can exceed what one page holds.
///     The controller pages up to a bounded number of pages and *reports* when
///     it stopped — a silently truncated portfolio view would read as a smaller
///     portfolio.
///   * **Property names come from the property contract**, not from the leasing
///     one: a unit knows its `propertyId`, not its name.
///   * **DEC-011 again.** Rents in different currencies are not summed into one
///     portfolio total; the currencies found are named instead.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../../portfolio_property/application/property_repository.dart';
import '../../portfolio_property/domain/property_dto.dart';
import '../../reference_slice/application/reference_slice_controller.dart';
import '../domain/lease_dto.dart';
import '../domain/unit_dto.dart';
import 'leasing_providers.dart';
import 'leasing_query_invalidation_source.dart';
import 'leasing_repository.dart';
import 'portfolio_rent_projection.dart';

const Object _unchanged = Object();

enum RentalOverviewPhase { idle, loading, ready, empty, forbidden, error }

/// One property's rental position.
class RentalOverviewRow {
  const RentalOverviewRow({
    required this.propertyId,
    required this.propertyName,
    required this.city,
    required this.summary,
    required this.expiringLeaseCount,
  });

  final String propertyId;

  /// Falls back to the id when the property contract could not resolve it —
  /// named as unresolved rather than silently dropped from the portfolio.
  final String propertyName;

  final String city;
  final RentRollLiveSummary summary;

  /// Effective leases of this property whose term ends within the horizon.
  final int expiringLeaseCount;
}

/// The portfolio totals. Deliberately not a [RentRollLiveSummary]: a portfolio
/// has no single reporting currency and no single property, and pretending
/// otherwise is how a wrong number gets published.
class RentalOverviewTotals {
  const RentalOverviewTotals({
    required this.propertyCount,
    required this.unitCount,
    required this.occupiedUnitCount,
    required this.vacantUnitCount,
    required this.offlineUnitCount,
    required this.effectiveLeaseCount,
    required this.expiringLeaseCount,
    required this.totalBaseRentMonthly,
    required this.currencies,
  });

  final int propertyCount;
  final int unitCount;
  final int occupiedUnitCount;
  final int vacantUnitCount;
  final int offlineUnitCount;
  final int effectiveLeaseCount;
  final int expiringLeaseCount;
  final double totalBaseRentMonthly;
  final List<String> currencies;

  double? get occupancyRate =>
      unitCount == 0 ? null : occupiedUnitCount / unitCount;

  String? get currencyCode => currencies.length == 1 ? currencies.single : null;

  bool get hasMixedCurrencies => currencies.length > 1;
}

class RentalOverviewState {
  const RentalOverviewState({
    required this.phase,
    this.rows = const <RentalOverviewRow>[],
    this.totals,
    this.asOfDate,
    this.truncated = false,
    this.message,
  });

  const RentalOverviewState.loading() : this(phase: RentalOverviewPhase.loading);

  final RentalOverviewPhase phase;
  final List<RentalOverviewRow> rows;
  final RentalOverviewTotals? totals;
  final DateTime? asOfDate;

  /// True when the paged read hit its bound and the view therefore describes
  /// only part of the portfolio. Never hidden.
  final bool truncated;

  final String? message;

  RentalOverviewState copyWith({
    RentalOverviewPhase? phase,
    List<RentalOverviewRow>? rows,
    Object? totals = _unchanged,
    Object? asOfDate = _unchanged,
    bool? truncated,
    Object? message = _unchanged,
  }) {
    return RentalOverviewState(
      phase: phase ?? this.phase,
      rows: rows ?? this.rows,
      totals: identical(totals, _unchanged)
          ? this.totals
          : totals as RentalOverviewTotals?,
      asOfDate: identical(asOfDate, _unchanged)
          ? this.asOfDate
          : asOfDate as DateTime?,
      truncated: truncated ?? this.truncated,
      message: identical(message, _unchanged) ? this.message : message as String?,
    );
  }
}

typedef RentalOverviewClock = DateTime Function();

class RentalOverviewController extends StateNotifier<RentalOverviewState> {
  RentalOverviewController({
    required PropertyRepository properties,
    required UnitSearchPort unitSearch,
    required LeaseSearchPort leaseSearch,
    required WorkspaceSessionScope scope,
    LeasingQueryInvalidationSource? invalidationSource,
    RentalOverviewClock? clock,
    Duration invalidationCoalesceWindow = const Duration(milliseconds: 250),
  }) : _properties = properties,
       _unitSearch = unitSearch,
       _leaseSearch = leaseSearch,
       _scope = scope,
       _invalidationSource = invalidationSource,
       _clock = clock ?? DateTime.now,
       _coalesceWindow = invalidationCoalesceWindow,
       super(const RentalOverviewState.loading());

  static const int pageSize = 100;

  /// The bound on the workspace-wide read. Five pages is generous for the
  /// portfolios this serves and small enough that a runaway read cannot hang
  /// the screen; hitting it is reported, not swallowed.
  static const int maxPages = 5;

  /// A lease is "expiring" when its term ends within this window.
  static const Duration expiryHorizon = Duration(days: 90);

  final PropertyRepository _properties;
  final UnitSearchPort _unitSearch;
  final LeaseSearchPort _leaseSearch;
  final WorkspaceSessionScope _scope;
  final LeasingQueryInvalidationSource? _invalidationSource;
  final RentalOverviewClock _clock;
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
      state = state.copyWith(
        phase: RentalOverviewPhase.idle,
        rows: const <RentalOverviewRow>[],
        totals: null,
      );
      return;
    }
    _subscribeToInvalidation(workspaceId);
    final generation = ++_generation;
    state = state.copyWith(phase: RentalOverviewPhase.loading, message: null);

    var truncated = false;

    final unitPage = await _readAllUnits(workspaceId);
    if (generation != _generation) {
      return;
    }
    if (unitPage.failure != null) {
      state = state.copyWith(
        phase: unitPage.failure == LeasingRepositoryFailureKind.forbidden
            ? RentalOverviewPhase.forbidden
            : RentalOverviewPhase.error,
        rows: const <RentalOverviewRow>[],
        totals: null,
        message: unitPage.message,
      );
      return;
    }
    truncated = truncated || unitPage.truncated;

    final leasePage = await _readAllLeases(workspaceId);
    if (generation != _generation) {
      return;
    }
    if (leasePage.failure != null) {
      state = state.copyWith(
        phase: leasePage.failure == LeasingRepositoryFailureKind.forbidden
            ? RentalOverviewPhase.forbidden
            : RentalOverviewPhase.error,
        rows: const <RentalOverviewRow>[],
        totals: null,
        message: leasePage.message,
      );
      return;
    }
    truncated = truncated || leasePage.truncated;

    // Names only — a failure here costs labels, not the view.
    final names = await _readPropertyNames(workspaceId);
    if (generation != _generation) {
      return;
    }

    final date = asOfDate;
    final horizon = date.add(expiryHorizon);
    final byProperty = <String, List<UnitSummaryDto>>{};
    for (final unit in unitPage.items) {
      byProperty.putIfAbsent(unit.propertyId, () => <UnitSummaryDto>[]).add(unit);
    }

    final rows = <RentalOverviewRow>[];
    for (final entry in byProperty.entries) {
      final propertyLeases = leasePage.items
          .where((lease) => lease.propertyId == entry.key)
          .toList(growable: false);
      // The same rule as the per-property rent roll, on purpose: one place
      // decides what counts.
      final live = computeLiveRentRoll(
        units: entry.value,
        effectiveLeases: propertyLeases,
        asOfDate: date,
      );
      final summary = names[entry.key];
      rows.add(
        RentalOverviewRow(
          propertyId: entry.key,
          propertyName: summary?.name ?? 'Objekt nicht auflösbar',
          city: summary?.city ?? '—',
          summary: live.summary,
          expiringLeaseCount: propertyLeases
              .where(
                (lease) =>
                    lease.isEffective &&
                    lease.endDate != null &&
                    !lease.endDate!.isBefore(date) &&
                    !lease.endDate!.isAfter(horizon),
              )
              .length,
        ),
      );
    }
    rows.sort((a, b) => a.propertyName.compareTo(b.propertyName));

    final currencies = rows
        .expand((row) => row.summary.currencies)
        .toSet()
        .toList()
      ..sort();

    state = state.copyWith(
      phase: rows.isEmpty
          ? RentalOverviewPhase.empty
          : RentalOverviewPhase.ready,
      rows: rows,
      asOfDate: date,
      truncated: truncated,
      totals: RentalOverviewTotals(
        propertyCount: rows.length,
        unitCount: rows.fold<int>(0, (sum, row) => sum + row.summary.unitCount),
        occupiedUnitCount: rows.fold<int>(
          0,
          (sum, row) => sum + row.summary.occupiedUnitCount,
        ),
        vacantUnitCount: rows.fold<int>(
          0,
          (sum, row) => sum + row.summary.vacantUnitCount,
        ),
        offlineUnitCount: rows.fold<int>(
          0,
          (sum, row) => sum + row.summary.offlineUnitCount,
        ),
        effectiveLeaseCount: rows.fold<int>(
          0,
          (sum, row) => sum + row.summary.effectiveLeaseCount,
        ),
        expiringLeaseCount: rows.fold<int>(
          0,
          (sum, row) => sum + row.expiringLeaseCount,
        ),
        totalBaseRentMonthly: rows.fold<double>(
          0,
          (sum, row) => sum + row.summary.totalBaseRentMonthly,
        ),
        currencies: currencies,
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

  Future<Map<String, PropertySummaryDto>> _readPropertyNames(
    String workspaceId,
  ) async {
    final byId = <String, PropertySummaryDto>{};
    String? cursor;
    for (var page = 0; page < maxPages; page++) {
      final result = await _properties.list(
        PropertyListQuery(
          workspaceId: workspaceId,
          page: PropertyPageRequest(limit: pageSize, cursor: cursor),
        ),
      );
      if (result is PropertyRepositoryFailure<PropertyPageResult>) {
        return byId;
      }
      final value =
          (result as PropertyRepositorySuccess<PropertyPageResult>).value;
      for (final property in value.items) {
        byId[property.id] = property;
      }
      cursor = value.nextCursor;
      if (cursor == null) {
        break;
      }
    }
    return byId;
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
          final aggregate = invalidation.aggregate;
          if (!invalidation.isReconciliation &&
              aggregate != LeasingAggregate.unit &&
              aggregate != LeasingAggregate.lease) {
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

final rentalOverviewControllerProvider = StateNotifierProvider.autoDispose<
  RentalOverviewController,
  RentalOverviewState
>((ref) {
  final controller = RentalOverviewController(
    properties: ref.watch(referencePropertyRepositoryProvider),
    unitSearch: ref.watch(unitSearchProvider),
    leaseSearch: ref.watch(leaseSearchProvider),
    scope: ref.watch(workspaceSessionScopeProvider),
    invalidationSource: ref.watch(leasingQueryInvalidationSourceProvider),
  );
  unawaited(controller.load());
  return controller;
});
