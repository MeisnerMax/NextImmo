import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/screens/property_detail/property_audit_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/state/security_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('property audit screen only shows relevant property events', (
    tester,
  ) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    final db = await appDatabase.instance;

    Future<void> insertProperty(String id) async {
      await db.insert('properties', <String, Object?>{
        'id': id,
        'name': 'Asset $id',
        'address_line1': 'A',
        'address_line2': null,
        'zip': '1',
        'city': 'Berlin',
        'country': 'DE',
        'property_type': 'multifamily',
        'units': 1,
        'sqft': null,
        'year_built': null,
        'notes': null,
        'created_at': 1,
        'updated_at': 1,
        'archived': 0,
      });
    }

    await insertProperty('p1');
    await insertProperty('p2');
    await db.insert('scenarios', <String, Object?>{
      'id': 's1',
      'property_id': 'p1',
      'name': 'Base',
      'strategy_type': 'hold',
      'is_base': 1,
      'workflow_status': 'approved',
      'changed_since_approval': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('scenarios', <String, Object?>{
      'id': 's2',
      'property_id': 'p2',
      'name': 'Other',
      'strategy_type': 'hold',
      'is_base': 1,
      'workflow_status': 'draft',
      'changed_since_approval': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('audit_log', <String, Object?>{
      'id': 'a1',
      'entity_type': 'property',
      'entity_id': 'p1',
      'action': 'create',
      'occurred_at': 1,
      'changed_at': 1,
      'workspace_id': 'ws1',
      'actor_user_id': 'u1',
      'user_id': 'u1',
      'actor_role': 'manager',
      'summary': 'Property created',
      'diff_json': null,
      'source': 'ui',
      'parent_entity_type': null,
      'parent_entity_id': null,
      'old_values_json': null,
      'new_values_json': null,
      'correlation_id': null,
      'reason': null,
      'is_system_event': 0,
    });
    await db.insert('audit_log', <String, Object?>{
      'id': 'a2',
      'entity_type': 'scenario',
      'entity_id': 's1',
      'action': 'approved',
      'occurred_at': 2,
      'changed_at': 2,
      'workspace_id': 'ws1',
      'actor_user_id': 'u1',
      'user_id': 'u1',
      'actor_role': 'manager',
      'summary': 'Scenario approved',
      'diff_json': null,
      'source': 'ui',
      'parent_entity_type': 'property',
      'parent_entity_id': 'p1',
      'old_values_json': null,
      'new_values_json': null,
      'correlation_id': null,
      'reason': null,
      'is_system_event': 0,
    });
    await db.insert('audit_log', <String, Object?>{
      'id': 'a3',
      'entity_type': 'scenario',
      'entity_id': 's2',
      'action': 'update',
      'occurred_at': 3,
      'changed_at': 3,
      'workspace_id': 'ws1',
      'actor_user_id': 'u2',
      'user_id': 'u2',
      'actor_role': 'analyst',
      'summary': 'Other property scenario updated',
      'diff_json': null,
      'source': 'ui',
      'parent_entity_type': 'property',
      'parent_entity_id': 'p2',
      'old_values_json': null,
      'new_values_json': null,
      'correlation_id': null,
      'reason': null,
      'is_system_event': 0,
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appDatabaseProvider.overrideWithValue(appDatabase),
          activeUserRoleProvider.overrideWithValue('viewer'),
        ],
        child: const MaterialApp(home: PropertyAuditScreen(propertyId: 'p1')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Property created'), findsOneWidget);
    expect(find.textContaining('Scenario approved'), findsOneWidget);
    expect(find.textContaining('Other property scenario updated'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await appDatabase.close();
  }, skip: true);
}
