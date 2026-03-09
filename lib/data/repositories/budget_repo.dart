import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_service.dart';
import '../../core/finance/budget_vs_actual.dart';
import '../../core/models/budget.dart';
import '../../core/models/ledger.dart';
import 'audit_log_repo.dart';

class BudgetRepo {
  BudgetRepo(this._db, this._engine, {AuditLogRepo? auditLogRepo})
    : _auditLogRepo = auditLogRepo;

  final Database _db;
  final BudgetVsActual _engine;
  final AuditLogRepo? _auditLogRepo;
  static const AuditService _auditService = AuditService();

  Future<BudgetRecord> createBudget({
    required String entityType,
    required String entityId,
    required int fiscalYear,
    required String versionName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final budget = BudgetRecord(
      id: const Uuid().v4(),
      entityType: entityType,
      entityId: entityId,
      fiscalYear: fiscalYear,
      versionName: versionName,
      status: 'draft',
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert(
      'budgets',
      budget.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _auditLogRepo?.recordEvent(
      entityType: 'budget',
      entityId: budget.id,
      action: 'create',
      summary: 'Budget created: ${budget.versionName}',
      source: 'ui',
    );
    return budget;
  }

  Future<void> renameBudget({
    required String budgetId,
    required String versionName,
  }) async {
    final before = await _db.query(
      'budgets',
      where: 'id = ?',
      whereArgs: <Object?>[budgetId],
      limit: 1,
    );
    await _db.update(
      'budgets',
      <String, Object?>{
        'version_name': versionName,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[budgetId],
    );
    final after = await _db.query(
      'budgets',
      where: 'id = ?',
      whereArgs: <Object?>[budgetId],
      limit: 1,
    );
    if (before.isNotEmpty && after.isNotEmpty) {
      await _auditLogRepo?.recordEvent(
        entityType: 'budget',
        entityId: budgetId,
        action: 'update',
        summary: 'Budget renamed',
        diffItems: _auditService.buildDiff(before.first, after.first),
        source: 'ui',
      );
    }
  }

  Future<void> setStatus({
    required String budgetId,
    required String status,
  }) async {
    final before = await _db.query(
      'budgets',
      where: 'id = ?',
      whereArgs: <Object?>[budgetId],
      limit: 1,
    );
    await _db.update(
      'budgets',
      <String, Object?>{
        'status': status,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[budgetId],
    );
    final after = await _db.query(
      'budgets',
      where: 'id = ?',
      whereArgs: <Object?>[budgetId],
      limit: 1,
    );
    if (before.isNotEmpty && after.isNotEmpty) {
      await _auditLogRepo?.recordEvent(
        entityType: 'budget',
        entityId: budgetId,
        action: 'update',
        summary: 'Budget status changed',
        diffItems: _auditService.buildDiff(before.first, after.first),
        source: 'ui',
      );
    }
  }

  Future<void> deleteBudget(String budgetId) async {
    final rows = await _db.query(
      'budgets',
      columns: const <String>['status'],
      where: 'id = ?',
      whereArgs: <Object?>[budgetId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return;
    }
    final status = rows.first['status']! as String;
    if (status == 'approved') {
      throw StateError('Approved budgets cannot be deleted.');
    }
    await _db.delete(
      'budgets',
      where: 'id = ?',
      whereArgs: <Object?>[budgetId],
    );
    await _auditLogRepo?.recordEvent(
      entityType: 'budget',
      entityId: budgetId,
      action: 'delete',
      summary: 'Budget deleted',
      source: 'ui',
    );
  }

  Future<BudgetLineRecord> upsertBudgetLine({
    String? id,
    required String budgetId,
    required String accountId,
    required String periodKey,
    required String direction,
    required double amount,
    String? notes,
  }) async {
    final line = BudgetLineRecord(
      id: id ?? const Uuid().v4(),
      budgetId: budgetId,
      accountId: accountId,
      periodKey: periodKey,
      direction: direction,
      amount: amount.abs(),
      notes: notes,
    );
    await _db.insert(
      'budget_lines',
      line.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _auditLogRepo?.recordEvent(
      entityType: 'budget_line',
      entityId: line.id,
      action: 'update',
      summary: 'Budget line upserted for budget $budgetId',
      source: 'ui',
    );
    return line;
  }

  Future<List<BudgetRecord>> listBudgets({
    required String entityType,
    required String entityId,
  }) async {
    final rows = await _db.query(
      'budgets',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: <Object?>[entityType, entityId],
      orderBy: 'fiscal_year DESC, updated_at DESC',
    );
    return rows.map(BudgetRecord.fromMap).toList();
  }

  Future<BudgetDetail?> getBudgetDetail(String budgetId) async {
    final budgetRows = await _db.query(
      'budgets',
      where: 'id = ?',
      whereArgs: <Object?>[budgetId],
      limit: 1,
    );
    if (budgetRows.isEmpty) {
      return null;
    }
    final lineRows = await _db.query(
      'budget_lines',
      where: 'budget_id = ?',
      whereArgs: <Object?>[budgetId],
      orderBy: 'period_key ASC',
    );
    return BudgetDetail(
      budget: BudgetRecord.fromMap(budgetRows.first),
      lines: lineRows.map(BudgetLineRecord.fromMap).toList(),
    );
  }

  Future<List<BudgetVarianceRecord>> computeBudgetVsActual({
    required String entityType,
    required String entityId,
    required String budgetId,
    String? fromPeriod,
    String? toPeriod,
  }) async {
    final detail = await getBudgetDetail(budgetId);
    if (detail == null) {
      return const [];
    }

    final ledgerWhere = <String>['le.entity_type = ?'];
    final args = <Object?>[entityType];
    if (entityId.isNotEmpty) {
      ledgerWhere.add('le.entity_id = ?');
      args.add(entityId);
    }
    if (fromPeriod != null) {
      ledgerWhere.add('le.period_key >= ?');
      args.add(fromPeriod);
    }
    if (toPeriod != null) {
      ledgerWhere.add('le.period_key <= ?');
      args.add(toPeriod);
    }

    final rows = await _db.rawQuery('''
      SELECT le.*
      FROM ledger_entries le
      WHERE ${ledgerWhere.join(' AND ')}
      ORDER BY le.period_key ASC
      ''', args);
    final actualEntries = rows.map(LedgerEntryRecord.fromMap).toList();

    final budgetLines =
        detail.lines.where((line) {
          if (fromPeriod != null && line.periodKey.compareTo(fromPeriod) < 0) {
            return false;
          }
          if (toPeriod != null && line.periodKey.compareTo(toPeriod) > 0) {
            return false;
          }
          return true;
        }).toList();

    return _engine.computeVariance(
      budgetLines: budgetLines,
      ledgerEntries: actualEntries,
    );
  }
}
