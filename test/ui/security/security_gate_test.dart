import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/security/password_hasher.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/security/security_gate.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  const testHasher = PasswordHasher(iterations: 1000, keyLength: 32);

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;

    final salt = testHasher.generateSalt();
    final hash = testHasher.hashPassword(password: '1234', salt: salt);
    await db.update('app_settings', <String, Object?>{
      'security_app_lock_enabled': 1,
      'security_password_hash': hash,
      'security_password_salt': salt,
      'security_password_updated_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = 1');
  });

  tearDown(() async {
    await appDatabase.close();
  });

  testWidgets('app lock gates ui until correct password', (tester) async {
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
            passwordHasherProvider.overrideWithValue(testHasher),
          ],
          child: const MaterialApp(home: Scaffold(body: SecurityGate())),
        ),
      );
      
      // Wait for security gate loading state to finish and lock screen to appear
      for (int i = 0; i < 40; i++) {
        await tester.pump();
        if (find.text('App is locked').evaluate().isNotEmpty) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(find.text('App is locked'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Unlock'));
      
      // Wait for validation error to appear
      for (int i = 0; i < 40; i++) {
        await tester.pump();
        if (find.text('Invalid password.').evaluate().isNotEmpty) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
      expect(find.text('Invalid password.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Unlock'));
      
      // Wait for unlock animation and dashboard screen transition
      for (int i = 0; i < 40; i++) {
        await tester.pump();
        if (find.text('Dashboard').evaluate().isNotEmpty) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
      expect(find.text('Dashboard'), findsWidgets);
    });

    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
  });
}
