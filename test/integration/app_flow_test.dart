import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/shell/app_scaffold.dart';
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
  });

  tearDownAll(() async {
    await appDatabase.close();
  });

  testWidgets('app scaffold shows navigation and properties page', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: AppScaffold()),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Properties'), findsWidgets);

    await tester.tap(find.text('Properties').last);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('New Property'), findsOneWidget);
  });
}
