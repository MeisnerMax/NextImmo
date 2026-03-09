import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/audit_log.dart';
import 'package:neximmo_app/data/repositories/audit_log_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late AuditLogRepo repo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    final db = await appDatabase.instance;
    repo = AuditLogRepo(db);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('records and filters audit events', () async {
    await repo.recordEvent(
      entityType: 'scenario_inputs',
      entityId: 's1',
      action: 'update',
      workspaceId: 'ws1',
      actorUserId: 'u1',
      actorRole: 'manager',
      source: 'ui',
      summary: 'changed',
      parentEntityType: 'property',
      parentEntityId: 'p1',
      oldValues: const <String, Object?>{'purchase_price': 100},
      newValues: const <String, Object?>{'purchase_price': 120},
      correlationId: 'corr-1',
      reason: 'review requested',
      diffItems: const <AuditDiffItem>[
        AuditDiffItem(fieldKey: 'purchase_price', before: 100, after: 120),
      ],
    );
    await repo.recordEvent(
      entityType: 'import_job',
      entityId: 'j1',
      action: 'import',
      workspaceId: 'ws1',
      actorUserId: 'u2',
      source: 'import',
      summary: 'imported 3',
      isSystemEvent: true,
    );

    final uiEvents = await repo.list(
      source: 'ui',
      userId: 'u1',
      parentEntityType: 'property',
      parentEntityId: 'p1',
    );
    expect(uiEvents.length, 1);
    expect(uiEvents.first.diffItems, isNotEmpty);
    expect(uiEvents.first.diffItems.first.fieldKey, 'purchase_price');
    expect(uiEvents.first.workspaceId, 'ws1');
    expect(uiEvents.first.actorRole, 'manager');
    expect(uiEvents.first.oldValues?['purchase_price'], 100);
    expect(uiEvents.first.newValues?['purchase_price'], 120);
    expect(uiEvents.first.correlationId, 'corr-1');
    expect(uiEvents.first.reason, 'review requested');
  });
}
