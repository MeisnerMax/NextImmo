import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/finance/covenant_engine.dart';
import 'package:neximmo_app/data/repositories/covenant_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late CovenantRepo repo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    repo = CovenantRepo(db, const CovenantEngine());

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('properties', <String, Object?>{
      'id': 'p1',
      'name': 'Property 1',
      'address_line1': 'Street 1',
      'address_line2': null,
      'zip': '10115',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'multifamily',
      'units': 1,
      'sqft': null,
      'year_built': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
      'archived': 0,
    });
    await db.insert('property_kpi_snapshots', <String, Object?>{
      'id': 'k1',
      'property_id': 'p1',
      'scenario_id': null,
      'period_date': '2026-01',
      'noi': 120,
      'occupancy': null,
      'capex': null,
      'valuation': 1000,
      'source': 'manual',
      'created_at': now,
    });
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test(
    'runChecks persists covenant checks and stays unique per period',
    () async {
      final loan = await repo.createLoan(
        assetPropertyId: 'p1',
        principal: 800,
        interestRatePercent: 0.05,
        termYears: 20,
        startDate: DateTime(2026, 1, 1).millisecondsSinceEpoch,
      );
      await repo.upsertLoanPeriod(
        loanId: loan.id,
        periodKey: '2026-01',
        balanceEnd: 700,
        debtService: 100,
      );
      final covenant = await repo.createCovenant(
        loanId: loan.id,
        kind: 'dscr',
        threshold: 1.1,
        operator: 'gte',
      );

      final first = await repo.runChecks(
        assetPropertyId: 'p1',
        fromPeriod: '2026-01',
        toPeriod: '2026-01',
      );
      expect(first.length, 1);
      expect(first.first.pass, isTrue);

      await repo.runChecks(
        assetPropertyId: 'p1',
        fromPeriod: '2026-01',
        toPeriod: '2026-01',
      );

      final rows = await db.query(
        'covenant_checks',
        where: 'covenant_id = ? AND period_key = ?',
        whereArgs: <Object?>[covenant.id, '2026-01'],
      );
      expect(rows.length, 1);
    },
  );
}
