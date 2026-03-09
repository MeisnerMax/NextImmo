import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/esg.dart';
import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/data/repositories/esg_repo.dart';
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

  test('upserts and reloads esg profile', () async {
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
    final repo = EsgRepository(db);
    final profile = EsgProfileRecord(
      propertyId: 'p1',
      epcRating: 'C',
      epcValidUntil: 123,
      emissionsKgCo2M2: 22.3,
      lastAuditDate: 100,
      targetRating: 'B',
      notes: 'n',
      updatedAt: 1,
    );
    await repo.upsertProfile(profile);

    final loaded = await repo.getProfile('p1');
    expect(loaded, isNotNull);
    expect(loaded!.epcRating, 'C');
    expect(loaded.emissionsKgCo2M2, closeTo(22.3, 1e-9));
  });
}
