import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/repositories/property_repo.dart' as legacy;
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/data/legacy_sqlite_property_repository_adapter.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late LegacySqlitePropertyRepositoryAdapter adapter;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    adapter = LegacySqlitePropertyRepositoryAdapter(
      legacyRepository: legacy.PropertyRepository(db),
      legacyWorkspaceId: 'legacy-workspace',
      legacyActorId: 'legacy-import',
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('maps persisted legacy fields without inventing a version', () async {
    await _insertProperty(
      db,
      id: 'property-1',
      createdAt: 1000,
      updatedAt: 2000,
    );

    final result = await adapter.getById(
      workspaceId: 'legacy-workspace',
      propertyId: 'property-1',
    );
    final property = (result as PropertyRepositorySuccess<PropertyDto>).value;

    expect(property.id, 'property-1');
    expect(property.workspaceId, 'legacy-workspace');
    expect(property.name, 'Musterobjekt');
    expect(property.addressLine2, 'Hinterhaus');
    expect(property.sqft, 420.5);
    expect(property.yearBuilt, 1998);
    expect(property.status, PropertyStatus.active);
    expect(
      property.createdAt,
      DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
    expect(
      property.updatedAt,
      DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
    );
    expect(property.createdBy, 'legacy-import');
    expect(
      property.version,
      LegacySqlitePropertyRepositoryAdapter.unsupportedVersion,
    );
  });

  test(
    'lists only the configured legacy workspace and archived state',
    () async {
      await _insertProperty(db, id: 'active', createdAt: 1000, updatedAt: 2000);
      await _insertProperty(
        db,
        id: 'archived',
        createdAt: 1000,
        updatedAt: 3000,
        archived: true,
      );

      final activeResult = await adapter.list(
        const PropertyListQuery(workspaceId: 'legacy-workspace'),
      );
      final allResult = await adapter.list(
        const PropertyListQuery(
          workspaceId: 'legacy-workspace',
          includeArchived: true,
        ),
      );
      final foreignResult = await adapter.list(
        const PropertyListQuery(workspaceId: 'foreign-workspace'),
      );

      final activeIds = (activeResult
              as PropertyRepositorySuccess<PropertyPageResult>)
          .value
          .items
          .map((property) => property.id);
      final allIds = (allResult
              as PropertyRepositorySuccess<PropertyPageResult>)
          .value
          .items
          .map((property) => property.id);
      expect(activeIds, contains('active'));
      expect(activeIds, isNot(contains('archived')));
      expect(allIds, containsAll(<String>['active', 'archived']));
      expect(
        (foreignResult as PropertyRepositoryFailure<PropertyPageResult>).kind,
        PropertyRepositoryFailureKind.forbidden,
      );
    },
  );

  test(
    'fails closed for foreign workspace detail and mutation access',
    () async {
      await _insertProperty(
        db,
        id: 'property-1',
        createdAt: 1000,
        updatedAt: 2000,
      );

      final detailResult = await adapter.getById(
        workspaceId: 'foreign-workspace',
        propertyId: 'property-1',
      );
      final updateResult = await adapter.update(
        _updateCommand(workspaceId: 'foreign-workspace'),
      );

      expect(
        (detailResult as PropertyRepositoryFailure<PropertyDto>).kind,
        PropertyRepositoryFailureKind.forbidden,
      );
      expect(
        (updateResult as PropertyRepositoryFailure<PropertyDto>).kind,
        PropertyRepositoryFailureKind.forbidden,
      );
    },
  );

  test('reports the durable concurrency and idempotency blocker', () async {
    await _insertProperty(
      db,
      id: 'property-1',
      createdAt: 1000,
      updatedAt: 2000,
    );

    final first = await adapter.update(
      _updateCommand(workspaceId: 'legacy-workspace'),
    );
    final retry = await adapter.update(
      _updateCommand(workspaceId: 'legacy-workspace'),
    );
    final persisted = await db.query(
      'properties',
      where: 'id = ?',
      whereArgs: <Object?>['property-1'],
      limit: 1,
    );

    for (final result in <PropertyRepositoryResult<PropertyDto>>[
      first,
      retry,
    ]) {
      final failure = result as PropertyRepositoryFailure<PropertyDto>;
      expect(failure.kind, PropertyRepositoryFailureKind.dependencyConflict);
      expect(
        failure.message,
        contains('no durable version or unique mutation id'),
      );
    }
    expect(persisted.single['name'], 'Musterobjekt');
    expect(persisted.single['updated_at'], 2000);
  });
}

Future<void> _insertProperty(
  Database db, {
  required String id,
  required int createdAt,
  required int updatedAt,
  bool archived = false,
}) {
  return db.insert('properties', <String, Object?>{
    'id': id,
    'name': 'Musterobjekt',
    'address_line1': 'Musterstrasse 1',
    'address_line2': 'Hinterhaus',
    'zip': '10115',
    'city': 'Berlin',
    'country': 'DE',
    'property_type': 'residential',
    'units': 4,
    'sqft': 420.5,
    'year_built': 1998,
    'notes': 'Legacy-Datensatz',
    'created_at': createdAt,
    'updated_at': updatedAt,
    'archived': archived ? 1 : 0,
  });
}

PropertyUpdateCommand _updateCommand({required String workspaceId}) {
  return PropertyUpdateCommand(
    propertyId: 'property-1',
    context: CommandContext(
      workspaceId: workspaceId,
      actorId: 'actor-1',
      mutationId: 'mutation-1',
      expectedVersion: 0,
      correlationId: 'correlation-1',
    ),
    changes: const PropertyUpdateDto(
      name: 'Geaendertes Objekt',
      addressLine1: 'Musterstrasse 1',
      zip: '10115',
      city: 'Berlin',
      country: 'DE',
      propertyType: 'residential',
      units: 4,
      status: PropertyStatus.active,
    ),
  );
}
