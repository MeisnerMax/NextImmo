import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/docs/documents_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('upload requires type selection when requirements exist', (
    tester,
  ) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    final db = await appDatabase.instance;

    await db.insert('document_types', <String, Object?>{
      'id': 't1',
      'name': 'Insurance',
      'entity_type': 'property',
      'required_fields_json': '[]',
      'created_at': 1,
    });
    await db.insert('required_documents', <String, Object?>{
      'id': 'r1',
      'entity_type': 'property',
      'property_type': null,
      'type_id': 't1',
      'required': 1,
      'expires_field_key': null,
      'created_at': 1,
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appDatabaseProvider.overrideWithValue(appDatabase),
        ],
        child: const MaterialApp(home: DocumentsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Document'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'property');
    await tester.enterText(fields.at(1), 'p1');
    await tester.enterText(fields.at(2), '/tmp/doc.pdf');
    await tester.enterText(fields.at(3), 'doc.pdf');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Type selection is required'), findsOneWidget);

    await appDatabase.close();
  });
}
