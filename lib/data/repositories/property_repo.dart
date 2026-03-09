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
