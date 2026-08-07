import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/property_detail/budget_vs_actual_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';
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

  for (final size in const <Size>[
    Size(390, 844),
    Size(1024, 768),
    Size(1440, 900),
  ]) {
    testWidgets('renders budget actions without overflow at ${size.width.toInt()} px', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            appDatabaseProvider.overrideWithValue(appDatabase),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: BudgetVsActualScreen(propertyId: 'p1')),
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('Finanzen & Budget'));

      expect(tester.takeException(), isNull);
      final budgetTab = find.text('Budget vs. Ist');
      await tester.ensureVisible(budgetTab);
      await tester.tap(budgetTab);
      await tester.pumpAndSettle();

      expect(find.text('Budget erstellen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
}
