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

/// Which revision of the lease-effectiveness rule produced a set of rent-roll
/// figures (RENT-ROLL-RULE-01, follow-up 4 from DEC-027).
///
/// `LEASING-ASOF-01` changed which leases count towards a rent roll, so two
/// snapshots of the same property for the same reporting date — one taken
/// before that migration, one after — legitimately differ. Without a marker the
/// difference reads as a rent change, and only `generatedAt` separates the two
/// eras, by inference.
///
/// This catalogue is the **client's** knowledge of the server's rule versions,
/// and it is deliberately allowed to be incomplete. The web build and the
/// database reach an environment through different pipelines, so a build can
/// meet a version it has never heard of. [forVersion] then returns null and the
/// UI must say "unknown" rather than describe the current rule, because naming
/// the wrong rule is worse than naming none.
class RentRollEffectivenessRule {
  const RentRollEffectivenessRule._(this.version, this.summary);

  /// The monotonic server version. Not an index into anything — a rule that
  /// this build does not know still has a number, and it is shown.
  final int version;

  /// What the rule decided, in one line, for a reader comparing two figures.
  final String summary;

  /// P2-D05 through migration 49: `end_date` was read as a termination.
  static const RentRollEffectivenessRule v1 = RentRollEffectivenessRule._(
    1,
    'Verträge nur bis zum geplanten Ende; beendete Verträge zählten auch für '
    'Stichtage nicht mehr, die sie abdeckten',
  );

  /// `LEASING-ASOF-01` / DEC-027 onward: a planned end is not a termination.
  static const RentRollEffectivenessRule v2 = RentRollEffectivenessRule._(
    2,
    'Laufende Verträge zählen über das geplante Ende hinaus; beendete zählen '
    'für Stichtage, die sie abdeckten',
  );

  static const List<RentRollEffectivenessRule> known =
      <RentRollEffectivenessRule>[v1, v2];

  /// The rule for [version], or null when there is none to name: either the
  /// figures carry no version at all (a snapshot frozen before the marker
  /// existed, or a server that does not publish one yet), or the version is
  /// newer than this build.
  static RentRollEffectivenessRule? forVersion(int? version) {
    if (version == null) {
      return null;
    }
    for (final rule in known) {
      if (rule.version == version) {
        return rule;
      }
    }
    return null;
  }
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
    required this.effectivenessRuleVersion,
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

  /// Which lease-effectiveness rule the server applied, or null when it did not
  /// say — a server older than RENT-ROLL-RULE-01. Required to pass, so a
  /// surface that renders a live figure without its rule is a choice somebody
  /// made rather than an accident the type allowed.
  final int? effectivenessRuleVersion;

  /// Null exactly when the contributing leases do not share one currency.
  final double? totalBaseRentMonthly;
  final double? totalAncillaryChargesMonthly;
  final double? totalParkingOtherChargesMonthly;
  final double? totalRentMonthly;

  String? get currencyCode => currencies.length == 1 ? currencies.single : null;

  bool get hasMixedCurrencies => currencies.length > 1;

  /// The named rule, or null when [effectivenessRuleVersion] is absent or newer
  /// than this build knows.
  RentRollEffectivenessRule? get effectivenessRule =>
      RentRollEffectivenessRule.forVersion(effectivenessRuleVersion);

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
    required this.effectivenessRuleVersion,
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

  /// Which revision of the lease-effectiveness rule froze these figures
  /// (RENT-ROLL-RULE-01), or **null** when the snapshot carries no marker.
  ///
  /// Null is a statement, not a gap: it means the rule was never recorded, not
  /// that it was rule 1. Every snapshot taken before RENT-ROLL-RULE-01 reads
  /// this way, and the server declines to guess which era it belongs to,
  /// because migration 50 opened a second one and nothing on the row separates
  /// them. Required to pass, following `FinanceKpiValue.definitionVersion`: a
  /// figure that cannot say what produced it must at least be unable to hide
  /// that.
  final int? effectivenessRuleVersion;

  /// Empty on a list projection, populated when the snapshot is read in full.
  final List<RentRollSnapshotLineDto> lines;

  /// The named rule, or null when [effectivenessRuleVersion] is absent or newer
  /// than this build knows. A caller must distinguish the two: the first means
  /// "not recorded", the second "recorded, but this build cannot name it", and
  /// neither may be rendered as the current rule.
  RentRollEffectivenessRule? get effectivenessRule =>
      RentRollEffectivenessRule.forVersion(effectivenessRuleVersion);

  /// True when the snapshot names a rule this build does not know — a database
  /// ahead of this build, which happens because the web build and the database
  /// reach an environment through different pipelines.
  bool get hasUnknownEffectivenessRule =>
      effectivenessRuleVersion != null && effectivenessRule == null;

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
