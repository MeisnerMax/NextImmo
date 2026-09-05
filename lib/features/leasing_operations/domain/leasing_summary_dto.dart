/// The server-authoritative leasing summary of one property
/// (LEASING-SUMMARY-01).
///
/// Everything here is counted or summed by the server. Nothing is divided:
/// there is no occupancy rate and no renewal risk, because "occupied by unit"
/// and "occupied by area" are different numbers and a risk score needs an
/// explained signal contract. Both inputs are published so the decision stays
/// where it belongs.
///
/// The types enforce that at the call site. Areas are nullable and travel with
/// the count of units that have none recorded, so a partial sum cannot be read
/// as a complete one. Rent is a list per currency and never a single total,
/// because adding EUR to CHF produces a number that is wrong in both.
library;

/// Units and floor area, with the coverage of the area figures attached.
class PropertyLeasingUnits {
  const PropertyLeasingUnits({
    required this.total,
    required this.occupied,
    required this.vacant,
    required this.offline,
    required this.areaSqmTotal,
    required this.areaSqmOccupied,
    required this.areaSqmVacant,
    required this.unitsWithoutArea,
  });

  final int total;
  final int occupied;
  final int vacant;
  final int offline;

  /// Summed over the units that record an area. Read together with
  /// [unitsWithoutArea] — alone it is not the area of the building.
  final num areaSqmTotal;
  final num areaSqmOccupied;
  final num areaSqmVacant;

  /// How many units carry no recorded area. Greater than zero means every
  /// area figure above is a partial sum and must be labelled as one.
  final int unitsWithoutArea;

  /// Whether the area figures cover every unit.
  bool get areaIsComplete => unitsWithoutArea == 0;
}

/// How long the building has stood empty, from the recorded vacancy start.
class PropertyLeasingVacancy {
  const PropertyLeasingVacancy({
    required this.longestVacancyDays,
    required this.vacantWithoutSince,
  });

  /// Null when no vacant unit records a start date. Deliberately nullable: a
  /// zero here would claim the vacancy began today.
  final int? longestVacancyDays;

  /// Vacant units with no recorded start. They are reported, never counted as
  /// vacant since today.
  final int vacantWithoutSince;
}

/// One expiry window, as the server cut it.
class PropertyLeaseExpiryWindow {
  const PropertyLeaseExpiryWindow({
    required this.days,
    required this.label,
    required this.expiring,
  });

  final int days;

  /// The server's own label. Rendered as sent, so a client cannot re-cut the
  /// window and report a different exposure under the same name.
  final String label;

  /// Leases whose end date falls between today and [days] from today.
  /// Cumulative: the 180-day window contains the 30-day one.
  final int expiring;
}

/// The lease roll: what is running, what runs out, what has already run out.
class PropertyLeaseRoll {
  const PropertyLeaseRoll({
    required this.active,
    required this.openEnded,
    required this.expiredOpen,
    required this.windows,
  });

  final int active;

  /// Leases with no end date. Their own count, not "not expiring": an
  /// open-ended obligation is a different thing from a long one.
  final int openEnded;

  /// Active leases already past their end date. Present exposure, not history.
  final int expiredOpen;

  final List<PropertyLeaseExpiryWindow> windows;
}

/// The dates the leases themselves carry, inside the server's window.
class PropertyLeaseDecisions {
  const PropertyLeaseDecisions({
    required this.windowDays,
    required this.noticeDue,
    required this.renewalOption,
    required this.breakOption,
  });

  final int windowDays;
  final int noticeDue;
  final int renewalOption;
  final int breakOption;

  int get total => noticeDue + renewalOption + breakOption;
}

/// Monthly base rent of the active leases in one currency.
///
/// There is no cross-currency total anywhere in this file, and no place to put
/// one.
class PropertyRentRollCurrency {
  const PropertyRentRollCurrency({
    required this.currencyCode,
    required this.monthlyBase,
    required this.leases,
  });

  final String currencyCode;
  final num monthlyBase;
  final int leases;
}

class PropertyLeasingSummaryDto {
  const PropertyLeasingSummaryDto({
    required this.asOf,
    required this.units,
    required this.vacancy,
    required this.leaseRoll,
    required this.decisions,
    required this.rentRoll,
  });

  /// When the server produced this snapshot. Shown so the surface states its
  /// freshness rather than implying live truth.
  final DateTime asOf;

  final PropertyLeasingUnits units;
  final PropertyLeasingVacancy vacancy;
  final PropertyLeaseRoll leaseRoll;
  final PropertyLeaseDecisions decisions;

  /// One entry per currency, server-ordered by currency code. Empty means no
  /// active lease, not zero rent.
  final List<PropertyRentRollCurrency> rentRoll;
}
