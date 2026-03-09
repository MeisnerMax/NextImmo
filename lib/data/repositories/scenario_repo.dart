import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_service.dart';
import '../../core/audit/audit_writer.dart';
import '../../core/models/audit_log.dart';
import '../../core/models/scenario.dart';
import '../../core/models/security.dart';
import '../../core/security/rbac.dart';
import 'audit_log_repo.dart';
import 'permission_guard.dart';
import 'search_repo.dart';

class ScenarioRepository {
  ScenarioRepository(
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

  Future<List<ScenarioRecord>> listByProperty(String propertyId) async {
    final rows = await _db.query(
      'scenarios',
      where: 'property_id = ?',
      whereArgs: <Object?>[propertyId],
      orderBy: 'updated_at DESC',
    );

    return rows.map(ScenarioRecord.fromMap).toList();
  }

  Future<ScenarioRecord?> getById(String scenarioId) async {
    final rows = await _db.query(
      'scenarios',
      where: 'id = ?',
      whereArgs: <Object?>[scenarioId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ScenarioRecord.fromMap(rows.first);
  }

  Future<ScenarioRecord> create({
    required String propertyId,
    required String name,
    required String strategyType,
    bool isBase = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final scenario = ScenarioRecord(
      id: const Uuid().v4(),
      propertyId: propertyId,
      name: name,
      strategyType: strategyType,
      isBase: isBase,
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

    await _ensureScenarioPermission(
      permission: Permission.scenarioCreate,
      propertyId: propertyId,
      message: 'You do not have permission to create scenarios.',
    );
    await _db.insert(
      'scenarios',
      scenario.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(searchRepo.buildScenarioRecord(scenario));
    }
    await _recordAudit(
      entityType: 'scenario',
      entityId: scenario.id,
      action: 'create',
      summary: 'Scenario created: ${scenario.name}',
      parentEntityType: 'property',
      parentEntityId: scenario.propertyId,
      newValues: scenario.toMap(),
    );
    return scenario;
  }

  Future<ScenarioRecord> duplicate({
    required ScenarioRecord source,
    required String newName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final copy = ScenarioRecord(
      id: const Uuid().v4(),
      propertyId: source.propertyId,
      name: newName,
      strategyType: source.strategyType,
      isBase: false,
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

    await _ensureScenarioPermission(
      permission: Permission.scenarioCreate,
      propertyId: source.propertyId,
      message: 'You do not have permission to duplicate scenarios.',
    );
    await _db.transaction((txn) async {
      await txn.insert(
        'scenarios',
        copy.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      final inputRows = await txn.query(
        'scenario_inputs',
        where: 'scenario_id = ?',
        whereArgs: <Object?>[source.id],
        limit: 1,
      );
      if (inputRows.isNotEmpty) {
        final inputMap =
            Map<String, Object?>.from(inputRows.first)
              ..['scenario_id'] = copy.id
              ..['updated_at'] = now;
        await txn.insert(
          'scenario_inputs',
          inputMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final valuationRows = await txn.query(
        'scenario_valuation',
        where: 'scenario_id = ?',
        whereArgs: <Object?>[source.id],
        limit: 1,
      );
      if (valuationRows.isNotEmpty) {
        final valuationMap =
            Map<String, Object?>.from(valuationRows.first)
              ..['scenario_id'] = copy.id
              ..['updated_at'] = now;
        await txn.insert(
          'scenario_valuation',
          valuationMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final incomeRows = await txn.query(
        'income_lines',
        where: 'scenario_id = ?',
        whereArgs: <Object?>[source.id],
      );
      for (final row in incomeRows) {
        final newRow =
            Map<String, Object?>.from(row)
              ..['id'] = const Uuid().v4()
              ..['scenario_id'] = copy.id;
        await txn.insert(
          'income_lines',
          newRow,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      final expenseRows = await txn.query(
        'expense_lines',
        where: 'scenario_id = ?',
        whereArgs: <Object?>[source.id],
      );
      for (final row in expenseRows) {
        final newRow =
            Map<String, Object?>.from(row)
              ..['id'] = const Uuid().v4()
              ..['scenario_id'] = copy.id;
        await txn.insert(
          'expense_lines',
          newRow,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });

    await _recordAudit(
      entityType: 'scenario',
      entityId: copy.id,
      action: 'duplicate',
      summary: 'Scenario duplicated from ${source.id}',
      parentEntityType: 'property',
      parentEntityId: copy.propertyId,
      oldValues: source.toMap(),
      newValues: copy.toMap(),
    );
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(searchRepo.buildScenarioRecord(copy));
    }

    return copy;
  }

  Future<void> rename(String scenarioId, String newName) async {
    final before = await _db.query(
      'scenarios',
      where: 'id = ?',
      whereArgs: <Object?>[scenarioId],
      limit: 1,
    );
    if (before.isEmpty) {
      return;
    }
    final beforeRecord = ScenarioRecord.fromMap(before.first);
    await _ensureScenarioPermission(
      permission: Permission.scenarioUpdate,
      propertyId: beforeRecord.propertyId,
      message: 'You do not have permission to update scenarios.',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final update = <String, Object?>{
      'name': newName,
      'updated_at': now,
    };
    if (beforeRecord.isApproved) {
      update['workflow_status'] = ScenarioWorkflowStatus.draft;
      update['changed_since_approval'] = 1;
    }
    await _db.update(
      'scenarios',
      update,
      where: 'id = ?',
      whereArgs: <Object?>[scenarioId],
    );
    final after = await _db.query(
      'scenarios',
      where: 'id = ?',
      whereArgs: <Object?>[scenarioId],
      limit: 1,
    );
    if (before.isNotEmpty && after.isNotEmpty) {
      final updatedRecord = ScenarioRecord.fromMap(after.first);
      final searchRepo = _searchRepo;
      if (searchRepo != null) {
        await searchRepo.upsertIndexEntry(
          searchRepo.buildScenarioRecord(updatedRecord),
        );
      }
      await _recordAudit(
        entityType: 'scenario',
        entityId: scenarioId,
        action: 'update',
        summary:
            beforeRecord.isApproved
                ? 'Scenario renamed and returned to draft'
                : 'Scenario renamed',
        parentEntityType: 'property',
        parentEntityId: updatedRecord.propertyId,
        oldValues: before.first,
        newValues: after.first,
        diffItems: _auditService.buildDiff(before.first, after.first),
      );
    }
  }

  Future<void> delete(String scenarioId) async {
    final before = await _db.query(
      'scenarios',
      where: 'id = ?',
      whereArgs: <Object?>[scenarioId],
      limit: 1,
    );
    if (before.isEmpty) {
      return;
    }
    final beforeRecord = ScenarioRecord.fromMap(before.first);
    await _ensureScenarioPermission(
      permission: Permission.scenarioDelete,
      propertyId: beforeRecord.propertyId,
      message: 'You do not have permission to delete scenarios.',
    );
    await _db.delete(
      'scenarios',
      where: 'id = ?',
      whereArgs: <Object?>[scenarioId],
    );
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.deleteIndexEntryByEntity(
        entityType: 'scenario',
        entityId: scenarioId,
      );
    }
    await _recordAudit(
      entityType: 'scenario',
      entityId: scenarioId,
      action: 'delete',
      summary: 'Scenario deleted: ${beforeRecord.name}',
      parentEntityType: 'property',
      parentEntityId: beforeRecord.propertyId,
      oldValues: before.first,
    );
  }

  Future<ScenarioRecord> submitForReview({
    required String scenarioId,
    String? reviewComment,
  }) {
    return _transitionWorkflow(
      scenarioId: scenarioId,
      nextStatus: ScenarioWorkflowStatus.inReview,
      permission: Permission.scenarioApprove,
      summary: 'Scenario moved to review',
      reviewComment: reviewComment,
    );
  }

  Future<ScenarioRecord> approve({
    required String scenarioId,
    String? reviewComment,
  }) {
    return _transitionWorkflow(
      scenarioId: scenarioId,
      nextStatus: ScenarioWorkflowStatus.approved,
      permission: Permission.scenarioApprove,
      summary: 'Scenario approved',
      reviewComment: reviewComment,
    );
  }

  Future<ScenarioRecord> reject({
    required String scenarioId,
    String? reviewComment,
  }) {
    return _transitionWorkflow(
      scenarioId: scenarioId,
      nextStatus: ScenarioWorkflowStatus.rejected,
      permission: Permission.scenarioApprove,
      summary: 'Scenario rejected',
      reviewComment: reviewComment,
    );
  }

  Future<ScenarioRecord> archive(String scenarioId) {
    return _transitionWorkflow(
      scenarioId: scenarioId,
      nextStatus: ScenarioWorkflowStatus.archived,
      permission: Permission.scenarioDelete,
      summary: 'Scenario archived',
    );
  }

  Future<ScenarioRecord> _transitionWorkflow({
    required String scenarioId,
    required String nextStatus,
    required String permission,
    required String summary,
    String? reviewComment,
  }) async {
    final before = await _db.query(
      'scenarios',
      where: 'id = ?',
      whereArgs: <Object?>[scenarioId],
      limit: 1,
    );
    if (before.isEmpty) {
      throw StateError('Scenario not found.');
    }
    final beforeRecord = ScenarioRecord.fromMap(before.first);
    await _ensureScenarioPermission(
      permission: permission,
      propertyId: beforeRecord.propertyId,
      message: 'You do not have permission to change scenario workflow state.',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final context = await _securityContext();
    final update = <String, Object?>{
      'workflow_status': nextStatus,
      'review_comment': reviewComment?.trim().isEmpty ?? true
          ? null
          : reviewComment!.trim(),
      'updated_at': now,
      'changed_since_approval': 0,
    };
    if (nextStatus == ScenarioWorkflowStatus.approved) {
      update['approved_by'] = context?.user.id;
      update['approved_at'] = now;
      update['rejected_by'] = null;
      update['rejected_at'] = null;
    } else if (nextStatus == ScenarioWorkflowStatus.rejected) {
      update['rejected_by'] = context?.user.id;
      update['rejected_at'] = now;
    }
    await _db.update(
      'scenarios',
      update,
      where: 'id = ?',
      whereArgs: <Object?>[scenarioId],
    );
    final after = await getById(scenarioId);
    if (after == null) {
      throw StateError('Scenario missing after workflow update.');
    }
    await _recordAudit(
      entityType: 'scenario',
      entityId: scenarioId,
      action: nextStatus,
      summary: summary,
      parentEntityType: 'property',
      parentEntityId: after.propertyId,
      oldValues: before.first,
      newValues: after.toMap(),
      diffItems: _auditService.buildDiff(before.first, after.toMap()),
      reason: reviewComment,
    );
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(searchRepo.buildScenarioRecord(after));
    }
    return after;
  }

  Future<void> _ensureScenarioPermission({
    required String permission,
    required String propertyId,
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
        scopeType: PermissionScopeType.property,
        scopeId: propertyId,
        propertyId: propertyId,
        workspaceId: context.workspace.id,
      ),
      message: message,
    );
  }

  Future<SecurityContextRecord?> _securityContext() async {
    final contextResolver = _securityContextResolver;
    if (contextResolver == null) {
      return null;
    }
    return contextResolver();
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
    String? reason,
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
        reason: reason,
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
      reason: reason,
    );
  }
}
