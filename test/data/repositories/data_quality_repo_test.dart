import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/repositories/data_quality_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late DataQualityRepo repo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    repo = DataQualityRepo(db);

    await db.insert('properties', <String, Object?>{
      'id': 'a1',
      'name': 'Asset 1',
      'address_line1': '',
      'address_line2': null,
      'zip': '',
      'city': '',
      'country': 'DE',
      'property_type': '',
      'units': 0,
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
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('loads quality snapshot for portfolio assets', () async {
    final snapshot = await repo.loadPortfolioSnapshot(portfolioId: 'p1');
    expect(snapshot.portfolioId, 'p1');
    expect(snapshot.assets.length, 1);
    expect(snapshot.assets.first.assetId, 'a1');
    expect(snapshot.assets.first.hasApprovedBudgetCurrentYear, isFalse);
  });
}
