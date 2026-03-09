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

  testWidgets('app lock gates ui until correct password', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    final db = await appDatabase.instance;

    const hasher = PasswordHasher(iterations: 1000, keyLength: 32);
    final salt = hasher.generateSalt();
    final hash = hasher.hashPassword(password: '1234', salt: salt);
    await db.update('app_settings', <String, Object?>{
      'security_app_lock_enabled': 1,
      'security_password_hash': hash,
      'security_password_salt': salt,
      'security_password_updated_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = 1');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appDatabaseProvider.overrideWithValue(appDatabase),
        ],
        child: const MaterialApp(home: SecurityGate()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('App is locked'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid password.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard'), findsWidgets);

    await appDatabase.close();
  });
}
