import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/tasks/task_templates_screen.dart';
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
    await db.insert('properties', <String, Object?>{
      'id': 'p1',
      'name': 'Objekt',
      'address_line1': 'Street',
      'address_line2': null,
      'zip': '10115',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'single_family',
      'units': 1,
      'sqft': null,
      'year_built': null,
      'notes': null,
      'created_at': 1,
      'updated_at': 1,
      'archived': 0,
    });
  });

  tearDownAll(() async {
    await appDatabase.close();
  });

  testWidgets('generate now shows generated status', (tester) async {
    await db.insert('task_templates', <String, Object?>{
      'id': 'tpl-1',
      'name': 'Monthly',
      'entity_type': 'property',
      'default_title': 'Review',
      'default_priority': 'normal',
      'default_due_days_offset': null,
      'recurrence_rule': 'monthly',
      'recurrence_interval': 1,
      'created_at': 1,
      'updated_at': 1,
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appDatabaseProvider.overrideWithValue(appDatabase),
        ],
        child: const MaterialApp(home: Scaffold(body: TaskTemplatesScreen())),
      ),
    );
    await tester.pumpAndSettle();

    final generateButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Generate now'),
    );
    generateButton.onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.textContaining('Generated'), findsOneWidget);
  });
}
