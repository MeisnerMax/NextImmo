/// Domain DTOs for the Unit aggregate (P2-D05, DOM-004, STM-003, AGG-004).
///
/// A unit is the rentable subdivision of a property. Its [UnitStatus] is
/// **derived**, not set: `vacant`/`occupied` follow from the leases effective on
/// it (AGG-004), and only `offline` is entered by an explicit, reason-carrying
/// transition. The contract mirrors that — there is no way to ask for
/// `occupied`, and the server refuses if you try.
library;

/// STM-003. `vacant` <-> `occupied` is derived from the effective leases;
/// `offline` is the only caller-driven state.
enum UnitStatus { vacant, occupied, offline }

/// Compact projection used by list results.
class UnitSummaryDto {
  const UnitSummaryDto({
    required this.id,
    required this.workspaceId,
    required this.propertyId,
    required this.unitCode,
    required this.status,
    required this.version,
    this.unitType,
    this.floor,
    this.areaSqm,
    this.rooms,
    this.vacancySince,
  });

  final String id;
  final String workspaceId;
  final String propertyId;
  final String unitCode;
  final UnitStatus status;
  final int version;
  final String? unitType;
  final String? floor;
  final double? areaSqm;
  final double? rooms;
  final DateTime? vacancySince;

  bool get isVacant => status == UnitStatus.vacant;
  bool get isOffline => status == UnitStatus.offline;
}

class UnitDto extends UnitSummaryDto {
  const UnitDto({
    required super.id,
    required super.workspaceId,
    required super.propertyId,
    required super.unitCode,
    required super.status,
    required super.version,
    super.unitType,
    super.floor,
    super.areaSqm,
    super.rooms,
    super.vacancySince,
    this.bathrooms,
    this.targetRentMonthly,
    this.marketRentMonthly,
    this.currencyCode,
    this.vacancyReason,
    this.offlineReason,
    this.marketingStatus,
    this.renovationStatus,
    this.expectedReadyDate,
    this.nextAction,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  final double? bathrooms;
  final double? targetRentMonthly;
  final double? marketRentMonthly;

  /// DEC-011: present whenever a money amount is.
  final String? currencyCode;
  final String? vacancyReason;

  /// Only ever set while [status] is [UnitStatus.offline] — the column
  /// describes the current state, it is not a history field.
  final String? offlineReason;
  final String? marketingStatus;
  final String? renovationStatus;
  final DateTime? expectedReadyDate;
  final String? nextAction;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;

  UnitSummaryDto toSummary() => UnitSummaryDto(
    id: id,
    workspaceId: workspaceId,
    propertyId: propertyId,
    unitCode: unitCode,
    status: status,
    version: version,
    unitType: unitType,
    floor: floor,
    areaSqm: areaSqm,
    rooms: rooms,
    vacancySince: vacancySince,
  );
}

/// Input for creating a unit. A new unit always starts [UnitStatus.vacant] —
/// it has no lease yet, and AGG-004 says that is exactly what vacant means.
class UnitDraft {
  const UnitDraft({
    required this.propertyId,
    required this.unitCode,
    this.unitType,
    this.floor,
    this.areaSqm,
    this.rooms,
    this.bathrooms,
    this.targetRentMonthly,
    this.marketRentMonthly,
    this.currencyCode,
    this.marketingStatus,
    this.renovationStatus,
    this.expectedReadyDate,
    this.nextAction,
    this.notes,
  });

  final String propertyId;
  final String unitCode;
  final String? unitType;
  final String? floor;
  final double? areaSqm;
  final double? rooms;
  final double? bathrooms;
  final double? targetRentMonthly;
  final double? marketRentMonthly;
  final String? currencyCode;
  final String? marketingStatus;
  final String? renovationStatus;
  final DateTime? expectedReadyDate;
  final String? nextAction;
  final String? notes;
}

/// Full desired attribute state for an update; every field is sent, so a null
/// clears the field and a value sets it (the whole-record shape of
/// [PartyUpdateDto], not a sparse patch).
///
/// Deliberately absent: `status`, `vacancySince` and `offlineReason`. Status is
/// derived or transitioned, never edited; the other two are maintained by the
/// transition that causes them. Putting them here would offer an edit the
/// server rejects.
class UnitUpdateDto {
  const UnitUpdateDto({
    required this.unitCode,
    this.unitType,
    this.floor,
    this.areaSqm,
    this.rooms,
    this.bathrooms,
    this.targetRentMonthly,
    this.marketRentMonthly,
    this.currencyCode,
    this.vacancyReason,
    this.marketingStatus,
    this.renovationStatus,
    this.expectedReadyDate,
    this.nextAction,
    this.notes,
  });

  final String unitCode;
  final String? unitType;
  final String? floor;
  final double? areaSqm;
  final double? rooms;
  final double? bathrooms;
  final double? targetRentMonthly;
  final double? marketRentMonthly;
  final String? currencyCode;
  final String? vacancyReason;
  final String? marketingStatus;
  final String? renovationStatus;
  final DateTime? expectedReadyDate;
  final String? nextAction;
  final String? notes;
}
