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

  test('getTenantsForProperty only returns tenants assigned to that property', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('properties', <String, Object?>{
      'id': 'p2',
      'name': 'Property 2',
      'address_line1': 'Street 2',
      'address_line2': null,
      'zip': '10117',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'rental',
      'units': 1,
      'sqft': null,
      'year_built': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
      'archived': 0,
    });
    await db.insert('units', <String, Object?>{
      'id': 'u2',
      'asset_property_id': 'p2',
      'unit_code': 'B1',
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

    final tenantA = await repo.upsertTenant(displayName: 'Tenant A');
    final tenantB = await repo.upsertTenant(displayName: 'Tenant B');
    await repo.createLease(
      assetPropertyId: 'p1',
      unitId: 'u1',
      tenantId: tenantA.id,
      leaseName: 'Lease A',
      startDate: DateTime(2024, 1, 1).millisecondsSinceEpoch,
      status: 'active',
      baseRentMonthly: 1000,
    );
    await repo.createLease(
      assetPropertyId: 'p2',
      unitId: 'u2',
      tenantId: tenantB.id,
      leaseName: 'Lease B',
      startDate: DateTime(2024, 1, 1).millisecondsSinceEpoch,
      status: 'active',
      baseRentMonthly: 1200,
    );

    final propertyTenants = await repo.getTenantsForProperty('p1');

    expect(propertyTenants.map((tenant) => tenant.id), [tenantA.id]);
  });

  test('deleteIndexationRule removes rule and audit log records it', () async {
    final lease = await repo.createLease(
      assetPropertyId: 'p1',
      unitId: 'u1',
      leaseName: 'Lease 1',
      startDate: DateTime(2024, 1, 1).millisecondsSinceEpoch,
      status: 'active',
      baseRentMonthly: 1000,
    );

    final rule = await repo.upsertIndexationRule(
      leaseId: lease.id,
      kind: 'cpi',
      effectiveFromPeriodKey: '2025-01',
      annualPercent: 0.02,
    );

    final rulesBefore = await repo.listIndexationRules(lease.id);
    expect(rulesBefore.length, 1);

    await repo.deleteIndexationRule(rule.id);

    final rulesAfter = await repo.listIndexationRules(lease.id);
    expect(rulesAfter.isEmpty, isTrue);

    final audits = await auditRepo.list(parentEntityId: 'p1');
    expect(
      audits.any((entry) => entry.entityType == 'lease_indexation_rule' && entry.action == 'delete'),
      isTrue,
    );
  });

  test('deleteManualOverride removes manual override and audit log records it', () async {
    final lease = await repo.createLease(
      assetPropertyId: 'p1',
      unitId: 'u1',
      leaseName: 'Lease 1',
      startDate: DateTime(2024, 1, 1).millisecondsSinceEpoch,
      status: 'active',
      baseRentMonthly: 1000,
    );

    await repo.upsertManualOverride(
      leaseId: lease.id,
      periodKey: '2025-02',
      rentMonthly: 2000,
    );

    final scheduleBefore = await repo.readSchedule(leaseId: lease.id);
    expect(scheduleBefore.any((row) => row.source == 'manual_override'), isTrue);

    await repo.deleteManualOverride(lease.id, '2025-02');

    final scheduleAfter = await repo.readSchedule(leaseId: lease.id);
    expect(scheduleAfter.any((row) => row.source == 'manual_override'), isFalse);

    final audits = await auditRepo.list(parentEntityId: 'p1');
    expect(
      audits.any((entry) => entry.entityType == 'lease_rent_schedule' && entry.action == 'delete'),
      isTrue,
    );
  });
}
