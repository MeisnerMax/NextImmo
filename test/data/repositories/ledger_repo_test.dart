import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/services/ledger_service.dart';
import 'package:neximmo_app/data/repositories/ledger_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late LedgerRepo repo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    repo = LedgerRepo(db, const LedgerService());
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('unique account name enforced', () async {
    await repo.createAccount(name: 'Rent', kind: 'income');
    expect(
      () => repo.createAccount(name: 'rent', kind: 'income'),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('cannot delete account with entries', () async {
    final account = await repo.createAccount(name: 'Tax', kind: 'expense');
    await repo.createEntry(
      entityType: 'property',
      entityId: 'p1',
      accountId: account.id,
      postedAt: DateTime(2026, 1, 1).millisecondsSinceEpoch,
      direction: 'out',
      amount: 120,
      currencyCode: 'EUR',
    );
    expect(() => repo.deleteAccount(account.id), throwsA(isA<StateError>()));
  });

  test('period key and aggregation are correct', () async {
    final account = await repo.createAccount(name: 'Ops', kind: 'other');
    await repo.createEntry(
      entityType: 'property',
      entityId: 'p1',
      accountId: account.id,
      postedAt: DateTime(2026, 3, 1).millisecondsSinceEpoch,
      direction: 'in',
      amount: 1000,
      currencyCode: 'EUR',
    );
    await repo.createEntry(
      entityType: 'property',
      entityId: 'p1',
      accountId: account.id,
      postedAt: DateTime(2026, 3, 10).millisecondsSinceEpoch,
      direction: 'out',
      amount: 250,
      currencyCode: 'EUR',
    );

    final entries = await repo.listEntries(
      entityType: 'property',
      entityId: 'p1',
    );
    expect(entries, isNotEmpty);
    expect(entries.first.periodKey, '2026-03');

    final agg = await repo.aggregateByPeriod(
      entityType: 'property',
      entityId: 'p1',
    );
    expect(agg.length, 1);
    expect(agg.first.totalIn, 1000);
    expect(agg.first.totalOut, 250);
    expect(agg.first.net, 750);
  });
}
