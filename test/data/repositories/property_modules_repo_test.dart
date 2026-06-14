import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/repositories/property_modules_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late PropertyModulesRepo repo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    repo = PropertyModulesRepo(db);

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('properties', <String, Object?>{
      'id': 'p1',
      'name': 'Property 1',
      'address_line1': 'Street 1',
      'address_line2': null,
      'zip': '10115',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'condo_sale',
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
      'status': 'for_sale',
      'market_rent_monthly': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('loads buyer interests and unit sale status for one property', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('contacts', <String, Object?>{
      'id': 'c1',
      'display_name': 'Buyer One',
      'legal_name': null,
      'role': 'buyer',
      'email': null,
      'phone': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('buyer_interests', <String, Object?>{
      'id': 'bi1',
      'property_id': 'p1',
      'unit_id': 'u1',
      'contact_id': 'c1',
      'interest_status': 'active',
      'budget_amount': 250000,
      'offer_amount': null,
      'viewing_at': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('unit_sale_details', <String, Object?>{
      'unit_id': 'u1',
      'property_id': 'p1',
      'sale_status': 'reserved',
      'asking_price': 260000,
      'minimum_price': 245000,
      'reserved_at': now,
      'sold_at': null,
      'buyer_contact_id': 'c1',
      'notes': null,
      'updated_at': now,
    });

    final interests = await repo.listBuyerInterests('p1');
    final buyers = await repo.listContactsForProperty(
      propertyId: 'p1',
      role: 'buyer',
    );
    final unitStatuses = await repo.listUnitSaleDetails('p1');

    expect(interests.length, 1);
    expect(buyers.map((contact) => contact.displayName), ['Buyer One']);
    expect(unitStatuses.single.saleStatus, 'reserved');
  });

  test('detects hotel modules from hotel room units or reservations', () async {
    expect(await repo.hasHotelModules('p1'), isFalse);

    await db.update(
      'units',
      <String, Object?>{'unit_type': 'hotel_room'},
      where: 'id = ?',
      whereArgs: <Object?>['u1'],
    );

    expect(await repo.hasHotelModules('p1'), isTrue);
  });
}

