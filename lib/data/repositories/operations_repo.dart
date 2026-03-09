import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/models/documents.dart';
import '../../core/models/operations.dart';
import '../../core/models/task.dart';
import '../../core/operations/operations_data_quality_engine.dart';

class OperationsRepo {
  const OperationsRepo([
    this._db,
    this._qualityEngine = const OperationsDataQualityEngine(),
  ]);

  final Database? _db;
  final OperationsDataQualityEngine _qualityEngine;

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('OperationsRepo database is not configured.');
    }
    return db;
  }

  Future<OperationsOverviewBundle> loadOverview(String propertyId) async {
    final now = DateTime.now();
    final units = await _loadUnits(propertyId);
    final leases = await _loadLeases(propertyId);
    final tenants = await _loadTenants();
    final snapshots = await _loadSnapshots(propertyId);
    final activeLeasesByUnit = _activeLeasesByUnit(leases, now);
    final issues = _qualityEngine.evaluate(
      propertyId: propertyId,
      units: units,
      leases: leases,
      tenantsById: tenants,
      snapshots: snapshots,
      now: now,
    );
    final alerts = await _loadAlertsForData(
      propertyId: propertyId,
      now: now,
      activeLeasesByUnit: activeLeasesByUnit,
      issues: issues,
    );
    final openAlerts =
        alerts.where((alert) => alert.status == 'open').toList(growable: false);

    final occupiedUnits =
        units.where((unit) => _resolveUnitStatus(unit, activeLeasesByUnit[unit.id]) == 'occupied').length;
    final vacantUnits =
        units.where((unit) => _resolveUnitStatus(unit, activeLeasesByUnit[unit.id]) == 'vacant').length;
    final offlineUnits =
        units.where((unit) => _resolveUnitStatus(unit, activeLeasesByUnit[unit.id]) == 'offline').length;
    final activeLeaseCount = activeLeasesByUnit.values.fold<int>(
      0,
      (sum, leasesForUnit) => sum + leasesForUnit.length,
    );
    final occupiedAreaSqft = units
        .where((unit) => _resolveUnitStatus(unit, activeLeasesByUnit[unit.id]) == 'occupied')
        .fold<double>(0, (sum, unit) => sum + (unit.sqft ?? 0));
    final leasedAreaSqft = units
        .where((unit) => (activeLeasesByUnit[unit.id]?.isNotEmpty ?? false))
        .fold<double>(0, (sum, unit) => sum + (unit.sqft ?? 0));

    final latestSnapshot = snapshots.isEmpty ? null : snapshots.first;
    final priorSnapshot = snapshots.length > 1 ? snapshots[1] : null;
    final rentRollDelta =
        latestSnapshot == null || priorSnapshot == null
            ? null
            : RentRollDeltaRecord(
              inPlaceRentDelta:
                  latestSnapshot.inPlaceRentMonthly - priorSnapshot.inPlaceRentMonthly,
              occupancyRateDelta:
                  latestSnapshot.occupancyRate - priorSnapshot.occupancyRate,
            );

    return OperationsOverviewBundle(
      unitsTotal: units.length,
      occupiedUnits: occupiedUnits,
      vacantUnits: vacantUnits,
      offlineUnits: offlineUnits,
      occupiedAreaSqft: occupiedAreaSqft,
      leasedAreaSqft: leasedAreaSqft,
      activeLeases: activeLeaseCount,
      expiringIn30Days: _countExpiring(activeLeasesByUnit, now, 30),
      expiringIn60Days: _countExpiring(activeLeasesByUnit, now, 60),
      expiringIn90Days: _countExpiring(activeLeasesByUnit, now, 90),
      expiringIn180Days: _countExpiring(activeLeasesByUnit, now, 180),
      unitsWithoutActiveLease:
          units.where((unit) => unit.status != 'offline' && (activeLeasesByUnit[unit.id]?.isEmpty ?? true)).length,
      unitsWithMissingTenantMasterData: _countMissingTenantMasterData(activeLeasesByUnit, tenants),
      dataConflicts: issues.where((issue) => issue.severity == 'critical').length,
      latestRentRollPeriod: latestSnapshot?.periodKey,
      rentRollDelta: rentRollDelta,
      openOperationalAlerts: openAlerts.length,
      alerts: openAlerts,
      dataQualityIssues: issues,
    );
  }

  Future<List<OperationsAlertRecord>> loadAlerts(
    String propertyId, {
    String? status,
  }) async {
    final now = DateTime.now();
    final units = await _loadUnits(propertyId);
    final leases = await _loadLeases(propertyId);
    final tenants = await _loadTenants();
    final snapshots = await _loadSnapshots(propertyId);
    final issues = _qualityEngine.evaluate(
      propertyId: propertyId,
      units: units,
      leases: leases,
      tenantsById: tenants,
      snapshots: snapshots,
      now: now,
    );
    final alerts = await _loadAlertsForData(
      propertyId: propertyId,
      now: now,
      activeLeasesByUnit: _activeLeasesByUnit(leases, now),
      issues: issues,
    );
    if (status == null) {
      return alerts;
    }
    return alerts.where((alert) => alert.status == status).toList(growable: false);
  }

  Future<void> updateAlertStatus({
    required String alertId,
    required String propertyId,
    required String status,
    String? resolutionNote,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database.insert(
      'operations_alert_states',
      <String, Object?>{
        'alert_id': alertId,
        'property_id': propertyId,
        'status': status,
        'resolution_note': resolutionNote,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<UnitDetailBundle> loadUnitDetail({
    required String propertyId,
    required String unitId,
  }) async {
    final unit = await _loadUnitById(unitId);
    if (unit == null) {
      throw StateError('Unit not found: $unitId');
    }
    final leaseRows = await _database.query(
      'leases',
      where: 'unit_id = ?',
      whereArgs: <Object?>[unitId],
      orderBy: 'start_date DESC',
    );
    final leaseHistory = leaseRows.map(LeaseRecord.fromMap).toList(growable: false);
    final activeLease = _selectCurrentLease(leaseHistory);
    final activeTenant =
        activeLease?.tenantId == null ? null : await _loadTenantById(activeLease!.tenantId!);
    final latestRentRollLine = await _loadLatestRentRollLine(
      propertyId: propertyId,
      unitId: unitId,
    );
    final alerts = await loadAlerts(propertyId);
    return UnitDetailBundle(
      unit: unit,
      activeLease: activeLease,
      leaseHistory: leaseHistory,
      activeTenant: activeTenant,
      latestRentRollLine: latestRentRollLine,
      alerts: alerts.where((alert) => alert.unitId == unitId).toList(growable: false),
      tasks: await _loadTasks(entityType: 'unit', entityId: unitId),
      documents: await _loadDocuments(entityType: 'unit', entityId: unitId),
    );
  }

  Future<TenantDetailBundle> loadTenantDetail({
    required String propertyId,
    required String tenantId,
  }) async {
    final tenant = await _loadTenantById(tenantId);
    if (tenant == null) {
      throw StateError('Tenant not found: $tenantId');
    }
    final leaseRows = await _database.query(
      'leases',
      where: 'tenant_id = ? AND asset_property_id = ?',
      whereArgs: <Object?>[tenantId, propertyId],
      orderBy: 'start_date DESC',
    );
    final leases = leaseRows.map(LeaseRecord.fromMap).toList(growable: false);
    final activeLeases = leases.where((lease) => _isActiveLease(lease, DateTime.now())).toList(growable: false);
    final unitIds = leases.map((lease) => lease.unitId).toSet().toList(growable: false);
    final relatedUnits = await _loadUnitsByIds(unitIds);
    final alerts = await loadAlerts(propertyId);
    return TenantDetailBundle(
      tenant: tenant,
      activeLeases: activeLeases,
      historicalLeases: leases,
      relatedUnits: relatedUnits,
      alerts: alerts.where((alert) => alert.tenantId == tenantId).toList(growable: false),
      tasks: await _loadTasks(entityType: 'tenant', entityId: tenantId),
      documents: await _loadDocuments(entityType: 'tenant', entityId: tenantId),
      duplicateWarnings: await _findDuplicateTenantWarnings(tenant),
    );
  }

  Future<LeaseDetailBundle> loadLeaseDetail({
    required String propertyId,
    required String leaseId,
  }) async {
    final lease = await _loadLeaseById(leaseId);
    if (lease == null) {
      throw StateError('Lease not found: $leaseId');
    }
    final unit = await _loadUnitById(lease.unitId);
    final tenant =
        lease.tenantId == null ? null : await _loadTenantById(lease.tenantId!);
    final rulesRows = await _database.query(
      'lease_indexation_rules',
      where: 'lease_id = ?',
      whereArgs: <Object?>[leaseId],
      orderBy: 'effective_from_period_key ASC, created_at ASC',
    );
    final scheduleRows = await _database.query(
      'lease_rent_schedule',
      where: 'lease_id = ?',
      whereArgs: <Object?>[leaseId],
      orderBy: 'period_key ASC',
    );
    final alerts = await loadAlerts(propertyId);
    return LeaseDetailBundle(
      lease: lease,
      unit: unit,
      tenant: tenant,
      rules: rulesRows.map(LeaseIndexationRuleRecord.fromMap).toList(growable: false),
      schedule: scheduleRows.map(LeaseRentScheduleRecord.fromMap).toList(growable: false),
      latestRentRollLine: await _loadLatestRentRollLine(
        propertyId: propertyId,
        leaseId: leaseId,
      ),
      alerts: alerts.where((alert) => alert.leaseId == leaseId).toList(growable: false),
      tasks: await _loadTasks(entityType: 'lease', entityId: leaseId),
      documents: await _loadDocuments(entityType: 'lease', entityId: leaseId),
    );
  }

  Future<List<UnitRecord>> _loadUnits(String propertyId) async {
    final rows = await _database.query(
      'units',
      where: 'asset_property_id = ?',
      whereArgs: <Object?>[propertyId],
      orderBy: 'unit_code COLLATE NOCASE',
    );
    return rows.map(UnitRecord.fromMap).toList(growable: false);
  }

  Future<UnitRecord?> _loadUnitById(String unitId) async {
    final rows = await _database.query(
      'units',
      where: 'id = ?',
      whereArgs: <Object?>[unitId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return UnitRecord.fromMap(rows.first);
  }

  Future<List<UnitRecord>> _loadUnitsByIds(List<String> unitIds) async {
    if (unitIds.isEmpty) {
      return const <UnitRecord>[];
    }
    final placeholders = List<String>.filled(unitIds.length, '?').join(',');
    final rows = await _database.rawQuery(
      'SELECT * FROM units WHERE id IN ($placeholders) ORDER BY unit_code COLLATE NOCASE',
      <Object?>[...unitIds],
    );
    return rows.map(UnitRecord.fromMap).toList(growable: false);
  }

  Future<List<LeaseRecord>> _loadLeases(String propertyId) async {
    final rows = await _database.query(
      'leases',
      where: 'asset_property_id = ?',
      whereArgs: <Object?>[propertyId],
      orderBy: 'start_date DESC',
    );
    return rows.map(LeaseRecord.fromMap).toList(growable: false);
  }

  Future<LeaseRecord?> _loadLeaseById(String leaseId) async {
    final rows = await _database.query(
      'leases',
      where: 'id = ?',
      whereArgs: <Object?>[leaseId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return LeaseRecord.fromMap(rows.first);
  }

  Future<Map<String, TenantRecord>> _loadTenants() async {
    final rows = await _database.query('tenants');
    return <String, TenantRecord>{
      for (final row in rows) (row['id']! as String): TenantRecord.fromMap(row),
    };
  }

  Future<TenantRecord?> _loadTenantById(String tenantId) async {
    final rows = await _database.query(
      'tenants',
      where: 'id = ?',
      whereArgs: <Object?>[tenantId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return TenantRecord.fromMap(rows.first);
  }

  Future<List<RentRollSnapshotRecord>> _loadSnapshots(String propertyId) async {
    final rows = await _database.query(
      'rent_roll_snapshots',
      where: 'asset_property_id = ?',
      whereArgs: <Object?>[propertyId],
      orderBy: 'period_key DESC',
      limit: 2,
    );
    return rows.map(RentRollSnapshotRecord.fromMap).toList(growable: false);
  }

  Future<Map<String, Map<String, Object?>>> _loadAlertStates(String propertyId) async {
    final rows = await _database.query(
      'operations_alert_states',
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
    );
    return <String, Map<String, Object?>>{
      for (final row in rows) row['alert_id']! as String: row,
    };
  }

  Future<List<TaskRecord>> _loadTasks({
    required String entityType,
    required String entityId,
  }) async {
    final rows = await _database.query(
      'tasks',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: <Object?>[entityType, entityId],
      orderBy: 'due_at ASC, created_at DESC',
    );
    return rows.map(TaskRecord.fromMap).toList(growable: false);
  }

  Future<List<DocumentRecord>> _loadDocuments({
    required String entityType,
    required String entityId,
  }) async {
    final rows = await _database.query(
      'documents',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: <Object?>[entityType, entityId],
      orderBy: 'created_at DESC',
    );
    return rows.map(DocumentRecord.fromMap).toList(growable: false);
  }

  Future<RentRollLineRecord?> _loadLatestRentRollLine({
    required String propertyId,
    String? unitId,
    String? leaseId,
  }) async {
    final snapshots = await _loadSnapshots(propertyId);
    if (snapshots.isEmpty) {
      return null;
    }
    final where = <String>['snapshot_id = ?'];
    final args = <Object?>[snapshots.first.id];
    if (unitId != null) {
      where.add('unit_id = ?');
      args.add(unitId);
    }
    if (leaseId != null) {
      where.add('lease_id = ?');
      args.add(leaseId);
    }
    final rows = await _database.query(
      'rent_roll_lines',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return RentRollLineRecord.fromMap(rows.first);
  }

  Future<List<String>> _findDuplicateTenantWarnings(TenantRecord tenant) async {
    final normalizedTarget = _normalizeName(tenant.displayName);
    if (normalizedTarget.isEmpty) {
      return const <String>[];
    }
    final rows = await _database.query(
      'tenants',
      columns: const <String>['id', 'display_name'],
      where: 'id != ?',
      whereArgs: <Object?>[tenant.id],
    );
    final warnings = <String>[];
    for (final row in rows) {
      final otherName = (row['display_name'] as String?) ?? '';
      final normalizedOther = _normalizeName(otherName);
      if (normalizedOther.isEmpty) {
        continue;
      }
      final similar =
          normalizedOther == normalizedTarget ||
          normalizedOther.contains(normalizedTarget) ||
          normalizedTarget.contains(normalizedOther);
      if (similar) {
        warnings.add('Possible duplicate tenant: $otherName');
      }
    }
    return warnings.toSet().toList(growable: false);
  }

  Future<List<OperationsAlertRecord>> _loadAlertsForData({
    required String propertyId,
    required DateTime now,
    required Map<String, List<LeaseRecord>> activeLeasesByUnit,
    required List<OperationsDataQualityIssue> issues,
  }) async {
    final alertStates = await _loadAlertStates(propertyId);
    final alerts = <OperationsAlertRecord>[
      ..._buildLeaseExpiryAlerts(activeLeasesByUnit, now),
      ..._buildQualityAlerts(issues, now),
    ].map((alert) {
      final alertId = alert.id ?? _buildAlertId(alert);
      final state = alertStates[alertId];
      return OperationsAlertRecord(
        id: alertId,
        type: alert.type,
        severity: alert.severity,
        message: alert.message,
        propertyId: alert.propertyId,
        unitId: alert.unitId,
        leaseId: alert.leaseId,
        tenantId: alert.tenantId,
        status: (state?['status'] as String?) ?? alert.status,
        createdAt: alert.createdAt,
        resolutionNote: state?['resolution_note'] as String? ?? alert.resolutionNote,
        recommendedAction: alert.recommendedAction,
      );
    }).toList(growable: false);
    alerts.sort((a, b) {
      final bySeverity = _severityRank(a.severity).compareTo(_severityRank(b.severity));
      if (bySeverity != 0) {
        return bySeverity;
      }
      return a.message.compareTo(b.message);
    });
    return alerts;
  }

  Map<String, List<LeaseRecord>> _activeLeasesByUnit(
    List<LeaseRecord> leases,
    DateTime now,
  ) {
    final today = now.millisecondsSinceEpoch;
    final grouped = <String, List<LeaseRecord>>{};
    for (final lease in leases) {
      if (lease.status != 'active') {
        continue;
      }
      if (lease.startDate > today) {
        continue;
      }
      if (lease.endDate != null && lease.endDate! < today) {
        continue;
      }
      grouped.putIfAbsent(lease.unitId, () => <LeaseRecord>[]).add(lease);
    }
    for (final entry in grouped.values) {
      entry.sort((a, b) => b.startDate.compareTo(a.startDate));
    }
    return grouped;
  }

  LeaseRecord? _selectCurrentLease(List<LeaseRecord> leases) {
    final now = DateTime.now();
    for (final lease in leases) {
      if (_isActiveLease(lease, now)) {
        return lease;
      }
    }
    return leases.isEmpty ? null : leases.first;
  }

  bool _isActiveLease(LeaseRecord lease, DateTime now) {
    if (lease.status != 'active') {
      return false;
    }
    final today = now.millisecondsSinceEpoch;
    if (lease.startDate > today) {
      return false;
    }
    return lease.endDate == null || lease.endDate! >= today;
  }

  String _resolveUnitStatus(UnitRecord unit, List<LeaseRecord>? activeLeases) {
    if (unit.status == 'offline') {
      return 'offline';
    }
    if ((activeLeases?.isNotEmpty ?? false)) {
      return 'occupied';
    }
    return 'vacant';
  }

  int _countExpiring(
    Map<String, List<LeaseRecord>> activeLeasesByUnit,
    DateTime now,
    int days,
  ) {
    final cutoff = now.add(Duration(days: days)).millisecondsSinceEpoch;
    var count = 0;
    for (final leases in activeLeasesByUnit.values) {
      for (final lease in leases) {
        if (lease.endDate != null &&
            lease.endDate! >= now.millisecondsSinceEpoch &&
            lease.endDate! <= cutoff) {
          count += 1;
        }
      }
    }
    return count;
  }

  int _countMissingTenantMasterData(
    Map<String, List<LeaseRecord>> activeLeasesByUnit,
    Map<String, TenantRecord> tenantsById,
  ) {
    var count = 0;
    for (final leases in activeLeasesByUnit.values) {
      for (final lease in leases) {
        final tenantId = lease.tenantId;
        if (tenantId == null) {
          count += 1;
          continue;
        }
        final tenant = tenantsById[tenantId];
        if (tenant == null ||
            (tenant.email == null || tenant.email!.trim().isEmpty) ||
            (tenant.phone == null || tenant.phone!.trim().isEmpty)) {
          count += 1;
        }
      }
    }
    return count;
  }

  List<OperationsAlertRecord> _buildLeaseExpiryAlerts(
    Map<String, List<LeaseRecord>> activeLeasesByUnit,
    DateTime now,
  ) {
    final createdAt = now.millisecondsSinceEpoch;
    final alerts = <OperationsAlertRecord>[];
    for (final leases in activeLeasesByUnit.values) {
      for (final lease in leases) {
        final endDate = lease.endDate;
        if (endDate == null) {
          continue;
        }
        final daysRemaining = DateTime.fromMillisecondsSinceEpoch(endDate)
            .difference(DateTime(now.year, now.month, now.day))
            .inDays;
        if (daysRemaining < 0 || daysRemaining > 180) {
          continue;
        }
        final severity =
            daysRemaining <= 30
                ? 'critical'
                : daysRemaining <= 90
                ? 'warning'
                : 'info';
        alerts.add(
          OperationsAlertRecord(
            type: 'lease_expiry',
            severity: severity,
            message: '${lease.leaseName} expires in $daysRemaining days.',
            propertyId: lease.assetPropertyId,
            unitId: lease.unitId,
            leaseId: lease.id,
            tenantId: lease.tenantId,
            createdAt: createdAt,
            recommendedAction: 'Review renewal, notice and follow-up actions for this lease.',
          ),
        );
      }
    }
    return alerts;
  }

  List<OperationsAlertRecord> _buildQualityAlerts(
    List<OperationsDataQualityIssue> issues,
    DateTime now,
  ) {
    final createdAt = now.millisecondsSinceEpoch;
    return issues
        .map(
          (issue) => OperationsAlertRecord(
            type: issue.type,
            severity: issue.severity,
            message: issue.message,
            propertyId: issue.propertyId,
            unitId: issue.unitId,
            leaseId: issue.leaseId,
            tenantId: issue.tenantId,
            createdAt: createdAt,
            recommendedAction: issue.recommendedAction,
          ),
        )
        .toList(growable: false);
  }

  String _buildAlertId(OperationsAlertRecord alert) {
    return <String>[
      alert.type,
      alert.propertyId ?? '',
      alert.unitId ?? '',
      alert.leaseId ?? '',
      alert.tenantId ?? '',
      alert.message,
    ].join('|');
  }

  int _severityRank(String severity) {
    switch (severity) {
      case 'critical':
        return 0;
      case 'warning':
        return 1;
      default:
        return 2;
    }
  }

  String _normalizeName(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
