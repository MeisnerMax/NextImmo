import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/scenario.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/property_detail/scenarios_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/state/security_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('viewer role disables destructive actions in scenarios screen', (
    tester,
  ) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    final db = await appDatabase.instance;
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appDatabaseProvider.overrideWithValue(appDatabase),
          activeUserRoleProvider.overrideWithValue('viewer'),
        ],
        child: MaterialApp(
          home: ScenariosScreen(
            propertyId: 'p1',
            scenarios: const [
              ScenarioRecord(
                id: 's1',
                propertyId: 'p1',
                name: 'Base',
                strategyType: 'hold',
                isBase: true,
                createdAt: 1,
                updatedAt: 1,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final newScenarioButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'New Scenario'),
    );
    expect(newScenarioButton.onPressed, isNull);

    final deleteButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Delete'),
    );
    expect(deleteButton.onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await appDatabase.close();
  }, skip: true);

  testWidgets('manager role sees approval controls for scenario workflow', (
    tester,
  ) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    final db = await appDatabase.instance;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appDatabaseProvider.overrideWithValue(appDatabase),
          activeUserRoleProvider.overrideWithValue('manager'),
        ],
        child: MaterialApp(
          home: ScenariosScreen(
            propertyId: 'p1',
            scenarios: const [
              ScenarioRecord(
                id: 's1',
                propertyId: 'p1',
                name: 'Draft Scenario',
                strategyType: 'hold',
                isBase: false,
                createdAt: 1,
                updatedAt: 1,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('DRAFT'), findsOneWidget);
    final approveButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Approve'),
    );
    expect(approveButton.onPressed, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await appDatabase.close();
  }, skip: true);
}
