import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/engine/analysis_engine.dart';
import 'package:neximmo_app/core/models/inputs.dart';
import 'package:neximmo_app/core/models/scenario_valuation.dart';
import 'package:neximmo_app/data/repositories/compare_repo.dart';
import 'package:neximmo_app/data/repositories/inputs_repo.dart';
import 'package:neximmo_app/data/repositories/scenario_valuation_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late InputsRepository inputsRepo;
  late ScenarioValuationRepo valuationRepo;
  late CompareRepo compareRepo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    inputsRepo = InputsRepository(db);
    valuationRepo = ScenarioValuationRepo(db);
    compareRepo = CompareRepo(db, inputsRepo, const AnalysisEngine());

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('properties', <String, Object?>{
      'id': 'property-1',
      'name': 'Asset',
      'address_line1': 'Main Street',
      'address_line2': null,
      'zip': '10115',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'multifamily',
      'units': 6,
      'sqft': null,
      'year_built': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
      'archived': 0,
    });
    await db.insert('scenarios', <String, Object?>{
      'id': 'scenario-1',
      'property_id': 'property-1',
      'name': 'Exit Cap',
      'strategy_type': 'hold',
      'is_base': 1,
      'created_at': now,
      'updated_at': now,
    });

    final settings = await inputsRepo.getSettings();
    await inputsRepo.upsertInputs(
      ScenarioInputs.defaults(
        scenarioId: 'scenario-1',
        settings: settings,
      ).copyWith(
        purchasePrice: 300000,
        rentMonthlyTotal: 3000,
        financingMode: 'cash',
        updatedAt: now,
      ),
    );
    await valuationRepo.upsert(
      ScenarioValuationRecord.defaults(
        scenarioId: 'scenario-1',
      ).copyWith(
        valuationMode: 'exit_cap',
        exitCapRatePercent: 0.05,
        stabilizedNoiMode: 'manual_noi',
        stabilizedNoiManual: 25000,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('loadScenarioBundles uses stored valuation for analysis', () async {
    final (settings, bundles) = await compareRepo.loadScenarioBundles();
    expect(settings.updatedAt, isNonZero);
    expect(bundles, hasLength(1));

    final bundle = bundles.single;
    expect(bundle.valuation.valuationMode, 'exit_cap');
    expect(bundle.analysis.metrics.valuationMode, 'exit_cap');
    expect(bundle.analysis.metrics.exitStabilizedNoi, 25000);
    expect(bundle.analysis.metrics.exitSalePrice, closeTo(500000, 0.0001));
  });
}
