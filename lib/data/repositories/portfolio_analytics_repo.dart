import 'package:csv/csv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/finance/portfolio_irr_engine.dart';
import '../../core/models/portfolio_analytics.dart';
import 'capital_events_repo.dart';

class PortfolioAnalyticsRepo {
  const PortfolioAnalyticsRepo(this._db, this._capitalEventsRepo, this._engine);

  final Database _db;
  final CapitalEventsRepo _capitalEventsRepo;
  final PortfolioIrrEngine _engine;

  Future<PortfolioIrrResult> computePortfolioIRR({
    required String portfolioId,
    required String fromPeriodKey,
    required String toPeriodKey,
  }) async {
    final cashflows = await computePortfolioCashflowTable(
      portfolioId: portfolioId,
      fromPeriodKey: fromPeriodKey,
      toPeriodKey: toPeriodKey,
    );
    return _engine.compute(cashflows: cashflows);
  }

  Future<List<PortfolioCashflowRecord>> computePortfolioCashflowTable({
    required String portfolioId,
    required String fromPeriodKey,
    required String toPeriodKey,
  }) async {
    final assetRows = await _db.query(
      'portfolio_properties',
      columns: const <String>['property_id'],
      where: 'portfolio_id = ?',
      whereArgs: <Object?>[portfolioId],
    );
    final assetIds = assetRows
        .map((row) => row['property_id'] as String)
        .toSet()
        .toList(growable: false);
    if (assetIds.isEmpty) {
      return const <PortfolioCashflowRecord>[];
    }

    final ledgerCashflows = await _loadLedgerCashflows(
      assetIds: assetIds,
      fromPeriodKey: fromPeriodKey,
      toPeriodKey: toPeriodKey,
    );
    final capitalCashflows = await _loadCapitalCashflows(
      assetIds: assetIds,
      fromPeriodKey: fromPeriodKey,
      toPeriodKey: toPeriodKey,
    );
    final all = <PortfolioCashflowRecord>[
      ...ledgerCashflows,
      ...capitalCashflows,
    ]..sort((a, b) => a.date.compareTo(b.date));
    return all;
  }

  Future<String> exportCashflowsCsv({
    required List<PortfolioCashflowRecord> cashflows,
  }) async {
    final rows = <List<dynamic>>[
      <dynamic>[
        'date',
        'period_key',
        'amount_signed',
        'source_type',
        'asset_id',
        'notes',
      ],
      ...cashflows.map(
        (entry) => <dynamic>[
          entry.date.toIso8601String().substring(0, 10),
          entry.periodKey,
          entry.amountSigned,
          entry.sourceType,
          entry.assetId,
          entry.notes,
        ],
      ),
    ];
    return const ListToCsvConverter().convert(rows);
  }

  Future<List<PortfolioCashflowRecord>> _loadLedgerCashflows({
    required List<String> assetIds,
    required String fromPeriodKey,
    required String toPeriodKey,
  }) async {
    final placeholders = List<String>.filled(assetIds.length, '?').join(',');
    final rows = await _db.rawQuery(
      '''
      SELECT le.*, la.kind AS account_kind
      FROM ledger_entries le
      INNER JOIN ledger_accounts la ON la.id = le.account_id
      WHERE le.entity_type = 'asset_property'
        AND le.entity_id IN ($placeholders)
        AND le.period_key >= ?
        AND le.period_key <= ?
      ORDER BY le.posted_at ASC, le.created_at ASC
      ''',
      <Object?>[...assetIds, fromPeriodKey, toPeriodKey],
    );

    return rows
        .map((row) {
          final direction = (row['direction'] as String?) ?? 'out';
          final amount = ((row['amount'] as num?) ?? 0).toDouble().abs();
          final accountKind = (row['account_kind'] as String?) ?? 'other';
          return PortfolioCashflowRecord(
            date: DateTime.fromMillisecondsSinceEpoch(
              (row['posted_at']! as num).toInt(),
            ),
            periodKey: row['period_key']! as String,
            amountSigned: _signedLedgerAmount(
              direction: direction,
              amount: amount,
              accountKind: accountKind,
            ),
            sourceType: 'ledger:$accountKind',
            assetId: row['entity_id'] as String?,
            notes: row['memo'] as String?,
          );
        })
        .toList(growable: false);
  }

  Future<List<PortfolioCashflowRecord>> _loadCapitalCashflows({
    required List<String> assetIds,
    required String fromPeriodKey,
    required String toPeriodKey,
  }) async {
    final events = await _capitalEventsRepo.listByAssetsAndRange(
      assetIds: assetIds,
      fromPeriodKey: fromPeriodKey,
      toPeriodKey: toPeriodKey,
    );
    return events
        .map(
          (event) => PortfolioCashflowRecord(
            date: DateTime.fromMillisecondsSinceEpoch(event.postedAt),
            periodKey: event.periodKey,
            amountSigned:
                event.direction == 'in' ? event.amount : -event.amount,
            sourceType: event.eventType,
            assetId: event.assetPropertyId,
            notes: event.notes,
          ),
        )
        .toList(growable: false);
  }

  double _signedLedgerAmount({
    required String direction,
    required double amount,
    required String accountKind,
  }) {
    final inbound = direction == 'in';
    if (accountKind == 'income') {
      return inbound ? amount : -amount;
    }
    if (accountKind == 'expense' ||
        accountKind == 'capex' ||
        accountKind == 'debt') {
      return inbound ? amount : -amount;
    }
    return inbound ? amount : -amount;
  }
}
