import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_service.dart';
import '../../core/audit/audit_writer.dart';
import '../../core/models/audit_log.dart';
import '../../core/models/inputs.dart';
import '../../core/models/property.dart';
import '../../core/models/scenario.dart';
import '../../core/models/security.dart';
import '../../core/models/settings.dart';
import '../../core/security/rbac.dart';
import 'audit_log_repo.dart';
import 'permission_guard.dart';
import 'search_repo.dart';

class PropertyCreateResult {
  const PropertyCreateResult({required this.property, required this.scenario});

  final PropertyRecord property;
  final ScenarioRecord scenario;
}

class PropertyRepository {
  PropertyRepository(
    this._db, {
    AuditLogRepo? auditLogRepo,
    SearchRepo? searchRepo,
    AuditWriter? auditWriter,
    PermissionGuard? permissionGuard,
    Future<SecurityContextRecord> Function()? securityContextResolver,
  }) : _auditLogRepo = auditLogRepo,
       _searchRepo = searchRepo,
       _auditWriter = auditWriter,
       _permissionGuard = permissionGuard,
       _securityContextResolver = securityContextResolver;

  final Database _db;
  final AuditLogRepo? _auditLogRepo;
  final SearchRepo? _searchRepo;
  final AuditWriter? _auditWriter;
  final PermissionGuard? _permissionGuard;
  final Future<SecurityContextRecord> Function()? _securityContextResolver;
  static const AuditService _auditService = AuditService();

  Future<List<PropertyRecord>> list({bool includeArchived = false}) async {
    final rows = await _db.query(
      'properties',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'updated_at DESC',
    );

    return rows.map(PropertyRecord.fromMap).toList();
  }

  Future<PropertyRecord?> getById(String id) async {
    final rows = await _db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return PropertyRecord.fromMap(rows.first);
  }

