import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/features/portfolio_property/data/sqlite_reference_migration_source_adapter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database database;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    database = await appDatabase.instance;
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('reads ordered reference rows without mutating SQLite', () async {
    await _insertProperty(database, 'property-z');
    await _insertProperty(database, 'property-a');
    final beforeChanges = await _totalChanges(database);
    final beforeCounts = await _tableCounts(database);

    final snapshot =
        await SqliteReferenceMigrationSourceAdapter(database).read();

    expect(snapshot.workspaces.map((row) => row['id']), <Object?>[
      'ws_default',
    ]);
    final propertyIds = snapshot.properties
        .map((row) => row['id']! as String)
        .toList(growable: false);
    expect(propertyIds, orderedEquals(propertyIds.toList()..sort()));
    expect(propertyIds, containsAll(<String>['property-a', 'property-z']));
    expect(await _totalChanges(database), beforeChanges);
    expect(await _tableCounts(database), beforeCounts);
  });
}

Future<void> _insertProperty(Database database, String id) {
  return database.insert('properties', <String, Object?>{
    'id': id,
    'name': 'Property $id',
    'address_line1': 'Musterstrasse 1',
    'zip': '10115',
    'city': 'Berlin',
    'country': 'DE',
    'property_type': 'residential',
    'units': 1,
    'created_at': 1000,
    'updated_at': 2000,
    'archived': 0,
  });
}

Future<int> _totalChanges(Database database) async {
  final rows = await database.rawQuery('SELECT total_changes() AS value');
  return (rows.single['value']! as num).toInt();
}

Future<Map<String, int>> _tableCounts(Database database) async {
  final counts = <String, int>{};
  for (final table in <String>[
    'workspaces',
    'properties',
    'import_jobs',
    'audit_log',
  ]) {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS value FROM $table',
    );
    counts[table] = (rows.single['value']! as num).toInt();
  }
  return counts;
}
