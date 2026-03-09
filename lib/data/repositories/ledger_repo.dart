import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/audit/audit_service.dart';
import '../../core/models/ledger.dart';
import '../../core/services/ledger_service.dart';
import 'audit_log_repo.dart';
import 'search_repo.dart';

class LedgerRepo {
  LedgerRepo(
    this._db,
    this._service, {
    AuditLogRepo? auditLogRepo,
    SearchRepo? searchRepo,
  }) : _auditLogRepo = auditLogRepo,
       _searchRepo = searchRepo;

  final Database _db;
  final LedgerService _service;
  final AuditLogRepo? _auditLogRepo;
  final SearchRepo? _searchRepo;
  static const AuditService _auditService = AuditService();

  Future<List<LedgerAccountRecord>> listAccounts() async {
    final rows = await _db.query(
      'ledger_accounts',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(LedgerAccountRecord.fromMap).toList();
  }

  Future<LedgerAccountRecord> createAccount({
    required String name,
    required String kind,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = LedgerAccountRecord(
      id: const Uuid().v4(),
      name: name.trim(),
      kind: kind.trim(),
      createdAt: now,
    );
    await _db.insert(
      'ledger_accounts',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _auditLogRepo?.recordEvent(
      entityType: 'ledger_account',
      entityId: record.id,
      action: 'create',
      summary: 'Ledger account created: ${record.name}',
      source: 'ui',
    );
    return record;
  }

  Future<void> renameAccount({
    required String accountId,
    required String name,
  }) async {
    final before = await _db.query(
      'ledger_accounts',
      where: 'id = ?',
      whereArgs: <Object?>[accountId],
      limit: 1,
    );
    await _db.update(
      'ledger_accounts',
      <String, Object?>{'name': name.trim()},
      where: 'id = ?',
      whereArgs: <Object?>[accountId],
    );
    final after = await _db.query(
      'ledger_accounts',
      where: 'id = ?',
      whereArgs: <Object?>[accountId],
      limit: 1,
    );
    if (before.isNotEmpty && after.isNotEmpty) {
      await _auditLogRepo?.recordEvent(
        entityType: 'ledger_account',
        entityId: accountId,
        action: 'update',
        summary: 'Ledger account renamed',
        diffItems: _auditService.buildDiff(before.first, after.first),
        source: 'ui',
      );
    }
  }

  Future<void> deleteAccount(String accountId) async {
    final linked = _firstIntValue(
      await _db.rawQuery(
        'SELECT COUNT(*) FROM ledger_entries WHERE account_id = ?',
        <Object?>[accountId],
      ),
    );
    if (linked > 0) {
      throw StateError('Cannot delete account with existing entries.');
    }
    await _db.delete(
      'ledger_accounts',
      where: 'id = ?',
      whereArgs: <Object?>[accountId],
    );
    await _auditLogRepo?.recordEvent(
      entityType: 'ledger_account',
      entityId: accountId,
      action: 'delete',
      summary: 'Ledger account deleted',
      source: 'ui',
    );
  }

  Future<LedgerEntryRecord> createEntry({
    required String entityType,
    required String? entityId,
    required String accountId,
    required int postedAt,
    required String direction,
    required double amount,
    required String currencyCode,
    String? counterparty,
    String? memo,
    String? documentId,
  }) async {
    final normalizedAmount = amount.abs();
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = LedgerEntryRecord(
      id: const Uuid().v4(),
      entityType: entityType,
      entityId: entityId,
      accountId: accountId,
      postedAt: postedAt,
      periodKey: _service.derivePeriodKey(postedAt),
      direction: direction,
      amount: normalizedAmount,
      currencyCode: currencyCode,
      counterparty: counterparty,
      memo: memo,
      documentId: documentId,
      createdAt: now,
    );
    await _db.insert(
      'ledger_entries',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.upsertIndexEntry(
        searchRepo.buildLedgerEntryRecord(record),
      );
    }
    await _auditLogRepo?.recordEvent(
      entityType: 'ledger_entry',
      entityId: record.id,
      action: 'create',
      summary: 'Ledger entry created',
      source: 'ui',
    );
    return record;
  }

  Future<void> updateEntry(LedgerEntryRecord entry) async {
    final before = await _db.query(
      'ledger_entries',
      where: 'id = ?',
      whereArgs: <Object?>[entry.id],
      limit: 1,
    );
    await _db.update(
      'ledger_entries',
      entry.toMap().map(
        (key, value) => MapEntry(
          key,
          key == 'amount' && value is num ? value.abs() : value,
        ),
      ),
      where: 'id = ?',
      whereArgs: <Object?>[entry.id],
    );
    final after = await _db.query(
      'ledger_entries',
      where: 'id = ?',
      whereArgs: <Object?>[entry.id],
      limit: 1,
    );
    if (before.isNotEmpty && after.isNotEmpty) {
      final searchRepo = _searchRepo;
      if (searchRepo != null) {
        await searchRepo.upsertIndexEntry(
          searchRepo.buildLedgerEntryRecord(LedgerEntryRecord.fromMap(after.first)),
        );
      }
      await _auditLogRepo?.recordEvent(
        entityType: 'ledger_entry',
        entityId: entry.id,
        action: 'update',
        summary: 'Ledger entry updated',
        diffItems: _auditService.buildDiff(before.first, after.first),
        source: 'ui',
      );
    }
  }

  Future<void> deleteEntry(String id) async {
    final before = await _db.query(
      'ledger_entries',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    await _db.delete(
      'ledger_entries',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    final searchRepo = _searchRepo;
    if (searchRepo != null) {
      await searchRepo.deleteIndexEntryByEntity(
        entityType: 'ledger_entry',
        entityId: id,
      );
    }
    await _auditLogRepo?.recordEvent(
      entityType: 'ledger_entry',
      entityId: id,
      action: 'delete',
      summary:
          before.isEmpty ? 'Ledger entry deleted' : 'Ledger entry deleted.',
      source: 'ui',
    );
  }

  Future<List<LedgerEntryRecord>> listEntries({
    String? entityType,
    String? entityId,
    String? periodFrom,
    String? periodTo,
    String? accountId,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (entityType != null) {
      where.add('entity_type = ?');
      args.add(entityType);
    }
    if (entityId != null) {
      where.add('entity_id = ?');
      args.add(entityId);
    }
    if (periodFrom != null) {
      where.add('period_key >= ?');
      args.add(periodFrom);
    }
    if (periodTo != null) {
      where.add('period_key <= ?');
      args.add(periodTo);
    }
    if (accountId != null) {
      where.add('account_id = ?');
      args.add(accountId);
    }
    final rows = await _db.query(
      'ledger_entries',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'posted_at DESC, created_at DESC',
    );
    return rows.map(LedgerEntryRecord.fromMap).toList();
  }

  Future<List<LedgerPeriodAggregate>> aggregateByPeriod({
    required String entityType,
    String? entityId,
    String metric = 'net',
  }) async {
    final where = <String>['entity_type = ?'];
    final args = <Object?>[entityType];
    if (entityId != null) {
      where.add('entity_id = ?');
      args.add(entityId);
    }
    final rows = await _db.query(
      'ledger_entries',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'period_key ASC',
    );

    final grouped = <String, List<LedgerEntryRecord>>{};
    for (final row in rows.map(LedgerEntryRecord.fromMap)) {
      grouped.putIfAbsent(row.periodKey, () => <LedgerEntryRecord>[]).add(row);
    }

    final results = <LedgerPeriodAggregate>[];
    final keys = grouped.keys.toList()..sort();
    for (final key in keys) {
      final items = grouped[key]!;
      var totalIn = 0.0;
      var totalOut = 0.0;
      for (final item in items) {
        final signed = _service.computeSignedAmount(
          direction: item.direction,
          amount: item.amount,
        );
        if (signed >= 0) {
          totalIn += signed;
        } else {
          totalOut += signed.abs();
        }
      }
      final net = totalIn - totalOut;
      results.add(
        LedgerPeriodAggregate(
          periodKey: key,
          totalIn: metric == 'in' ? totalIn : totalIn,
          totalOut: metric == 'out' ? totalOut : totalOut,
          net: net,
        ),
      );
    }
    return results;
  }

  int _firstIntValue(List<Map<String, Object?>> rows) {
    if (rows.isEmpty || rows.first.isEmpty) {
      return 0;
    }
    final value = rows.first.values.first;
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString()) ?? 0;
  }
}
