class AssetOperatingCostRecord {
  const AssetOperatingCostRecord({
    required this.id,
    required this.propertyId,
    required this.scope,
    required this.costType,
    this.unitCode,
    this.provider,
    this.contractNumber,
    this.allocationKey,
    this.monthlyAmount,
    this.yearlyAmount,
    this.canceled = false,
    this.startDate,
    this.endDate,
    this.nextDueDate,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String propertyId;
  final String scope;
  final String costType;
  final String? unitCode;
  final String? provider;
  final String? contractNumber;
  final String? allocationKey;
  final double? monthlyAmount;
  final double? yearlyAmount;
  final bool canceled;
  final int? startDate;
  final int? endDate;
  final int? nextDueDate;
  final String? notes;
  final int createdAt;
  final int updatedAt;

  double get yearlyRunRate {
    if (canceled) {
      return 0;
    }
    final yearly = yearlyAmount;
    if (yearly != null) {
      return yearly;
    }
    return (monthlyAmount ?? 0) * 12;
  }

  double get monthlyRunRate {
    if (canceled) {
      return 0;
    }
    final monthly = monthlyAmount;
    if (monthly != null) {
      return monthly;
    }
    return (yearlyAmount ?? 0) / 12;
  }

  double yearlyRunRateForYear(int year) {
    final yearly = yearlyRunRate;
    if (yearly == 0) {
      return 0;
    }
    final yearStart = DateTime(year).millisecondsSinceEpoch;
    final yearEnd = DateTime(year + 1).millisecondsSinceEpoch;
    final activeStart = startDate ?? yearStart;
    final activeEnd =
        endDate == null
            ? yearEnd
            : DateTime.fromMillisecondsSinceEpoch(endDate!)
                .add(const Duration(days: 1))
                .millisecondsSinceEpoch;
    final overlapStart = activeStart > yearStart ? activeStart : yearStart;
    final overlapEnd = activeEnd < yearEnd ? activeEnd : yearEnd;
    if (overlapEnd <= overlapStart) {
      return 0;
    }
    return yearly * ((overlapEnd - overlapStart) / (yearEnd - yearStart));
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'property_id': propertyId,
      'scope': scope,
      'unit_code': unitCode,
      'cost_type': costType,
      'provider': provider,
      'contract_number': contractNumber,
      'allocation_key': allocationKey,
      'monthly_amount': monthlyAmount,
      'yearly_amount': yearlyAmount,
      'canceled': canceled ? 1 : 0,
      'start_date': startDate,
      'end_date': endDate,
      'next_due_date': nextDueDate,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory AssetOperatingCostRecord.fromMap(Map<String, Object?> map) {
    return AssetOperatingCostRecord(
      id: map['id']! as String,
      propertyId: map['property_id']! as String,
      scope: map['scope']! as String,
      unitCode: map['unit_code'] as String?,
      costType: map['cost_type']! as String,
      provider: map['provider'] as String?,
      contractNumber: map['contract_number'] as String?,
      allocationKey: map['allocation_key'] as String?,
      monthlyAmount: (map['monthly_amount'] as num?)?.toDouble(),
      yearlyAmount: (map['yearly_amount'] as num?)?.toDouble(),
      canceled: ((map['canceled'] as num?) ?? 0) == 1,
      startDate: (map['start_date'] as num?)?.toInt(),
      endDate: (map['end_date'] as num?)?.toInt(),
      nextDueDate: (map['next_due_date'] as num?)?.toInt(),
      notes: map['notes'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class AssetOperatingCostHistoryRecord {
  const AssetOperatingCostHistoryRecord({
    required this.id,
    required this.costId,
    required this.propertyId,
    required this.action,
    required this.scope,
    required this.costType,
    this.unitCode,
    this.provider,
    this.contractNumber,
    this.allocationKey,
    this.monthlyAmount,
    this.yearlyAmount,
    this.canceled = false,
    this.startDate,
    this.endDate,
    this.nextDueDate,
    this.notes,
    required this.changedAt,
  });

  final String id;
  final String costId;
  final String propertyId;
  final String action;
  final String scope;
  final String costType;
  final String? unitCode;
  final String? provider;
  final String? contractNumber;
  final String? allocationKey;
  final double? monthlyAmount;
  final double? yearlyAmount;
  final bool canceled;
  final int? startDate;
  final int? endDate;
  final int? nextDueDate;
  final String? notes;
  final int changedAt;

  double get yearlyRunRate {
    if (canceled) {
      return 0;
    }
    final yearly = yearlyAmount;
    if (yearly != null) {
      return yearly;
    }
    return (monthlyAmount ?? 0) * 12;
  }

  factory AssetOperatingCostHistoryRecord.fromMap(Map<String, Object?> map) {
    return AssetOperatingCostHistoryRecord(
      id: map['id']! as String,
      costId: map['cost_id']! as String,
      propertyId: map['property_id']! as String,
      action: map['action']! as String,
      scope: map['scope']! as String,
      unitCode: map['unit_code'] as String?,
      costType: map['cost_type']! as String,
      provider: map['provider'] as String?,
      contractNumber: map['contract_number'] as String?,
      allocationKey: map['allocation_key'] as String?,
      monthlyAmount: (map['monthly_amount'] as num?)?.toDouble(),
      yearlyAmount: (map['yearly_amount'] as num?)?.toDouble(),
      canceled: ((map['canceled'] as num?) ?? 0) == 1,
      startDate: (map['start_date'] as num?)?.toInt(),
      endDate: (map['end_date'] as num?)?.toInt(),
      nextDueDate: (map['next_due_date'] as num?)?.toInt(),
      notes: map['notes'] as String?,
      changedAt: (map['changed_at']! as num).toInt(),
    );
  }
}

class RentalIncomePlanRecord {
  const RentalIncomePlanRecord({
    required this.id,
    required this.propertyId,
    required this.year,
    required this.unitCode,
    this.tenantName,
    this.rentType,
    this.targetRentMonthly,
    this.sideCostsMonthly,
    required this.months,
    this.statusNote,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String propertyId;
  final int year;
  final String unitCode;
  final String? tenantName;
  final String? rentType;
  final double? targetRentMonthly;
  final double? sideCostsMonthly;
  final List<double> months;
  final String? statusNote;
  final int createdAt;
  final int updatedAt;

  double get annualTotal => months.fold<double>(0, (sum, value) => sum + value);

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'property_id': propertyId,
      'year': year,
      'unit_code': unitCode,
      'tenant_name': tenantName,
      'rent_type': rentType,
      'target_rent_monthly': targetRentMonthly,
      'side_costs_monthly': sideCostsMonthly,
      for (var i = 0; i < 12; i++) 'month_${i + 1}': months[i],
      'status_note': statusNote,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory RentalIncomePlanRecord.fromMap(Map<String, Object?> map) {
    return RentalIncomePlanRecord(
      id: map['id']! as String,
      propertyId: map['property_id']! as String,
      year: (map['year']! as num).toInt(),
      unitCode: map['unit_code']! as String,
      tenantName: map['tenant_name'] as String?,
      rentType: map['rent_type'] as String?,
      targetRentMonthly: (map['target_rent_monthly'] as num?)?.toDouble(),
      sideCostsMonthly: (map['side_costs_monthly'] as num?)?.toDouble(),
      months: List<double>.generate(
        12,
        (index) => ((map['month_${index + 1}'] as num?) ?? 0).toDouble(),
      ),
      statusNote: map['status_note'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class HotelKpiRecord {
  const HotelKpiRecord({
    required this.id,
    required this.propertyId,
    required this.periodKey,
    this.roomsTotal,
    this.roomsAvailable,
    this.roomsOccupied,
    this.adr,
    this.revPar,
    this.fbRevenue,
    this.roomRevenue,
    this.totalRevenue,
    this.gopPercent,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String propertyId;
  final String periodKey;
  final int? roomsTotal;
  final int? roomsAvailable;
  final int? roomsOccupied;
  final double? adr;
  final double? revPar;
  final double? fbRevenue;
  final double? roomRevenue;
  final double? totalRevenue;
  final double? gopPercent;
  final String? notes;
  final int createdAt;
  final int updatedAt;

  double? get occupancyRate {
    final available = roomsAvailable;
    if (available == null || available == 0 || roomsOccupied == null) {
      return null;
    }
    return roomsOccupied! / available;
  }

  factory HotelKpiRecord.fromMap(Map<String, Object?> map) {
    return HotelKpiRecord(
      id: map['id']! as String,
      propertyId: map['property_id']! as String,
      periodKey: map['period_key']! as String,
      roomsTotal: (map['rooms_total'] as num?)?.toInt(),
      roomsAvailable: (map['rooms_available'] as num?)?.toInt(),
      roomsOccupied: (map['rooms_occupied'] as num?)?.toInt(),
      adr: (map['adr'] as num?)?.toDouble(),
      revPar: (map['revpar'] as num?)?.toDouble(),
      fbRevenue: (map['fb_revenue'] as num?)?.toDouble(),
      roomRevenue: (map['room_revenue'] as num?)?.toDouble(),
      totalRevenue: (map['total_revenue'] as num?)?.toDouble(),
      gopPercent: (map['gop_percent'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class RenovationProjectRecord {
  const RenovationProjectRecord({
    required this.id,
    required this.propertyId,
    required this.projectCode,
    this.category,
    this.measure,
    required this.status,
    this.startDate,
    this.plannedEndDate,
    this.actualEndDate,
    this.budgetAmount,
    this.actualAmount,
    this.owner,
    this.nextStep,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String propertyId;
  final String projectCode;
  final String? category;
  final String? measure;
  final String status;
  final int? startDate;
  final int? plannedEndDate;
  final int? actualEndDate;
  final double? budgetAmount;
  final double? actualAmount;
  final String? owner;
  final String? nextStep;
  final int createdAt;
  final int updatedAt;

  double get varianceAmount => (actualAmount ?? 0) - (budgetAmount ?? 0);

  factory RenovationProjectRecord.fromMap(Map<String, Object?> map) {
    return RenovationProjectRecord(
      id: map['id']! as String,
      propertyId: map['property_id']! as String,
      projectCode: map['project_code']! as String,
      category: map['category'] as String?,
      measure: map['measure'] as String?,
      status: map['status']! as String,
      startDate: (map['start_date'] as num?)?.toInt(),
      plannedEndDate: (map['planned_end_date'] as num?)?.toInt(),
      actualEndDate: (map['actual_end_date'] as num?)?.toInt(),
      budgetAmount: (map['budget_amount'] as num?)?.toDouble(),
      actualAmount: (map['actual_amount'] as num?)?.toDouble(),
      owner: map['owner'] as String?,
      nextStep: map['next_step'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class ServiceChargeSettlementLine {
  const ServiceChargeSettlementLine({
    required this.costType,
    required this.totalYearlyCost,
    required this.allocationKey,
    required this.allocationShare,
    required this.timeShare,
    required this.tenantShare,
  });

  final String costType;
  final double totalYearlyCost;
  final String allocationKey;
  final double allocationShare;
  final double timeShare;
  final double tenantShare;
}

class AssetWorkbookSourceItem {
  const AssetWorkbookSourceItem({
    required this.sourceSheet,
    required this.label,
    required this.detail,
    required this.count,
    required this.complete,
  });

  final String sourceSheet;
  final String label;
  final String detail;
  final int count;
  final bool complete;
}

class AssetWorkbookPropertySummary {
  const AssetWorkbookPropertySummary({
    required this.id,
    required this.name,
    required this.address,
    required this.propertyType,
    required this.units,
    required this.area,
    required this.yearBuilt,
    required this.statusLabel,
    required this.notes,
  });

  final String id;
  final String name;
  final String address;
  final String propertyType;
  final int units;
  final double? area;
  final int? yearBuilt;
  final String statusLabel;
  final String? notes;
}

class AssetWorkbookBundle {
  const AssetWorkbookBundle({
    required this.propertyId,
    required this.property,
    required this.costs,
    required this.rentalPlans,
    required this.hotelKpis,
    required this.renovations,
    required this.settlementLines,
    required this.settlementSummaries,
    required this.annualRent,
    required this.monthlyRentRunRate,
    required this.annualOperatingCosts,
    required this.openDepositAmount,
    required this.leaseItems,
    required this.depositItems,
    required this.sourceItems,
  });

  final String propertyId;
  final AssetWorkbookPropertySummary property;
  final List<AssetOperatingCostRecord> costs;
  final List<RentalIncomePlanRecord> rentalPlans;
  final List<HotelKpiRecord> hotelKpis;
  final List<RenovationProjectRecord> renovations;
  final List<ServiceChargeSettlementLine> settlementLines;
  final List<ServiceChargeSettlementSummary> settlementSummaries;
  final double annualRent;
  final double monthlyRentRunRate;
  final double annualOperatingCosts;
  final double openDepositAmount;
  final List<LeasePaymentItem> leaseItems;
  final List<LeaseDepositItem> depositItems;
  final List<AssetWorkbookSourceItem> sourceItems;
}

class ServiceChargeSettlementSummary {
  const ServiceChargeSettlementSummary({
    required this.unitCode,
    required this.area,
    required this.allocationShare,
    required this.allocatedCosts,
    required this.directCosts,
    required this.annualPrepayments,
  });

  final String unitCode;
  final double area;
  final double allocationShare;
  final double allocatedCosts;
  final double directCosts;
  final double annualPrepayments;

  double get totalCosts => allocatedCosts + directCosts;

  double get settlementBalance => annualPrepayments - totalCosts;
}

class LeaseDepositItem {
  const LeaseDepositItem({
    required this.leaseName,
    required this.tenantName,
    required this.amount,
    required this.status,
    required this.notes,
  });

  final String leaseName;
  final String tenantName;
  final double amount;
  final String status;
  final String? notes;
}

class LeasePaymentItem {
  const LeasePaymentItem({
    required this.unitCode,
    required this.leaseName,
    required this.tenantName,
    required this.status,
    required this.baseRentMonthly,
    required this.ancillaryChargesMonthly,
    required this.otherChargesMonthly,
    required this.securityDeposit,
    required this.depositStatus,
    required this.notes,
  });

  final String unitCode;
  final String leaseName;
  final String tenantName;
  final String status;
  final double baseRentMonthly;
  final double ancillaryChargesMonthly;
  final double otherChargesMonthly;
  final double securityDeposit;
  final String depositStatus;
  final String? notes;

  double get warmRentMonthly =>
      baseRentMonthly + ancillaryChargesMonthly + otherChargesMonthly;

  double get annualWarmRent => warmRentMonthly * 12;
}

class PortfolioRentalOverviewRow {
  const PortfolioRentalOverviewRow({
    required this.propertyId,
    required this.propertyName,
    required this.propertyType,
    required this.units,
    required this.occupiedUnits,
    required this.vacantUnits,
    required this.annualRent,
    required this.monthlyRentRunRate,
    required this.annualOperatingCosts,
    required this.openDepositAmount,
    required this.serviceChargeBalance,
    required this.ownerLabels,
    required this.sourceAreasComplete,
    required this.sourceAreasTotal,
    required this.missingSourceLabels,
  });

  final String propertyId;
  final String propertyName;
  final String propertyType;
  final int units;
  final int occupiedUnits;
  final int vacantUnits;
  final double annualRent;
  final double monthlyRentRunRate;
  final double annualOperatingCosts;
  final double openDepositAmount;
  final double serviceChargeBalance;
  final List<String> ownerLabels;
  final int sourceAreasComplete;
  final int sourceAreasTotal;
  final List<String> missingSourceLabels;

  double get netAnnualAfterCosts => annualRent - annualOperatingCosts;

  double get sourceCoverageRate =>
      sourceAreasTotal == 0 ? 0 : sourceAreasComplete / sourceAreasTotal;
}

class PortfolioRentalOverview {
  const PortfolioRentalOverview({
    required this.rows,
    required this.assetsTotal,
    required this.assetsNotActive,
    required this.rentedUnits,
    required this.emptyUnits,
    required this.annualRent,
    required this.monthlyRentRunRate,
    required this.annualOperatingCosts,
    required this.openDepositAmount,
    required this.serviceChargeBalance,
    required this.sourceAreasComplete,
    required this.sourceAreasTotal,
  });

  final List<PortfolioRentalOverviewRow> rows;
  final int assetsTotal;
  final int assetsNotActive;
  final int rentedUnits;
  final int emptyUnits;
  final double annualRent;
  final double monthlyRentRunRate;
  final double annualOperatingCosts;
  final double openDepositAmount;
  final double serviceChargeBalance;
  final int sourceAreasComplete;
  final int sourceAreasTotal;

  double get sourceCoverageRate =>
      sourceAreasTotal == 0 ? 0 : sourceAreasComplete / sourceAreasTotal;
}
