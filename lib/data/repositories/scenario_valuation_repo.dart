import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/audit/audit_service.dart';
import '../../core/audit/audit_writer.dart';
import '../../core/models/audit_log.dart';
import '../../core/models/scenario.dart';
import '../../core/models/scenario_valuation.dart';
import 'audit_log_repo.dart';

class ScenarioValuationRepo {
  const ScenarioValuationRepo(
    this._db, {
    AuditLogRepo? auditLogRepo,
    AuditWriter? auditWriter,
  }) : _auditLogRepo = auditLogRepo,
       _auditWriter = auditWriter;

  final Database _db;
  final AuditLogRepo? _auditLogRepo;
  final AuditWriter? _auditWriter;
  static const AuditService _auditService = AuditService();

  Future<ScenarioValuationRecord> getForScenario(String scenarioId) async {
    final rows = await _db.query(
      'scenario_valuation',
      where: 'scenario_id = ?',
      whereArgs: <Object?>[scenarioId],
      limit: 1,
    );
    if (rows.isEmpty) {
      final defaults = ScenarioValuationRecord.defaults(scenarioId: scenarioId);
      await upsert(defaults);
      return defaults;
    }
    return ScenarioValuationRecord.fromMap(rows.first);
  }

  Future<void> upsert(ScenarioValuationRecord record) async {
    final before = await _db.query(
      'scenario_valuation',
      where: 'scenario_id = ?',
      whereArgs: <Object?>[record.scenarioId],
      limit: 1,
    );
    await _db.insert(
      'scenario_valuation',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _markScenarioChangedIfApproved(record.scenarioId);
    final context = await _scenarioContext(record.scenarioId);
    await _recordAudit(
      entityType: 'scenario_valuation',
      entityId: record.scenarioId,
      action: before.isEmpty ? 'create' : 'update',
      summary:
          before.isEmpty
              ? 'Scenario valuation created'
              : 'Scenario valuation updated',
      parentEntityId: context?.propertyId,
      oldValues: before.isEmpty ? null : before.first,
      newValues: record.toMap(),
      diffItems:
          before.isEmpty
              ? const <AuditDiffItem>[]
              : _auditService.buildDiff(before.first, record.toMap()),
    );
  }

  Future<void> _markScenarioChangedIfApproved(String scenarioId) async {
    final rows = await _db.query(
      'scenarios',
      columns: const <String>['workflow_status'],
      where: 'id = ?',
      whereArgs: <Object?>[scenarioId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return;
    }
    final status =
        (rows.first['workflow_status'] as String?) ?? ScenarioWorkflowStatus.draft;
    if (status != ScenarioWorkflowStatus.approved) {
      return;
    }
    await _db.update(
      'scenarios',
      <String, Object?>{
        'workflow_status': ScenarioWorkflowStatus.draft,
        'changed_since_approval': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[scenarioId],
    );
  }

  Future<_ScenarioValuationContext?> _scenarioContext(String scenarioId) async {
    final rows = await _db.query(
      'scenarios',
      columns: const <String>['property_id'],
      where: 'id = ?',
      whereArgs: <Object?>[scenarioId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _ScenarioValuationContext(
      propertyId: rows.first['property_id']! as String,
    );
  }

  Future<void> _recordAudit({
    required String entityType,
    required String entityId,
    required String action,
    String? summary,
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
        parentEntityType: parentEntityId == null ? null : 'property',
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
      parentEntityType: parentEntityId == null ? null : 'property',
      parentEntityId: parentEntityId,
      oldValues: oldValues,
      newValues: newValues,
      diffItems: diffItems,
      source: 'ui',
    );
  }
}

class _ScenarioValuationContext {
  const _ScenarioValuationContext({required this.propertyId});

  final String propertyId;
}
