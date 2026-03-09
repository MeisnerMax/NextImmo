import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/operations/rent_roll_engine.dart';
import 'package:neximmo_app/data/repositories/rent_roll_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late RentRollRepo repo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    repo = RentRollRepo(db, const RentRollEngine());

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('properties', <String, Object?>{
      'id': 'p1',
      'name': 'Property 1',
      'address_line1': 'Street 1',
      'address_line2': null,
      'zip': '10115',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'multifamily',
      'units': 1,
      'sqft': null,
      'year_built': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
      'archived': 0,
    });

    await db.insert('units', <String, Object?>{
      'id': 'u1',
      'asset_property_id': 'p1',
      'unit_code': 'A1',
      'unit_type': 'apartment',
      'beds': null,
      'baths': null,
      'sqft': null,
      'floor': null,
      'status': 'occupied',
      'market_rent_monthly': 1200,
      'notes': null,
      'created_at': now,
      'updated_at': now,
    });

    await db.insert('tenants', <String, Object?>{
      'id': 't1',
      'display_name': 'Alice',
      'legal_name': null,
      'email': null,
      'phone': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
    });

    await db.insert('leases', <String, Object?>{
      'id': 'l1',
      'asset_property_id': 'p1',
      'unit_id': 'u1',
      'tenant_id': 't1',
      'lease_name': 'Lease 1',
      'start_date': DateTime(2025, 1, 1).millisecondsSinceEpoch,
      'end_date': null,
      'move_in_date': null,
      'move_out_date': null,
      'status': 'active',
      'base_rent_monthly': 1000,
      'currency_code': 'EUR',
      'security_deposit': null,
      'payment_day_of_month': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('generateSnapshot creates persisted snapshot and lines', () async {
    final result = await repo.generateSnapshot(
      assetPropertyId: 'p1',
      periodKey: '2026-02',
    );

    expect(result.lines.length, 1);
    expect(result.snapshot.periodKey, '2026-02');

    final snapshots = await repo.listSnapshots('p1');
    expect(snapshots.length, 1);

    final loaded = await repo.getSnapshot(result.snapshot.id);
    expect(loaded, isNotNull);
    expect(loaded!.lines.length, 1);
  });
}
