import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/property_detail/budget_vs_actual_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('ledger_accounts', <String, Object?>{
      'id': 'a1',
      'name': 'Rent',
      'kind': 'income',
      'created_at': now,
    });
    await db.insert('budgets', <String, Object?>{
      'id': 'b1',
      'entity_type': 'asset_property',
      'entity_id': 'p1',
      'fiscal_year': 2026,
      'version_name': 'Base',
      'status': 'draft',
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDownAll(() async {
    await appDatabase.close();
  });

  testWidgets('renders budget actions for property', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appDatabaseProvider.overrideWithValue(appDatabase),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BudgetVsActualScreen(propertyId: 'p1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create Budget'), findsOneWidget);
  });
}
