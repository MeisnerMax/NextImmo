import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/maintenance/contractors_screen.dart';
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
    await db.insert('contractors', <String, Object?>{
      'id': 'contractor-1',
      'company_name': 'Muster Haustechnik',
      'trade_category': 'Sanitär / Heizung',
      'contact_name': 'Max Muster',
      'phone': '+49 30 123456',
      'email': 'kontakt@example.de',
      'address': 'Musterstraße 1, Berlin',
      'hourly_rate': 85.0,
      'service_areas_json': '["Berlin"]',
      'notes': null,
      'created_at': now,
      'updated_at': now,
      'rating_price': 4.0,
      'rating_quality': 4.5,
      'rating_speed': 4.0,
      'rating_communication': 4.5,
      'rating_punctuality': 5.0,
      'insurance_cert_expiry': null,
      'is_active': 1,
    });
  });

  tearDownAll(() async {
    await appDatabase.close();
  });

  for (final size in const <Size>[
    Size(390, 844),
    Size(800, 1000),
    Size(1440, 1000),
  ]) {
    testWidgets('bleibt bei ${size.width.toInt()} px ohne Overflow nutzbar', (
      tester,
    ) async {
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
            home: const Scaffold(body: ContractorsScreen()),
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('Muster Haustechnik'));

      expect(find.text('Muster Haustechnik'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Muster Haustechnik'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Kontakt- und Stammdaten'), findsOneWidget);
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
