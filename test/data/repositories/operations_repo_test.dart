import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/repositories/operations_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late OperationsRepo repo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    final db = await appDatabase.instance;
    repo = OperationsRepo(db);

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
      'units': 2,
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
      'beds': 2,
      'baths': 1,
      'sqft': 70,
      'floor': '1',
      'status': 'occupied',
      'target_rent_monthly': 1200,
      'market_rent_monthly': 1250,
      'offline_reason': null,
      'vacancy_since': null,
      'vacancy_reason': null,
      'marketing_status': null,
      'renovation_status': null,
      'expected_ready_date': null,
      'next_action': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('units', <String, Object?>{
      'id': 'u2',
      'asset_property_id': 'p1',
      'unit_code': 'A2',
      'unit_type': 'apartment',
      'beds': 1,
      'baths': 1,
      'sqft': 50,
      'floor': '2',
      'status': 'vacant',
      'target_rent_monthly': 900,
      'market_rent_monthly': 950,
      'offline_reason': null,
      'vacancy_since': null,
      'vacancy_reason': null,
      'marketing_status': null,
      'renovation_status': null,
      'expected_ready_date': null,
      'next_action': null,
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
      'alternative_contact': null,
      'billing_contact': null,
      'status': 'active',
      'move_in_reference': null,
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
      'start_date': DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch,
      'end_date': DateTime.now().add(const Duration(days: 20)).millisecondsSinceEpoch,
      'move_in_date': null,
      'move_out_date': null,
      'status': 'active',
      'base_rent_monthly': 1100,
      'currency_code': 'EUR',
      'security_deposit': 2000,
      'payment_day_of_month': 3,
      'billing_frequency': 'monthly',
      'lease_signed_date': null,
      'notice_date': null,
      'renewal_option_date': null,
      'break_option_date': null,
      'executed_date': null,
      'deposit_status': 'received',
      'rent_free_period_months': null,
      'ancillary_charges_monthly': null,
      'parking_other_charges_monthly': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('rent_roll_snapshots', <String, Object?>{
      'id': 'rr1',
      'asset_property_id': 'p1',
      'period_key': '2026-02',
      'snapshot_at': now,
      'occupancy_rate': 0.5,
      'gpr_monthly': 2200,
      'vacancy_loss_monthly': 1100,
      'egi_monthly': 1100,
      'in_place_rent_monthly': 1100,
      'market_rent_monthly': 2200,
      'notes': null,
    });
    await db.insert('rent_roll_snapshots', <String, Object?>{
      'id': 'rr0',
      'asset_property_id': 'p1',
      'period_key': '2026-01',
      'snapshot_at': now - 1000,
      'occupancy_rate': 1.0,
      'gpr_monthly': 2000,
      'vacancy_loss_monthly': 0,
      'egi_monthly': 2000,
      'in_place_rent_monthly': 2000,
      'market_rent_monthly': 2000,
      'notes': null,
    });
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('loadOverview returns counts deltas and alerts', () async {
    final bundle = await repo.loadOverview('p1');

    expect(bundle.unitsTotal, 2);
    expect(bundle.occupiedUnits, 1);
    expect(bundle.vacantUnits, 1);
    expect(bundle.activeLeases, 1);
    expect(bundle.occupiedAreaSqft, 70);
    expect(bundle.leasedAreaSqft, 70);
    expect(bundle.expiringIn30Days, 1);
    expect(bundle.unitsWithoutActiveLease, 1);
    expect(bundle.unitsWithMissingTenantMasterData, 1);
    expect(bundle.latestRentRollPeriod, '2026-02');
    expect(bundle.rentRollDelta, isNotNull);
    expect(bundle.rentRollDelta!.inPlaceRentDelta, -900);
    expect(bundle.alerts, isNotEmpty);
    expect(bundle.dataQualityIssues, isNotEmpty);
    expect(
      bundle.alerts.any((alert) => alert.type == 'lease_expiry'),
      isTrue,
    );
    expect(
      bundle.dataQualityIssues.any((issue) => issue.type == 'vacancy_missing_since'),
      isTrue,
    );
  });

  test('alert status overlay persists dismiss and resolve state', () async {
    final alerts = await repo.loadAlerts('p1');
    final target = alerts.firstWhere((alert) => alert.type == 'vacancy_missing_since');

    await repo.updateAlertStatus(
      alertId: target.id!,
      propertyId: 'p1',
      status: 'dismissed',
    );
    var refreshed = await repo.loadAlerts('p1', status: 'dismissed');
    expect(refreshed.any((alert) => alert.id == target.id), isTrue);

    await repo.updateAlertStatus(
      alertId: target.id!,
      propertyId: 'p1',
      status: 'resolved',
      resolutionNote: 'Reviewed and confirmed.',
    );
    refreshed = await repo.loadAlerts('p1', status: 'resolved');
    final resolved = refreshed.firstWhere((alert) => alert.id == target.id);
    expect(resolved.resolutionNote, 'Reviewed and confirmed.');
  });
}
