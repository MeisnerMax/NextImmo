import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/portfolio/portfolio_analytics_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders analytics screen and computes baseline state', (
    tester,
  ) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    final db = await appDatabase.instance;

    await db.insert('portfolios', <String, Object?>{
      'id': 'p1',
      'name': 'Fund',
      'description': null,
      'created_at': 1,
      'updated_at': 1,
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appDatabaseProvider.overrideWithValue(appDatabase),
        ],
        child: const MaterialApp(
          home: PortfolioAnalyticsScreen(
            portfolioId: 'p1',
            portfolioName: 'Fund',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Portfolio Analytics'), findsOneWidget);
    expect(find.text('Portfolio IRR'), findsOneWidget);

    await appDatabase.close();
  });
}
