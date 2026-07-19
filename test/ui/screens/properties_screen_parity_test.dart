import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/properties_screen.dart';
import 'package:neximmo_app/ui/screens/property_detail/property_shell.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/state/property_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Golden-path widget coverage for the canonical `PropertiesScreen`.
///
/// Origin: W0-Shell-Cleanup (MOD-CLEAN-003/004). Written as a V1-vs-V2 parity
/// test before the V1 list screen and the `PropertyShellV2` wrapper were
/// deleted; kept as the permanent characterization of the surviving
/// implementation (the list screens previously had no dedicated widget test).
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

  testWidgets('properties list exposes the golden path and opens the shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        appDatabaseProvider.overrideWithValue(appDatabase),
        propertiesControllerProvider.overrideWith(
          _SeededPropertiesController.new,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: PropertiesScreen()),
          ),
        ),
      );
      for (var attempt = 0; attempt < 40; attempt += 1) {
        await tester.pump();
        if (find.text('Asset Alpha').evaluate().isNotEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    expect(find.text('Asset Alpha'), findsWidgets);
    expect(find.text('New Property'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);

    container.read(selectedPropertyIdProvider.notifier).state = 'p1';
    await tester.pump();
    expect(find.byType(PropertyShell), findsOneWidget);

    // Opening the shell kicks off queries against the shared in-memory DB;
    // sqflite arms a 10s lock-warning timer for them. Let it fire so the test
    // tears down without a pending-timer error.
    await tester.pump(const Duration(seconds: 11));
  });
}

class _SeededPropertiesController extends PropertiesController {
  @override
  Future<List<PropertyRecord>> build() async {
    return const <PropertyRecord>[
      PropertyRecord(
        id: 'p1',
        name: 'Asset Alpha',
        addressLine1: 'Main Street 1',
        zip: '10115',
        city: 'Berlin',
        country: 'DE',
        propertyType: 'multifamily',
        units: 12,
        createdAt: 1,
        updatedAt: 1,
      ),
    ];
  }
}
