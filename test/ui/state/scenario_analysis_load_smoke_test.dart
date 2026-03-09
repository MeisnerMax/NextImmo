import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/engine/analysis_engine.dart';
import 'package:neximmo_app/data/repositories/criteria_repo.dart';
import 'package:neximmo_app/data/repositories/inputs_repo.dart';
import 'package:neximmo_app/data/repositories/scenario_repo.dart';
import 'package:neximmo_app/data/repositories/scenario_valuation_repo.dart';
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

    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert('properties', <String, Object?>{
      'id': 'property-1',
      'name': 'Test Property',
      'address_line1': 'Main Street 1',
      'address_line2': null,
      'zip': '10115',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'single_family',
      'units': 1,
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
      'name': 'Base',
      'strategy_type': 'rental',
      'is_base': 1,
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('scenario analysis load pipeline completes', () async {
    final scenarioRepo = ScenarioRepository(db);
    final inputsRepo = InputsRepository(db);
    final valuationRepo = ScenarioValuationRepo(db);
    final criteriaRepo = CriteriaRepository(db);
    const engine = AnalysisEngine();

    final scenario = await scenarioRepo.getById('scenario-1');
    expect(scenario, isNotNull);

    final settings = await inputsRepo.getSettings();
    final inputs = await inputsRepo.getInputs(
      scenarioId: 'scenario-1',
      settings: settings,
    );
    final valuation = await valuationRepo.getForScenario('scenario-1');
    final incomeLines = await inputsRepo.listIncomeLines('scenario-1');
    final expenseLines = await inputsRepo.listExpenseLines('scenario-1');

    final analysis = engine.run(
      inputs: inputs,
      settings: settings,
      incomeLines: incomeLines,
      expenseLines: expenseLines,
      valuation: valuation,
    );

    final propertyOverride = await criteriaRepo.getPropertyOverride(
      'property-1',
    );
    final defaultSet = await criteriaRepo.getDefaultSet();

    expect(propertyOverride, isNull);
    expect(defaultSet, isNull);
    expect(analysis.metrics.monthlyCashflowYear1, isA<double>());
  });
}
