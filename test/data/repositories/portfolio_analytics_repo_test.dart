import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/finance/portfolio_irr_engine.dart';
import 'package:neximmo_app/core/services/ledger_service.dart';
import 'package:neximmo_app/data/repositories/capital_events_repo.dart';
import 'package:neximmo_app/data/repositories/portfolio_analytics_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late PortfolioAnalyticsRepo repo;
  late CapitalEventsRepo capitalRepo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;

    capitalRepo = CapitalEventsRepo(db, const LedgerService());
    repo = PortfolioAnalyticsRepo(db, capitalRepo, const PortfolioIrrEngine());

    await db.insert('properties', <String, Object?>{
      'id': 'a1',
      'name': 'Asset 1',
      'address_line1': 'Main',
      'address_line2': null,
      'zip': '10000',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'multifamily',
      'units': 10,
      'sqft': null,
      'year_built': null,
      'notes': null,
      'created_at': 1,
      'updated_at': 1,
      'archived': 0,
    });
    await db.insert('portfolios', <String, Object?>{
      'id': 'p1',
      'name': 'Fund',
      'description': null,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('portfolio_properties', <String, Object?>{
      'portfolio_id': 'p1',
      'property_id': 'a1',
      'created_at': 1,
    });
    await db.insert('ledger_accounts', <String, Object?>{
      'id': 'acc_income',
      'name': 'Rent',
      'kind': 'income',
      'created_at': 1,
    });
    await db.insert('ledger_accounts', <String, Object?>{
      'id': 'acc_expense',
      'name': 'Opex',
      'kind': 'expense',
      'created_at': 1,
    });
    await db.insert('ledger_entries', <String, Object?>{
      'id': 'e1',
      'entity_type': 'asset_property',
      'entity_id': 'a1',
      'account_id': 'acc_income',
      'posted_at': DateTime(2026, 1, 10).millisecondsSinceEpoch,
      'period_key': '2026-01',
      'direction': 'in',
      'amount': 10000,
      'currency_code': 'EUR',
      'counterparty': null,
      'memo': null,
      'document_id': null,
      'created_at': 1,
    });
    await db.insert('ledger_entries', <String, Object?>{
      'id': 'e2',
      'entity_type': 'asset_property',
      'entity_id': 'a1',
      'account_id': 'acc_expense',
      'posted_at': DateTime(2026, 1, 15).millisecondsSinceEpoch,
      'period_key': '2026-01',
      'direction': 'out',
      'amount': 4000,
      'currency_code': 'EUR',
      'counterparty': null,
      'memo': null,
      'document_id': null,
      'created_at': 1,
    });
    await capitalRepo.create(
      assetPropertyId: 'a1',
      eventType: 'equity_contribution',
      postedAt: DateTime(2026, 1, 1).millisecondsSinceEpoch,
      direction: 'out',
      amount: 50000,
    );
    await capitalRepo.create(
      assetPropertyId: 'a1',
      eventType: 'disposition_proceeds',
      postedAt: DateTime(2026, 12, 31).millisecondsSinceEpoch,
      direction: 'in',
      amount: 70000,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('aggregates cashflows and computes irr', () async {
    final result = await repo.computePortfolioIRR(
      portfolioId: 'p1',
      fromPeriodKey: '2026-01',
      toPeriodKey: '2026-12',
    );

    expect(result.datedCashflows, isNotEmpty);
    expect(result.periodTable, isNotEmpty);
    expect(result.totalInflows, greaterThan(0));
    expect(result.totalOutflows, greaterThan(0));
    expect(result.irr, isNotNull);
  });
}
