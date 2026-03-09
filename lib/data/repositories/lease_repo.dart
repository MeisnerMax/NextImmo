import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_service.dart';
import '../../core/audit/audit_writer.dart';
import '../../core/models/audit_log.dart';
import '../../core/models/operations.dart';
import '../../core/operations/lease_indexation_engine.dart';
import 'audit_log_repo.dart';

class LeaseValidationException implements Exception {
  const LeaseValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LeaseRepo {
  LeaseRepo(
    this._db,
    this._engine, {
    AuditLogRepo? auditLogRepo,
    AuditWriter? auditWriter,
  }) : _auditLogRepo = auditLogRepo,
       _auditWriter = auditWriter;

  final Database _db;
  final LeaseIndexationEngine _engine;
  final AuditLogRepo? _auditLogRepo;
  final AuditWriter? _auditWriter;
  static const AuditService _auditService = AuditService();

  Future<List<TenantRecord>> listTenants() async {
    final rows = await _db.query(
      'tenants',
      orderBy: 'display_name COLLATE NOCASE',
    );
    return rows.map(TenantRecord.fromMap).toList();
  }

  Future<TenantRecord> upsertTenant({
    String? id,
    required String displayName,
    String? legalName,
    String? email,
    String? phone,
    String? alternativeContact,
    String? billingContact,
    String? status,
    String? moveInReference,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing =
        id == null
            ? null
            : await _db.query(
              'tenants',
              where: 'id = ?',
              whereArgs: <Object?>[id],
              limit: 1,
            );
    final record = TenantRecord(
      id: id ?? const Uuid().v4(),
      displayName: displayName,
      legalName: legalName,
      email: email,
      phone: phone,
      alternativeContact: alternativeContact,
      billingContact: billingContact,
      status: status ?? 'active',
      moveInReference: moveInReference,
      notes: notes,
      createdAt:
          existing == null || existing.isEmpty
              ? now
              : TenantRecord.fromMap(existing.first).createdAt,
      updatedAt: now,
    );
    await _db.insert(
      'tenants',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _recordAudit(
      entityType: 'tenant',
      entityId: record.id,
      action: existing == null || existing.isEmpty ? 'create' : 'update',
      summary:
          existing == null || existing.isEmpty
              ? 'Tenant created: ${record.displayName}'
              : 'Tenant updated: ${record.displayName}',
      oldValues: existing == null || existing.isEmpty ? null : existing.first,
      newValues: record.toMap(),
      diffItems:
          existing == null || existing.isEmpty
              ? const <AuditDiffItem>[]
              : _auditService.buildDiff(existing.first, record.toMap()),
      parentEntityType: 'property',
      parentEntityId: await _resolveTenantPropertyId(record.id),
    );
    return record;
  }

  Future<List<LeaseRecord>> listLeasesByAsset(String assetPropertyId) async {
    final rows = await _db.query(
      'leases',
      where: 'asset_property_id = ?',
      whereArgs: <Object?>[assetPropertyId],
      orderBy: 'start_date DESC',
    );
    return rows.map(LeaseRecord.fromMap).toList();
  }

  Future<TenantRecord?> getTenantById(String tenantId) async {
    final rows = await _db.query(
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

  Future<List<LeaseRecord>> listLeasesByTenant(String tenantId) async {
    final rows = await _db.query(
      'leases',
      where: 'tenant_id = ?',
      whereArgs: <Object?>[tenantId],
      orderBy: 'start_date DESC',
    );
    return rows.map(LeaseRecord.fromMap).toList(growable: false);
  }

  Future<LeaseRecord?> getLeaseById(String leaseId) async {
    final rows = await _db.query(
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

  Future<LeaseRecord> createLease({
    required String assetPropertyId,
    required String unitId,
    String? tenantId,
    required String leaseName,
    required int startDate,
    int? endDate,
    int? moveInDate,
    int? moveOutDate,
    String status = 'draft',
    required double baseRentMonthly,
    String currencyCode = 'EUR',
    double? securityDeposit,
    int? paymentDayOfMonth,
    String billingFrequency = 'monthly',
    int? leaseSignedDate,
    int? noticeDate,
    int? renewalOptionDate,
    int? breakOptionDate,
    int? executedDate,
    String? depositStatus,
    int? rentFreePeriodMonths,
    double? ancillaryChargesMonthly,
    double? parkingOtherChargesMonthly,
    String? notes,
  }) async {
    await _validateLease(
      unitId: unitId,
      startDate: startDate,
      endDate: endDate,
      status: status,
      paymentDayOfMonth: paymentDayOfMonth,
      securityDeposit: securityDeposit,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final lease = LeaseRecord(
      id: const Uuid().v4(),
      assetPropertyId: assetPropertyId,
      unitId: unitId,
      tenantId: tenantId,
      leaseName: leaseName,
      startDate: startDate,
      endDate: endDate,
      moveInDate: moveInDate,
      moveOutDate: moveOutDate,
      status: status,
      baseRentMonthly: baseRentMonthly,
      currencyCode: currencyCode,
      securityDeposit: securityDeposit,
      paymentDayOfMonth: paymentDayOfMonth,
      billingFrequency: billingFrequency,
      leaseSignedDate: leaseSignedDate,
      noticeDate: noticeDate,
      renewalOptionDate: renewalOptionDate,
      breakOptionDate: breakOptionDate,
      executedDate: executedDate,
      depositStatus: depositStatus ?? 'unknown',
      rentFreePeriodMonths: rentFreePeriodMonths,
      ancillaryChargesMonthly: ancillaryChargesMonthly,
      parkingOtherChargesMonthly: parkingOtherChargesMonthly,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert(
      'leases',
      lease.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _recordAudit(
      entityType: 'lease',
      entityId: lease.id,
      action: 'create',
      summary: 'Lease created: ${lease.leaseName}',
      newValues: lease.toMap(),
      parentEntityType: 'property',
      parentEntityId: lease.assetPropertyId,
    );
    return lease;
  }

  Future<void> updateLease(LeaseRecord lease) async {
    await _validateLease(
      unitId: lease.unitId,
      startDate: lease.startDate,
      endDate: lease.endDate,
      status: lease.status,
      paymentDayOfMonth: lease.paymentDayOfMonth,
      securityDeposit: lease.securityDeposit,
      excludingLeaseId: lease.id,
    );
    final before = await _db.query(
      'leases',
      where: 'id = ?',
      whereArgs: <Object?>[lease.id],
      limit: 1,
    );
    await _db.update(
      'leases',
      lease.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[lease.id],
    );
    final after = await _db.query(
      'leases',
      where: 'id = ?',
      whereArgs: <Object?>[lease.id],
      limit: 1,
    );
    if (before.isNotEmpty && after.isNotEmpty) {
      await _recordAudit(
        entityType: 'lease',
        entityId: lease.id,
        action: 'update',
        summary: 'Lease updated',
        oldValues: before.first,
        newValues: after.first,
        diffItems: _auditService.buildDiff(before.first, after.first),
        parentEntityType: 'property',
        parentEntityId: lease.assetPropertyId,
      );
    }
  }

  Future<void> deleteLease(String leaseId) async {
    final before = await _db.query(
      'leases',
      where: 'id = ?',
      whereArgs: <Object?>[leaseId],
      limit: 1,
    );
    await _db.delete('leases', where: 'id = ?', whereArgs: <Object?>[leaseId]);
    await _recordAudit(
      entityType: 'lease',
      entityId: leaseId,
      action: 'delete',
      summary: 'Lease deleted',
      oldValues: before.isEmpty ? null : before.first,
      parentEntityType: 'property',
      parentEntityId:
          before.isEmpty ? null : before.first['asset_property_id'] as String?,
    );
  }

  Future<List<LeaseIndexationRuleRecord>> listIndexationRules(
    String leaseId,
  ) async {
    final rows = await _db.query(
      'lease_indexation_rules',
      where: 'lease_id = ?',
      whereArgs: <Object?>[leaseId],
      orderBy: 'effective_from_period_key ASC, created_at ASC',
    );
    return rows.map(LeaseIndexationRuleRecord.fromMap).toList();
  }

  Future<LeaseIndexationRuleRecord> upsertIndexationRule({
    String? id,
    required String leaseId,
    required String kind,
    required String effectiveFromPeriodKey,
    double? annualPercent,
    double? fixedStepAmount,
    double? capPercent,
    double? floorPercent,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rule = LeaseIndexationRuleRecord(
      id: id ?? const Uuid().v4(),
      leaseId: leaseId,
      kind: kind,
      effectiveFromPeriodKey: effectiveFromPeriodKey,
      annualPercent: annualPercent,
      fixedStepAmount: fixedStepAmount,
      capPercent: capPercent,
      floorPercent: floorPercent,
      notes: notes,
      createdAt: now,
    );
    await _db.insert(
      'lease_indexation_rules',
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final propertyId = await _resolveLeasePropertyId(leaseId);
    await _recordAudit(
      entityType: 'lease_indexation_rule',
      entityId: rule.id,
      action: id == null ? 'create' : 'update',
      summary:
          id == null ? 'Lease indexation rule created' : 'Lease indexation rule updated',
      newValues: rule.toMap(),
      parentEntityType: propertyId == null ? null : 'property',
      parentEntityId: propertyId,
    );
    return rule;
  }

  Future<List<LeaseRentScheduleRecord>> readSchedule({
    required String leaseId,
    String? fromPeriod,
    String? toPeriod,
  }) async {
    final where = <String>['lease_id = ?'];
    final args = <Object?>[leaseId];
    if (fromPeriod != null) {
      where.add('period_key >= ?');
      args.add(fromPeriod);
    }
    if (toPeriod != null) {
      where.add('period_key <= ?');
      args.add(toPeriod);
    }
    final rows = await _db.query(
      'lease_rent_schedule',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'period_key ASC',
    );
    return rows.map(LeaseRentScheduleRecord.fromMap).toList();
  }

  Future<List<LeaseRentScheduleRecord>> rebuildRentSchedule({
    required String leaseId,
    required String fromPeriod,
    required String toPeriod,
  }) async {
    final lease = await getLeaseById(leaseId);
    if (lease == null) {
      throw StateError('Lease not found: $leaseId');
    }

    final rules = await listIndexationRules(leaseId);
    final existing = await readSchedule(
      leaseId: leaseId,
      fromPeriod: fromPeriod,
      toPeriod: toPeriod,
    );
    final manualOverrides = <String, LeaseRentScheduleRecord>{
      for (final row in existing)
        if (row.source == 'manual_override') row.periodKey: row,
    };

    final generated = _engine.buildRentSchedule(
      lease: lease,
      indexationRules: rules,
      fromPeriodKey: fromPeriod,
      toPeriodKey: toPeriod,
      manualOverrides: manualOverrides,
    );

    await _db.transaction((txn) async {
      await txn.delete(
        'lease_rent_schedule',
        where:
            'lease_id = ? AND period_key >= ? AND period_key <= ? AND source != ?',
        whereArgs: <Object?>[leaseId, fromPeriod, toPeriod, 'manual_override'],
      );
      for (final row in generated) {
        await txn.insert(
          'lease_rent_schedule',
          row.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    final propertyId = await _resolveLeasePropertyId(leaseId);
    await _recordAudit(
      entityType: 'lease',
      entityId: leaseId,
      action: 'rebuild_schedule',
      summary: 'Lease rent schedule rebuilt',
      parentEntityType: propertyId == null ? null : 'property',
      parentEntityId: propertyId,
    );

    return readSchedule(
      leaseId: leaseId,
      fromPeriod: fromPeriod,
      toPeriod: toPeriod,
    );
  }

  Future<LeaseRentScheduleRecord> upsertManualOverride({
    required String leaseId,
    required String periodKey,
    required double rentMonthly,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = LeaseRentScheduleRecord(
      id: const Uuid().v4(),
      leaseId: leaseId,
      periodKey: periodKey,
      rentMonthly: rentMonthly,
      source: 'manual_override',
      createdAt: now,
    );
    await _db.insert(
      'lease_rent_schedule',
      row.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final propertyId = await _resolveLeasePropertyId(leaseId);
    await _recordAudit(
      entityType: 'lease_rent_schedule',
      entityId: row.id,
      action: 'update',
      summary: 'Manual rent override saved',
      newValues: row.toMap(),
      parentEntityType: propertyId == null ? null : 'property',
      parentEntityId: propertyId,
    );
    return row;
  }

  Future<void> _validateLease({
    required String unitId,
    required int startDate,
    required int? endDate,
    required String status,
    required int? paymentDayOfMonth,
    required double? securityDeposit,
    String? excludingLeaseId,
  }) async {
    if (endDate != null && endDate < startDate) {
      throw const LeaseValidationException('Lease end date must be after start date.');
    }
    if (paymentDayOfMonth != null &&
        (paymentDayOfMonth < 1 || paymentDayOfMonth > 31)) {
      throw const LeaseValidationException('Payment day must be between 1 and 31.');
    }
    if (securityDeposit != null && securityDeposit < 0) {
      throw const LeaseValidationException('Security deposit cannot be negative.');
    }
    if (status != 'active') {
      return;
    }

    final rows = await _db.query(
      'leases',
      where:
          'unit_id = ? AND status = ?${excludingLeaseId == null ? '' : ' AND id != ?'}',
      whereArgs: <Object?>[
        unitId,
        'active',
        if (excludingLeaseId != null) excludingLeaseId,
      ],
    );
    final overlapping = rows
        .map(LeaseRecord.fromMap)
        .where(
          (existing) => _rangesOverlap(
            startDate,
            endDate,
            existing.startDate,
            existing.endDate,
          ),
        )
        .toList(growable: false);
    if (overlapping.isNotEmpty) {
      throw const LeaseValidationException(
        'This unit already has an overlapping active lease.',
      );
    }
  }

  bool _rangesOverlap(
    int startA,
    int? endA,
    int startB,
    int? endB,
  ) {
    final effectiveEndA = endA ?? DateTime(9999).millisecondsSinceEpoch;
    final effectiveEndB = endB ?? DateTime(9999).millisecondsSinceEpoch;
    return startA <= effectiveEndB && startB <= effectiveEndA;
  }

  Future<String?> _resolveLeasePropertyId(String leaseId) async {
    final rows = await _db.query(
      'leases',
      columns: const <String>['asset_property_id'],
      where: 'id = ?',
      whereArgs: <Object?>[leaseId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['asset_property_id'] as String?;
  }

  Future<String?> _resolveTenantPropertyId(String tenantId) async {
    final rows = await _db.query(
      'leases',
      columns: const <String>['asset_property_id'],
      where: 'tenant_id = ?',
      whereArgs: <Object?>[tenantId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['asset_property_id'] as String?;
  }

  Future<void> _recordAudit({
    required String entityType,
    required String entityId,
    required String action,
    String? summary,
    String? parentEntityType,
    String? parentEntityId,
    Map<String, Object?>? oldValues,
    Map<String, Object?>? newValues,
    List<AuditDiffItem> diffItems = const <AuditDiffItem>[],
  }) async {
    final auditWriter = _auditWriter;
    if (auditWriter != null) {
      await auditWriter.record(
        entityType: entityType,
        entityId: entityId,
        action: action,
        summary: summary,
        parentEntityType: parentEntityType,
        parentEntityId: parentEntityId,
        oldValues: oldValues,
        newValues: newValues,
        diffItems: diffItems,
      );
      return;
    }
    await _auditLogRepo?.recordEvent(
      entityType: entityType,
      entityId: entityId,
      action: action,
      summary: summary,
      parentEntityType: parentEntityType,
      parentEntityId: parentEntityId,
      oldValues: oldValues,
      newValues: newValues,
      diffItems: diffItems,
      source: 'ui',
    );
  }
}
