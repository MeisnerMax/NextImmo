import 'documents.dart';
import 'task.dart';

class UnitRecord {
  const UnitRecord({
    required this.id,
    required this.assetPropertyId,
    required this.unitCode,
    required this.unitType,
    required this.beds,
    required this.baths,
    required this.sqft,
    required this.floor,
    required this.status,
    required this.targetRentMonthly,
    required this.marketRentMonthly,
    required this.offlineReason,
    required this.vacancySince,
    required this.vacancyReason,
    required this.marketingStatus,
    required this.renovationStatus,
    required this.expectedReadyDate,
    required this.nextAction,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String assetPropertyId;
  final String unitCode;
  final String? unitType;
  final double? beds;
  final double? baths;
  final double? sqft;
  final String? floor;
  final String status;
  final double? targetRentMonthly;
  final double? marketRentMonthly;
  final String? offlineReason;
  final int? vacancySince;
  final String? vacancyReason;
  final String? marketingStatus;
  final String? renovationStatus;
  final int? expectedReadyDate;
  final String? nextAction;
  final String? notes;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'asset_property_id': assetPropertyId,
      'unit_code': unitCode,
      'unit_type': unitType,
      'beds': beds,
      'baths': baths,
      'sqft': sqft,
      'floor': floor,
      'status': status,
      'target_rent_monthly': targetRentMonthly,
      'market_rent_monthly': marketRentMonthly,
      'offline_reason': offlineReason,
      'vacancy_since': vacancySince,
      'vacancy_reason': vacancyReason,
      'marketing_status': marketingStatus,
      'renovation_status': renovationStatus,
      'expected_ready_date': expectedReadyDate,
      'next_action': nextAction,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory UnitRecord.fromMap(Map<String, Object?> map) {
    return UnitRecord(
      id: map['id']! as String,
      assetPropertyId: map['asset_property_id']! as String,
      unitCode: map['unit_code']! as String,
      unitType: map['unit_type'] as String?,
      beds: (map['beds'] as num?)?.toDouble(),
      baths: (map['baths'] as num?)?.toDouble(),
      sqft: (map['sqft'] as num?)?.toDouble(),
      floor: map['floor'] as String?,
      status: map['status']! as String,
      targetRentMonthly: (map['target_rent_monthly'] as num?)?.toDouble(),
      marketRentMonthly: (map['market_rent_monthly'] as num?)?.toDouble(),
      offlineReason: map['offline_reason'] as String?,
      vacancySince: (map['vacancy_since'] as num?)?.toInt(),
      vacancyReason: map['vacancy_reason'] as String?,
      marketingStatus: map['marketing_status'] as String?,
      renovationStatus: map['renovation_status'] as String?,
      expectedReadyDate: (map['expected_ready_date'] as num?)?.toInt(),
      nextAction: map['next_action'] as String?,
      notes: map['notes'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class TenantRecord {
  const TenantRecord({
    required this.id,
    required this.displayName,
    required this.legalName,
    required this.email,
    required this.phone,
    required this.alternativeContact,
    required this.billingContact,
    required this.status,
    required this.moveInReference,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String displayName;
  final String? legalName;
  final String? email;
  final String? phone;
  final String? alternativeContact;
  final String? billingContact;
  final String? status;
  final String? moveInReference;
  final String? notes;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'display_name': displayName,
      'legal_name': legalName,
      'email': email,
      'phone': phone,
      'alternative_contact': alternativeContact,
      'billing_contact': billingContact,
      'status': status,
      'move_in_reference': moveInReference,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory TenantRecord.fromMap(Map<String, Object?> map) {
    return TenantRecord(
      id: map['id']! as String,
      displayName: map['display_name']! as String,
      legalName: map['legal_name'] as String?,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      alternativeContact: map['alternative_contact'] as String?,
      billingContact: map['billing_contact'] as String?,
      status: map['status'] as String? ?? 'active',
      moveInReference: map['move_in_reference'] as String?,
      notes: map['notes'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class LeaseRecord {
  const LeaseRecord({
    required this.id,
    required this.assetPropertyId,
    required this.unitId,
    required this.tenantId,
    required this.leaseName,
    required this.startDate,
    required this.endDate,
    required this.moveInDate,
    required this.moveOutDate,
    required this.status,
    required this.baseRentMonthly,
    required this.currencyCode,
    required this.securityDeposit,
    required this.paymentDayOfMonth,
    required this.billingFrequency,
    required this.leaseSignedDate,
    required this.noticeDate,
    required this.renewalOptionDate,
    required this.breakOptionDate,
    required this.executedDate,
    required this.depositStatus,
    required this.rentFreePeriodMonths,
    required this.ancillaryChargesMonthly,
    required this.parkingOtherChargesMonthly,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String assetPropertyId;
  final String unitId;
  final String? tenantId;
  final String leaseName;
  final int startDate;
  final int? endDate;
  final int? moveInDate;
  final int? moveOutDate;
  final String status;
  final double baseRentMonthly;
  final String currencyCode;
  final double? securityDeposit;
  final int? paymentDayOfMonth;
  final String billingFrequency;
  final int? leaseSignedDate;
  final int? noticeDate;
  final int? renewalOptionDate;
  final int? breakOptionDate;
  final int? executedDate;
  final String? depositStatus;
  final int? rentFreePeriodMonths;
  final double? ancillaryChargesMonthly;
  final double? parkingOtherChargesMonthly;
  final String? notes;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'asset_property_id': assetPropertyId,
      'unit_id': unitId,
      'tenant_id': tenantId,
      'lease_name': leaseName,
      'start_date': startDate,
      'end_date': endDate,
      'move_in_date': moveInDate,
      'move_out_date': moveOutDate,
      'status': status,
      'base_rent_monthly': baseRentMonthly,
      'currency_code': currencyCode,
      'security_deposit': securityDeposit,
      'payment_day_of_month': paymentDayOfMonth,
      'billing_frequency': billingFrequency,
      'lease_signed_date': leaseSignedDate,
      'notice_date': noticeDate,
      'renewal_option_date': renewalOptionDate,
      'break_option_date': breakOptionDate,
      'executed_date': executedDate,
      'deposit_status': depositStatus,
      'rent_free_period_months': rentFreePeriodMonths,
      'ancillary_charges_monthly': ancillaryChargesMonthly,
      'parking_other_charges_monthly': parkingOtherChargesMonthly,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory LeaseRecord.fromMap(Map<String, Object?> map) {
    return LeaseRecord(
      id: map['id']! as String,
      assetPropertyId: map['asset_property_id']! as String,
      unitId: map['unit_id']! as String,
      tenantId: map['tenant_id'] as String?,
      leaseName: map['lease_name']! as String,
      startDate: (map['start_date']! as num).toInt(),
      endDate: (map['end_date'] as num?)?.toInt(),
      moveInDate: (map['move_in_date'] as num?)?.toInt(),
      moveOutDate: (map['move_out_date'] as num?)?.toInt(),
      status: map['status']! as String,
      baseRentMonthly: (map['base_rent_monthly']! as num).toDouble(),
      currencyCode: map['currency_code']! as String,
      securityDeposit: (map['security_deposit'] as num?)?.toDouble(),
      paymentDayOfMonth: (map['payment_day_of_month'] as num?)?.toInt(),
      billingFrequency: (map['billing_frequency'] as String?) ?? 'monthly',
      leaseSignedDate: (map['lease_signed_date'] as num?)?.toInt(),
      noticeDate: (map['notice_date'] as num?)?.toInt(),
      renewalOptionDate: (map['renewal_option_date'] as num?)?.toInt(),
      breakOptionDate: (map['break_option_date'] as num?)?.toInt(),
      executedDate: (map['executed_date'] as num?)?.toInt(),
      depositStatus: map['deposit_status'] as String? ?? 'unknown',
      rentFreePeriodMonths: (map['rent_free_period_months'] as num?)?.toInt(),
      ancillaryChargesMonthly:
          (map['ancillary_charges_monthly'] as num?)?.toDouble(),
      parkingOtherChargesMonthly:
          (map['parking_other_charges_monthly'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class LeaseRentScheduleRecord {
  const LeaseRentScheduleRecord({
    required this.id,
    required this.leaseId,
    required this.periodKey,
    required this.rentMonthly,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final String leaseId;
  final String periodKey;
  final double rentMonthly;
  final String source;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'lease_id': leaseId,
      'period_key': periodKey,
      'rent_monthly': rentMonthly,
      'source': source,
      'created_at': createdAt,
    };
  }

  factory LeaseRentScheduleRecord.fromMap(Map<String, Object?> map) {
    return LeaseRentScheduleRecord(
      id: map['id']! as String,
      leaseId: map['lease_id']! as String,
      periodKey: map['period_key']! as String,
      rentMonthly: (map['rent_monthly']! as num).toDouble(),
      source: map['source']! as String,
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}

class LeaseIndexationRuleRecord {
  const LeaseIndexationRuleRecord({
    required this.id,
    required this.leaseId,
    required this.kind,
    required this.effectiveFromPeriodKey,
    required this.annualPercent,
    required this.fixedStepAmount,
    required this.capPercent,
    required this.floorPercent,
    required this.notes,
    required this.createdAt,
  });

  final String id;
  final String leaseId;
  final String kind;
  final String effectiveFromPeriodKey;
  final double? annualPercent;
  final double? fixedStepAmount;
  final double? capPercent;
  final double? floorPercent;
  final String? notes;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'lease_id': leaseId,
      'kind': kind,
      'effective_from_period_key': effectiveFromPeriodKey,
      'annual_percent': annualPercent,
      'fixed_step_amount': fixedStepAmount,
      'cap_percent': capPercent,
      'floor_percent': floorPercent,
      'notes': notes,
      'created_at': createdAt,
    };
  }

  factory LeaseIndexationRuleRecord.fromMap(Map<String, Object?> map) {
    return LeaseIndexationRuleRecord(
      id: map['id']! as String,
      leaseId: map['lease_id']! as String,
      kind: map['kind']! as String,
      effectiveFromPeriodKey: map['effective_from_period_key']! as String,
      annualPercent: (map['annual_percent'] as num?)?.toDouble(),
      fixedStepAmount: (map['fixed_step_amount'] as num?)?.toDouble(),
      capPercent: (map['cap_percent'] as num?)?.toDouble(),
      floorPercent: (map['floor_percent'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}

class RentRollSnapshotRecord {
  const RentRollSnapshotRecord({
    required this.id,
    required this.assetPropertyId,
    required this.periodKey,
    required this.snapshotAt,
    required this.occupancyRate,
    required this.gprMonthly,
    required this.vacancyLossMonthly,
    required this.egiMonthly,
    required this.inPlaceRentMonthly,
    required this.marketRentMonthly,
    required this.notes,
  });

  final String id;
  final String assetPropertyId;
  final String periodKey;
  final int snapshotAt;
  final double occupancyRate;
  final double gprMonthly;
  final double vacancyLossMonthly;
  final double egiMonthly;
  final double inPlaceRentMonthly;
  final double? marketRentMonthly;
  final String? notes;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'asset_property_id': assetPropertyId,
      'period_key': periodKey,
      'snapshot_at': snapshotAt,
      'occupancy_rate': occupancyRate,
      'gpr_monthly': gprMonthly,
      'vacancy_loss_monthly': vacancyLossMonthly,
      'egi_monthly': egiMonthly,
      'in_place_rent_monthly': inPlaceRentMonthly,
      'market_rent_monthly': marketRentMonthly,
      'notes': notes,
    };
  }

  factory RentRollSnapshotRecord.fromMap(Map<String, Object?> map) {
    return RentRollSnapshotRecord(
      id: map['id']! as String,
      assetPropertyId: map['asset_property_id']! as String,
      periodKey: map['period_key']! as String,
      snapshotAt: (map['snapshot_at']! as num).toInt(),
      occupancyRate: (map['occupancy_rate']! as num).toDouble(),
      gprMonthly: (map['gpr_monthly']! as num).toDouble(),
      vacancyLossMonthly: (map['vacancy_loss_monthly']! as num).toDouble(),
      egiMonthly: (map['egi_monthly']! as num).toDouble(),
      inPlaceRentMonthly: (map['in_place_rent_monthly']! as num).toDouble(),
      marketRentMonthly: (map['market_rent_monthly'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
    );
  }
}

class RentRollLineRecord {
  const RentRollLineRecord({
    required this.id,
    required this.snapshotId,
    required this.unitId,
    required this.leaseId,
    required this.tenantName,
    required this.status,
    required this.inPlaceRentMonthly,
    required this.marketRentMonthly,
    required this.leaseEndDate,
    required this.createdAt,
  });

  final String id;
  final String snapshotId;
  final String unitId;
  final String? leaseId;
  final String? tenantName;
  final String status;
  final double inPlaceRentMonthly;
  final double? marketRentMonthly;
  final int? leaseEndDate;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'snapshot_id': snapshotId,
      'unit_id': unitId,
      'lease_id': leaseId,
      'tenant_name': tenantName,
      'status': status,
      'in_place_rent_monthly': inPlaceRentMonthly,
      'market_rent_monthly': marketRentMonthly,
      'lease_end_date': leaseEndDate,
      'created_at': createdAt,
    };
  }

  factory RentRollLineRecord.fromMap(Map<String, Object?> map) {
    return RentRollLineRecord(
      id: map['id']! as String,
      snapshotId: map['snapshot_id']! as String,
      unitId: map['unit_id']! as String,
      leaseId: map['lease_id'] as String?,
      tenantName: map['tenant_name'] as String?,
      status: map['status']! as String,
      inPlaceRentMonthly: (map['in_place_rent_monthly']! as num).toDouble(),
      marketRentMonthly: (map['market_rent_monthly'] as num?)?.toDouble(),
      leaseEndDate: (map['lease_end_date'] as num?)?.toInt(),
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}

class RentRollSnapshotBundle {
  const RentRollSnapshotBundle({required this.snapshot, required this.lines});

  final RentRollSnapshotRecord snapshot;
  final List<RentRollLineRecord> lines;
}

class OperationsAlertRecord {
  const OperationsAlertRecord({
    this.id,
    required this.type,
    required this.severity,
    required this.message,
    this.propertyId,
    this.unitId,
    this.leaseId,
    this.tenantId,
    this.status = 'open',
    this.createdAt,
    this.resolutionNote,
    this.recommendedAction,
  });

  final String? id;
  final String type;
  final String severity;
  final String message;
  final String? propertyId;
  final String? unitId;
  final String? leaseId;
  final String? tenantId;
  final String status;
  final int? createdAt;
  final String? resolutionNote;
  final String? recommendedAction;
}

class OperationsDataQualityIssue {
  const OperationsDataQualityIssue({
    required this.type,
    required this.severity,
    required this.message,
    required this.recommendedAction,
    required this.propertyId,
    this.unitId,
    this.leaseId,
    this.tenantId,
  });

  final String type;
  final String severity;
  final String message;
  final String recommendedAction;
  final String propertyId;
  final String? unitId;
  final String? leaseId;
  final String? tenantId;
}

class RentRollDeltaRecord {
  const RentRollDeltaRecord({
    required this.inPlaceRentDelta,
    required this.occupancyRateDelta,
  });

  final double inPlaceRentDelta;
  final double occupancyRateDelta;
}

class OperationsOverviewBundle {
  const OperationsOverviewBundle({
    required this.unitsTotal,
    required this.occupiedUnits,
    required this.vacantUnits,
    required this.offlineUnits,
    this.occupiedAreaSqft = 0,
    this.leasedAreaSqft = 0,
    required this.activeLeases,
    required this.expiringIn30Days,
    required this.expiringIn60Days,
    required this.expiringIn90Days,
    required this.expiringIn180Days,
    required this.unitsWithoutActiveLease,
    required this.unitsWithMissingTenantMasterData,
    required this.dataConflicts,
    required this.latestRentRollPeriod,
    required this.rentRollDelta,
    required this.openOperationalAlerts,
    required this.alerts,
    this.dataQualityIssues = const <OperationsDataQualityIssue>[],
  });

  final int unitsTotal;
  final int occupiedUnits;
  final int vacantUnits;
  final int offlineUnits;
  final double occupiedAreaSqft;
  final double leasedAreaSqft;
  final int activeLeases;
  final int expiringIn30Days;
  final int expiringIn60Days;
  final int expiringIn90Days;
  final int expiringIn180Days;
  final int unitsWithoutActiveLease;
  final int unitsWithMissingTenantMasterData;
  final int dataConflicts;
  final String? latestRentRollPeriod;
  final RentRollDeltaRecord? rentRollDelta;
  final int openOperationalAlerts;
  final List<OperationsAlertRecord> alerts;
  final List<OperationsDataQualityIssue> dataQualityIssues;
}

class UnitDetailBundle {
  const UnitDetailBundle({
    required this.unit,
    required this.activeLease,
    required this.leaseHistory,
    required this.activeTenant,
    required this.latestRentRollLine,
    required this.alerts,
    required this.tasks,
    required this.documents,
  });

  final UnitRecord unit;
  final LeaseRecord? activeLease;
  final List<LeaseRecord> leaseHistory;
  final TenantRecord? activeTenant;
  final RentRollLineRecord? latestRentRollLine;
  final List<OperationsAlertRecord> alerts;
  final List<TaskRecord> tasks;
  final List<DocumentRecord> documents;
}

class TenantDetailBundle {
  const TenantDetailBundle({
    required this.tenant,
    required this.activeLeases,
    required this.historicalLeases,
    required this.relatedUnits,
    required this.alerts,
    required this.tasks,
    required this.documents,
    required this.duplicateWarnings,
  });

  final TenantRecord tenant;
  final List<LeaseRecord> activeLeases;
  final List<LeaseRecord> historicalLeases;
  final List<UnitRecord> relatedUnits;
  final List<OperationsAlertRecord> alerts;
  final List<TaskRecord> tasks;
  final List<DocumentRecord> documents;
  final List<String> duplicateWarnings;
}

class LeaseDetailBundle {
  const LeaseDetailBundle({
    required this.lease,
    required this.unit,
    required this.tenant,
    required this.rules,
    required this.schedule,
    required this.latestRentRollLine,
    required this.alerts,
    required this.tasks,
    required this.documents,
  });

  final LeaseRecord lease;
  final UnitRecord? unit;
  final TenantRecord? tenant;
  final List<LeaseIndexationRuleRecord> rules;
  final List<LeaseRentScheduleRecord> schedule;
  final RentRollLineRecord? latestRentRollLine;
  final List<OperationsAlertRecord> alerts;
  final List<TaskRecord> tasks;
  final List<DocumentRecord> documents;
}

class RentRollComputationLine {
  const RentRollComputationLine({
    required this.unit,
    required this.lease,
    required this.tenantName,
    required this.status,
    required this.inPlaceRentMonthly,
    required this.marketRentMonthly,
    required this.leaseEndDate,
  });

  final UnitRecord unit;
  final LeaseRecord? lease;
  final String? tenantName;
  final String status;
  final double inPlaceRentMonthly;
  final double? marketRentMonthly;
  final int? leaseEndDate;
}

class RentRollComputationResult {
  const RentRollComputationResult({
    required this.occupancyRate,
    required this.gprMonthly,
    required this.vacancyLossMonthly,
    required this.egiMonthly,
    required this.inPlaceRentMonthly,
    required this.marketRentMonthly,
    required this.lines,
  });

  final double occupancyRate;
  final double gprMonthly;
  final double vacancyLossMonthly;
  final double egiMonthly;
  final double inPlaceRentMonthly;
  final double? marketRentMonthly;
  final List<RentRollComputationLine> lines;
}
