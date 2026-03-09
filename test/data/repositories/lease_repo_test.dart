import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/operations/lease_indexation_engine.dart';
import 'package:neximmo_app/data/repositories/audit_log_repo.dart';
import 'package:neximmo_app/data/repositories/lease_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;
  late LeaseRepo repo;
  late AuditLogRepo auditRepo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
    auditRepo = AuditLogRepo(db);
    repo = LeaseRepo(
      db,
      const LeaseIndexationEngine(),
      auditLogRepo: auditRepo,
    );

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
      'status': 'vacant',
      'market_rent_monthly': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('rebuild schedule persists and manual override wins', () async {
    final lease = await repo.createLease(
      assetPropertyId: 'p1',
      unitId: 'u1',
      leaseName: 'Lease 1',
      startDate: DateTime(2024, 1, 1).millisecondsSinceEpoch,
      status: 'active',
      baseRentMonthly: 1000,
    );

    await repo.upsertIndexationRule(
      leaseId: lease.id,
      kind: 'cpi',
      effectiveFromPeriodKey: '2025-01',
      annualPercent: 0.02,
    );

    await repo.upsertManualOverride(
      leaseId: lease.id,
      periodKey: '2025-02',
      rentMonthly: 2000,
    );

    final rows = await repo.rebuildRentSchedule(
      leaseId: lease.id,
      fromPeriod: '2025-01',
      toPeriod: '2025-03',
    );

    expect(rows.length, 3);
    final manual = rows.firstWhere((row) => row.periodKey == '2025-02');
    expect(manual.source, 'manual_override');
    expect(manual.rentMonthly, 2000);

    final audits = await auditRepo.list(parentEntityId: 'p1');
    expect(
      audits.any(
        (entry) =>
            entry.entityType == 'lease' && entry.action == 'rebuild_schedule',
      ),
      isTrue,
    );
  });

  test('createLease rejects overlapping active leases', () async {
    await repo.createLease(
      assetPropertyId: 'p1',
      unitId: 'u1',
      leaseName: 'Lease 1',
      startDate: DateTime(2025, 1, 1).millisecondsSinceEpoch,
      endDate: DateTime(2025, 12, 31).millisecondsSinceEpoch,
      status: 'active',
      baseRentMonthly: 1000,
    );

    await expectLater(
      repo.createLease(
        assetPropertyId: 'p1',
        unitId: 'u1',
        leaseName: 'Lease 2',
        startDate: DateTime(2025, 6, 1).millisecondsSinceEpoch,
        endDate: DateTime(2026, 5, 31).millisecondsSinceEpoch,
        status: 'active',
        baseRentMonthly: 1100,
      ),
      throwsA(
        isA<LeaseValidationException>().having(
          (error) => error.message,
          'message',
          'This unit already has an overlapping active lease.',
        ),
      ),
    );
  });
}
