/// Domain DTOs for the RentRollSnapshot aggregate (P2-D05, AGG-007).
///
/// A snapshot is **immutable**: once frozen it can never be updated or deleted,
/// which is why nothing here carries a version or an `updatedAt`/`updatedBy`. A
/// row that can never be written twice has nothing to hold an optimistic
/// concurrency token against, and carrying one would advertise a second writer
/// that does not exist.
///
/// Immutable is deliberately NOT the same claim as unique-per-period: several
/// snapshots may exist for the same property and date, each frozen, ordered by
/// [RentRollSnapshotDto.generatedAt]. Picking "the current one" is the reader's
/// job. (With OPN-DOM-005 open there is no delete path anywhere, so a unique
/// constraint would let one bad run poison a reporting period permanently.)
library;

import 'unit_dto.dart';

/// One frozen per-unit row. Every money figure is a SUM over the leases
/// effective on the snapshot's reporting date, because OPN-DOM-001 allows a
/// unit to hold several concurrent leases. [effectiveLeaseCount] travels with
/// the line so the sum is auditable: "2 leases, 1050" is checkable, a bare
/// "1050" is not.
class RentRollSnapshotLineDto {
  const RentRollSnapshotLineDto({
    required this.id,
    required this.unitId,
    required this.unitCode,
    required this.unitStatus,
    required this.effectiveLeaseCount,
    required this.baseRentMonthly,
    required this.ancillaryChargesMonthly,
    required this.parkingOtherChargesMonthly,
    required this.totalRentMonthly,
    this.areaSqm,
  });

  final String id;
  final String unitId;

  /// Frozen at generation time. A later rename does not rewrite what a past
  /// rent roll said — that is the entire point of a snapshot.
  final String unitCode;

  /// Also frozen. This is what makes the zero-rent case below legible.
  final UnitStatus unitStatus;

  final int effectiveLeaseCount;
  final double baseRentMonthly;
  final double ancillaryChargesMonthly;
  final double parkingOtherChargesMonthly;
  final double totalRentMonthly;
  final double? areaSqm;

  /// True when this unit contributed nothing to the snapshot.
  ///
  /// Worth understanding rather than treating as a bug: a unit can be
  /// [UnitStatus.occupied] and still be empty here. The AGG-004 occupancy
  /// invariant is status-based (it is trigger-enforced, and triggers only fire
  /// on writes), while the rent roll additionally requires the lease term to
  /// cover the reporting date, because it is a point-in-time report. A unit let
  /// from July contributes 0.00 to a March rent roll while being legitimately
  /// occupied. [unitStatus] is frozen here precisely so a UI can say that.
  bool get isEmpty => effectiveLeaseCount == 0;

  /// The mismatch above, named. Useful for a column note or tooltip.
  bool get isOccupiedButOutsideTerm =>
      unitStatus == UnitStatus.occupied && effectiveLeaseCount == 0;
}

/// One line of the **live** rent roll (P2-D05b). Same figures as a frozen line,
/// minus the identity a computed row does not have, plus the currencies found
/// on that unit.
class RentRollLiveLineDto {
  const RentRollLiveLineDto({
    required this.unitId,
    required this.unitCode,
    required this.unitStatus,
    required this.effectiveLeaseCount,
    required this.baseRentMonthly,
    required this.ancillaryChargesMonthly,
    required this.parkingOtherChargesMonthly,
    required this.totalRentMonthly,
    required this.currencies,
    this.areaSqm,
  });

  final String unitId;
  final String unitCode;
  final UnitStatus unitStatus;
  final int effectiveLeaseCount;
  final double baseRentMonthly;
  final double ancillaryChargesMonthly;
  final double parkingOtherChargesMonthly;
  final double totalRentMonthly;

  /// Distinct currencies of the leases contributing to this unit. More than one
  /// means the amounts above are a cross-currency sum and must not be read as
  /// one number.
  final List<String> currencies;

  final double? areaSqm;

  String? get currencyCode => currencies.length == 1 ? currencies.single : null;

  bool get hasMixedCurrencies => currencies.length > 1;

  bool get isEmpty => effectiveLeaseCount == 0;

  /// See [RentRollSnapshotLineDto.isOccupiedButOutsideTerm] — the same fact,
  /// computed live.
  bool get isOccupiedButOutsideTerm =>
      unitStatus == UnitStatus.occupied && effectiveLeaseCount == 0;
}

