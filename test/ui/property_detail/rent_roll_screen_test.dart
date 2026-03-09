import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/property_detail/rent_roll_screen.dart';
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

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('properties', <String, Object?>{
      'id': 'p1',
      'name': 'Property 1',
      'address_line1': 'Street 1',
      'address_line2': null,
      'zip': '10115',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'multifamily',
      'units': 1,
      'sqft': null,
      'year_built': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
      'archived': 0,
    });
    await db.insert('units', <String, Object?>{
      'id': 'u1',
      'asset_property_id': 'p1',
      'unit_code': 'A1',
      'unit_type': 'apartment',
      'beds': null,
      'baths': null,
      'sqft': null,
      'floor': null,
      'status': 'vacant',
      'market_rent_monthly': 1000,
      'notes': null,
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDownAll(() async {
    await appDatabase.close();
  });

  testWidgets('renders rent roll actions', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appDatabaseProvider.overrideWithValue(appDatabase),
        ],
        child: const MaterialApp(
          home: Scaffold(body: RentRollScreen(propertyId: 'p1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Generate Snapshot'), findsOneWidget);
  });
}
