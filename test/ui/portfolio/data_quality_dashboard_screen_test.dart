import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/portfolio/data_quality_dashboard_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows quality score and issues list container', (tester) async {
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appDatabaseProvider.overrideWithValue(appDatabase),
        ],
        child: const MaterialApp(
          home: DataQualityDashboardScreen(
            portfolioId: 'p1',
            portfolioName: 'Fund',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Data Quality'), findsOneWidget);
    expect(find.text('Portfolio Score'), findsOneWidget);

    await appDatabase.close();
  });
}
