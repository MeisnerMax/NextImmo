import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/capital_event.dart';
import '../../core/services/ledger_service.dart';

class CapitalEventsRepo {
  const CapitalEventsRepo(this._db, this._ledgerService);

  final Database _db;
  final LedgerService _ledgerService;

  Future<CapitalEventRecord> create({
    required String assetPropertyId,
    required String eventType,
    required int postedAt,
    required String direction,
    required double amount,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = CapitalEventRecord(
      id: const Uuid().v4(),
      assetPropertyId: assetPropertyId,
      eventType: eventType,
      postedAt: postedAt,
      periodKey: _ledgerService.derivePeriodKey(postedAt),
      direction: direction,
      amount: amount.abs(),
      notes: notes,
      createdAt: now,
    );
    await _db.insert(
      'capital_events',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return record;
  }

  Future<List<CapitalEventRecord>> listByAssetsAndRange({
    required List<String> assetIds,
    String? fromPeriodKey,
    String? toPeriodKey,
  }) async {
    if (assetIds.isEmpty) {
      return const <CapitalEventRecord>[];
    }
    final placeholders = List<String>.filled(assetIds.length, '?').join(',');
    final where = <String>['asset_property_id IN ($placeholders)'];
    final args = <Object?>[...assetIds];
    if (fromPeriodKey != null) {
      where.add('period_key >= ?');
      args.add(fromPeriodKey);
    }
    if (toPeriodKey != null) {
      where.add('period_key <= ?');
      args.add(toPeriodKey);
    }
    final rows = await _db.query(
      'capital_events',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'posted_at ASC, created_at ASC',
    );
    return rows.map(CapitalEventRecord.fromMap).toList();
  }
}
