import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/finance/covenant_engine.dart';
import '../../core/models/covenant.dart';

class CovenantRepo {
  const CovenantRepo(this._db, this._engine);

  final Database _db;
  final CovenantEngine _engine;

  Future<List<LoanRecord>> listLoansByAsset(String assetPropertyId) async {
    final rows = await _db.query(
      'loans',
      where: 'asset_property_id = ?',
      whereArgs: <Object?>[assetPropertyId],
      orderBy: 'created_at DESC',
    );
    return rows.map(LoanRecord.fromMap).toList();
  }

  Future<LoanRecord> createLoan({
    required String assetPropertyId,
    String? lenderName,
    required double principal,
    required double interestRatePercent,
    required int termYears,
    required int startDate,
    String amortizationType = 'standard',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final loan = LoanRecord(
      id: const Uuid().v4(),
      assetPropertyId: assetPropertyId,
      lenderName: lenderName,
      principal: principal,
      interestRatePercent: interestRatePercent,
      termYears: termYears,
      startDate: startDate,
      amortizationType: amortizationType,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert(
      'loans',
      loan.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return loan;
  }

  Future<LoanPeriodRecord> upsertLoanPeriod({
    String? id,
    required String loanId,
    required String periodKey,
    required double balanceEnd,
    required double debtService,
  }) async {
    final period = LoanPeriodRecord(
      id: id ?? const Uuid().v4(),
      loanId: loanId,
      periodKey: periodKey,
      balanceEnd: balanceEnd,
      debtService: debtService,
    );
    await _db.insert(
      'loan_periods',
      period.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return period;
  }

  Future<List<LoanPeriodRecord>> listLoanPeriods(String loanId) async {
    final rows = await _db.query(
      'loan_periods',
      where: 'loan_id = ?',
      whereArgs: <Object?>[loanId],
      orderBy: 'period_key ASC',
    );
    return rows.map(LoanPeriodRecord.fromMap).toList();
  }

  Future<CovenantRecord> createCovenant({
    required String loanId,
    required String kind,
    required double threshold,
    required String operator,
    String severity = 'hard',
  }) async {
    final covenant = CovenantRecord(
      id: const Uuid().v4(),
      loanId: loanId,
      kind: kind,
      threshold: threshold,
      operator: operator,
      severity: severity,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.insert(
      'covenants',
      covenant.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return covenant;
  }

  Future<List<CovenantRecord>> listCovenantsByLoan(String loanId) async {
    final rows = await _db.query(
      'covenants',
      where: 'loan_id = ?',
      whereArgs: <Object?>[loanId],
      orderBy: 'created_at ASC',
    );
    return rows.map(CovenantRecord.fromMap).toList();
  }

  Future<List<CovenantCheckRecord>> listChecksByLoan(String loanId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT cc.*
      FROM covenant_checks cc
      INNER JOIN covenants c ON c.id = cc.covenant_id
      WHERE c.loan_id = ?
      ORDER BY cc.period_key DESC
      ''',
      <Object?>[loanId],
    );
    return rows.map(CovenantCheckRecord.fromMap).toList();
  }

  Future<List<CovenantCheckRecord>> runChecks({
    required String assetPropertyId,
    required String fromPeriod,
    required String toPeriod,
  }) async {
    final loans = await listLoansByAsset(assetPropertyId);
    if (loans.isEmpty) {
      return const [];
    }
    final periods = _periodRange(fromPeriod, toPeriod);
    final now = DateTime.now().millisecondsSinceEpoch;
    final checks = <CovenantCheckRecord>[];

    for (final loan in loans) {
      final covenants = await listCovenantsByLoan(loan.id);
      final periodRows = await listLoanPeriods(loan.id);
      final loanByPeriod = <String, LoanPeriodRecord>{
        for (final row in periodRows) row.periodKey: row,
      };

      for (final covenant in covenants) {
        for (final period in periods) {
          final valuation = await _readValuation(assetPropertyId, period);
          final noi = await _readNoi(assetPropertyId, period);
          final loanPeriod = loanByPeriod[period];
          double? actual;
          String? notes;

          if (covenant.kind == 'dscr') {
            actual = _engine.computeDSCR(noi, loanPeriod?.debtService);
            if (actual == null) {
              notes = 'Unknown DSCR due to missing NOI or debt service.';
            }
          } else if (covenant.kind == 'ltv') {
            actual = _engine.computeLTV(loanPeriod?.balanceEnd, valuation);
            if (actual == null) {
              notes = 'Unknown LTV due to missing balance or valuation.';
            }
          }

          final pass =
              _engine.evaluate(
                operator: covenant.operator,
                actual: actual,
                threshold: covenant.threshold,
              ) ??
              false;

          final check = CovenantCheckRecord(
            id: const Uuid().v4(),
            covenantId: covenant.id,
            periodKey: period,
            actualValue: actual,
            pass: pass,
            checkedAt: now,
            notes: notes,
          );

          await _db.insert(
            'covenant_checks',
            check.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          checks.add(check);

          if (!pass && actual != null) {
            final message =
                'Covenant breach ($period): ${covenant.kind.toUpperCase()} ${actual.toStringAsFixed(3)} vs ${covenant.operator} ${covenant.threshold.toStringAsFixed(3)}';
            final existing = await _db.rawQuery(
              'SELECT COUNT(*) FROM notifications WHERE entity_type = ? AND entity_id = ? AND kind = ? AND message = ?',
              <Object?>['covenant', covenant.id, 'covenant_breach', message],
            );
            if (_firstInt(existing) == 0) {
              await _db.insert('notifications', <String, Object?>{
                'id': const Uuid().v4(),
                'entity_type': 'covenant',
                'entity_id': covenant.id,
                'kind': 'covenant_breach',
                'message': message,
                'due_at': null,
                'read_at': null,
                'created_at': now,
              }, conflictAlgorithm: ConflictAlgorithm.abort);
            }
          }
        }
      }
    }

    return checks;
  }

  Future<double?> _readValuation(
    String assetPropertyId,
    String periodKey,
  ) async {
    final rows = await _db.query(
      'property_kpi_snapshots',
      columns: const <String>['valuation'],
      where: 'property_id = ? AND period_date = ?',
      whereArgs: <Object?>[assetPropertyId, periodKey],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return (rows.first['valuation'] as num?)?.toDouble();
  }

  Future<double?> _readNoi(String assetPropertyId, String periodKey) async {
    final snapshotRows = await _db.query(
      'property_kpi_snapshots',
      columns: const <String>['noi'],
      where: 'property_id = ? AND period_date = ?',
      whereArgs: <Object?>[assetPropertyId, periodKey],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (snapshotRows.isNotEmpty) {
      final noi = (snapshotRows.first['noi'] as num?)?.toDouble();
      if (noi != null) {
        return noi;
      }
    }

    final ledgerRows = await _db.rawQuery(
      '''
      SELECT le.direction, le.amount, la.kind
      FROM ledger_entries le
      INNER JOIN ledger_accounts la ON la.id = le.account_id
      WHERE le.entity_id = ?
        AND le.period_key = ?
        AND le.entity_type IN ('asset_property', 'property')
      ''',
      <Object?>[assetPropertyId, periodKey],
    );

    if (ledgerRows.isEmpty) {
      return null;
    }

    var income = 0.0;
    var expense = 0.0;
    for (final row in ledgerRows) {
      final direction = row['direction']! as String;
      final amount = (row['amount']! as num).toDouble().abs();
      final signed = direction == 'in' ? amount : -amount;
      final kind = row['kind']! as String;
      if (kind == 'income') {
        income += signed;
      } else if (kind == 'expense') {
        expense += signed;
      }
    }
    return income + expense;
  }

  List<String> _periodRange(String fromPeriod, String toPeriod) {
    final start = _toDate(fromPeriod);
    final end = _toDate(toPeriod);
    if (start == null || end == null || start.isAfter(end)) {
      return const [];
    }
    final values = <String>[];
    var cursor = DateTime(start.year, start.month);
    while (!cursor.isAfter(end)) {
      final month = cursor.month.toString().padLeft(2, '0');
      values.add('${cursor.year}-$month');
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return values;
  }

  DateTime? _toDate(String periodKey) {
    final parts = periodKey.split('-');
    if (parts.length != 2) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) {
      return null;
    }
    return DateTime(year, month);
  }

  int _firstInt(List<Map<String, Object?>> rows) {
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
