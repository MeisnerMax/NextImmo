import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/inputs.dart';
import 'package:neximmo_app/core/models/scenario.dart';
import 'package:neximmo_app/core/models/scenario_valuation.dart';
import 'package:neximmo_app/data/repositories/inputs_repo.dart';
import 'package:neximmo_app/data/repositories/scenario_repo.dart';
import 'package:neximmo_app/data/repositories/scenario_valuation_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late ScenarioRepository scenarioRepo;
  late InputsRepository inputsRepo;
  late ScenarioValuationRepo valuationRepo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    scenarioRepo = ScenarioRepository(db);
    inputsRepo = InputsRepository(db);
    valuationRepo = ScenarioValuationRepo(db);

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
      'name': 'Base',
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
        purchasePrice: 250000,
        rentMonthlyTotal: 2400,
        updatedAt: now,
      ),
    );
    await valuationRepo.upsert(
      ScenarioValuationRecord.defaults(
        scenarioId: 'scenario-1',
      ).copyWith(
        valuationMode: 'exit_cap',
        exitCapRatePercent: 0.0575,
        stabilizedNoiMode: 'manual_noi',
        stabilizedNoiManual: 42000,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('duplicate copies valuation inputs and line items', () async {
    await db.insert('income_lines', <String, Object?>{
      'id': 'income-1',
      'scenario_id': 'scenario-1',
      'name': 'Laundry',
      'amount_monthly': 150,
      'enabled': 1,
    });
    await db.insert('expense_lines', <String, Object?>{
      'id': 'expense-1',
      'scenario_id': 'scenario-1',
      'name': 'Repairs',
      'kind': 'fixed',
      'amount_monthly': 80,
      'percent': 0,
      'enabled': 1,
    });

    final source = await scenarioRepo.getById('scenario-1');
    expect(source, isNotNull);

    final copy = await scenarioRepo.duplicate(
      source: source!,
      newName: 'Copy',
    );

    final copiedInputs = await inputsRepo.getInputs(
      scenarioId: copy.id,
      settings: await inputsRepo.getSettings(),
    );
    final copiedValuation = await valuationRepo.getForScenario(copy.id);
    final copiedIncome = await inputsRepo.listIncomeLines(copy.id);
    final copiedExpense = await inputsRepo.listExpenseLines(copy.id);

    expect(copiedInputs.purchasePrice, 250000);
    expect(copiedInputs.rentMonthlyTotal, 2400);
    expect(copiedValuation.valuationMode, 'exit_cap');
    expect(copiedValuation.exitCapRatePercent, closeTo(0.0575, 0.000001));
    expect(copiedValuation.stabilizedNoiMode, 'manual_noi');
    expect(copiedValuation.stabilizedNoiManual, 42000);
    expect(copiedIncome, hasLength(1));
    expect(copiedExpense, hasLength(1));
  });

  test('approval workflow persists and changes after approval reset to draft', () async {
    final approved = await scenarioRepo.approve(
      scenarioId: 'scenario-1',
      reviewComment: 'Ready for approval',
    );

    expect(approved.workflowStatus, ScenarioWorkflowStatus.approved);
    expect(approved.reviewComment, 'Ready for approval');
    expect(approved.changedSinceApproval, isFalse);

    await inputsRepo.upsertInputs(
      (
        await inputsRepo.getInputs(
          scenarioId: 'scenario-1',
          settings: await inputsRepo.getSettings(),
        )
      ).copyWith(
        rentMonthlyTotal: 2600,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    final changed = await scenarioRepo.getById('scenario-1');
    expect(changed, isNotNull);
    expect(changed!.workflowStatus, ScenarioWorkflowStatus.draft);
    expect(changed.changedSinceApproval, isTrue);
  });
}
