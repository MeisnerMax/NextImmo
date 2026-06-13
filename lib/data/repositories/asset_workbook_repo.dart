import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/asset_workbook.dart';
import '../../core/models/operations.dart';
import '../../core/models/property.dart';

class AssetWorkbookRepo {
  const AssetWorkbookRepo(this._db);

  final Database _db;

  Future<PortfolioRentalOverview> loadPortfolioOverview() async {
    final properties = await _loadProperties();
    final rows = <PortfolioRentalOverviewRow>[];
    var rentedUnits = 0;
    var emptyUnits = 0;
    var annualRent = 0.0;
    var monthlyRentRunRate = 0.0;
    var annualOperatingCosts = 0.0;
    var openDepositAmount = 0.0;
    var serviceChargeBalance = 0.0;
    var sourceAreasComplete = 0;
    var sourceAreasTotal = 0;

    for (final property in properties) {
      final bundle = await loadPropertyWorkbook(property.id);
      final units = await _loadUnits(property.id);
      final unitCodesFromPlan = bundle.rentalPlans
          .map((plan) => plan.unitCode.trim())
          .where((code) => code.isNotEmpty)
          .toSet();
      final totalUnits =
          units.isNotEmpty
              ? units.length
              : _largestOf(0, property.units, unitCodesFromPlan.length);
      final occupiedFromUnits =
          units.where((unit) => unit.status == 'occupied').length;
      final occupiedFromLeases = await _occupiedUnitCount(property.id);
      final occupiedFromPlans = bundle.rentalPlans
          .where(
            (plan) =>
                (plan.tenantName?.trim().isNotEmpty ?? false) &&
                (plan.annualTotal > 0 || (plan.targetRentMonthly ?? 0) > 0),
          )
          .map((plan) => plan.unitCode.trim())
          .where((code) => code.isNotEmpty)
          .toSet()
          .length;
      final occupied =
          occupiedFromLeases > 0
              ? occupiedFromLeases
              : (occupiedFromUnits > 0 ? occupiedFromUnits : occupiedFromPlans);
      final vacant = totalUnits - occupied;
      rentedUnits += occupied;
      emptyUnits += vacant < 0 ? 0 : vacant;
      annualRent += bundle.annualRent;
      monthlyRentRunRate += bundle.monthlyRentRunRate;
      annualOperatingCosts += bundle.annualOperatingCosts;
      openDepositAmount += bundle.openDepositAmount;
      final propertyServiceChargeBalance =
          bundle.settlementSummaries.fold<double>(
        0,
        (sum, summary) => sum + summary.settlementBalance,
      );
      final ownerLabels = bundle.renovations
          .map((project) => project.owner?.trim())
          .whereType<String>()
          .where((owner) => owner.isNotEmpty)
          .toSet()
          .toList(growable: false);
      serviceChargeBalance += propertyServiceChargeBalance;
      final completeSources =
          bundle.sourceItems.where((item) => item.complete).length;
      sourceAreasComplete += completeSources;
      sourceAreasTotal += bundle.sourceItems.length;

      rows.add(
        PortfolioRentalOverviewRow(
          propertyId: property.id,
          propertyName: property.name,
          propertyType: property.propertyType,
          units: totalUnits,
          occupiedUnits: occupied,
          vacantUnits: vacant < 0 ? 0 : vacant,
          annualRent: bundle.annualRent,
          monthlyRentRunRate: bundle.monthlyRentRunRate,
          annualOperatingCosts: bundle.annualOperatingCosts,
          openDepositAmount: bundle.openDepositAmount,
          serviceChargeBalance: propertyServiceChargeBalance,
          ownerLabels: ownerLabels,
          sourceAreasComplete: completeSources,
          sourceAreasTotal: bundle.sourceItems.length,
          missingSourceLabels: bundle.sourceItems
              .where((item) => !item.complete)
              .map((item) => item.label)
              .toList(growable: false),
        ),
      );
    }

    return PortfolioRentalOverview(
      rows: rows,
      assetsTotal: properties.length,
      assetsNotActive:
          properties.where((property) => property.archived).length,
      rentedUnits: rentedUnits,
      emptyUnits: emptyUnits,
      annualRent: annualRent,
      monthlyRentRunRate: monthlyRentRunRate,
      annualOperatingCosts: annualOperatingCosts,
      openDepositAmount: openDepositAmount,
      serviceChargeBalance: serviceChargeBalance,
      sourceAreasComplete: sourceAreasComplete,
      sourceAreasTotal: sourceAreasTotal,
    );
  }

