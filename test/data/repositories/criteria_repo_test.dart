import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/data/repositories/criteria_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('sets and clears property criteria override', () async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      'properties',
      const PropertyRecord(
        id: 'p1',
        name: 'P',
        addressLine1: 'A',
        zip: '1',
        city: 'C',
        country: 'DE',
        propertyType: 'single_family',
        units: 1,
        createdAt: 0,
        updatedAt: 0,
      ).toMap(),
    );

    await db.insert('criteria_sets', <String, Object?>{
      'id': 'set1',
      'name': 'Set 1',
      'is_default': 1,
      'created_at': now,
      'updated_at': now,
    });

    final repo = CriteriaRepository(db);

    await repo.setPropertyOverride(propertyId: 'p1', criteriaSetId: 'set1');
    final override = await repo.getPropertyOverride('p1');
    expect(override, 'set1');

    await repo.clearPropertyOverride('p1');
    final cleared = await repo.getPropertyOverride('p1');
    expect(cleared, isNull);
  });

  test('enforces unique criteria set names case-insensitive', () async {
    final repo = CriteriaRepository(db);
    await repo.createSet(name: 'BuyBox A');

    expect(() => repo.createSet(name: 'buybox a'), throwsA(isA<StateError>()));
  });
}
