import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/docs/documents_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
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
  });

  tearDown(() async {
    await appDatabase.close();
  });

  testWidgets('upload requires type selection when requirements exist', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            appDatabaseProvider.overrideWithValue(appDatabase),
          ],
          child: const MaterialApp(home: Scaffold(body: DocumentsScreen())),
        ),
      );
      
      // Wait for the main button to appear
      for (int i = 0; i < 40; i++) {
        await tester.pump();
        if (find.text('Dokument erfassen').evaluate().isNotEmpty) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });

    await tester.tap(find.text('Dokument erfassen'));
    
    await tester.runAsync(() async {
      // Wait for the dialog to open and transition to settle
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).evaluate().isNotEmpty) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });

    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'p1');
    await tester.enterText(fields.at(1), '/tmp/doc.pdf');
    await tester.enterText(fields.at(2), 'doc.pdf');
    await tester.tap(find.text('Speichern'));
    
    await tester.runAsync(() async {
      // Wait for error validation text to appear
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.textContaining('Fuer diese Ebene ist ein Dokumenttyp erforderlich.').evaluate().isNotEmpty) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });

    expect(find.textContaining('Fuer diese Ebene ist ein Dokumenttyp erforderlich.'), findsOneWidget);

    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
  });
}
