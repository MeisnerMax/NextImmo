import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/repositories/audit_log_repo.dart';
import 'package:neximmo_app/data/repositories/inputs_repo.dart';
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
    await db.insert('properties', <String, Object?>{
      'id': 'p1',
      'name': 'Asset',
      'address_line1': 'A',
      'address_line2': null,
      'zip': '1',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'multifamily',
      'units': 1,
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

  test('updating scenario inputs creates audit event with diff', () async {
    final audit = AuditLogRepo(db);
    final repo = InputsRepository(db, auditLogRepo: audit);
    final settings = await repo.getSettings();
    final inputs = await repo.getInputs(scenarioId: 's1', settings: settings);
    await repo.upsertInputs(
      inputs.copyWith(purchasePrice: 220000, updatedAt: 2),
    );

    final events = await audit.list(
      entityType: 'scenario_inputs',
      entityId: 's1',
    );
    expect(events, isNotEmpty);
    expect(events.first.diffItems.isNotEmpty, isTrue);
  });
}
