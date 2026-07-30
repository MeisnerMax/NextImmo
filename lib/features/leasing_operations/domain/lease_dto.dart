/// Domain DTOs for the Lease aggregate (P2-D05, DOM-004, STM-005, AGG-006).
///
/// OPN-DOM-001 (decided 2026-07-29, documented default overridden): a unit MAY
/// hold several concurrently effective leases. Nothing in this contract assumes
/// a unit has at most one — reads return lists, and the rent roll sums per unit.
///
/// A lease is "effective" exactly when its status is [LeaseStatus.active]. That
/// is status-based rather than date-based on purpose: the AGG-004 occupancy
/// invariant is trigger-enforced server-side, and triggers only fire on writes.
/// Date-driven expiry is an explicit transition, not an implicit lapse.
library;

/// STM-005: draft -> reviewed -> sent -> tenantSigned -> landlordSigned ->
/// active -> ended, with [cancelled] as the abort from any non-terminal state.
enum LeaseStatus {
  draft,
  reviewed,
  sent,
  tenantSigned,
  landlordSigned,
  active,
  ended,
  cancelled;

  /// The one status that makes a lease count towards occupancy and the rent
  /// roll. Mirrors `private.lease_status_is_effective`.
  bool get isEffective => this == LeaseStatus.active;

  bool get isTerminal => this == LeaseStatus.ended || this == LeaseStatus.cancelled;
}

enum LeaseBillingFrequency { monthly, quarterly, semiannual, annual }

/// Compact projection used by list results.
class LeaseSummaryDto {
  const LeaseSummaryDto({
    required this.id,
    required this.workspaceId,
    required this.propertyId,
    required this.unitId,
    required this.leaseName,
    required this.status,
    required this.startDate,
    required this.baseRentMonthly,
    required this.currencyCode,
    required this.version,
    this.tenantPartyId,
    this.endDate,
  });

  final String id;
  final String workspaceId;
  final String propertyId;
  final String unitId;
  final String leaseName;
  final LeaseStatus status;
  final DateTime startDate;
  final double baseRentMonthly;
  final String currencyCode;
  final int version;

  /// The tenant is a Party role (AGG-005 / P2-D02), not a separate person
  /// master. Null while a draft has not named one.
  final String? tenantPartyId;
  final DateTime? endDate;

  bool get isEffective => status.isEffective;

  /// Whether this lease covers [date] by term. Note this is NOT the same
  /// question as [isEffective]: the rent roll needs both, the AGG-004 invariant
  /// needs only the status.
  bool coversDate(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final from = DateTime.utc(startDate.year, startDate.month, startDate.day);
    if (day.isBefore(from)) {
      return false;
    }
    final until = endDate;
    if (until == null) {
      return true;
    }
    final to = DateTime.utc(until.year, until.month, until.day);
    return !day.isAfter(to);
  }
}

