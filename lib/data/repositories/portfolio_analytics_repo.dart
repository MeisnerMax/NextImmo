import 'package:csv/csv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/finance/portfolio_irr_engine.dart';
import '../../core/models/portfolio_analytics.dart';
import 'asset_workbook_repo.dart';
import 'capital_events_repo.dart';

class PortfolioAnalyticsRepo {
  const PortfolioAnalyticsRepo(
    this._db,
    this._capitalEventsRepo,
    this._engine,
    this._assetWorkbookRepo,
  );

  final Database _db;
  final CapitalEventsRepo _capitalEventsRepo;
  final PortfolioIrrEngine _engine;
  final AssetWorkbookRepo _assetWorkbookRepo;

  Future<PortfolioMetricsSnapshot> loadOverviewMetrics({
    required Set<String> activePropertyIds,
  }) async {
    final rentalOverview = await _assetWorkbookRepo.loadPortfolioOverview(
      includeArchived: true,
    );
    final activeRows = rentalOverview.rows
        .where((row) => activePropertyIds.contains(row.propertyId))
        .toList(growable: false);

    final purchasePriceRows = await _db.rawQuery('''
      SELECT s.property_id, si.purchase_price
      FROM scenario_inputs si
      INNER JOIN scenarios s ON s.id = si.scenario_id
      WHERE s.is_base = 1
    ''');
    final purchasePrices = {
      for (final row in purchasePriceRows)
        row['property_id'] as String:
            ((row['purchase_price'] as num?) ?? 0).toDouble(),
    };
    final activePurchasePrices = {
      for (final entry in purchasePrices.entries)
        if (activePropertyIds.contains(entry.key)) entry.key: entry.value,
    };

    final loanRows = await _db.rawQuery('''
      SELECT asset_property_id, SUM(principal) AS loan_total
      FROM loans
      GROUP BY asset_property_id
    ''');
    final loanTotals = {
      for (final row in loanRows)
        if (activePropertyIds.contains(row['asset_property_id']))
          row['asset_property_id'] as String:
              ((row['loan_total'] as num?) ?? 0).toDouble(),
    };

    final rentedUnits = activeRows.fold<int>(
      0,
      (sum, row) => sum + row.occupiedUnits,
    );
    final emptyUnits = activeRows.fold<int>(
      0,
      (sum, row) => sum + row.vacantUnits,
    );
    final rentableUnits = rentedUnits + emptyUnits;
    final vacancyRate = rentableUnits == 0 ? 0.0 : emptyUnits / rentableUnits;

    final opex = activeRows.fold<double>(
      0,
      (sum, row) => sum + row.annualOperatingCosts,
    );
    final annualRent = activeRows.fold<double>(
      0,
      (sum, row) => sum + row.annualRent,
    );
    final noi = annualRent - opex;

    final estimatedMarketValue = noi <= 0 ? 0.0 : noi / 0.055;

    var totalAcquisitionCosts = 0.0;
    for (final price in activePurchasePrices.values) {
      totalAcquisitionCosts += price;
    }

    var totalLoanPrincipal = 0.0;
    for (final loan in loanTotals.values) {
      totalLoanPrincipal += loan;
    }

    final netYield =
        totalAcquisitionCosts <= 0 ? 0.0 : noi / totalAcquisitionCosts;
    final portfolioLtv =
        estimatedMarketValue <= 0 ? 0.0 : totalLoanPrincipal / estimatedMarketValue;

    final propertyKpis = <String, PropertyPortfolioKpis>{};
    for (final row in rentalOverview.rows) {
      final pId = row.propertyId;
      final pPrice = purchasePrices[pId] ?? 0.0;
      final pNoi = row.annualRent - row.annualOperatingCosts;
      final pYield = pPrice > 0 ? pNoi / pPrice : 0.0;
      final pCashflow = pNoi / 12;
      final pMarketValue = pNoi <= 0 ? 0.0 : pNoi / 0.055;
      final pBkQuote =
          row.annualRent > 0 ? row.annualOperatingCosts / row.annualRent : 0.0;
      propertyKpis[pId] = PropertyPortfolioKpis(
        propertyYield: pYield,
        cashflowMonthly: pCashflow,
        estimatedMarketValue: pMarketValue,
        units: row.units,
        occupiedUnits: row.occupiedUnits,
        annualOperatingCosts: row.annualOperatingCosts,
        bkQuote: pBkQuote,
        serviceChargeBalance: row.serviceChargeBalance,
      );
    }

    return PortfolioMetricsSnapshot(
      totalValue: estimatedMarketValue,
      totalAcquisitionCosts: totalAcquisitionCosts,
      netYield: netYield,
      vacancyRate: vacancyRate,
      ltv: portfolioLtv,
      totalLoanPrincipal: totalLoanPrincipal,
      propertyKpis: propertyKpis,
    );
  }

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
