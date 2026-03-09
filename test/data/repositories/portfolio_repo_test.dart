import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/data/repositories/portfolio_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('attach and detach property to portfolio', () async {
    final repo = PortfolioRepository(db);
    await db.insert(
      'properties',
      const PropertyRecord(
        id: 'p1',
        name: 'Property 1',
        addressLine1: 'A',
        zip: '1',
        city: 'C',
        country: 'DE',
        propertyType: 'single_family',
        units: 1,
        createdAt: 0,
        updatedAt: 0,
      ).toMap(),
    );

    final portfolio = await repo.createPortfolio(name: 'Portfolio A');
    await repo.attachProperty(portfolioId: portfolio.id, propertyId: 'p1');

    final assigned = await repo.listPortfolioProperties(portfolio.id);
    expect(assigned.length, 1);
    expect(assigned.first.id, 'p1');

    await repo.detachProperty(portfolioId: portfolio.id, propertyId: 'p1');
    final afterDetach = await repo.listPortfolioProperties(portfolio.id);
    expect(afterDetach, isEmpty);
  });
}