class LeaseDto extends LeaseSummaryDto {
  const LeaseDto({
    required super.id,
    required super.workspaceId,
    required super.propertyId,
    required super.unitId,
    required super.leaseName,
    required super.status,
    required super.startDate,
    required super.baseRentMonthly,
    required super.currencyCode,
    required super.version,
    super.tenantPartyId,
    super.endDate,
    required this.billingFrequency,
    this.moveInDate,
    this.moveOutDate,
    this.signedDate,
    this.noticeDate,
    this.renewalOptionDate,
    this.breakOptionDate,
    this.ancillaryChargesMonthly,
    this.parkingOtherChargesMonthly,
    this.securityDeposit,
    this.paymentDayOfMonth,
    this.rentFreePeriodMonths,
    this.endedAt,
    this.cancelledAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  final LeaseBillingFrequency billingFrequency;
  final DateTime? moveInDate;
  final DateTime? moveOutDate;
  final DateTime? signedDate;
  final DateTime? noticeDate;
  final DateTime? renewalOptionDate;
  final DateTime? breakOptionDate;
  final double? ancillaryChargesMonthly;
  final double? parkingOtherChargesMonthly;
  final double? securityDeposit;
  final int? paymentDayOfMonth;
  final int? rentFreePeriodMonths;

  /// Exactly the terminal status carries its timestamp, so "is this lease over"
  /// has one answer rather than two.
  final DateTime? endedAt;
  final DateTime? cancelledAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;

  /// Base plus the recurring charges that travel with it. Matches the rent-roll
  /// line's per-unit total for a single lease.
  double get totalRentMonthly =>
      baseRentMonthly +
      (ancillaryChargesMonthly ?? 0) +
      (parkingOtherChargesMonthly ?? 0);

  LeaseSummaryDto toSummary() => LeaseSummaryDto(
    id: id,
    workspaceId: workspaceId,
    propertyId: propertyId,
    unitId: unitId,
    leaseName: leaseName,
    status: status,
    startDate: startDate,
    baseRentMonthly: baseRentMonthly,
    currencyCode: currencyCode,
    version: version,
    tenantPartyId: tenantPartyId,
    endDate: endDate,
  );
}

/// Input for creating a lease. A new lease always starts [LeaseStatus.draft];
/// activation is a separate audited transition, because that is the write that
/// changes the unit's occupancy.
class LeaseDraft {
  const LeaseDraft({
    required this.unitId,
    required this.leaseName,
    required this.startDate,
    required this.baseRentMonthly,
    required this.currencyCode,
    this.tenantPartyId,
    this.endDate,
    this.moveInDate,
    this.signedDate,
    this.ancillaryChargesMonthly,
    this.parkingOtherChargesMonthly,
    this.securityDeposit,
    this.paymentDayOfMonth,
    this.billingFrequency = LeaseBillingFrequency.monthly,
    this.rentFreePeriodMonths,
    this.notes,
  });

  final String unitId;
  final String leaseName;
  final DateTime startDate;
  final double baseRentMonthly;
  final String currencyCode;
  final String? tenantPartyId;
  final DateTime? endDate;
  final DateTime? moveInDate;
  final DateTime? signedDate;
  final double? ancillaryChargesMonthly;
  final double? parkingOtherChargesMonthly;
  final double? securityDeposit;
  final int? paymentDayOfMonth;
  final LeaseBillingFrequency billingFrequency;
  final int? rentFreePeriodMonths;
  final String? notes;
}

/// Full desired commercial state for an update; every field is sent, so a null
/// clears and a value sets (whole-record shape, as [UnitUpdateDto]).
///
/// The server only accepts this while the lease is not yet binding: once a
/// lease is active or terminal its terms are not editable in place — a change
/// of terms is a new lease. Attempting it returns `validationFailed`.
///
/// Deliberately absent: `status`, `unitId`, `propertyId`, and the terminal
/// timestamps. Status moves through transitions; the rest are protected columns.
class LeaseUpdateDto {
  const LeaseUpdateDto({
    required this.leaseName,
    required this.startDate,
    required this.baseRentMonthly,
    required this.billingFrequency,
    this.tenantPartyId,
    this.endDate,
    this.moveInDate,
    this.signedDate,
    this.noticeDate,
    this.renewalOptionDate,
    this.breakOptionDate,
    this.ancillaryChargesMonthly,
    this.parkingOtherChargesMonthly,
    this.securityDeposit,
    this.paymentDayOfMonth,
    this.rentFreePeriodMonths,
    this.notes,
  });

  final String leaseName;
  final DateTime startDate;
  final double baseRentMonthly;
  final LeaseBillingFrequency billingFrequency;
  final String? tenantPartyId;
  final DateTime? endDate;
  final DateTime? moveInDate;
  final DateTime? signedDate;
  final DateTime? noticeDate;
  final DateTime? renewalOptionDate;
  final DateTime? breakOptionDate;
  final double? ancillaryChargesMonthly;
  final double? parkingOtherChargesMonthly;
  final double? securityDeposit;
  final int? paymentDayOfMonth;
  final int? rentFreePeriodMonths;
  final String? notes;
}
