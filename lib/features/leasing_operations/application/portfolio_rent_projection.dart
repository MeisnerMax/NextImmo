/// The client-side rent projection that the **portfolio** view still needs
/// (Welle 3, AP7).
///
/// This is what is left of the arithmetic P2-D05b moved into Postgres. The
/// per-property rent roll no longer computes anything — it reads
/// `RentRollPort.readLive`. The portfolio view cannot yet: it summarises every
/// property at once, and calling one server read per property would trade a
/// bounded pair of list reads for N round trips.
///
/// It is therefore deliberately **narrower** than the server document: base
/// rent only, from the lease summary projection. Ancillary and parking charges
/// are not in that projection, and the portfolio table does not claim them.
/// A workspace-wide live read would delete this file; until then this is the
/// one place the rule is mirrored, and it mirrors it exactly:
///
///   * a lease contributes when it is effective **and** its term covers the
///     reporting date;
///   * amounts in different currencies are never summed (DEC-011) — the
///     currencies found travel with the row and the header instead.
library;

import '../domain/lease_dto.dart';
import '../domain/unit_dto.dart';

/// One line of the live rent roll: a unit and the leases effective on it right
/// now. Mirrors [RentRollSnapshotLineDto] in shape so both tables read alike,
/// but is computed client-side and says so.
class RentRollLiveRow {
  const RentRollLiveRow({
    required this.unitId,
    required this.unitCode,
    required this.unitStatus,
    required this.effectiveLeaseCount,
    required this.baseRentMonthly,
    required this.currencies,
    this.areaSqm,
  });

  final String unitId;
  final String unitCode;
  final UnitStatus unitStatus;

  /// Leases that are both effective (status `active`) **and** whose term covers
  /// the reporting date. Both conditions matter — see
  /// [isOccupiedButOutsideTerm].
  final int effectiveLeaseCount;

  final double baseRentMonthly;

  /// The distinct currencies among the contributing leases. More than one means
  /// the sum on this row is not a meaningful number.
  final List<String> currencies;

  final double? areaSqm;

  String? get currencyCode => currencies.length == 1 ? currencies.single : null;

  bool get hasMixedCurrencies => currencies.length > 1;

  /// A unit can be [UnitStatus.occupied] and still contribute nothing: AGG-004
  /// occupancy is status-based, while a rent roll additionally needs the lease
  /// term to cover the reporting date. Not a bug — a fact that has to be said.
  bool get isOccupiedButOutsideTerm =>
      unitStatus == UnitStatus.occupied && effectiveLeaseCount == 0;
}

/// The header of the live rent roll. Same figures as a snapshot header, minus
/// the ones the summary projection cannot supply.
class RentRollLiveSummary {
  const RentRollLiveSummary({
    required this.asOfDate,
    required this.unitCount,
    required this.occupiedUnitCount,
    required this.vacantUnitCount,
    required this.offlineUnitCount,
    required this.effectiveLeaseCount,
    required this.totalBaseRentMonthly,
    required this.currencies,
  });

  final DateTime asOfDate;
  final int unitCount;
  final int occupiedUnitCount;
  final int vacantUnitCount;
  final int offlineUnitCount;
  final int effectiveLeaseCount;
  final double totalBaseRentMonthly;
  final List<String> currencies;

  /// Null when the property has no units, rather than a misleading 0 %.
  double? get occupancyRate =>
      unitCount == 0 ? null : occupiedUnitCount / unitCount;

  String? get currencyCode => currencies.length == 1 ? currencies.single : null;

  /// DEC-011: no silent cross-currency sum. The surface names the currencies
  /// instead of printing a number that means nothing.
  bool get hasMixedCurrencies => currencies.length > 1;
}

/// The live rent roll of one property: rows plus their header.
class RentRollLive {
  const RentRollLive({required this.rows, required this.summary});

  final List<RentRollLiveRow> rows;
  final RentRollLiveSummary summary;
}

/// The live rent-roll computation, as a pure function over the two reads.
///
/// It exists as a named, testable seam because it is **temporary**: the same
/// arithmetic already lives in Postgres next to `create_rent_roll_snapshot`,
/// and the durable fix is a server-side live read that reuses it, so the two
/// cannot drift. Whoever adds that read deletes this function and keeps its
/// tests pointed at the new source.
///
/// Two rules are mirrored deliberately, because getting them wrong is what
/// makes a rent roll silently false:
///
///   * A lease contributes only when it is effective **and** its term covers
///     [asOfDate]. `effectiveLeases` is expected to be the status-filtered
///     read; the term window is applied here.
///   * DEC-011: amounts in different currencies are never summed into one
///     number. The currencies found travel with the row and the header, and the
///     surface reports them instead of printing a meaningless total.
RentRollLive computeLiveRentRoll({
  required List<UnitSummaryDto> units,
  required List<LeaseSummaryDto> effectiveLeases,
  required DateTime asOfDate,
}) {
  final rows = <RentRollLiveRow>[];
  for (final unit in units) {
    final contributing = effectiveLeases
        .where(
          (lease) =>
              lease.unitId == unit.id &&
              lease.isEffective &&
              lease.coversDate(asOfDate),
        )
        .toList(growable: false);
    final currencies =
        contributing.map((lease) => lease.currencyCode).toSet().toList()..sort();
    rows.add(
      RentRollLiveRow(
        unitId: unit.id,
        unitCode: unit.unitCode,
        unitStatus: unit.status,
        effectiveLeaseCount: contributing.length,
        baseRentMonthly: contributing.fold<double>(
          0,
          (sum, lease) => sum + lease.baseRentMonthly,
        ),
        currencies: currencies,
        areaSqm: unit.areaSqm,
      ),
    );
  }

  final allCurrencies = rows.expand((row) => row.currencies).toSet().toList()
    ..sort();

  return RentRollLive(
    rows: rows,
    summary: RentRollLiveSummary(
      asOfDate: asOfDate,
      unitCount: units.length,
      occupiedUnitCount: units
          .where((unit) => unit.status == UnitStatus.occupied)
          .length,
      vacantUnitCount: units
          .where((unit) => unit.status == UnitStatus.vacant)
          .length,
      offlineUnitCount: units
          .where((unit) => unit.status == UnitStatus.offline)
          .length,
      effectiveLeaseCount: rows.fold<int>(
        0,
        (sum, row) => sum + row.effectiveLeaseCount,
      ),
      totalBaseRentMonthly: rows.fold<double>(
        0,
        (sum, row) => sum + row.baseRentMonthly,
      ),
      currencies: allCurrencies,
    ),
  );
}
