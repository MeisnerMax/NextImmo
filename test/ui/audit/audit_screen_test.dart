import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/audit/audit_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('audit screen filters by entity type', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    final db = await appDatabase.instance;

    await db.insert('audit_log', <String, Object?>{
      'id': 'a1',
      'occurred_at': 1,
      'workspace_id': 'ws1',
      'actor_user_id': 'u1',
      'actor_role': 'manager',
      'entity_type': 'scenario_inputs',
      'entity_id': 's1',
      'action': 'update',
      'changed_at': 1,
      'user_id': null,
      'parent_entity_type': null,
      'parent_entity_id': null,
      'old_values_json': null,
      'new_values_json': null,
      'summary': 'inputs updated',
      'diff_json': null,
      'source': 'ui',
      'correlation_id': null,
      'reason': null,
      'is_system_event': 0,
    });
    await db.insert('audit_log', <String, Object?>{
      'id': 'a2',
      'occurred_at': 2,
      'workspace_id': 'ws1',
      'actor_user_id': 'u2',
      'actor_role': 'analyst',
      'entity_type': 'import_job',
      'entity_id': 'j1',
      'action': 'import',
      'changed_at': 2,
      'user_id': null,
      'parent_entity_type': null,
      'parent_entity_id': null,
      'old_values_json': null,
      'new_values_json': null,
      'summary': 'import done',
      'diff_json': null,
      'source': 'import',
      'correlation_id': null,
      'reason': null,
      'is_system_event': 1,
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appDatabaseProvider.overrideWithValue(appDatabase),
        ],
        child: const MaterialApp(home: AuditScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('scenario_inputs:s1'), findsOneWidget);
    expect(find.textContaining('import_job:j1'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'scenario_inputs');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('scenario_inputs:s1'), findsOneWidget);
    expect(find.textContaining('import_job:j1'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await appDatabase.close();
  }, skip: true);
}