/// The **live** rent roll of one property (P2-D05b): the current state,
/// computed server-side from the same helpers that build a snapshot.
///
/// Deliberately not a [RentRollSnapshotDto]: nothing was written, so there is
/// no id, no `generatedAt` and no `createdBy` — only [computedAt]. And unlike a
/// snapshot, which is refused outright when the contributing leases disagree on
/// currency, a live read still answers: it reports every currency it found and
/// leaves the totals **null**, because a null says "not summable" while a zero
/// would say something false.
class RentRollLiveDto {
  const RentRollLiveDto({
    required this.workspaceId,
    required this.propertyId,
    required this.asOfDate,
    required this.computedAt,
    required this.currencies,
    required this.unitCount,
    required this.occupiedUnitCount,
    required this.vacantUnitCount,
    required this.offlineUnitCount,
    required this.effectiveLeaseCount,
    required this.lines,
    this.totalBaseRentMonthly,
    this.totalAncillaryChargesMonthly,
    this.totalParkingOtherChargesMonthly,
    this.totalRentMonthly,
  });

  final String workspaceId;
  final String propertyId;
  final DateTime asOfDate;
  final DateTime computedAt;
  final List<String> currencies;
  final int unitCount;
  final int occupiedUnitCount;
  final int vacantUnitCount;
  final int offlineUnitCount;
  final int effectiveLeaseCount;
  final List<RentRollLiveLineDto> lines;

  /// Null exactly when the contributing leases do not share one currency.
  final double? totalBaseRentMonthly;
  final double? totalAncillaryChargesMonthly;
  final double? totalParkingOtherChargesMonthly;
  final double? totalRentMonthly;

  String? get currencyCode => currencies.length == 1 ? currencies.single : null;

  bool get hasMixedCurrencies => currencies.length > 1;

  double? get occupancyRate =>
      unitCount == 0 ? null : occupiedUnitCount / unitCount;

  List<RentRollLiveLineDto> get occupiedOutsideTermLines => lines
      .where((line) => line.isOccupiedButOutsideTerm)
      .toList(growable: false);
}

/// The frozen header. Its totals are exactly the sums of its [lines] — the
/// server enforces that structurally (check constraints pin that the occupancy
/// counters partition the units and that each total is the sum of its parts),
/// so a consumer may rely on it rather than recomputing defensively.
class RentRollSnapshotDto {
  const RentRollSnapshotDto({
    required this.id,
    required this.workspaceId,
    required this.propertyId,
    required this.asOfDate,
    required this.currencyCode,
    required this.generatedAt,
    required this.unitCount,
    required this.occupiedUnitCount,
    required this.vacantUnitCount,
    required this.offlineUnitCount,
    required this.effectiveLeaseCount,
    required this.totalBaseRentMonthly,
    required this.totalAncillaryChargesMonthly,
    required this.totalParkingOtherChargesMonthly,
    required this.totalRentMonthly,
    required this.createdAt,
    required this.createdBy,
    this.lines = const <RentRollSnapshotLineDto>[],
  });

  final String id;
  final String workspaceId;
  final String propertyId;

  /// The reporting date the figures describe.
  final DateTime asOfDate;

  /// DEC-011. Derived from the contributing leases; never guessed. A property
  /// whose leases disagree on currency cannot be snapshotted at all — the
  /// server refuses with a currency-mismatch failure rather than summing.
  final String currencyCode;

  /// When the snapshot was taken. Statuses are read at this moment, so the pair
  /// ([asOfDate], [generatedAt]) is what makes a figure explainable later.
  final DateTime generatedAt;

  final int unitCount;
  final int occupiedUnitCount;
  final int vacantUnitCount;
  final int offlineUnitCount;
  final int effectiveLeaseCount;
  final double totalBaseRentMonthly;
  final double totalAncillaryChargesMonthly;
  final double totalParkingOtherChargesMonthly;
  final double totalRentMonthly;
  final DateTime createdAt;
  final String createdBy;

  /// Empty on a list projection, populated when the snapshot is read in full.
  final List<RentRollSnapshotLineDto> lines;

  /// Share of units that are occupied, or null when the property has no units
  /// (rather than a misleading 0%).
  double? get occupancyRate =>
      unitCount == 0 ? null : occupiedUnitCount / unitCount;

  /// Lines that are occupied but contributed nothing because their lease term
  /// does not cover [asOfDate]. Empty on a list projection.
  List<RentRollSnapshotLineDto> get occupiedOutsideTermLines => lines
      .where((line) => line.isOccupiedButOutsideTerm)
      .toList(growable: false);
}
