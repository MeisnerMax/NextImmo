import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/repositories/operations_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/features/leasing_operations/application/operations_signals_contract.dart';
import 'package:neximmo_app/features/leasing_operations/data/legacy_operations_signals_adapter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _workspaceId = 'legacy-workspace';

const LeasingCommandContext _context = LeasingCommandContext(
  workspaceId: _workspaceId,
  actorId: 'legacy',
  mutationId: 'mutation-1',
  correlationId: 'correlation-1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late LegacySqliteOperationsSignalsAdapter adapter;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    final db = await appDatabase.instance;
    final repo = OperationsRepo(db);
    adapter = LegacySqliteOperationsSignalsAdapter(
      repo: repo,
      legacyWorkspaceId: _workspaceId,
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
      'start_date': DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch,
      'end_date': DateTime.now()
          .add(const Duration(days: 20))
          .millisecondsSinceEpoch,
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
  });

  tearDown(() async {
    await appDatabase.close();
  });

  group('LegacySqliteOperationsSignalsAdapter.list', () {
    test('projects the existing engine output onto OperationsSignalDto', () async {
      final result = await adapter.list(
        const OperationsSignalsQuery(workspaceId: _workspaceId, propertyId: 'p1'),
      );

      final signals = (result as OperationsSignalsSuccess).value as List;
      expect(signals, isNotEmpty);
      final expiry = signals.firstWhere((signal) => signal.type == 'lease_expiry');
      expect(expiry.severity, 'critical');
      expect(expiry.leaseId, 'l1');
      expect(expiry.unitId, 'u1');
      final contact = signals.firstWhere(
        (signal) => signal.type == 'missing_tenant_contact',
      );
      expect(contact.tenantPartyId, 't1');
      // Every legacy id survives as-is (message-derived), not the new stable
      // scheme — the adapter's header states why.
      expect(signals.every((signal) => signal.signalKey.isNotEmpty), isTrue);
    });

    test('is forbidden for a workspace that is not the resolved legacy one', () async {
      final result = await adapter.list(
        const OperationsSignalsQuery(workspaceId: 'other-workspace', propertyId: 'p1'),
      );

      expect(
        (result as OperationsSignalsFailure).kind,
        OperationsSignalsFailureKind.forbidden,
      );
    });

    test('is forbidden when the legacy workspace id is unresolved', () async {
      final unresolvedAdapter = LegacySqliteOperationsSignalsAdapter(
        repo: OperationsRepo(await appDatabase.instance),
        legacyWorkspaceId: '',
      );

      final result = await unresolvedAdapter.list(
        const OperationsSignalsQuery(workspaceId: '', propertyId: 'p1'),
      );

      expect(
        (result as OperationsSignalsFailure).kind,
        OperationsSignalsFailureKind.forbidden,
      );
    });
  });

  group('LegacySqliteOperationsSignalsAdapter.updateStatus', () {
    test('acknowledges a signal and the read side reflects it', () async {
      final first = await adapter.list(
        const OperationsSignalsQuery(workspaceId: _workspaceId, propertyId: 'p1'),
      );
      final signals =
          (first as OperationsSignalsSuccess).value as List<dynamic>;
      final expiry = signals.firstWhere((signal) => signal.type == 'lease_expiry');

      final ack = await adapter.updateStatus(
        UpdateOperationsSignalStatusCommand(
          context: _context,
          propertyId: 'p1',
          signalType: 'lease_expiry',
          signalKey: expiry.signalKey as String,
          status: 'dismissed',
          resolutionNote: 'reviewed',
        ),
      );
      expect((ack as OperationsSignalsSuccess).value, isNotNull);

      final second = await adapter.list(
        const OperationsSignalsQuery(workspaceId: _workspaceId, propertyId: 'p1'),
      );
      final updatedSignals =
          (second as OperationsSignalsSuccess).value as List<dynamic>;
      final updatedExpiry = updatedSignals.firstWhere(
        (signal) => signal.type == 'lease_expiry',
      );
      expect(updatedExpiry.status, 'dismissed');
      expect(updatedExpiry.resolutionNote, 'reviewed');
    });

    test('refuses a non-null expectedVersion: there is nothing to compare it to', () async {
      final result = await adapter.updateStatus(
        const UpdateOperationsSignalStatusCommand(
          context: _context,
          propertyId: 'p1',
          signalType: 'lease_expiry',
          signalKey: 'lease_expiry|p1|u1|l1|t1|Lease 1 expires in 20 days.',
          status: 'dismissed',
          expectedVersion: 1,
        ),
      );

      expect(
        (result as OperationsSignalsFailure).kind,
        OperationsSignalsFailureKind.mutationConflict,
      );
    });
  });
}
