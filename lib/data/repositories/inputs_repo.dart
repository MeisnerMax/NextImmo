import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_service.dart';
import '../../core/audit/audit_writer.dart';
import '../../core/models/audit_log.dart';
import '../../core/models/inputs.dart';
import '../../core/models/scenario.dart';
import '../../core/models/settings.dart';
import 'audit_log_repo.dart';

class InputsRepository {
  InputsRepository(this._db, {AuditLogRepo? auditLogRepo, AuditWriter? auditWriter})
    : _auditLogRepo = auditLogRepo,
      _auditWriter = auditWriter;

  final Database _db;
  final AuditLogRepo? _auditLogRepo;
  final AuditWriter? _auditWriter;
  static const AuditService _auditService = AuditService();

  Future<AppSettingsRecord> getSettings() async {
    final rows = await _db.query('app_settings', where: 'id = 1', limit: 1);
    if (rows.isEmpty) {
      final settings = AppSettingsRecord(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _db.insert(
        'app_settings',
        settings.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return settings;
    }
    return AppSettingsRecord.fromMap(rows.first);
  }

  Future<void> updateSettings(AppSettingsRecord settings) async {
    await _db.insert(
      'app_settings',
      settings.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ScenarioInputs> getInputs({
    required String scenarioId,
    required AppSettingsRecord settings,
  }) async {
    final rows = await _db.query(
      'scenario_inputs',
      where: 'scenario_id = ?',
      whereArgs: <Object?>[scenarioId],
      limit: 1,
    );
    if (rows.isEmpty) {
      final defaults = ScenarioInputs.defaults(
        scenarioId: scenarioId,
        settings: settings,
      );
      await _db.insert(
        'scenario_inputs',
        defaults.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return defaults;
    }
    return ScenarioInputs.fromMap(rows.first);
  }

  Future<void> upsertInputs(ScenarioInputs inputs) async {
    final context = await _scenarioContext(inputs.scenarioId);
    final before = await _db.query(
      'scenario_inputs',
      where: 'scenario_id = ?',
      whereArgs: <Object?>[inputs.scenarioId],
      limit: 1,
    );
    await _db.insert(
      'scenario_inputs',
      inputs.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final action = before.isEmpty ? 'create' : 'update';
    final diffItems =
        before.isEmpty
            ? const <AuditDiffItem>[]
            : _auditService.buildDiff(before.first, inputs.toMap());
    await _markScenarioChangedIfApproved(inputs.scenarioId);
    await _recordAudit(
      entityType: 'scenario_inputs',
      entityId: inputs.scenarioId,
      action: action,
      summary:
          action == 'create'
              ? 'Scenario inputs created'
              : 'Scenario inputs updated',
      parentEntityId: context?.propertyId,
      oldValues: before.isEmpty ? null : before.first,
      newValues: inputs.toMap(),
      diffItems: diffItems,
    );
  }

  Future<List<IncomeLine>> listIncomeLines(String scenarioId) async {
    final rows = await _db.query(
      'income_lines',
      where: 'scenario_id = ?',
      whereArgs: <Object?>[scenarioId],
      orderBy: 'name ASC',
    );
    return rows.map(IncomeLine.fromMap).toList();
  }

  Future<List<ExpenseLine>> listExpenseLines(String scenarioId) async {
    final rows = await _db.query(
      'expense_lines',
      where: 'scenario_id = ?',
      whereArgs: <Object?>[scenarioId],
      orderBy: 'name ASC',
    );
    return rows.map(ExpenseLine.fromMap).toList();
  }

  Future<IncomeLine> addIncomeLine({
    required String scenarioId,
    required String name,
    required double amountMonthly,
  }) async {
    final context = await _scenarioContext(scenarioId);
    final line = IncomeLine(
      id: const Uuid().v4(),
      scenarioId: scenarioId,
      name: name,
      amountMonthly: amountMonthly,
      enabled: true,
    );
    await _db.insert(
      'income_lines',
      line.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _markScenarioChangedIfApproved(scenarioId);
    await _recordAudit(
      entityType: 'income_line',
      entityId: line.id,
      action: 'create',
      summary: 'Income line created for scenario $scenarioId',
      parentEntityId: context?.propertyId,
      newValues: line.toMap(),
    );
    return line;
  }

  Future<void> updateIncomeLine(IncomeLine line) async {
    final context = await _scenarioContext(line.scenarioId);
    final before = await _db.query(
      'income_lines',
      where: 'id = ?',
      whereArgs: <Object?>[line.id],
      limit: 1,
    );
    await _db.update(
      'income_lines',
      line.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[line.id],
    );
    if (before.isNotEmpty) {
      await _markScenarioChangedIfApproved(line.scenarioId);
      await _recordAudit(
        entityType: 'income_line',
        entityId: line.id,
        action: 'update',
        summary: 'Income line updated',
        parentEntityId: context?.propertyId,
        oldValues: before.first,
        newValues: line.toMap(),
        diffItems: _auditService.buildDiff(before.first, line.toMap()),
      );
    }
  }

  Future<void> setIncomeLineEnabled(String id, bool enabled) async {
    final before = await _db.query(
      'income_lines',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    await _db.update(
      'income_lines',
      <String, Object?>{'enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    final after = await _db.query(
      'income_lines',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (before.isNotEmpty && after.isNotEmpty) {
      final scenarioId = after.first['scenario_id'] as String;
      final context = await _scenarioContext(scenarioId);
      await _markScenarioChangedIfApproved(scenarioId);
      await _recordAudit(
        entityType: 'income_line',
        entityId: id,
        action: 'update',
        summary: 'Income line enabled flag changed',
        parentEntityId: context?.propertyId,
        oldValues: before.first,
        newValues: after.first,
        diffItems: _auditService.buildDiff(before.first, after.first),
      );
    }
  }

  Future<ExpenseLine> addExpenseLine({
    required String scenarioId,
    required String name,
    required String kind,
    double amountMonthly = 0,
    double percent = 0,
  }) async {
    final context = await _scenarioContext(scenarioId);
    final line = ExpenseLine(
      id: const Uuid().v4(),
      scenarioId: scenarioId,
      name: name,
      kind: kind,
      amountMonthly: amountMonthly,
      percent: percent,
      enabled: true,
    );
    await _db.insert(
      'expense_lines',
      line.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _markScenarioChangedIfApproved(scenarioId);
    await _recordAudit(
      entityType: 'expense_line',
      entityId: line.id,
      action: 'create',
      summary: 'Expense line created for scenario $scenarioId',
      parentEntityId: context?.propertyId,
      newValues: line.toMap(),
    );
    return line;
  }

  Future<void> updateExpenseLine(ExpenseLine line) async {
    final context = await _scenarioContext(line.scenarioId);
    final before = await _db.query(
      'expense_lines',
      where: 'id = ?',
      whereArgs: <Object?>[line.id],
      limit: 1,
    );
    await _db.update(
      'expense_lines',
      line.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[line.id],
    );
    if (before.isNotEmpty) {
      await _markScenarioChangedIfApproved(line.scenarioId);
      await _recordAudit(
        entityType: 'expense_line',
        entityId: line.id,
        action: 'update',
        summary: 'Expense line updated',
        parentEntityId: context?.propertyId,
        oldValues: before.first,
        newValues: line.toMap(),
        diffItems: _auditService.buildDiff(before.first, line.toMap()),
      );
    }
  }

  Future<void> setExpenseLineEnabled(String id, bool enabled) async {
    final before = await _db.query(
      'expense_lines',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    await _db.update(
      'expense_lines',
      <String, Object?>{'enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    final after = await _db.query(
      'expense_lines',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (before.isNotEmpty && after.isNotEmpty) {
      final scenarioId = after.first['scenario_id'] as String;
      final context = await _scenarioContext(scenarioId);
      await _markScenarioChangedIfApproved(scenarioId);
      await _recordAudit(
        entityType: 'expense_line',
        entityId: id,
        action: 'update',
        summary: 'Expense line enabled flag changed',
        parentEntityId: context?.propertyId,
        oldValues: before.first,
        newValues: after.first,
        diffItems: _auditService.buildDiff(before.first, after.first),
      );
    }
  }

  Future<void> deleteIncomeLine(String id) async {
    final before = await _db.query(
      'income_lines',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    final scenarioId = before.isEmpty ? null : before.first['scenario_id'] as String?;
    final context =
        scenarioId == null ? null : await _scenarioContext(scenarioId);
    await _db.delete('income_lines', where: 'id = ?', whereArgs: <Object?>[id]);
    if (scenarioId != null) {
      await _markScenarioChangedIfApproved(scenarioId);
    }
    await _recordAudit(
      entityType: 'income_line',
      entityId: id,
      action: 'delete',
      summary: 'Income line deleted',
      parentEntityId: context?.propertyId,
      oldValues: before.isEmpty ? null : before.first,
      newValues: const <String, Object?>{},
      diffItems:
          before.isEmpty
              ? const <AuditDiffItem>[]
              : _auditService.buildDiff(
                before.first,
                const <String, Object?>{},
              ),
    );
  }

  Future<void> deleteExpenseLine(String id) async {
    final before = await _db.query(
      'expense_lines',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    final scenarioId = before.isEmpty ? null : before.first['scenario_id'] as String?;
    final context =
        scenarioId == null ? null : await _scenarioContext(scenarioId);
    await _db.delete(
      'expense_lines',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (scenarioId != null) {
      await _markScenarioChangedIfApproved(scenarioId);
    }
    await _recordAudit(
      entityType: 'expense_line',
      entityId: id,
      action: 'delete',
      summary: 'Expense line deleted',
      parentEntityId: context?.propertyId,
      oldValues: before.isEmpty ? null : before.first,
      newValues: const <String, Object?>{},
      diffItems:
          before.isEmpty
              ? const <AuditDiffItem>[]
              : _auditService.buildDiff(
                before.first,
                const <String, Object?>{},
              ),
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

  Future<_ScenarioContext?> _scenarioContext(String scenarioId) async {
    final rows = await _db.query(
      'scenarios',
      columns: const <String>['id', 'property_id'],
      where: 'id = ?',
      whereArgs: <Object?>[scenarioId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _ScenarioContext(
      scenarioId: rows.first['id']! as String,
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

class _ScenarioContext {
  const _ScenarioContext({required this.scenarioId, required this.propertyId});

  final String scenarioId;
  final String propertyId;
}
