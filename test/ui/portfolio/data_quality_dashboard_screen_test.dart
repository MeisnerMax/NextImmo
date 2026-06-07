import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/portfolio/data_quality_dashboard_screen.dart';
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

    await db.insert('portfolios', <String, Object?>{
      'id': 'p1',
      'name': 'Fund',
      'description': null,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('properties', <String, Object?>{
      'id': 'a1',
      'name': 'Asset 1',
      'address_line1': '',
      'address_line2': null,
      'zip': '',
      'city': '',
      'country': 'DE',
      'property_type': '',
      'units': 0,
      'sqft': null,
      'year_built': null,
      'notes': null,
      'created_at': 1,
      'updated_at': 1,
      'archived': 0,
    });
    await db.insert('portfolio_properties', <String, Object?>{
      'portfolio_id': 'p1',
      'property_id': 'a1',
      'created_at': 1,
    });
  });

  tearDown(() async {
    await appDatabase.close();
  });

  testWidgets('shows quality score and issues list container', (tester) async {
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
          child: const MaterialApp(
            home: Scaffold(
              body: DataQualityDashboardScreen(
                portfolioId: 'p1',
                portfolioName: 'Fund',
              ),
            ),
          ),
        ),
      );

      // Wait for the data loading to complete and main dashboard tiles to appear
      for (int i = 0; i < 40; i++) {
        await tester.pump();
        if (find.text('Portfolio Score').evaluate().isNotEmpty) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });

    expect(find.textContaining('Data Quality'), findsOneWidget);
    expect(find.text('Portfolio Score'), findsOneWidget);

    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
  });
}
