import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/finance/budget_vs_actual.dart';
import 'package:neximmo_app/data/repositories/budget_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late BudgetRepo repo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    repo = BudgetRepo(db, const BudgetVsActual());

    await db.insert('ledger_accounts', <String, Object?>{
      'id': 'a1',
      'name': 'Rent',
      'kind': 'income',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('status guard blocks deleting approved budget', () async {
    final budget = await repo.createBudget(
      entityType: 'asset_property',
      entityId: 'p1',
      fiscalYear: 2026,
      versionName: 'Base',
    );
    await repo.setStatus(budgetId: budget.id, status: 'approved');

    expect(() => repo.deleteBudget(budget.id), throwsA(isA<StateError>()));
  });

  test('computeBudgetVsActual returns variance rows', () async {
    final budget = await repo.createBudget(
      entityType: 'asset_property',
      entityId: 'p1',
      fiscalYear: 2026,
      versionName: 'Draft',
    );
    await repo.upsertBudgetLine(
      budgetId: budget.id,
      accountId: 'a1',
      periodKey: '2026-01',
      direction: 'in',
      amount: 100,
    );
    await db.insert('ledger_entries', <String, Object?>{
      'id': 'e1',
      'entity_type': 'asset_property',
      'entity_id': 'p1',
      'account_id': 'a1',
      'posted_at': DateTime(2026, 1, 15).millisecondsSinceEpoch,
      'period_key': '2026-01',
      'direction': 'in',
      'amount': 90,
      'currency_code': 'EUR',
      'counterparty': null,
      'memo': null,
      'document_id': null,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    final rows = await repo.computeBudgetVsActual(
      entityType: 'asset_property',
      entityId: 'p1',
      budgetId: budget.id,
      fromPeriod: '2026-01',
      toPeriod: '2026-01',
    );

    expect(rows.length, 1);
    expect(rows.first.budgetAmount, 100);
    expect(rows.first.actualAmount, 90);
    expect(rows.first.varianceAmount, -10);
  });
}
