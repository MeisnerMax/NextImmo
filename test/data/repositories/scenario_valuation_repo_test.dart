import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/repositories/scenario_valuation_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late ScenarioValuationRepo repo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    repo = ScenarioValuationRepo(db);

    await db.insert('properties', <String, Object?>{
      'id': 'p1',
      'name': 'Asset',
      'address_line1': 'Main',
      'address_line2': null,
      'zip': '10000',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'multifamily',
      'units': 8,
      'sqft': null,
      'year_built': null,
      'notes': null,
      'created_at': 1,
      'updated_at': 1,
      'archived': 0,
    });
    await db.insert('scenarios', <String, Object?>{
      'id': 's1',
      'property_id': 'p1',
      'name': 'Base',
      'strategy_type': 'hold',
      'is_base': 1,
      'created_at': 1,
      'updated_at': 1,
    });
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('creates defaults and persists updates', () async {
    final defaults = await repo.getForScenario('s1');
    expect(defaults.valuationMode, 'appreciation');

    final updated = defaults.copyWith(
      valuationMode: 'exit_cap',
      exitCapRatePercent: 0.055,
      stabilizedNoiMode: 'manual_noi',
      stabilizedNoiManual: 45000,
      updatedAt: 10,
    );
    await repo.upsert(updated);
    final loaded = await repo.getForScenario('s1');
    expect(loaded.valuationMode, 'exit_cap');
    expect(loaded.exitCapRatePercent, closeTo(0.055, 0.000001));
    expect(loaded.stabilizedNoiManual, 45000);
  });
}
