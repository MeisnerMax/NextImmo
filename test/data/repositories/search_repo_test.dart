import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/repositories/property_repo.dart';
import 'package:neximmo_app/data/repositories/search_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late SearchRepo repo;
  late PropertyRepository propertyRepo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    repo = SearchRepo(db);
    propertyRepo = PropertyRepository(db, searchRepo: repo);

    await db.insert('properties', <String, Object?>{
      'id': 'p1',
      'name': 'Berlin Asset',
      'address_line1': 'Street',
      'address_line2': null,
      'zip': '10115',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'multifamily',
      'units': 4,
      'sqft': null,
      'year_built': null,
      'notes': 'Great location',
      'created_at': 1,
      'updated_at': 1,
      'archived': 0,
    });
    await db.insert('notifications', <String, Object?>{
      'id': 'n1',
      'entity_type': 'property',
      'entity_id': 'p1',
      'kind': 'test',
      'message': 'Rent reminder',
      'due_at': null,
      'read_at': null,
      'created_at': 1,
    });
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('rebuild and search returns expected matches', () async {
    await repo.rebuildIndex();
    final byProperty = await repo.search(query: 'Berlin');
    expect(byProperty.any((e) => e.entityType == 'property'), isTrue);

    final byNotification = await repo.search(query: 'reminder');
    expect(byNotification.any((e) => e.entityType == 'notification'), isTrue);
  });

  test('property create and archive update search index incrementally', () async {
    final property = await propertyRepo.create(
      name: 'Hamburg Asset',
      addressLine1: 'Harbor 1',
      zip: '20095',
      city: 'Hamburg',
      country: 'DE',
      propertyType: 'office',
      units: 1,
    );

    var results = await repo.search(query: 'Hamburg');
    expect(results.any((entry) => entry.entityType == 'property'), isTrue);

    await propertyRepo.archive(property.id, archived: true);
    results = await repo.search(query: 'Hamburg');
    expect(results.where((entry) => entry.entityId == property.id), isEmpty);

    await propertyRepo.archive(property.id, archived: false);
    results = await repo.search(query: 'Hamburg');
    expect(results.where((entry) => entry.entityId == property.id), isNotEmpty);
  });
}