  Future<PropertyRecord> create({
    required String name,
    required String addressLine1,
    String? addressLine2,
    required String zip,
    required String city,
    required String country,
    required String propertyType,
    required int units,
    double? sqft,
    int? yearBuilt,
    String? notes,
  }) async {
    await _ensurePermission(
      permission: Permission.propertyCreate,
      message: 'You do not have permission to create properties.',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = PropertyRecord(
      id: const Uuid().v4(),
      name: name,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      zip: zip,
      city: city,
      country: country,
      propertyType: propertyType,
      units: units,
      sqft: sqft,
      yearBuilt: yearBuilt,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );

    await _db.insert(
      'properties',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(searchRepo.buildPropertyRecord(record));
    }
    await _recordAudit(
      entityType: 'property',
      entityId: record.id,
      action: 'create',
      summary: 'Property created: ${record.name}',
      newValues: record.toMap(),
    );
    return record;
  }

  Future<PropertyCreateResult> createWithBaseScenario({
    required String name,
    required String addressLine1,
    String? addressLine2,
    required String zip,
    required String city,
    required String country,
    required String propertyType,
    required int units,
    double? sqft,
    int? yearBuilt,
    String? notes,
    required String strategyType,
    required AppSettingsRecord settings,
    required double purchasePrice,
    required double rentMonthly,
    required double rehabBudget,
    required String financingMode,
  }) async {
    await _ensurePermission(
      permission: Permission.propertyCreate,
      message: 'You do not have permission to create properties.',
    );
    final now = DateTime.now().millisecondsSinceEpoch;

    final property = PropertyRecord(
      id: const Uuid().v4(),
      name: name,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      zip: zip,
      city: city,
      country: country,
      propertyType: propertyType,
      units: units,
      sqft: sqft,
      yearBuilt: yearBuilt,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );

    final scenario = ScenarioRecord(
      id: const Uuid().v4(),
      propertyId: property.id,
      name: 'Base',
      strategyType: strategyType,
      isBase: true,
      workflowStatus: ScenarioWorkflowStatus.draft,
      approvedBy: null,
      approvedAt: null,
      rejectedBy: null,
      rejectedAt: null,
      reviewComment: null,
      changedSinceApproval: false,
      createdAt: now,
      updatedAt: now,
    );

    final inputs = ScenarioInputs.defaults(
      scenarioId: scenario.id,
      settings: settings,
    ).copyWith(
      purchasePrice: purchasePrice,
      rentMonthlyTotal: rentMonthly,
      rehabBudget: rehabBudget,
      financingMode: financingMode,
      updatedAt: now,
    );

    await _db.transaction((txn) async {
      await txn.insert(
        'properties',
        property.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await txn.insert(
        'scenarios',
        scenario.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await txn.insert(
        'scenario_inputs',
        inputs.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(searchRepo.buildPropertyRecord(property));
      await searchRepo.upsertIndexEntry(searchRepo.buildScenarioRecord(scenario));
    }
    await _recordAudit(
      entityType: 'property',
      entityId: property.id,
      action: 'create',
      summary: 'Property with base scenario created',
      newValues: property.toMap(),
    );

    return PropertyCreateResult(property: property, scenario: scenario);
  }

  Future<void> archive(String id, {required bool archived}) async {
    await _ensurePermission(
      permission: Permission.propertyUpdate,
      message: 'You do not have permission to update properties.',
    );
    final before = await _db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    await _db.update(
      'properties',
      <String, Object?>{
        'archived': archived ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    final after = await _db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (before.isNotEmpty && after.isNotEmpty) {
      final updated = PropertyRecord.fromMap(after.first);
      final searchRepo = _searchRepo;
      if (searchRepo != null && updated.archived) {
        await searchRepo.deleteIndexEntryByEntity(
          entityType: 'property',
          entityId: id,
        );
      } else if (searchRepo != null) {
        await searchRepo.upsertIndexEntry(searchRepo.buildPropertyRecord(updated));
      }
      await _recordAudit(
        entityType: 'property',
        entityId: id,
        action: 'update',
        summary: archived ? 'Property archived' : 'Property unarchived',
        oldValues: before.first,
        newValues: after.first,
        diffItems: _auditService.buildDiff(before.first, after.first),
      );
    }
  }

  Future<void> deletePermanently(String id) async {
    await _ensurePermission(
      permission: Permission.propertyDelete,
      message: 'You do not have permission to delete properties.',
    );
    final before = await _db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (before.isEmpty) {
      return;
    }

    await _db.transaction((txn) async {
      final unitIds = await _loadEntityIds(
        txn,
        table: 'units',
        where: 'asset_property_id = ?',
        whereArgs: <Object?>[id],
      );
      final leaseIds = await _loadEntityIds(
        txn,
        table: 'leases',
        where: 'asset_property_id = ?',
        whereArgs: <Object?>[id],
      );
      final tenantIds = await _loadStringColumn(
        txn,
        table: 'leases',
        column: 'tenant_id',
        where: 'asset_property_id = ? AND tenant_id IS NOT NULL',
        whereArgs: <Object?>[id],
      );
      final ticketIds = await _loadEntityIds(
        txn,
        table: 'maintenance_tickets',
        where: 'asset_property_id = ?',
        whereArgs: <Object?>[id],
      );

      await _deleteEntityReferences(
        txn,
        entityTypes: const <String>['property', 'asset_property'],
        entityId: id,
      );
      for (final unitId in unitIds) {
        await _deleteEntityReferences(
          txn,
          entityTypes: const <String>['unit'],
          entityId: unitId,
        );
      }
      for (final leaseId in leaseIds) {
        await _deleteEntityReferences(
          txn,
          entityTypes: const <String>['lease'],
          entityId: leaseId,
        );
      }
      for (final ticketId in ticketIds) {
        await _deleteEntityReferences(
          txn,
          entityTypes: const <String>['maintenance_ticket'],
          entityId: ticketId,
        );
      }

      await txn.rawDelete(
        '''
        DELETE FROM scenario_version_blobs
        WHERE version_id IN (
          SELECT sv.id
          FROM scenario_versions sv
          INNER JOIN scenarios s ON s.id = sv.scenario_id
          WHERE s.property_id = ?
        )
        ''',
        <Object?>[id],
      );
      await txn.rawDelete(
        '''
        DELETE FROM scenario_versions
        WHERE scenario_id IN (SELECT id FROM scenarios WHERE property_id = ?)
        ''',
        <Object?>[id],
      );
      await txn.rawDelete(
        '''
        DELETE FROM scenario_valuation
        WHERE scenario_id IN (SELECT id FROM scenarios WHERE property_id = ?)
        ''',
        <Object?>[id],
      );
      await txn.rawDelete(
        '''
        DELETE FROM scenario_inputs
        WHERE scenario_id IN (SELECT id FROM scenarios WHERE property_id = ?)
        ''',
        <Object?>[id],
      );
      await txn.rawDelete(
        '''
        DELETE FROM expense_lines
        WHERE scenario_id IN (SELECT id FROM scenarios WHERE property_id = ?)
        ''',
        <Object?>[id],
      );
      await txn.rawDelete(
        '''
        DELETE FROM income_lines
        WHERE scenario_id IN (SELECT id FROM scenarios WHERE property_id = ?)
        ''',
        <Object?>[id],
      );
      await txn.rawDelete(
        '''
        DELETE FROM reports
        WHERE property_id = ?
           OR scenario_id IN (SELECT id FROM scenarios WHERE property_id = ?)
        ''',
        <Object?>[id, id],
      );
      await txn.rawDelete(
        '''
        DELETE FROM search_index
        WHERE entity_type = 'scenario'
          AND entity_id IN (SELECT id FROM scenarios WHERE property_id = ?)
        ''',
        <Object?>[id],
      );
      await txn.delete(
        'scenarios',
        where: 'property_id = ?',
        whereArgs: <Object?>[id],
      );

      await _deleteBudgetsForEntity(txn, id);
      await txn.delete(
        'ledger_entries',
        where: "entity_type IN ('property', 'asset_property') AND entity_id = ?",
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        'comps_sales',
        where: 'property_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        'comps_rentals',
        where: 'property_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        'property_criteria_overrides',
        where: 'property_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        'portfolio_properties',
        where: 'property_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        'property_profiles',
        where: 'property_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        'property_kpi_snapshots',
        where: 'property_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        'esg_profiles',
        where: 'property_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        'operations_alert_states',
        where: 'property_id = ?',
        whereArgs: <Object?>[id],
      );

      await txn.delete(
        'asset_operating_cost_history',
        where: 'property_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        'asset_operating_costs',
        where: 'property_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        'rental_income_plans',
        where: 'property_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        'hotel_kpis',
        where: 'property_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        'renovation_projects',
        where: 'property_id = ?',
        whereArgs: <Object?>[id],
      );

      await txn.rawDelete(
        '''
        DELETE FROM covenant_checks
        WHERE covenant_id IN (
          SELECT c.id
          FROM covenants c
          INNER JOIN loans l ON l.id = c.loan_id
          WHERE l.asset_property_id = ?
        )
        ''',
        <Object?>[id],
      );
      await txn.rawDelete(
        '''
        DELETE FROM covenants
        WHERE loan_id IN (SELECT id FROM loans WHERE asset_property_id = ?)
        ''',
        <Object?>[id],
      );
      await txn.rawDelete(
        '''
        DELETE FROM loan_periods
        WHERE loan_id IN (SELECT id FROM loans WHERE asset_property_id = ?)
        ''',
        <Object?>[id],
      );
      await txn.delete(
        'loans',
        where: 'asset_property_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        'capital_events',
        where: 'asset_property_id = ?',
        whereArgs: <Object?>[id],
      );

      await txn.rawDelete(
        '''
        DELETE FROM rent_roll_lines
        WHERE snapshot_id IN (
          SELECT id FROM rent_roll_snapshots WHERE asset_property_id = ?
        )
        ''',
        <Object?>[id],
      );
      await txn.delete(
        'rent_roll_snapshots',
        where: 'asset_property_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.rawDelete(
        '''
        DELETE FROM lease_rent_schedule
        WHERE lease_id IN (SELECT id FROM leases WHERE asset_property_id = ?)
        ''',
        <Object?>[id],
      );
      await txn.rawDelete(
        '''
        DELETE FROM lease_indexation_rules
        WHERE lease_id IN (SELECT id FROM leases WHERE asset_property_id = ?)
        ''',
        <Object?>[id],
      );
      await txn.delete(
        'maintenance_tickets',
        where: 'asset_property_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        'leases',
        where: 'asset_property_id = ?',
        whereArgs: <Object?>[id],
      );
      for (final tenantId in tenantIds) {
        await _deleteTenantIfOrphaned(txn, tenantId);
      }
      await txn.delete(
        'units',
        where: 'asset_property_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        'properties',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });

    await _recordAudit(
      entityType: 'property',
      entityId: id,
      action: 'delete',
      summary: 'Property permanently deleted',
      oldValues: before.first,
    );
  }

  Future<List<String>> _loadEntityIds(
    Transaction txn, {
    required String table,
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final rows = await txn.query(
      table,
      columns: const <String>['id'],
      where: where,
      whereArgs: whereArgs,
    );
    return rows
        .map((row) => row['id'])
        .whereType<String>()
        .toList(growable: false);
  }

  Future<List<String>> _loadStringColumn(
    Transaction txn, {
    required String table,
    required String column,
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final rows = await txn.query(
      table,
      columns: <String>[column],
      where: where,
      whereArgs: whereArgs,
      distinct: true,
    );
    return rows
        .map((row) => row[column])
        .whereType<String>()
        .toList(growable: false);
  }

  Future<void> _deleteTenantIfOrphaned(
    Transaction txn,
    String tenantId,
  ) async {
    final remainingLeases = await txn.query(
      'leases',
      columns: const <String>['id'],
      where: 'tenant_id = ?',
      whereArgs: <Object?>[tenantId],
      limit: 1,
    );
    if (remainingLeases.isNotEmpty) {
      return;
    }
    await _deleteEntityReferences(
      txn,
      entityTypes: const <String>['tenant'],
      entityId: tenantId,
    );
    await txn.delete(
      'tenants',
      where: 'id = ?',
      whereArgs: <Object?>[tenantId],
    );
  }

  Future<void> _deleteEntityReferences(
    Transaction txn, {
    required List<String> entityTypes,
    required String entityId,
  }) async {
    final placeholders = List<String>.filled(entityTypes.length, '?').join(', ');
    final args = <Object?>[...entityTypes, entityId];
    final where = 'entity_type IN ($placeholders) AND entity_id = ?';
    final documentIds = await _loadEntityIds(
      txn,
      table: 'documents',
      where: where,
      whereArgs: args,
    );

    await txn.rawDelete(
      '''
      DELETE FROM document_metadata
      WHERE document_id IN (SELECT id FROM documents WHERE $where)
      ''',
      args,
    );
    await txn.rawDelete(
      '''
      DELETE FROM search_index
      WHERE entity_type = 'document'
        AND entity_id IN (SELECT id FROM documents WHERE $where)
      ''',
      args,
    );
    await txn.delete('documents', where: where, whereArgs: args);
    for (final documentId in documentIds) {
      await _deleteEntityReferences(
        txn,
        entityTypes: const <String>['document'],
        entityId: documentId,
      );
    }

    await txn.rawDelete(
      '''
      DELETE FROM task_checklist_items
      WHERE task_id IN (SELECT id FROM tasks WHERE $where)
      ''',
      args,
    );
    await txn.rawDelete(
      '''
      DELETE FROM search_index
      WHERE entity_type = 'task'
        AND entity_id IN (SELECT id FROM tasks WHERE $where)
      ''',
      args,
    );
    await txn.delete('tasks', where: where, whereArgs: args);
    await txn.delete('task_generated_instances', where: where, whereArgs: args);
    await txn.delete('notes', where: where, whereArgs: args);
    await txn.delete('notifications', where: where, whereArgs: args);
    await txn.delete('search_index', where: where, whereArgs: args);
  }

  Future<void> _deleteBudgetsForEntity(Transaction txn, String propertyId) async {
    await txn.rawDelete(
      '''
      DELETE FROM budget_lines
      WHERE budget_id IN (
        SELECT id
        FROM budgets
        WHERE entity_type IN ('property', 'asset_property') AND entity_id = ?
      )
      ''',
      <Object?>[propertyId],
    );
    await txn.delete(
      'budgets',
      where: "entity_type IN ('property', 'asset_property') AND entity_id = ?",
      whereArgs: <Object?>[propertyId],
    );
  }

  Future<void> _ensurePermission({
    required String permission,
    required String message,
  }) async {
    final guard = _permissionGuard;
    final contextResolver = _securityContextResolver;
    if (guard == null || contextResolver == null) {
      return;
    }
    final context = await contextResolver();
    guard.ensurePermission(
      role: context.user.role,
      permission: permission,
      context: PermissionContext(
        scopeType: PermissionScopeType.workspace,
        scopeId: context.workspace.id,
        workspaceId: context.workspace.id,
      ),
      message: message,
    );
  }

  Future<void> _recordAudit({
    required String entityType,
    required String entityId,
    required String action,
    String? summary,
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
      oldValues: oldValues,
      newValues: newValues,
      diffItems: diffItems,
      source: 'ui',
    );
  }
}