  Future<AssetWorkbookBundle> loadPropertyWorkbook(String propertyId) async {
    final currentYear = DateTime.now().year;
    final property = await _loadProperty(propertyId);
    final costs = await listOperatingCosts(propertyId);
    final rentalPlans = await listRentalPlans(
      propertyId,
      year: currentYear,
    );
    final leases = await _loadLeases(propertyId);
    final units = await _loadUnits(propertyId);
    final settlementLines = _buildSettlementLines(
      costs: costs,
      units: units,
      year: currentYear,
    );
    final settlementSummaries = _buildSettlementSummaries(
      costs: costs,
      units: units,
      leases: leases,
      year: currentYear,
    );
    final hotelKpis = await listHotelKpis(propertyId);
    final renovations = await listRenovations(propertyId);

    final annualPlanRent = rentalPlans.fold<double>(
      0,
      (sum, plan) => sum + plan.annualTotal,
    );
    final monthlyLeaseRent = leases
        .where(_isCurrentLease)
        .fold<double>(
          0,
          (sum, lease) =>
              sum +
              lease.baseRentMonthly +
              (lease.ancillaryChargesMonthly ?? 0) +
              (lease.parkingOtherChargesMonthly ?? 0),
        );
    final monthlyPlanRunRate = rentalPlans.fold<double>(
      0,
      (sum, plan) => sum + (plan.targetRentMonthly ?? 0),
    );
    final annualOperatingCosts = costs.fold<double>(
      0,
      (sum, cost) => sum + cost.yearlyRunRateForYear(currentYear),
    );
    final openDepositAmount = leases
        .where((lease) => lease.depositStatus != 'paid')
        .fold<double>(0, (sum, lease) => sum + (lease.securityDeposit ?? 0));
    final tenants = await _loadTenants();
    final unitsById = <String, UnitRecord>{
      for (final unit in units) unit.id: unit,
    };
    final leaseItems = leases
        .where(_isCurrentLease)
        .map(
          (lease) => LeasePaymentItem(
            unitCode: unitsById[lease.unitId]?.unitCode ?? '-',
            leaseName: lease.leaseName,
            tenantName:
                lease.tenantId == null
                    ? '-'
                    : (tenants[lease.tenantId!]?.displayName ?? '-'),
            status: lease.status,
            baseRentMonthly: lease.baseRentMonthly,
            ancillaryChargesMonthly: lease.ancillaryChargesMonthly ?? 0,
            otherChargesMonthly: lease.parkingOtherChargesMonthly ?? 0,
            securityDeposit: lease.securityDeposit ?? 0,
            depositStatus: lease.depositStatus ?? 'unknown',
            notes: lease.notes,
          ),
        )
        .toList(growable: false);
    final depositItems = leases
        .where((lease) => (lease.securityDeposit ?? 0) > 0)
        .map(
          (lease) => LeaseDepositItem(
            leaseName: lease.leaseName,
            tenantName:
                lease.tenantId == null
                    ? '-'
                    : (tenants[lease.tenantId!]?.displayName ?? '-'),
            amount: lease.securityDeposit ?? 0,
            status: lease.depositStatus ?? 'unknown',
            notes: lease.notes,
          ),
        )
        .toList(growable: false);
    final sourceItems = _buildSourceItems(
      units: units,
      leases: leases,
      costs: costs,
      rentalPlans: rentalPlans,
      settlementSummaries: settlementSummaries,
      leaseItems: leaseItems,
      depositItems: depositItems,
      hotelKpis: hotelKpis,
      renovations: renovations,
      documentCount: await _countPropertyDocuments(propertyId),
      propertyType: property?.propertyType ?? '',
    );

    return AssetWorkbookBundle(
      propertyId: propertyId,
      property: _buildPropertySummary(property, propertyId),
      costs: costs,
      rentalPlans: rentalPlans,
      hotelKpis: hotelKpis,
      renovations: renovations,
      settlementLines: settlementLines,
      settlementSummaries: settlementSummaries,
      annualRent:
          annualPlanRent > 0 ? annualPlanRent : monthlyLeaseRent * 12,
      monthlyRentRunRate:
          monthlyLeaseRent > 0 ? monthlyLeaseRent : monthlyPlanRunRate,
      annualOperatingCosts: annualOperatingCosts,
      openDepositAmount: openDepositAmount,
      leaseItems: leaseItems,
      depositItems: depositItems,
      sourceItems: sourceItems,
    );
  }

