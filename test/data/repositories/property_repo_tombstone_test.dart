import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/security.dart';
import 'package:neximmo_app/core/security/rbac.dart';
import 'package:neximmo_app/data/repositories/audit_log_repo.dart';
import 'package:neximmo_app/data/repositories/permission_guard.dart';
import 'package:neximmo_app/data/repositories/property_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Contract for `PropertyRepository.tombstone`/`restore` (Phase 2 Wave 1 / AP9,
/// DEBT-012 / STM-002). Replaces the previous hard-delete cascade: deletion is
/// now a reversible soft tombstone that keeps the row and all children for audit
/// and restore, and hides the property from active views via `archived = 1`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late AuditLogRepo audit;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    audit = AuditLogRepo(db);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<Map<String, Object?>> propertyRow(String id) async {
    final rows = await db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.single;
  }

  test(
    'tombstone keeps the row and children, hides from active views, audits',
    () async {
      final repo = PropertyRepository(db, auditLogRepo: audit);
      await _insertProperty(db, id: 'p1');
      await _insertUnit(db, id: 'u1', propertyId: 'p1');

      await repo.tombstone('p1', actorId: 'user-1');

      // Row retained and marked, not deleted.
      final row = await propertyRow('p1');
      expect(row['deleted_at'], isNotNull);
      expect(row['deleted_by'], 'user-1');
      expect(row['archived'], 1);

      // Children retained (no cascade).
      final units = await db.query(
        'units',
        where: 'id = ?',
        whereArgs: <Object?>['u1'],
      );
      expect(units, isNotEmpty);

      // Hidden from the active list, present in the archived list as deleted.
      final active = await repo.list();
      expect(active.map((p) => p.id), isNot(contains('p1')));
      final all = await repo.list(includeArchived: true);
      final tombstoned = all.firstWhere((p) => p.id == 'p1');
      expect(tombstoned.isDeleted, isTrue);

      // Append-only audit event.
      final events = await audit.list(
        entityType: 'property',
        entityId: 'p1',
        action: 'delete',
      );
      expect(events, isNotEmpty);
      expect(events.first.summary, 'Property deleted (soft tombstone)');
    },
  );

  test('tombstone is idempotent: a second call is a no-op', () async {
    final repo = PropertyRepository(db, auditLogRepo: audit);
    await _insertProperty(db, id: 'p1');

    await repo.tombstone('p1');
    await repo.tombstone('p1');

    final events = await audit.list(
      entityType: 'property',
      entityId: 'p1',
      action: 'delete',
    );
    expect(events.length, 1);
  });

  test('tombstone is a no-op for an unknown id (no throw, no audit)', () async {
    final repo = PropertyRepository(db, auditLogRepo: audit);
    await _insertProperty(db, id: 'p1');

    await repo.tombstone('does-not-exist');

    expect((await propertyRow('p1'))['deleted_at'], isNull);
    final events = await audit.list(
      entityType: 'property',
      entityId: 'does-not-exist',
    );
    expect(events, isEmpty);
  });

  test('restore brings a tombstoned property back with children intact', () async {
    final repo = PropertyRepository(db, auditLogRepo: audit);
    await _insertProperty(db, id: 'p1');
    await _insertUnit(db, id: 'u1', propertyId: 'p1');
    await repo.tombstone('p1', actorId: 'user-1');

    await repo.restore('p1', actorId: 'user-2');

    final row = await propertyRow('p1');
    expect(row['deleted_at'], isNull);
    expect(row['deleted_by'], isNull);
    expect(row['archived'], 0);

    final active = await repo.list();
    expect(active.map((p) => p.id), contains('p1'));
    final units = await db.query(
      'units',
      where: 'id = ?',
      whereArgs: <Object?>['u1'],
    );
    expect(units, isNotEmpty);

    final events = await audit.list(
      entityType: 'property',
      entityId: 'p1',
      action: 'update',
    );
    expect(events.any((e) => e.summary == 'Property restored'), isTrue);
  });

  test('restore is a no-op when the property is not tombstoned', () async {
    final repo = PropertyRepository(db, auditLogRepo: audit);
    await _insertProperty(db, id: 'p1');

    await repo.restore('p1');

    expect((await propertyRow('p1'))['archived'], 0);
    final events = await audit.list(entityType: 'property', entityId: 'p1');
    expect(events.any((e) => e.summary == 'Property restored'), isFalse);
  });

  test('archive stays soft and distinct: archived=1 but not tombstoned', () async {
    final repo = PropertyRepository(db, auditLogRepo: audit);
    await _insertProperty(db, id: 'p1');

    await repo.archive('p1', archived: true);

    final row = await propertyRow('p1');
    expect(row['archived'], 1);
    expect(row['deleted_at'], isNull);
    final all = await repo.list(includeArchived: true);
    expect(all.firstWhere((p) => p.id == 'p1').isDeleted, isFalse);
  });

  test('tombstone requires property.delete: a viewer is blocked', () async {
    final repo = PropertyRepository(
      db,
      auditLogRepo: audit,
      permissionGuard: const PermissionGuard(Rbac()),
      securityContextResolver: () async => _context(role: 'viewer'),
    );
    await _insertProperty(db, id: 'p1');

    await expectLater(
      () => repo.tombstone('p1'),
      throwsA(isA<PermissionDenied>()),
    );
    expect((await propertyRow('p1'))['deleted_at'], isNull);
  });
}

Future<void> _insertProperty(Database db, {required String id}) {
  return db.insert('properties', <String, Object?>{
    'id': id,
    'name': 'Musterobjekt',
    'address_line1': 'Musterstrasse 1',
    'address_line2': null,
    'zip': '10115',
    'city': 'Berlin',
    'country': 'DE',
    'property_type': 'residential',
    'units': 1,
    'sqft': null,
    'year_built': null,
    'notes': null,
    'created_at': 1000,
    'updated_at': 2000,
    'archived': 0,
  });
}

Future<void> _insertUnit(
  Database db, {
  required String id,
  required String propertyId,
}) {
  return db.insert('units', <String, Object?>{
    'id': id,
    'asset_property_id': propertyId,
    'unit_code': 'A1',
    'status': 'vacant',
    'created_at': 1000,
    'updated_at': 2000,
  });
}

SecurityContextRecord _context({required String role}) {
  return SecurityContextRecord(
    workspace: const WorkspaceRecord(
      id: 'w1',
      name: 'HQ',
      docsRootPath: '.',
      createdAt: 1,
    ),
    user: LocalUserRecord(
      id: 'me',
      workspaceId: 'w1',
      email: 'me@hq.io',
      displayName: 'Me',
      passwordHash: 'x',
      passwordSalt: 'y',
      role: role,
      createdAt: 1,
    ),
  );
}
