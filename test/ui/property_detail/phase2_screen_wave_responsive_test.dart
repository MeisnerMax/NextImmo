import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/scenario.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/property_detail/scenarios_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/state/scenario_state.dart';
import 'package:neximmo_app/ui/state/security_state.dart';
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

  // The leases case moved out with Welle 3 AP3: the legacy `LeasesScreen` is
  // gone and its replacement is covered at the same three sizes in
  // `leases_panel_test.dart`, on the P2-D05 contract instead of on SQLite.
  for (final size in const [Size(390, 844), Size(1024, 768), Size(1440, 900)]) {
    testWidgets(
      'scenarios render without overflow at ${size.width.toInt()} px',
      (tester) async {
        await _pumpAtSize(
          tester,
          size: size,
          appDatabase: appDatabase,
          db: db,
          child: const ScenariosScreen(propertyId: 'p1', scenarios: []),
        );

        expect(find.text('Szenarien & Bewertung'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _pumpAtSize(
  WidgetTester tester, {
  required Size size,
  required AppDatabase appDatabase,
  required Database db,
  required Widget child,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        appDatabaseProvider.overrideWithValue(appDatabase),
        activeUserRoleProvider.overrideWithValue('viewer'),
        scenariosByPropertyProvider.overrideWith(_EmptyScenariosController.new),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

class _EmptyScenariosController extends ScenariosByPropertyController {
  @override
  Future<List<ScenarioRecord>> build(String propertyId) async => const [];
}
