import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/ledger/ledger_screen.dart';
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
  });

  tearDownAll(() async {
    await appDatabase.close();
  });

  testWidgets('displays existing ledger entry', (tester) async {
    const longEntityType = 'entity_type_with_a_really_long_identifier_name';
    await db.insert('ledger_accounts', <String, Object?>{
      'id': 'acc-1',
      'name': 'Rent',
      'kind': 'income',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await db.insert('ledger_entries', <String, Object?>{
      'id': 'entry-1',
      'entity_type': longEntityType,
      'entity_id': null,
      'account_id': 'acc-1',
      'posted_at': DateTime.now().millisecondsSinceEpoch,
      'period_key': '2026-03',
      'direction': 'in',
      'amount': 123.45,
      'currency_code': 'EUR',
      'counterparty': null,
      'memo': null,
      'document_id': null,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appDatabaseProvider.overrideWithValue(appDatabase),
        ],
        child: const MaterialApp(home: Scaffold(body: LedgerScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('123.45'), findsOneWidget);
    expect(find.byTooltip(longEntityType), findsOneWidget);
  });
}
