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
          child: const MaterialApp(home: AppScaffold()),
        ),
      );
      for (var attempt = 0; attempt < 40; attempt += 1) {
        await tester.pump();
        if (find.text('Objekte').evaluate().isNotEmpty) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });

    await tester.pump();

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Objekte'), findsWidgets);

    await tester.tap(find.text('Objekte').last);

    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 40; attempt += 1) {
        await tester.pump();
        if (find.text('New Property').evaluate().isNotEmpty) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });

    await tester.pump();

    expect(find.text('New Property'), findsOneWidget);
  });
}