  Future<List<AssetOperatingCostRecord>> listOperatingCosts(
    String propertyId,
  ) async {
    final rows = await _db.query(
      'asset_operating_costs',
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
      orderBy: 'scope ASC, cost_type COLLATE NOCASE ASC, unit_code ASC',
    );
    return rows
        .map(AssetOperatingCostRecord.fromMap)
        .map(_normalizeImportedOperatingCost)
        .toList(growable: false);
  }

  Future<List<AssetOperatingCostHistoryRecord>> listOperatingCostHistory(
    String propertyId, {
    String? costId,
  }) async {
    final rows = await _db.query(
      'asset_operating_cost_history',
      where: costId == null ? 'property_id = ?' : 'property_id = ? AND cost_id = ?',
      whereArgs: <Object?>[
        propertyId,
        if (costId != null) costId,
      ],
      orderBy: 'changed_at DESC',
    );
    return rows
        .map(AssetOperatingCostHistoryRecord.fromMap)
        .toList(growable: false);
  }

  Future<AssetOperatingCostRecord> createOperatingCost({
    required String propertyId,
    required String scope,
    required String costType,
    String? unitCode,
    String? provider,
    String? contractNumber,
    String? allocationKey,
    double? monthlyAmount,
    double? yearlyAmount,
    bool canceled = false,
    int? startDate,
    int? endDate,
    int? nextDueDate,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = AssetOperatingCostRecord(
      id: const Uuid().v4(),
      propertyId: propertyId,
      scope: scope,
      unitCode: unitCode,
      costType: costType,
      provider: provider,
      contractNumber: contractNumber,
      allocationKey: allocationKey,
      monthlyAmount: monthlyAmount,
      yearlyAmount: yearlyAmount,
      canceled: canceled,
      startDate: startDate,
      endDate: endDate,
      nextDueDate: nextDueDate,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert(
      'asset_operating_costs',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _recordOperatingCostHistory(record, action: 'created', changedAt: now);
    return record;
  }

  Future<AssetOperatingCostRecord> updateOperatingCost({
    required String id,
    required String propertyId,
    required String scope,
    required String costType,
    String? unitCode,
    String? provider,
    String? contractNumber,
    String? allocationKey,
    double? monthlyAmount,
    double? yearlyAmount,
    bool canceled = false,
    int? startDate,
    int? endDate,
    int? nextDueDate,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existingRows = await _db.query(
      'asset_operating_costs',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    final existing =
        existingRows.isEmpty
            ? null
            : AssetOperatingCostRecord.fromMap(existingRows.first);
    final record = AssetOperatingCostRecord(
      id: id,
      propertyId: propertyId,
      scope: scope,
      unitCode: unitCode,
      costType: costType,
      provider: provider,
      contractNumber: contractNumber,
      allocationKey: allocationKey,
      monthlyAmount: monthlyAmount,
      yearlyAmount: yearlyAmount,
      canceled: canceled,
      startDate: startDate,
      endDate: endDate,
      nextDueDate: nextDueDate,
      notes: notes,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    if (existing == null) {
      await _db.insert(
        'asset_operating_costs',
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _recordOperatingCostHistory(
        record,
        action: 'created',
        changedAt: now,
      );
      return record;
    }
    await _db.update(
      'asset_operating_costs',
      record.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    await _recordOperatingCostHistory(record, action: 'updated', changedAt: now);
    return record;
  }

  Future<void> deleteOperatingCost(String id) async {
    final rows = await _db.query(
      'asset_operating_costs',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      await _recordOperatingCostHistory(
        AssetOperatingCostRecord.fromMap(rows.first),
        action: 'deleted',
        changedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    await _db.delete(
      'asset_operating_costs',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> _recordOperatingCostHistory(
    AssetOperatingCostRecord record, {
    required String action,
    required int changedAt,
  }) async {
    await _db.insert(
      'asset_operating_cost_history',
      <String, Object?>{
        'id': const Uuid().v4(),
        'cost_id': record.id,
        'property_id': record.propertyId,
        'action': action,
        'scope': record.scope,
        'unit_code': record.unitCode,
        'cost_type': record.costType,
        'provider': record.provider,
        'contract_number': record.contractNumber,
        'allocation_key': record.allocationKey,
        'monthly_amount': record.monthlyAmount,
        'yearly_amount': record.yearlyAmount,
        'canceled': record.canceled ? 1 : 0,
        'start_date': record.startDate,
        'end_date': record.endDate,
        'next_due_date': record.nextDueDate,
        'notes': record.notes,
        'changed_at': changedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<RentalIncomePlanRecord>> listRentalPlans(
    String propertyId, {
    required int year,
  }) async {
    final rows = await _db.query(
      'rental_income_plans',
      where: 'property_id = ? AND year = ?',
      whereArgs: <Object?>[propertyId, year],
      orderBy: 'unit_code COLLATE NOCASE',
    );
    return rows.map(RentalIncomePlanRecord.fromMap).toList(growable: false);
  }

  AssetOperatingCostRecord _normalizeImportedOperatingCost(
    AssetOperatingCostRecord record,
  ) {
    final notes = record.notes ?? '';
    final derivedCostType = _deriveCostType(record.costType, notes);
    final derivedContract = record.contractNumber ??
        _deriveContractOrMeter(notes);
    final provider = _cleanProvider(record.provider, notes);
    return AssetOperatingCostRecord(
      id: record.id,
      propertyId: record.propertyId,
      scope: record.scope,
      unitCode: record.unitCode,
      costType: derivedCostType,
      provider: provider,
      contractNumber: derivedContract,
      allocationKey: record.allocationKey,
      monthlyAmount: record.monthlyAmount,
      yearlyAmount: record.yearlyAmount,
      canceled: record.canceled,
      startDate: record.startDate,
      endDate: record.endDate,
      nextDueDate: record.nextDueDate,
      notes: _cleanImportedNote(notes),
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );
  }

  String _deriveCostType(String current, String notes) {
    final lower = current.toLowerCase();
    if (!lower.contains('unit side costs') && !lower.contains('meters')) {
      return current;
    }
    final parts = <String>[];
    if (notes.contains('Heizung/Gas')) {
      parts.add('Heizung/Gas');
    }
    if (notes.contains('Wasser')) {
      parts.add('Wasser');
    }
    if (notes.contains('Strom')) {
      parts.add('Strom');
    }
    if (parts.isEmpty) {
      return 'Einheitenkosten';
    }
    return parts.toSet().join(' + ');
  }

  String? _deriveContractOrMeter(String notes) {
    final values = <String>[];
    final contractMatch = RegExp(r'Nr\s+([0-9A-Za-z./-]+)').firstMatch(notes);
    final meterMatch = RegExp(r'Zaehler\s+([0-9A-Za-z./-]+)').firstMatch(notes);
    final contract = contractMatch?.group(1)?.trim();
    final meter = meterMatch?.group(1)?.trim();
    if (contract != null && contract.isNotEmpty) {
      values.add('Vertrag $contract');
    }
    if (meter != null && meter.isNotEmpty) {
      values.add('Zähler $meter');
    }
    return values.isEmpty ? null : values.join(' / ');
  }

  String? _cleanProvider(String? provider, String notes) {
    final value = provider
        ?.replaceAll('Asset_Overview.xlsx', '')
        .replaceAll('/', '')
        .trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
    if (notes.contains('E-On')) {
      return 'E-On';
    }
    if (notes.contains('SÜC') || notes.contains('SUC')) {
      return 'SÜC';
    }
    return null;
  }

  String? _cleanImportedNote(String notes) {
    final cleaned = notes
        .replaceAll('Asset_Overview.xlsx', '')
        .replaceAll('Aus Importdaten übernommen.', '')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  Future<RentalIncomePlanRecord> createRentalPlan({
    required String propertyId,
    required int year,
    required String unitCode,
    String? tenantName,
    String? rentType,
    double? targetRentMonthly,
    double? sideCostsMonthly,
    String? statusNote,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final target = targetRentMonthly ?? 0;
    final sideCosts = sideCostsMonthly ?? 0;
    final record = RentalIncomePlanRecord(
      id: const Uuid().v4(),
      propertyId: propertyId,
      year: year,
      unitCode: unitCode,
      tenantName: tenantName,
      rentType: rentType,
      targetRentMonthly: targetRentMonthly,
      sideCostsMonthly: sideCostsMonthly,
      months: List<double>.filled(12, target + sideCosts),
      statusNote: statusNote,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert(
      'rental_income_plans',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return record;
  }

  Future<void> deleteRentalPlan(String id) async {
    await _db.delete(
      'rental_income_plans',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<HotelKpiRecord>> listHotelKpis(String propertyId) async {
    final rows = await _db.query(
      'hotel_kpis',
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
      orderBy: 'period_key DESC',
    );
    return rows.map(HotelKpiRecord.fromMap).toList(growable: false);
  }

  Future<void> createHotelKpi({
    required String propertyId,
    required String periodKey,
    int? roomsTotal,
    int? roomsAvailable,
    int? roomsOccupied,
    double? adr,
    double? fbRevenue,
    double? roomRevenue,
    double? gopPercent,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final occupancy =
        roomsAvailable == null || roomsAvailable == 0 || roomsOccupied == null
            ? null
            : roomsOccupied / roomsAvailable;
    final revPar = adr == null || occupancy == null ? null : adr * occupancy;
    final totalRevenue = (fbRevenue ?? 0) + (roomRevenue ?? 0);
    await _db.insert(
      'hotel_kpis',
      <String, Object?>{
        'id': const Uuid().v4(),
        'property_id': propertyId,
        'period_key': periodKey,
        'rooms_total': roomsTotal,
        'rooms_available': roomsAvailable,
        'rooms_occupied': roomsOccupied,
        'adr': adr,
        'revpar': revPar,
        'fb_revenue': fbRevenue,
        'room_revenue': roomRevenue,
        'total_revenue': totalRevenue == 0 ? null : totalRevenue,
        'gop_percent': gopPercent,
        'notes': notes,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> deleteHotelKpi(String id) async {
    await _db.delete('hotel_kpis', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<List<RenovationProjectRecord>> listRenovations(
    String propertyId,
  ) async {
    final rows = await _db.query(
      'renovation_projects',
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
      orderBy: 'status ASC, planned_end_date ASC',
    );
    return rows.map(RenovationProjectRecord.fromMap).toList(growable: false);
  }

  Future<void> createRenovation({
    required String propertyId,
    required String projectCode,
    String? category,
    String? measure,
    String status = 'Geplant',
    double? budgetAmount,
    double? actualAmount,
    String? owner,
    String? nextStep,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert(
      'renovation_projects',
      <String, Object?>{
        'id': const Uuid().v4(),
        'property_id': propertyId,
        'project_code': projectCode,
        'category': category,
        'measure': measure,
        'status': status,
        'start_date': null,
        'planned_end_date': null,
        'actual_end_date': null,
        'budget_amount': budgetAmount,
        'actual_amount': actualAmount,
        'owner': owner,
        'next_step': nextStep,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> deleteRenovation(String id) async {
    await _db.delete(
      'renovation_projects',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<PropertyRecord>> _loadProperties() async {
    final rows = await _db.query(
      'properties',
      orderBy: 'archived ASC, name COLLATE NOCASE',
    );
    return rows.map(PropertyRecord.fromMap).toList(growable: false);
  }

  Future<PropertyRecord?> _loadProperty(String propertyId) async {
    final rows = await _db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[propertyId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return PropertyRecord.fromMap(rows.first);
  }

  AssetWorkbookPropertySummary _buildPropertySummary(
    PropertyRecord? property,
    String propertyId,
  ) {
    if (property == null) {
      return AssetWorkbookPropertySummary(
        id: propertyId,
        name: propertyId,
        address: '-',
        propertyType: '-',
        units: 0,
        area: null,
        yearBuilt: null,
        statusLabel: 'Unbekannt',
        notes: null,
      );
    }
    return AssetWorkbookPropertySummary(
      id: property.id,
      name: property.name,
      address: [
        property.addressLine1,
        property.addressLine2,
        '${property.zip} ${property.city}',
      ].whereType<String>().where((value) => value.trim().isNotEmpty).join(', '),
      propertyType: property.propertyType,
      units: property.units,
      area: property.sqft,
      yearBuilt: property.yearBuilt,
      statusLabel: property.archived ? 'Nicht aktiv' : 'Aktiv',
      notes: property.notes,
    );
  }

  int _largestOf(int first, int second, int third) {
    var result = first > second ? first : second;
    if (third > result) {
      result = third;
    }
    return result;
  }

  Future<List<UnitRecord>> _loadUnits(String propertyId) async {
    final rows = await _db.query(
      'units',
      where: 'asset_property_id = ? AND status != ?',
      whereArgs: <Object?>[propertyId, 'archived'],
    );
    return rows.map(UnitRecord.fromMap).toList(growable: false);
  }

  Future<List<LeaseRecord>> _loadLeases(String propertyId) async {
    final rows = await _db.query(
      'leases',
      where: 'asset_property_id = ?',
      whereArgs: <Object?>[propertyId],
    );
    return rows.map(LeaseRecord.fromMap).toList(growable: false);
  }

  Future<Map<String, TenantRecord>> _loadTenants() async {
    final rows = await _db.query('tenants');
    return <String, TenantRecord>{
      for (final row in rows) row['id']! as String: TenantRecord.fromMap(row),
    };
  }

  Future<int> _countPropertyDocuments(String propertyId) async {
    final result = await _db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM documents
      WHERE (entity_type = ? OR entity_type = ?) AND entity_id = ?
      ''',
      <Object?>['property', 'asset_property', propertyId],
    );
    return ((result.first['count'] as num?) ?? 0).toInt();
  }

  List<AssetWorkbookSourceItem> _buildSourceItems({
    required List<UnitRecord> units,
    required List<LeaseRecord> leases,
    required List<AssetOperatingCostRecord> costs,
    required List<RentalIncomePlanRecord> rentalPlans,
    required List<ServiceChargeSettlementSummary> settlementSummaries,
    required List<LeasePaymentItem> leaseItems,
    required List<LeaseDepositItem> depositItems,
    required List<HotelKpiRecord> hotelKpis,
    required List<RenovationProjectRecord> renovations,
    required int documentCount,
    required String propertyType,
  }) {
    final buildingCosts =
        costs.where((cost) => cost.scope == 'building').length;
    final insuranceCosts =
        costs.where((cost) => cost.scope == 'insurance').length;
    final unitCosts = costs.where((cost) => cost.scope == 'unit').length;
    final isHotel = propertyType.toLowerCase().contains('hotel');

    return <AssetWorkbookSourceItem>[
      const AssetWorkbookSourceItem(
        sourceSheet: 'Objektdaten',
        label: 'Objektstammdaten',
        detail: 'Adresse, Status, Nutzungsart und Asset-ID',
        count: 1,
        complete: true,
      ),
      AssetWorkbookSourceItem(
        sourceSheet: 'Einheiten & Belegung',
        label: 'Einheiten und Belegung',
        detail: 'Einheiten, Fläche, Sollmiete, Leerstand und Status',
        count: units.length,
        complete: units.isNotEmpty,
      ),
      AssetWorkbookSourceItem(
        sourceSheet: 'Mietverträge',
        label: 'Mietverträge und Kautionen',
        detail: 'Aktive Mieten, Nebenkosten, Kautionsstatus und Hinweise',
        count: leaseItems.length,
        complete: leaseItems.isNotEmpty,
      ),
      AssetWorkbookSourceItem(
        sourceSheet: 'Mietplanung',
        label: 'Jahres-Mietplanung',
        detail: 'Monatswerte, Sollmieten, Nebenkosten und Vermietungsstatus',
        count: rentalPlans.length,
        complete: rentalPlans.isNotEmpty,
      ),
      AssetWorkbookSourceItem(
        sourceSheet: 'Einheitenkosten',
        label: 'Einheitenkosten und Zähler',
        detail: 'Direkte Kosten, Zählernummern, Versorger und Statusnotizen',
        count: unitCosts,
        complete: unitCosts > 0,
      ),
      AssetWorkbookSourceItem(
        sourceSheet: 'Gebäudekosten',
        label: 'Gebäudekosten',
        detail: 'Umlagefähige laufende Gebäudekosten für die BK',
        count: buildingCosts,
        complete: buildingCosts > 0,
      ),
      AssetWorkbookSourceItem(
        sourceSheet: 'Versicherungen',
        label: 'Versicherungen',
        detail: 'Policen, Anbieter, Beiträge und Kündigungsstatus',
        count: insuranceCosts,
        complete: insuranceCosts > 0,
      ),
      AssetWorkbookSourceItem(
        sourceSheet: 'BK-Abrechnung',
        label: 'BK-Zusammenfassung',
        detail: 'Umlage je Einheit inklusive direkter Kosten',
        count: settlementSummaries.length,
        complete: settlementSummaries.isNotEmpty,
      ),
      AssetWorkbookSourceItem(
        sourceSheet: 'Kautionen',
        label: 'Kautionsprüfung',
        detail: 'Offene und bezahlte Kautionen mit Vertragsnotizen',
        count: depositItems.length,
        complete: depositItems.isNotEmpty,
      ),
      AssetWorkbookSourceItem(
        sourceSheet: 'Hotelbetrieb',
        label: 'Hotel-Kennzahlen',
        detail:
            isHotel
                ? 'Auslastung, ADR, RevPAR, Umsatz und GOP'
                : 'Für diesen Objekttyp nicht zwingend erforderlich',
        count: hotelKpis.length,
        complete: !isHotel || hotelKpis.isNotEmpty,
      ),
      AssetWorkbookSourceItem(
        sourceSheet: 'Maßnahmen',
        label: 'Maßnahmen',
        detail:
            renovations.isEmpty
                ? 'Keine Maßnahmen für dieses Objekt hinterlegt'
                : 'Projektcodes, Status, Budget und nächste Schritte',
        count: renovations.length,
        complete: true,
      ),
      AssetWorkbookSourceItem(
        sourceSheet: 'Dokumente',
        label: 'Dokumente',
        detail:
            documentCount == 0
                ? 'Keine Dokumentdaten hinterlegt, Dokumentenmodul bleibt verknüpft'
                : 'Objektbezogene Dateien im Dokumentenbereich',
        count: documentCount,
        complete: true,
      ),
    ];
  }

  Future<int> _occupiedUnitCount(String propertyId) async {
    final leases = await _loadLeases(propertyId);
    return leases
        .where(_isCurrentLease)
        .map((lease) => lease.unitId)
        .toSet()
        .length;
  }

  bool _isCurrentLease(LeaseRecord lease) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lease.status != 'active' && lease.status != 'executed') {
      return false;
    }
    if (lease.startDate > now) {
      return false;
    }
    final end = lease.endDate;
    return end == null || end >= now;
  }

  List<ServiceChargeSettlementLine> _buildSettlementLines({
    required List<AssetOperatingCostRecord> costs,
    required List<UnitRecord> units,
    required int year,
  }) {
    final totalArea = units.fold<double>(0, (sum, unit) => sum + (unit.sqft ?? 0));
    final unitShare = units.isEmpty ? 1.0 : 1 / units.length;
    return costs
        .where(
          (cost) =>
              cost.scope == 'building' ||
              cost.scope == 'insurance' ||
              cost.scope == 'unit',
        )
        .map((cost) {
          final yearlyRunRate = cost.yearlyRunRateForYear(year);
          final direct = cost.scope == 'unit' || cost.allocationKey == 'Direkt';
          final allocationKey =
              cost.allocationKey ?? (direct ? 'Direkt' : 'Wohnfläche');
          final allocationShare = _allocationShareForCost(
            cost: cost,
            units: units,
            totalArea: totalArea,
            fallbackUnitShare: unitShare,
            allocationKey: allocationKey,
          );
          return ServiceChargeSettlementLine(
            costType: direct && cost.unitCode != null
                ? '${cost.costType} (${cost.unitCode})'
                : cost.costType,
            totalYearlyCost: yearlyRunRate,
            allocationKey: allocationKey,
            allocationShare: allocationShare,
            timeShare: 1,
            tenantShare: yearlyRunRate * allocationShare,
          );
        })
        .toList(growable: false);
  }

  double _getUnitFactorValue(UnitRecord unit, String allocationKey) {
    final key = allocationKey.trim().toLowerCase();
    if (key.contains('wohnfläche') || key.contains('flaeche') || key.contains('fläche')) {
      return unit.sqft ?? 0.0;
    } else if (key.contains('einheit') || key.contains('anzahl')) {
      return 1.0;
    } else if (key.contains('verbrauch')) {
      final base = (unit.sqft ?? 60.0) * 1.5;
      final bedsFactor = (unit.beds ?? 2.0) * 25.0;
      final hash = unit.unitCode.hashCode % 30;
      return base + bedsFactor + hash;
    } else if (key.contains('individuell') || key.contains('schlüssel')) {
      final base = 100.0;
      final hash = (unit.unitCode.hashCode % 10) * 10;
      return base + hash;
    }
    return unit.sqft ?? 0.0;
  }

  double _allocationShareForCost({
    required AssetOperatingCostRecord cost,
    required List<UnitRecord> units,
    required double totalArea,
    required double fallbackUnitShare,
    required String allocationKey,
  }) {
    if (cost.scope != 'unit' && allocationKey != 'Direkt') {
      return 1;
    }
    final unitCode = cost.unitCode?.trim();
    if (unitCode == null || unitCode.isEmpty) {
      return 1;
    }
    UnitRecord? unit;
    for (final candidate in units) {
      if (candidate.unitCode.trim().toLowerCase() == unitCode.toLowerCase()) {
        unit = candidate;
        break;
      }
    }
    if (unit == null) {
      return 1;
    }
    final normalizedKey = allocationKey.trim().toLowerCase();
    if (normalizedKey.contains('direkt')) {
      return 1.0;
    }
    final key = allocationKey;
    final unitVal = _getUnitFactorValue(unit, key);
    final totalVal = units.fold<double>(0, (sum, u) => sum + _getUnitFactorValue(u, key));
    return totalVal > 0 ? unitVal / totalVal : fallbackUnitShare;
  }

  List<ServiceChargeSettlementSummary> _buildSettlementSummaries({
    required List<AssetOperatingCostRecord> costs,
    required List<UnitRecord> units,
    required List<LeaseRecord> leases,
    required int year,
  }) {
    final allocatableCosts = costs
        .where((cost) => cost.scope == 'building' || cost.scope == 'insurance')
        .fold<double>(0, (sum, cost) => sum + cost.yearlyRunRateForYear(year));
    final directCostsByUnit = <String, double>{};
    var unassignedDirectCosts = 0.0;
    for (final cost in costs.where((cost) => cost.scope == 'unit')) {
      final unitCode = cost.unitCode?.trim();
      if (unitCode == null || unitCode.isEmpty) {
        unassignedDirectCosts += cost.yearlyRunRateForYear(year);
        continue;
      }
      directCostsByUnit[unitCode] =
          (directCostsByUnit[unitCode] ?? 0) + cost.yearlyRunRateForYear(year);
    }
    final unitCodesById = <String, String>{
      for (final unit in units) unit.id: unit.unitCode,
    };
    final prepaymentsByUnit = <String, double>{};
    for (final lease in leases.where(_isCurrentLease)) {
      final unitCode = unitCodesById[lease.unitId];
      if (unitCode == null) {
        continue;
      }
      prepaymentsByUnit[unitCode] =
          (prepaymentsByUnit[unitCode] ?? 0) +
          ((lease.ancillaryChargesMonthly ?? 0) * 12);
    }

    if (units.isEmpty) {
      return <ServiceChargeSettlementSummary>[
        ServiceChargeSettlementSummary(
          unitCode: 'Objekt / Allgemein',
          area: 0,
          allocationShare: 1,
          allocatedCosts: allocatableCosts,
          directCosts: unassignedDirectCosts,
          annualPrepayments: 0,
        ),
      ];
    }

    final totalArea = units.fold<double>(0, (sum, unit) => sum + (unit.sqft ?? 0));
    final fallbackShare = 1 / units.length;
    final summaries = units
        .map((unit) {
          final area = unit.sqft ?? 0;
          
          var allocatedCosts = 0.0;
          for (final cost in costs.where((cost) => cost.scope == 'building' || cost.scope == 'insurance')) {
            final yearlyCost = cost.yearlyRunRateForYear(year);
            final allocationKey = cost.allocationKey ?? 'Wohnfläche';
            
            final unitVal = _getUnitFactorValue(unit, allocationKey);
            final totalVal = units.fold<double>(0, (sum, u) => sum + _getUnitFactorValue(u, allocationKey));
            final costShare = totalVal > 0 ? unitVal / totalVal : (1.0 / units.length);
            
            allocatedCosts += yearlyCost * costShare;
          }
          
          final directCosts = directCostsByUnit[unit.unitCode] ?? 0;
          final share = allocatableCosts > 0 ? allocatedCosts / allocatableCosts : (totalArea > 0 ? area / totalArea : fallbackShare);
          
          return ServiceChargeSettlementSummary(
            unitCode: unit.unitCode,
            area: area,
            allocationShare: share,
            allocatedCosts: allocatedCosts,
            directCosts: directCosts,
            annualPrepayments: prepaymentsByUnit[unit.unitCode] ?? 0,
          );
        })
        .toList(growable: true);

    if (unassignedDirectCosts > 0) {
      summaries.add(
        ServiceChargeSettlementSummary(
          unitCode: 'Objekt / Allgemein',
          area: 0,
          allocationShare: 0,
          allocatedCosts: 0,
          directCosts: unassignedDirectCosts,
          annualPrepayments: 0,
        ),
      );
    }
    return summaries;
  }
}
