import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/portfolio/portfolio_analytics_screen.dart';
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
  });

  tearDown(() async {
    await appDatabase.close();
  });

  testWidgets('renders analytics screen and computes baseline state', (
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
          child: const MaterialApp(
            home: Scaffold(
              body: PortfolioAnalyticsScreen(
                portfolioId: 'p1',
                portfolioName: 'Fund',
              ),
            ),
          ),
        ),
      );

      // Wait for data to load and chart elements/tabs to appear
      for (int i = 0; i < 40; i++) {
        await tester.pump();
        if (find.text('Portfolio IRR').evaluate().isNotEmpty) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });

    expect(find.textContaining('Portfolio Analytics'), findsOneWidget);
    expect(find.text('Portfolio IRR'), findsOneWidget);

    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
  });
}
