import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/repositories/maintenance_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late MaintenanceRepo repo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    repo = MaintenanceRepo(db);

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
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('crud and due notification generation', () async {
    final ticket = await repo.createTicket(
      assetPropertyId: 'p1',
      title: 'Fix HVAC',
      dueAt: DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      createTask: true,
    );
    expect(ticket.title, 'Fix HVAC');

    final listed = await repo.listTickets(assetPropertyId: 'p1');
    expect(listed.length, 1);

    final count = await repo.createDueNotifications(dueSoonDays: 3);
    expect(count, 1);

    final notifications = await db.query('notifications');
    expect(notifications.length, 1);

    await repo.deleteTicket(ticket.id);
    final afterDelete = await repo.listTickets(assetPropertyId: 'p1');
    expect(afterDelete, isEmpty);
  });
}
